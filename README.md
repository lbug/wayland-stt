# wayland-stt

Push-to-toggle dictation for Ubuntu/GNOME on Wayland.
Press **F9** → recording starts. Press **F9** again → audio goes to OpenRouter
(`microsoft/mai-transcribe-2`), the text lands in the clipboard, a notification confirms it.
**Shift+F9** does the same fully offline (see [Private mode](#private-mode-shiftf9)).

One bash script, no daemon, no background process while idle.

## Why another dictation tool?

Most Linux dictation tools run local models and type text via `ydotool`/uinput, which needs
root or the `input` group plus a background daemon, and global hotkeys are often fragile on
GNOME Wayland. wayland-stt takes the opposite trade-off:

- **Native GNOME shortcut** — no key grabbing, no autostart, works on Wayland as designed.
- **Clipboard, not typing** — no extra privileges; paste wherever you want with Ctrl+V.
- **Cloud model via OpenRouter** — top-tier accuracy (60 languages, code switching), ~1 s latency,
  swap models with one config line. Audio leaves your machine, except in the optional
  [private mode](#private-mode-shiftf9) (Shift+F9), which runs Parakeet locally.

Tested on Ubuntu 26.04 / GNOME 50 (Wayland). Requires PipeWire, `curl`, `jq`, `wl-clipboard`,
`libnotify`; `ffmpeg` is optional (Opus compression, ~10× smaller uploads) and so is
[`nemo-speech`](https://github.com/NVIDIA/NeMo-Speech.cpp) for the private mode.

## How it works

- **Hotkey:** a GNOME custom shortcut runs `stt-toggle`. Wayland doesn't let apps grab global
  keys, so the compositor's own shortcut system is the native way — and it needs no autostart,
  GNOME restores it on login.
- **Recording:** `pw-record` (PipeWire), 16 kHz mono, encoded to Opus before upload (~3 KB/s).
- **API:** `POST https://openrouter.ai/api/v1/audio/transcriptions` (JSON, base64 audio). Private mode skips this and calls `nemo-speech` instead.
- **Clipboard:** `wl-copy`. **Notification:** a banner when the text is ready (or on error); each one replaces the previous, so the tray holds a single entry. While recording, GNOME's own mic indicator shows in the top bar.
- Safety: recording auto-stops after `STT_MAX_SECONDS` (600); presses during transcription are ignored. Rate limits (429) and server errors (5xx) are retried automatically, with a notification, so a long dictation isn't lost to a short throttle.

## Install

```bash
sudo apt install wl-clipboard      # only missing dependency on a stock Ubuntu 26.04
./install.sh                       # F9 + Shift+F9 (private mode); or: ./install.sh '<Super>h' '<Super><Shift>h'
$EDITOR ~/.config/wayland-stt/config   # set OPENROUTER_API_KEY
```

`install.sh` symlinks the script, so edits in this repo are live on the next key press;
rerun it only to change the keys. Uninstall: `./install.sh --uninstall`.

## Configuration

All settings live in `~/.config/wayland-stt/config` (re-read on every key press, no reinstall):

| Variable | Default | |
|---|---|---|
| `OPENROUTER_API_KEY` | — | required |
| `STT_MODEL` | `microsoft/mai-transcribe-2` | any OpenRouter transcription model |
| `STT_LANGUAGE` | auto-detect | ISO-639-1, e.g. `de` |
| `STT_PHRASES` | empty | comma-separated terms to bias recognition towards (see below) |
| `STT_MAX_SECONDS` | `600` | recording safety stop |
| `STT_RETRIES` | `5` | retries on HTTP 429/5xx; waits `Retry-After` (max 60 s), else 2, 4, 8, … s |
| `STT_LOCAL_MODEL` | `parakeet-tdt` | model for the private mode (`nemo-speech model list`) |
| `STT_LOCAL_BIN` | `nemo-speech` | binary used by the private mode |
| `STT_FALLBACK_MODEL` | `openai/gpt-4o-mini-transcribe` | tried (with its own retries) when the main model still returns 429/5xx; set empty to disable. `STT_PHRASES` only biases MAI models, so the fallback ignores it |

**Keyword biasing.** Names and jargon you dictate often come out right when listed:

```
STT_PHRASES="Pydantic AI, ColBERT, vLLM, Qdrant, Langfuse"
```

Real-voice test (German sentences full of AI jargon, same speaker, same pronunciation):

| | without list | with list |
|---|---|---|
| Pydantic AI | Pedantic AI | Pydantic AI |
| Reranking mit ColBERT | Ranking mit Colbert | Reranking mit ColBERT |
| vLLM | VLLM | vLLM |
| pgvector und Qdrant | pgvector und Qutrend | pgvector und Qdrant |
| Evals … Ragas | Events … Regas | Evals … Ragas |

8 jargon errors → 0. Common acronyms (RLHF, DPO, GGUF, KV-Cache, MCP) were already right without a list.
Sent as Azure `phraseList`, so it works with `microsoft/mai-transcribe-*`; other models ignore it.

Available models:

```bash
curl -s "https://openrouter.ai/api/v1/models?output_modalities=transcription" | jq -r '.data[].id'
```

A pre-commit hook (`.githooks/`, enabled by `install.sh`) blocks commits containing a real API key.

Note: F9 and Shift+F9 are then taken globally. Both are unbound in GNOME and rarely used by apps.

## Private mode (Shift+F9)

`stt-toggle --local` transcribes on your machine with [NeMo-Speech.cpp](https://github.com/NVIDIA/NeMo-Speech.cpp)
(`nemo-speech`, model `parakeet-tdt` = Parakeet-TDT-0.6B-v3). Nothing is uploaded, and there is
no retry or fallback to the cloud: if the local run fails you get an error. The mode is fixed by the
key that *starts* the recording; stopping with either key uses it.

```bash
curl -fsSL https://github.com/NVIDIA/NeMo-Speech.cpp/raw/main/scripts/install.sh | sh
nemo-speech pull parakeet-tdt      # 681 MiB, once
```

Measured on an RTX 3090 with a 55 s German dictation: about 0.8 s including model load (CPU: ~4 s).
It is accurate on prose and numbers but weaker on jargon than MAI with `STT_PHRASES`
(14.7 % vs 5.4 % word error rate on one recording with 13 technical terms; without the phrase list MAI
reached 10.1 %). In 76 s of free speech the differences were mostly proper nouns ("Open Router", "ParaKey"). `nemo-speech`'s `--speech-context` had no effect on Parakeet in v0.2.0, so
`STT_PHRASES` does not apply to the local mode. `STT_LOCAL_MODEL` selects another `nemo-speech` model.

## Test

```bash
tests/run.sh    # offline: fake recorder/clipboard/notify + mock API
```

## License

MIT
