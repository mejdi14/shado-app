# Shadow Studio

Local English shadowing app for one user on one Mac. Import a YouTube link or an audio/video file, transcribe it locally, split it into phrases, then record takes and get practice feedback (word accuracy, pace & rhythm, intonation). No accounts, API keys or cloud audio processing. See `README.md` for the user-facing description.

## Working rules

- **Do not test the app yourself.** The user does all testing. Do not start the server, run the launcher, open the app in a browser or preview tool, take screenshots, record audio, import videos, or run end-to-end checks. Make the change, say what you changed and what the user should try, and stop.
- A syntax-only check is fine and not "testing": `.venv/bin/python -m py_compile app.py`. Do not go beyond it unless asked.
- Do not claim something works or is verified. Say it is untested and describe what to check.
- Keep changes small and scoped to the request. Don't refactor, rename or reformat unrelated code.
- Ask before adding dependencies, changing the port, or changing where data is stored.
- Do not create a git repo, commits or branches unless asked (this folder is not a git repository).

## Stack and layout

- Backend: Python 3.12+, FastAPI + uvicorn, single file `app.py`. Transcription with faster-whisper (English `base` model), audio with FFmpeg, scipy/numpy for analysis, yt-dlp for YouTube.
- Frontend: plain HTML/CSS/JS in `static/` (no build step, no framework). `app.js`, `index.html` and `style.css` are minified or dense, one-line-per-function style. Match that style when editing; read the surrounding lines before changing them.
- `create_sample.py`: builds the built-in guided sample with the macOS `say` command.
- `Start Shadow Studio.command`: launcher. Creates `.venv`, installs `requirements.txt`, checks FFmpeg, starts `app.py`.
- `data/`: user lessons, recordings and cached model files (`data/models`). **Never delete, reset or modify anything in `data/`.** It is the user's practice history.
- `.venv/`, `__pycache__/`: generated. Don't edit.

## Running (for the user, not for you)

Double-click `Start Shadow Studio.command`, or run `.venv/bin/python app.py`. The app serves at `http://127.0.0.1:8765` (override with `SHADOW_PORT`).

## Behaviour that must stay true

- **Local only.** The server must keep accepting only `127.0.0.1:PORT` / `localhost:PORT` hosts. State-changing requests require the `x-shadow-token` header. Keep the CSP and security headers in the `local_only` middleware. Don't bind to `0.0.0.0` or add external services.
- **Privacy.** No audio, transcripts or recordings leave the Mac. The only network use is YouTube imports and the one-time Hugging Face model download.
- **Import limits** (keep these in sync across files when changed):
  - Max length: 30 minutes. `app.py` (`16000*1800` in `finish_import`, `>1800` in the yt-dlp `limit` filter, `duration=1801` in `upload`), the hint text in `static/index.html`, and `README.md`.
  - Max file size: 150 MB. `app.py` (`max_filesize` and the upload size check), `static/app.js` import form check, `static/index.html` file-drop label, and `README.md`.
- **Phrase length:** edited phrases must be 30 seconds or less (`app.py` `edit`, hint in `static/index.html`). Recorded takes are capped at 34 seconds (`static/app.js` auto-stop, `README.md`).
- **Honest feedback.** Scores are practice heuristics, not validated pronunciation grades. Keep that wording in the UI and README; don't present them as assessments.
- **YouTube:** no cookies, no logins. If a link fails, the fallback is file upload.
- **Jobs run one at a time** (`ThreadPoolExecutor(max_workers=1)`) because transcription is heavy. Don't raise this without asking.

## Editing conventions

- When a user-visible limit or behaviour changes, update the UI text in `static/index.html`, error messages in `app.py`, and `README.md` together.
- Error messages are plain, friendly sentences shown directly to the user.
- Python: match the existing compact style in `app.py`. No new files or abstractions for one-off changes.
- Don't add comments that restate the code.

## When finishing a task

Reply briefly: what changed (files), anything the user needs to do (e.g. restart the server), and what to test. Mention any limit or side effect you noticed but didn't change.
