# wayland-stt

Push-to-toggle dictation for Ubuntu/GNOME on Wayland.
Press **F9** → recording starts. Press **F9** again → audio goes to OpenRouter
(`microsoft/mai-transcribe-2`), the text lands in the clipboard, a notification confirms it.

One ~90-line bash script, no daemon, no background process while idle.

## How it works

- **Hotkey:** a GNOME custom shortcut runs `stt-toggle`. Wayland doesn't let apps grab global
  keys, so the compositor's own shortcut system is the native way — and it needs no autostart,
  GNOME restores it on login.
- **Recording:** `pw-record` (PipeWire), 16 kHz mono, encoded to Opus before upload (~3 KB/s).
- **API:** `POST https://openrouter.ai/api/v1/audio/transcriptions` (multipart, OpenAI-compatible).
- **Clipboard:** `wl-copy`. **Notification:** only when the text is ready (or on error); while recording, GNOME's own mic indicator shows in the top bar.
- Safety: recording auto-stops after `STT_MAX_SECONDS` (600); presses during transcription are ignored.

## Install

```bash
sudo apt install wl-clipboard      # only missing dependency on a stock Ubuntu 26.04
./install.sh                       # or: ./install.sh '<Super>h'
$EDITOR ~/.config/wayland-stt/config   # set OPENROUTER_API_KEY
```

`install.sh` symlinks the script, so edits in this repo are live on the next key press;
rerun it only to change the key. Uninstall: `./install.sh --uninstall`.

## Configuration

All settings live in `~/.config/wayland-stt/config` (re-read on every key press, no reinstall):

| Variable | Default | |
|---|---|---|
| `OPENROUTER_API_KEY` | — | required |
| `STT_MODEL` | `microsoft/mai-transcribe-2` | any OpenRouter transcription model |
| `STT_LANGUAGE` | auto-detect | ISO-639-1, e.g. `de` |
| `STT_MAX_SECONDS` | `600` | recording safety stop |

Available models:

```bash
curl -s "https://openrouter.ai/api/v1/models?output_modalities=transcription" | jq -r '.data[].id'
```

A pre-commit hook (`.githooks/`, enabled by `install.sh`) blocks commits containing a real API key.

Note: F9 is then taken globally. It is unbound in GNOME and rarely used by apps.

## Test

```bash
tests/run.sh    # offline: fake recorder/clipboard/notify + mock API
```
