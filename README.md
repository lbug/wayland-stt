# wayland-stt

Push-to-toggle dictation for Ubuntu/GNOME on Wayland.
Press **F9** → recording starts. Press **F9** again → audio goes to OpenRouter
(`microsoft/mai-transcribe-2`), the text lands in the clipboard, a notification confirms it.

One ~80-line bash script, no daemon, no background process while idle.

## Why another dictation tool?

Most Linux dictation tools run local models and type text via `ydotool`/uinput, which needs
root or the `input` group plus a background daemon, and global hotkeys are often fragile on
GNOME Wayland. wayland-stt takes the opposite trade-off:

- **Native GNOME shortcut** — no key grabbing, no autostart, works on Wayland as designed.
- **Clipboard, not typing** — no extra privileges; paste wherever you want with Ctrl+V.
- **Cloud model via OpenRouter** — top-tier accuracy (60 languages, code switching), ~1 s latency,
  swap models with one config line. Audio leaves your machine; if you need offline, use
  a local-model tool such as Speech Note or nerd-dictation instead.

Tested on Ubuntu 26.04 / GNOME 50 (Wayland). Requires PipeWire, `curl`, `jq`, `wl-clipboard`,
`libnotify`; `ffmpeg` is optional (Opus compression, ~10× smaller uploads).

## How it works

- **Hotkey:** a GNOME custom shortcut runs `stt-toggle`. Wayland doesn't let apps grab global
  keys, so the compositor's own shortcut system is the native way — and it needs no autostart,
  GNOME restores it on login.
- **Recording:** `pw-record` (PipeWire), 16 kHz mono, encoded to Opus before upload (~3 KB/s).
- **API:** `POST https://openrouter.ai/api/v1/audio/transcriptions` (JSON, base64 audio).
- **Clipboard:** `wl-copy`. **Notification:** a banner when the text is ready (or on error); each one replaces the previous, so the tray holds a single entry. While recording, GNOME's own mic indicator shows in the top bar.
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
| `STT_PHRASES` | empty | comma-separated terms to bias recognition towards (see below) |
| `STT_MAX_SECONDS` | `600` | recording safety stop |

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

Note: F9 is then taken globally. It is unbound in GNOME and rarely used by apps.

## Test

```bash
tests/run.sh    # offline: fake recorder/clipboard/notify + mock API
```

## License

MIT
