#!/bin/zsh
cd "${0:A:h}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export HF_HOME="$PWD/data/models"
export SHADOW_PORT="${SHADOW_PORT:-8765}"
if curl --silent --fail "http://127.0.0.1:$SHADOW_PORT/api/status" | /usr/bin/grep -q '"local":true'; then
  open "http://127.0.0.1:$SHADOW_PORT"
  exit 0
fi
if [[ ! -x .venv/bin/python ]]; then
  PYTHON="$(command -v python3.12 || command -v python3.13 || command -v python3)"
  "$PYTHON" -m venv .venv || exit 1
fi
if ! .venv/bin/python -c 'import fastapi, uvicorn, faster_whisper, scipy, multipart, yt_dlp' 2>/dev/null; then
  .venv/bin/python -m pip install -r requirements.txt || { echo 'Setup needs an internet connection. Please try again.'; read; exit 1; }
fi
if ! command -v ffmpeg >/dev/null; then
  echo 'FFmpeg is needed to read audio and video files. Install it with Homebrew: brew install ffmpeg'
  read; exit 1
fi
if [[ -x /usr/bin/say ]]; then .venv/bin/python create_sample.py; fi
if [[ "${SHADOW_NO_BROWSER:-0}" != 1 ]]; then
(.venv/bin/python -c 'import time,urllib.request,webbrowser,os
url="http://127.0.0.1:"+os.environ.get("SHADOW_PORT","8765")
for _ in range(40):
 try:
  urllib.request.urlopen(url+"/api/status",timeout=1)
  webbrowser.open(url)
  break
 except Exception: time.sleep(.25)' &)
fi
echo 'Shadow Studio is running locally. Keep this window open. Press Control-C to stop.'
.venv/bin/python app.py
