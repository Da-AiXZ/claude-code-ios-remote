#!/usr/bin/env bash
set -euo pipefail

# 用法：package-ipa.sh <.app路径> <输出ipa路径>
APP_PATH="$1"
OUT_IPA="$2"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: .app not found at $APP_PATH" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
PAYLOAD_DIR="$WORK_DIR/Payload"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

# ad-hoc 签名 app 包（TrollStore 会接受）。
codesign --force --deep --sign - "$PAYLOAD_DIR/$(basename "$APP_PATH")"

# 打包成 .ipa
(cd "$WORK_DIR" && zip -r -q "$OUT_IPA" Payload)
echo "Packaged IPA: $OUT_IPA"
