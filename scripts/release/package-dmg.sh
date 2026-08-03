#!/bin/sh
set -eu

fail() {
  printf 'package-dmg: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: package-dmg.sh --app Keep3.app --version X.Y.Z --output-dir DIR

The first verified DMG becomes the canonical candidate. Re-running with the
same output directory verifies and reuses those bytes instead of rebuilding.
USAGE
  exit 64
}

app=''
version=''
output_dir=''
while test "$#" -gt 0; do
  case "$1" in
    --app) app=${2-}; shift 2 ;;
    --version) version=${2-}; shift 2 ;;
    --output-dir) output_dir=${2-}; shift 2 ;;
    --help|-h) usage ;;
    *) usage ;;
  esac
done

test -d "$app" || fail "--app must name an existing app bundle"
printf '%s\n' "$version" | /usr/bin/ruby -e '
  value = STDIN.read.strip
  exit(value.match?(/\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/) ? 0 : 1)
' || fail "--version must be MAJOR.MINOR.PATCH"
test -n "$output_dir" || fail "--output-dir is required"
mkdir -p "$output_dir"

dmg="$output_dir/Keep3-$version.dmg"
digest_file="$dmg.sha256"
if test -e "$dmg" || test -e "$digest_file"; then
  test -f "$dmg" && test -f "$digest_file" \
    || fail "candidate DMG and digest sidecar must exist together"
  expected=$(tr -d '[:space:]' < "$digest_file")
  actual=$(shasum -a 256 "$dmg" | awk '{print $1}')
  test "$actual" = "$expected" || fail "canonical candidate digest changed"
  printf '%s\n' "$dmg"
  exit 0
fi

temporary_directory=$(mktemp -d /tmp/keep3-package-dmg-XXXXXX)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
staging="$temporary_directory/staging"
mkdir -p "$staging"
/usr/bin/ditto "$app" "$staging/Keep3.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/首次打开 Keep3.html" <<'HTML'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>首次打开 Keep3</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
    body { max-width: 720px; margin: 0 auto; padding: 48px 24px 72px; color: #17141c; background: #f4efe6; line-height: 1.7; }
    header { padding-bottom: 28px; border-bottom: 1px solid #d7cfc3; }
    h1 { margin: 0 0 12px; font-size: clamp(2rem, 8vw, 3.5rem); line-height: 1.05; letter-spacing: -0.05em; }
    header p { margin: 0; color: #655f69; }
    ol { margin: 0; padding: 28px 0; list-style: none; counter-reset: steps; }
    li { display: grid; padding: 24px 0; grid-template-columns: 48px 1fr; border-bottom: 1px solid #d7cfc3; counter-increment: steps; }
    li::before { color: #b33a2c; font: 700 0.75rem ui-monospace, monospace; content: "0" counter(steps); }
    strong { display: block; margin-bottom: 4px; font-size: 1.05rem; }
    p { margin: 0; }
    footer { color: #655f69; font-size: 0.92rem; }
    a { color: #8e2e23; font-weight: 650; }
  </style>
</head>
<body>
  <header>
    <h1>首次打开 Keep3</h1>
    <p>当前版本未经过 Apple Developer ID 公证，因此 macOS 会在第一次打开时要求你手动确认。</p>
  </header>
  <ol>
    <li><div><strong>先拖入“应用程序”</strong><p>将 Keep3.app 拖到旁边的 Applications 文件夹。</p></div></li>
    <li><div><strong>使用 Control-click 打开</strong><p>在 Finder → 应用程序中，按住 Control 点击 Keep3，选择“打开”。</p></div></li>
    <li><div><strong>必要时在系统设置中确认</strong><p>如果仍被拦截，前往“系统设置 → 隐私与安全性”，点击“仍要打开”。</p></div></li>
  </ol>
  <footer>
    <p>这不会关闭 Gatekeeper，也不需要运行额外的终端命令。请只打开从 Keep3 官方发布渠道下载并完成校验的版本。</p>
    <p><a href="https://support.apple.com/102445">查看 Apple 官方说明</a></p>
  </footer>
</body>
</html>
HTML

temporary_dmg="$temporary_directory/Keep3-$version.dmg"
hdiutil create -quiet \
  -fs HFS+ \
  -format UDZO \
  -volname "Keep3 $version" \
  -srcfolder "$staging" \
  "$temporary_dmg"
test -f "$temporary_dmg" || fail "hdiutil did not produce a DMG"
mv "$temporary_dmg" "$dmg"
digest=$(shasum -a 256 "$dmg" | awk '{print $1}')
printf '%s\n' "$digest" > "$digest_file"
printf '%s\n' "$dmg"
