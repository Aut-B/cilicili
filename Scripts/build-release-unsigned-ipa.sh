#!/bin/zsh
set -euo pipefail

# Build a production Release IPA without signing it. The resulting archive is
# intended for a third-party sideloader that applies its own signature.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/build/ReleaseUnsignedDerivedData"
EXPORT_DIR="$ROOT_DIR/build/release-unsigned-ipa"
LOG_DIR="$ROOT_DIR/build/logs"
LOG_PATH="$LOG_DIR/release-unsigned-ipa.log"
IPA_PATH="$EXPORT_DIR/bili-release-unsigned.ipa"

mkdir -p "$EXPORT_DIR" "$LOG_DIR"

echo "Building Release (unsigned, device) ..."

build_app() {
  local optimization_level="$1"
  local log_path="$2"
  xcodebuild build \
    -project "$ROOT_DIR/bili.xcodeproj" \
    -scheme bili \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    OTHER_SWIFT_FLAGS="-Xfrontend -solver-expression-time-threshold=10000" \
    SWIFT_OPTIMIZATION_LEVEL="$optimization_level" \
    ENABLE_DEBUG_DYLIB=NO > "$log_path" 2>&1
}

OPTIMIZED_LOG="$LOG_DIR/release-unsigned-ipa.optimized-attempt.log"

# 优先使用 -O。-Onone 不做任何优化，在 A9 等老机型上详情页滚动与页面加载会明显卡顿；
# 但 Xcode 26 的 SIL 优化在 -O 下曾触发 swift-frontend 段错误，故失败时回退到 -Onone 保证出包。
echo "Attempt 1: SWIFT_OPTIMIZATION_LEVEL=-O ..."
if build_app "-O" "$OPTIMIZED_LOG"; then
  cp "$OPTIMIZED_LOG" "$LOG_PATH"
  echo "Optimized (-O) build succeeded."
else
  echo "Optimized (-O) build failed, falling back to -Onone." >&2
  echo "=== -O 尝试：error 汇总（去重）===" >&2
  grep -E ": error:" "$OPTIMIZED_LOG" | sort -u >&2 || true
  echo "=== -O 尝试：日志尾部 ===" >&2
  tail -40 "$OPTIMIZED_LOG" >&2

  echo "Attempt 2: SWIFT_OPTIMIZATION_LEVEL=-Onone ..."
  if ! build_app "-Onone" "$LOG_PATH"; then
    echo "Build failed. Log: $LOG_PATH" >&2
    echo "=== 全部 error 汇总（去重）===" >&2
    grep -E ": error:" "$LOG_PATH" | sort -u >&2 || true
    echo "=== 日志尾部 ===" >&2
    tail -80 "$LOG_PATH" >&2
    exit 1
  fi

  {
    echo ""
    echo "================================================================"
    echo "注意：-O 优化构建失败，本次产物为 -Onone（未优化）回退构建。"
    echo "================================================================"
    echo "=== -O 尝试：error 汇总（去重）==="
    grep -E ": error:" "$OPTIMIZED_LOG" | sort -u || true
    echo "=== -O 尝试：日志尾部 ==="
    tail -60 "$OPTIMIZED_LOG" || true
  } >> "$LOG_PATH"
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-iphoneos/bili.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but app bundle not found: $APP_PATH" >&2
  exit 1
fi

zsh "$ROOT_DIR/Scripts/remove-empty-frameworks.sh" "$APP_PATH"

echo "Packaging IPA ..."
PAYLOAD_DIR="$EXPORT_DIR/Payload"
rm -rf "$PAYLOAD_DIR" "$IPA_PATH"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

(cd "$EXPORT_DIR" && zip -qry "$IPA_PATH" Payload)
rm -rf "$PAYLOAD_DIR"

echo "Unsigned Release IPA: $IPA_PATH"
echo "Build log: $LOG_PATH"
