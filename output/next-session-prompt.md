Coordinate and implement the Shadow Studio missing-features roadmap without stopping for questions. You are the coordinator: make every product and technical decision yourself using the decisions below, launch one implementation session per feature, review each result, and keep going until the roadmap is done. I will test everything myself at the end.

Project root: /Users/mejdihafiene/StudioProjects/Shadow Studio
Mobile repo: /Users/mejdihafiene/StudioProjects/Shadow Studio/shado mobile (app in kmp-shadow-app/)
Feature report (source of truth for scope, evidence and item IDs): output/shadow-studio-missing-features.md (PDF: output/pdf/shadow-studio-missing-features.pdf)
Earlier reports: output/pdf/shadow-studio-product-audit.pdf, output/pdf/shadow-studio-mobile-roadmap.pdf
Baseline: desktop commit 3d1b8bf, mobile commit 74be04d.

## 1. Owner decisions (already made; do not ask again)

- D1 Accounts: add optional sign-in on iOS and Android only, using the existing Supabase template code (email and password with confirmation and reset, Google, Sign in with Apple). An account is never required to practise. It only links a Pro purchase across devices. No audio, transcripts, takes or lesson data are ever uploaded. The Mac app, browser and engine stay account-free. Remove the template author's hosted Supabase URL and key: read Supabase URL, anon key and Google client IDs from build configuration (Gradle properties, iOS xcconfig) with empty defaults, so the app works without them and hides sign-in when they are missing. Implement real in-app account deletion through a Supabase edge function. Handle the login deep link on both platforms.
- D2 Payments: a "Pro" option on iOS and Android through StoreKit 2 and Google Play Billing (monthly and yearly subscriptions plus a lifetime unlock). Product IDs come from build configuration with placeholder defaults. Everything that exists today stays free. Pro unlocks only new features from this roadmap: progress over time (F7) and export (F4). Build a shared entitlement source with offline grace, a plan screen, restore purchases, a manage-subscription link and terms/privacy links. When signed in, record the verified entitlement through a Supabase edge function that verifies receipts server-side. If store credentials are not configured, the function returns "not configured" and the app relies on the local store entitlement; never trust a client-asserted entitlement on the server. Remove the template Stripe client screens and code from both apps. Leave the Supabase Stripe functions and tables in place but unused, and say so in SETUP.md. The Mac app and browser stay free.
- D3 Phones: keep the iOS Simulator and Android (emulator or USB through adb reverse) only. No LAN or Wi-Fi changes and no pairing. Keep the loopback default.
- D4 Analytics: none. Remove PostHog completely from both apps: manifest meta-data, Info.plist keys, SDK dependencies, trackers, screen names and their tests.
- D5 Distribution: prepare release configuration without secrets.
  - Android release signing reads from local, uncommitted properties. Minify is on, with keep rules for serialization, Ktor and Supabase. Cleartext is allowed only for 127.0.0.1 and localhost through a network security config. Add backup rules.
  - Add PrivacyInfo.xcprivacy for iOS.
  - Fill the iOS app icon set and Android launcher icons with a simple generated Shadow Studio icon; write it as a vector/SVG source and committed PNGs, generated with a script that needs no new dependency.
  - Set version 1.1 / build 2 on both.
  - Do NOT rename bundle IDs, the applicationId or the Kotlin package. They need my own domain; list them as a final TODO.
  - Mac: add optional Developer ID signing and notarisation steps to "Build Mac App.command", driven by environment variables. Keep ad-hoc signing as the default when they are unset.
- D6 Interface language: English only. No localisation work.

Update both CLAUDE.md files, the root README.md and shado mobile/SETUP.md in the first implementation session so the written rules match these decisions. Optional mobile accounts and mobile Pro are now allowed, no analytics, and audio and lesson data still never leave the Mac. Preserve every other rule.

## 2. What to implement, in this order

Use the IDs from the report. Skip anything listed there as deferred or "only if needed" unless it is named here.

