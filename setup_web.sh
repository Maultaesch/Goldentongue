#!/usr/bin/env bash
# Prepares the Flutter project for the web build, Cloudflare Pages and phone installation (PWA).
# Usage: scripts/setup_web.sh https://api.example.com
set -euo pipefail
API_ORIGIN="${1:?usage: scripts/setup_web.sh https://api.example.com}"

flutter create --platforms=ios,android,web --org io.goldentongue . > /dev/null

cp web_extras/_redirects web/_redirects
sed "s#__API_ORIGIN__#${API_ORIGIN}#g" web_extras/_headers > web/_headers
cp web_extras/manifest.json web/manifest.json
cp web_extras/favicon.png web/favicon.png
mkdir -p web/icons && cp web_extras/icons/*.png web/icons/

# Phone-friendly page shell: title, safe areas, dark theme colour, iOS "Add to Home Screen" support.
python3 - <<'PY'
import re
p = 'web/index.html'
s = open(p, encoding='utf-8').read()
s = re.sub(r'<title>[^<]*</title>', '<title>GoldenTongue</title>', s)
s = re.sub(r'<meta name="viewport"[^>]*>', '', s)
tags = '''  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#000000">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="GoldenTongue">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <style>html,body{background:#000;margin:0}</style>
'''
if 'viewport-fit=cover' not in s:
    s = s.replace('<head>', '<head>\n' + tags, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
echo "Web files ready (headers use ${API_ORIGIN})."
