#!/usr/bin/env bash
# Offline test suite: fake recorder, fake clipboard, fake notify-send, mock API.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
PORT=$((20000 + RANDOM % 20000))
export MOCK_LOG=$T/api.log XDG_RUNTIME_DIR=$T/run STT_CONFIG=$T/none
export STT_API_URL=http://127.0.0.1:$PORT/ OPENROUTER_API_KEY=test-key
export STT_RECORDER=$T/bin/fake-rec STT_CLIP=$T/bin/fake-clip PATH=$T/bin:$PATH
mkdir -p "$T/bin" "$T/run"
python3 "$ROOT/tests/mock_server.py" $PORT & SRV=$!

cat >"$T/bin/fake-rec" <<'R'
#!/usr/bin/env bash
# mimics pw-record: writes audio until SIGINT
out=${@: -1}; trap 'exit 0' INT TERM
ffmpeg -loglevel error -f lavfi -i sine=frequency=440:duration=2 -ar 16000 -ac 1 -y "$out"
while :; do sleep 0.05; done
R
printf '#!/bin/sh\ncat > "%s/clip"\n' "$T" >"$T/bin/fake-clip"
printf '#!/bin/sh\necho "$*" >> "%s/notify.log"; echo 7\n' "$T" >"$T/bin/notify-send"
chmod +x "$T/bin/"*
for _ in $(seq 50); do curl -s "http://127.0.0.1:$PORT" -o /dev/null && break; sleep 0.1; done

pass=0 fail=0
check() { if eval "$2"; then echo "  ok   $1"; ((pass++)); else echo "  FAIL $1"; ((fail++)); fi; }
S="$ROOT/stt-toggle"
reset() { rm -rf "$T/run/"* "$T/clip" "$T/notify.log" "$MOCK_LOG"; }

echo "1) happy path: press, press"
reset; "$S"; sleep 1
check "recorder running after 1st press" '[[ -s $T/run/wayland-stt/rec.pid ]] && kill -0 $(cat $T/run/wayland-stt/rec.pid)'
check "no notification on start" '[[ ! -e $T/notify.log ]]'
out=$("$S")
check "no transcript on non-tty stdout (keeps it out of the journal)" '[[ -z $out ]]'
check "clipboard has trimmed text" '[[ $(cat $T/clip) == "Hallo Welt, äöü ß – Test." ]]'
check "upload is JSON with base64 opus/ogg" 'grep -q "\"has_ogg\": true" $MOCK_LOG && grep -q "\"format\": \"ogg\"" $MOCK_LOG && grep -q application/json $MOCK_LOG'
check "model sent" 'grep -q "\"model\": \"microsoft/mai-transcribe-2\"" $MOCK_LOG'
check "no language/provider by default" 'grep -q "\"language\": null, \"provider\": null" $MOCK_LOG'
check "done notification" 'grep -q "In Zwischenablage kopiert" $T/notify.log'
check "done notification is a banner (normal urgency)" 'grep -q -- "-u normal -p ✅ In Zwischenablage" $T/notify.log'
check "exactly one notification per dictation" '[[ $(wc -l < $T/notify.log) == 1 ]]'
check "temp files cleaned up" '[[ ! -e $T/run/wayland-stt/rec.wav && ! -e $T/run/wayland-stt/req.json && ! -e $T/run/wayland-stt/busy ]]'
check "recorder stopped" '! pgrep -f "$T/bin/fake-rec" >/dev/null'

echo "2) language option"
reset; STT_LANGUAGE=de "$S"; sleep 1; STT_LANGUAGE=de "$S" >/dev/null
check "language=de sent" 'grep -q "\"language\": \"de\"" $MOCK_LOG'

echo "2b) keyword biasing"
reset; STT_PHRASES=" Vicinae,Ptyxis , ,wayland-stt " "$S"; sleep 1; STT_PHRASES=" Vicinae,Ptyxis , ,wayland-stt " "$S" >/dev/null
check "phrases trimmed, empties dropped, azure phraseList" 'grep -q "\"provider\": {\"options\": {\"azure\": {\"phraseList\": {\"phrases\": \[\"Vicinae\", \"Ptyxis\", \"wayland-stt\"\]}}}}" $MOCK_LOG'
reset; STT_PHRASES=" , " "$S"; sleep 1; STT_PHRASES=" , " "$S" >/dev/null
check "blank phrase list sends no provider options" 'grep -q "\"provider\": null" $MOCK_LOG'

echo "3) wrong API key"
reset; "$S"; sleep 1; OPENROUTER_API_KEY=bad "$S" 2>/dev/null; rc=$?
check "exit code != 0" '[[ $rc != 0 ]]'
check "error notification shows HTTP 401 message" 'grep -q "HTTP 401: No auth credentials" $T/notify.log'
check "clipboard untouched" '[[ ! -e $T/clip ]]'
check "busy lock released" '[[ ! -e $T/run/wayland-stt/busy ]]'
"$S"; sleep 0.3; check "next press starts fresh recording" '[[ -s $T/run/wayland-stt/rec.pid ]]'; "$S" >/dev/null

echo "4) missing API key"
reset; "$S"; sleep 1; OPENROUTER_API_KEY= "$S" 2>/dev/null
check "clear error" 'grep -q "OPENROUTER_API_KEY fehlt" $T/notify.log'

echo "5) empty transcript"
reset; kill $SRV; MOCK_MODE=empty python3 "$ROOT/tests/mock_server.py" $PORT & SRV=$!; sleep 0.5
"$S"; sleep 1; "$S" 2>/dev/null
check "empty transcript reported" 'grep -q "Leeres Transkript" $T/notify.log'
kill $SRV; python3 "$ROOT/tests/mock_server.py" $PORT & SRV=$!; sleep 0.5

echo "6) API unreachable"
reset; "$S"; sleep 1; STT_API_URL=http://127.0.0.1:1/ "$S" 2>/dev/null
check "network error reported" 'grep -q "Netzwerkfehler" $T/notify.log'

echo "7) press during transcription is ignored"
reset; mkdir -p $T/run/wayland-stt; touch $T/run/wayland-stt/busy; "$S"
check "no new recording" '[[ ! -e $T/run/wayland-stt/rec.pid ]] && grep -q "läuft noch" $T/notify.log'
touch -d "-10 min" $T/run/wayland-stt/busy; "$S"; sleep 0.3
check "stale lock (>3 min) ignored" '[[ -s $T/run/wayland-stt/rec.pid ]]'; "$S" >/dev/null

echo "8) max-duration safety stop still transcribes"
reset; STT_MAX_SECONDS=1 "$S"; sleep 2.5
check "recorder auto-stopped" '! kill -0 $(cat $T/run/wayland-stt/rec.pid) 2>/dev/null'
"$S"; check "leftover audio transcribed" '[[ -s $T/clip ]]'
"$S"; sleep 1; "$S"
check "next notification replaces the previous one (-r id)" 'grep -q -- "-r 7" $T/notify.log'

echo "9) stale pid without audio -> starts new recording"
reset; mkdir -p $T/run/wayland-stt; echo 999999 > $T/run/wayland-stt/rec.pid; "$S"; sleep 0.3
check "new recording started" '[[ $(cat $T/run/wayland-stt/rec.pid) != 999999 ]]'; "$S" >/dev/null

echo; echo "$pass passed, $fail failed"; exit $((fail > 0))
