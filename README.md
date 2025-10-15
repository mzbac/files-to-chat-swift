# files-to-chat-swift

Swift CLI for macOS that turns local plain-text sources into a conversational context for MLX language models. It ingests `.txt` (and optionally PDF/markdown/code), builds a single prompt, primes an MLX-backed chat session, and streams answers in the terminal. Prompt KV caches are persisted on disk so repeated runs warm instantly.

---

## Highlights

- **Apple Silicon native**: depends only on MLX + Vision/PDFKit, compiled via Xcode toolchain.
- **Streaming UX**: type questions and watch responses stream token-by-token.
- **Prompt caching**: stores KV tensors per document fingerprint (`8bit` by default, `bf16` optional).
- **Flexible I/O**: point at files or directories, include/exclude extensions, OCR PDFs.

---

## Requirements

- macOS with Apple Silicon (Metal-enabled)
- Xcode 16+ (command-line tools)
- MLX runtime (pulled automatically through SwiftPM)

---

## Build & Test

```bash
xcodebuild -scheme files-to-chat-swift \
           -destination 'platform=OS X' \
           build -derivedDataPath .xcodebuild

xcodebuild -scheme files-to-chat-swift \
           -destination 'platform=OS X' \
           test -derivedDataPath .xcodebuild
```

---

## Usage

```bash
# Show usage and options
.xcodebuild/Build/Products/Debug/files-to-chat-swift --help

# Basic run with the default model
MODEL_ID="mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510" \
.xcodebuild/Build/Products/Debug/files-to-chat-swift sample_docs

# Include markdown and Swift files, exclude logs
MODEL_ID="..." \
.xcodebuild/Build/Products/Debug/files-to-chat-swift \
  --ext txt,md,swift --exclude log,tmp docs/

# Enable PDF OCR (requires Vision/PDFKit)
MODEL_ID="..." \
.xcodebuild/Build/Products/Debug/files-to-chat-swift --ext pdf sample_docs

# Persist prompt cache as bf16 instead of 8-bit
MODEL_ID="..." \
.xcodebuild/Build/Products/Debug/files-to-chat-swift --cache-precision bf16 sample_docs
```

- Answers stream live; type `exit` to quit.
- Progress messages show document prep, model load time, and cache usage.

---

## Prompt Cache Details

First run warms the model with your documents; subsequent runs reuse the saved KV tensors if the fingerprint matches.

- Location: `~/.cache/files-to-chat-swift/<MODEL_ID>/prompt.<hash>.<8bit|bf16>.safetensors`
- `--cache-precision 8bit` (default) stores quantized caches for small footprint.
- `--cache-precision bf16` stores full-precision caches (larger files, no quantization).
- Corrupt or mismatched cache files are removed automatically and regenerated.

---

## Command-Line Flags

| Flag / Option             | Description                                                        |
|---------------------------|--------------------------------------------------------------------|
| `-h`, `--help`            | Print usage information                                            |
| `-e`, `--ext EXT`         | Include extensions (repeatable, comma-separated)                   |
| `-x`, `--exclude EXT`     | Exclude extensions (repeatable, comma-separated)                   |
| `--cache-precision P`     | Choose `8bit` (default) or `bf16` prompt caches                    |


Environment variable `MODEL_ID` selects the MLX model (default: `mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510`).

---

## Troubleshooting

- **Cache mismatch**: delete the `.safetensors` file in the cache directory and rerun.
- **OCR issues**: ensure Vision/PDFKit are available; exclude PDFs if OCR isn’t desired.
- **Slow start**: first run must warm the model; afterward the cache drastically speeds up initialization.

---

## Development Notes

- Core code lives in `Sources/AppCore/**`, CLI entry point is `Sources/App/Main.swift`.
- Tests reside under `Tests/AppTests`.
- Streaming and caching rely on MLXLMCommon’s chat utilities; inspect `PersistentChatSession` for advanced behavior.

Happy chatting! ✨