1. R6: fix the mobile CI workflow path (kmp/ → kmp-shadow-app/).
2. Rules and docs update for D1–D6, and T1: remove PostHog, the template Greeting scaffolding and template docs (move BOILERPLATE-NOTES.md, PORTING.md, TASKS.md and docs/ into an archive/ folder). Keep the deep-link scheme until step 9 renames it to `shadowstudio`.
3. W1–W3 on Mac, browser, iOS and Android:
   - a skippable first-run walkthrough, shown once, with "Show walkthrough again" in Settings or Help;
   - microphone priming before the system prompt, with Open Settings recovery;
   - in-app help covering how feedback works (practice estimates), the modes, keyboard shortcuts and troubleshooting.
4. S1: browser preferences dialog, dark mode and Reset defaults.
5. S2: mobile Settings: Reset defaults, engine status from /api/status with a copyable summary that excludes paths and tokens, default import language, a microphone check, and Show walkthrough again.
6. S3: Mac Settings: theme override, default import language, ElevenLabs default voice and status, and a shortcut reference.
7. F1: rename a session (engine route + Mac, browser, iOS, Android).
8. F2: delete and pin takes (engine route + all clients). Keep `latest`, counts and backup/restore consistent.
9. F3: cancel an import safely (engine + all clients).
10. A0 partial + A1–A4: optional accounts as decided in D1, including the deep-link scheme rename and account deletion.
11. P1–P4: Pro on mobile as decided in D2, plus the receipt-verification edge function.
12. F4: transcript export (TXT, SRT, VTT) and single-lesson export. Pro-gated on mobile; free on Mac and browser.
13. F7: progress over time (daily and weekly totals, streak, optional daily goal, per-phrase score trend). Local reminders are opt-in. Pro-gated on mobile; free on Mac and browser. Scores stay "practice estimates".
14. F5: auto-advance, repeat count and pause-between-phrases on all clients.
15. L1 and L3:
    - an About and Acknowledgements screen with third-party licences on all clients;
    - privacy policy and terms pages (Markdown in the repo, linked from the apps). Do not choose a project licence; list the LICENSE file as a final TODO for me;
    - acknowledged consent before the ElevenLabs PDF text upload on the Mac.
16. R4, R5 and L2: release configuration, icons, PrivacyInfo.xcprivacy and Mac signing hooks as decided in D5.
17. Q1–Q2: ShadowStore tests with a fake API; engine unit tests for pure helpers using temporary folders, never data/.
18. M2, M3, M5:
    - live level while recording;
    - next-step excerpt replay;
    - haptics;
    - lock-screen controls for the original audio;
    - Android audio focus below API 29.

Do not start D3 LAN work, Voice Training, the Mouth Guide or PDF on mobile, the self-contained Mac engine (R2), auto-update (R3), localisation, or the bundle and package rename (T2).

## 3. How to run the sessions

- Start one fresh local Claude Code session per numbered step, one at a time, from the shared checkout with the CLI. Examples:
  - `claude -p --model opus --effort high --output-format json --session-id <uuid> --add-dir <scratchpad> --allowedTools ...`
  - `claude -p --model sonnet --effort medium ...`
- Pass the feature brief on stdin. Capture each session ID and use `--resume <id>` for corrections within that feature.
- Model choice:
  - Opus with high effort for steps that touch saved data, the engine, accounts, payments, security, release configuration or several platforms at once: 2, 7–13, 16, 17.
  - Sonnet with medium effort for the UI, settings, help, docs and accessibility steps: 1, 3–6, 14, 15, 18.
- Use lighter agents for light work, at every level:
  - **You, the coordinator:** don't do simple or mechanical work yourself on Opus. Hand it to a subagent with an explicit model:
    - Haiku for file discovery, source inventories, grep sweeps, documentation lookups and reading long logs or session reports;
    - Sonnet for git housekeeping, small mechanical edits (status columns, docs, renames in a few files) and drafting routine feature briefs.

    Keep design decisions, diff reviews and accepting commits on Opus.
  - **Every feature session:** put the same rule in each brief. Use Haiku subagents for searching and inventories, and Sonnet subagents for mechanical edits, test scaffolding and other routine changes within the feature. Keep tricky logic, saved-data handling and security on the session's own model.
  - **Always:** check a subagent's result before relying on it, and set the subagent's model explicitly (`model: "haiku"` or `model: "sonnet"`).
