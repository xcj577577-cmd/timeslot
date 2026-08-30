#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
DERIVED_DIR=${1:-$(mktemp -d /tmp/timeslot-release-verify.XXXXXX)}
APP_PATH="$DERIVED_DIR/Build/Products/Release/时隙.app"
APPEX_PATH="$APP_PATH/Contents/PlugIns/CountdownDesktopWidget.appex"
APP_BINARY="$APP_PATH/Contents/MacOS/时隙"
WIDGET_BINARY="$APPEX_PATH/Contents/MacOS/CountdownDesktopWidget"
VERIFY_TMP=$(mktemp -d /tmp/timeslot-signing-verify.XXXXXX)

cleanup() {
    rm -rf "$VERIFY_TMP"
}
trap cleanup EXIT

fail() {
    print -u2 -- "验证失败：$1"
    exit 1
}

assert_plist_value() {
    local plist=$1
    local key=$2
    local expected=$3
    local actual
    actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null) \
        || fail "$plist 缺少 $key"
    [[ "$actual" == "$expected" ]] \
        || fail "$plist 的 $key 为 $actual，预期 $expected"
}

cd "$PROJECT_ROOT"

swift test --disable-sandbox

xcodebuild \
    -project CountdownWidget.xcodeproj \
    -scheme CountdownWidget \
    -configuration Release \
    -derivedDataPath "$DERIVED_DIR" \
    build \
    -quiet

[[ -d "$APP_PATH" ]] || fail "未生成时隙.app"
[[ -d "$APPEX_PATH" ]] || fail "主应用未嵌入桌面小组件扩展"
[[ -x "$APP_BINARY" ]] || fail "主应用可执行文件缺失"
[[ -x "$WIDGET_BINARY" ]] || fail "小组件可执行文件缺失"

lipo "$APP_BINARY" -verify_arch arm64 x86_64 >/dev/null \
    || fail "主应用不是 arm64 + x86_64 通用二进制"
lipo "$WIDGET_BINARY" -verify_arch arm64 x86_64 >/dev/null \
    || fail "小组件不是 arm64 + x86_64 通用二进制"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH" > "$VERIFY_TMP/app-entitlements.plist" 2>/dev/null
codesign -d --entitlements :- "$APPEX_PATH" > "$VERIFY_TMP/widget-entitlements.plist" 2>/dev/null

plutil -lint "$VERIFY_TMP/app-entitlements.plist" >/dev/null
plutil -lint "$VERIFY_TMP/widget-entitlements.plist" >/dev/null
assert_plist_value "$VERIFY_TMP/app-entitlements.plist" "com.apple.security.app-sandbox" "true"
assert_plist_value "$VERIFY_TMP/widget-entitlements.plist" "com.apple.security.app-sandbox" "true"
assert_plist_value \
    "$VERIFY_TMP/app-entitlements.plist" \
    "com.apple.security.application-groups:0" \
    "4FKFDX48HX.com.xianz.countdownwidget.shared"
assert_plist_value \
    "$VERIFY_TMP/widget-entitlements.plist" \
    "com.apple.security.application-groups:0" \
    "4FKFDX48HX.com.xianz.countdownwidget.shared"

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" \
    "$VERIFY_TMP/app-entitlements.plist" >/dev/null 2>&1; then
    fail "主应用意外声明了网络客户端权限"
fi
if /usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" \
    "$VERIFY_TMP/widget-entitlements.plist" >/dev/null 2>&1; then
    fail "小组件意外声明了网络客户端权限"
fi

APP_PRIVACY="$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
WIDGET_PRIVACY="$APPEX_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
[[ -f "$APP_PRIVACY" ]] || fail "主应用缺少 PrivacyInfo.xcprivacy"
[[ -f "$WIDGET_PRIVACY" ]] || fail "小组件缺少 PrivacyInfo.xcprivacy"
plutil -lint "$APP_PRIVACY" >/dev/null
plutil -lint "$WIDGET_PRIVACY" >/dev/null
assert_plist_value "$APP_PRIVACY" "NSPrivacyTracking" "false"
assert_plist_value "$WIDGET_PRIVACY" "NSPrivacyTracking" "false"

assert_plist_value "$APP_PATH/Contents/Info.plist" "CFBundleShortVersionString" "2.3.0"
assert_plist_value "$APP_PATH/Contents/Info.plist" "CFBundleVersion" "53"
assert_plist_value \
    "$APPEX_PATH/Contents/Info.plist" \
    "NSExtension:NSExtensionPointIdentifier" \
    "com.apple.widgetkit-extension"

print -- "Release 验证通过：$APP_PATH"