- Keep normal permission controls (no bypass flags). Pre-approve only what sessions need:
  - Read, Grep, Glob, Edit, Write and Agent;
  - git status, diff, log, show, add and commit;
  - read-only shell tools (ls, cat, sed -n, grep, head, tail, cut, find, wc);
  - `.venv/bin/python -m py_compile` and `.venv/bin/python -I <scratchpad>/*`;
  - `./gradlew` and the absolute path to kmp-shadow-app/gradlew;
  - xcodebuild.

  Tell each session to run commands from the right directory without `cd … &&` chains, because compound commands are denied.
- Each brief contains:
  - the project and report paths;
  - the item IDs and the decisions that apply;
  - the relevant prior commits;
  - scope and acceptance criteria;
  - the rules in section 4;
  - the report format: commit hashes, files and design, static checks with exact results, unresolved gaps, and manual test steps per platform.
- After each session, read its report, review the actual diff and commits in both repos, and confirm only that feature's files were staged. Fix problems with `--resume` before starting the next step. If something is blocked (tool, permission, missing credential, compile error you cannot fix), record the exact blocker and continue with the next independent step. Never stop to ask me.

## 4. Rules for every session

- Never run, launch or test anything at runtime: no app, engine (app.py), launcher, browser, iOS Simulator, Android emulator or device. No recording, importing, backup or restore. I will test at the end.
- Allowed static checks only:
  - `.venv/bin/python -m py_compile app.py`;
  - offline Gradle compile and unit-test tasks (`:sharedLogic:compileKotlinMetadata`, `:sharedLogic:testAndroidHostTest`, `:androidApp:compileDebugKotlin`, `:androidApp:testDebugUnitTest`);
  - `xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`;
  - throwaway Python scripts on temporary folders in the scratchpad.

  Never run `iosSimulatorArm64Test`, simctl, adb or anything that boots a simulator.
- Never read, modify, delete or reset anything in data/. Never commit data/, .venv/, __pycache__/, build outputs or secrets.
- Keep the storage location, port 8765, the loopback default, the single-job worker, and the import limits:
  - 30 minutes and 150 MB;
  - 20,000 PDF characters;
  - 30 s phrases and 34 s takes.

  Keep the "practice estimate" wording. Recordings, audio, transcripts and lessons never leave the Mac.
- New dependencies are allowed only where these decisions need them (Google Play Billing; whatever Supabase modules the template already uses). Do not add others.
- When an engine route or response shape changes, update mac/Models.swift and ShadowModels.kt in the same feature.
- Preserve my unrelated uncommitted changes: in the desktop repo, untracked sample-practice.pdf and video-remake-kit*; in the mobile repo, the deleted flutter/ files and modified kmp-shadow-app/gradle.properties. Stage explicit paths only (never `git add -A`, `.` or `-u`). Commit each logical change in the correct repo with a short imperative message. No branches, pushes, amends or rebases.
- Match the existing code style; small, scoped changes; no comments that restate code. Do not claim anything works; say it is untested.

## 5. Final handoff to me

When all steps are done, or blocked, give me one consolidated report:
- the features in order with their commit hashes (repo + hash);
- exact reasons for anything blocked or skipped;
- everything I must configure myself (Supabase project and keys, Google and Apple sign-in IDs, store product IDs and server credentials, Android keystore, Apple team and Developer ID, bundle and package IDs);
- which static checks ran and their results;
- one manual test checklist grouped by Mac, browser, iOS and Android, including a short end-to-end practice check per platform, the walkthrough, sign-in and account deletion, a sandbox purchase and restore on each store, rename, take delete and pin, cancel import, export, and a backup and restore check on a disposable library.

Also update output/shadow-studio-missing-features.md with a status column (done, blocked, deferred) and commit it.
