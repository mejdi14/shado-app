# Shadow Studio: missing features report

17 November 2026. Source review of desktop commit `683158b` and mobile commit `74be04d` (repo `shado mobile`). Nothing was launched; every item below is based on reading the code and docs. Companion PDF: `output/pdf/shadow-studio-missing-features.pdf`. Previous reports: `output/pdf/shadow-studio-product-audit.pdf`, `output/pdf/shadow-studio-mobile-roadmap.pdf`.

## How a coordinator should use this report

- **Decisions first.** Section 0 lists owner decisions. Login, payments, analytics, phone-over-Wi-Fi and store release change what the product is, and the current project rules forbid them: `CLAUDE.md` requires "No accounts, API keys or cloud audio processing", loopback-only, and an account-free product. Do not start any item marked **Gate D1–D6** until the owner has answered that decision in writing and `CLAUDE.md` has been updated to match.
- **One session per item**, in the order in section 11. Opus with high effort for anything that touches saved data, accounts, payments, security or several platforms. Sonnet with medium effort for UI, settings, copy, docs and accessibility. Haiku for file discovery and lookups.
- **Carry the project rules into every brief.** Read `CLAUDE.md` and `AGENTS.md` in both repos. Do not launch the app, engine, simulator or device. Never touch `data/`. Stage explicit paths only. Commit each logical change in the right repo. Preserve the user's unrelated uncommitted changes:
  - desktop: untracked `sample-practice.pdf` and `video-remake-kit*`;
  - mobile: deleted `flutter/` files and a modified `kmp-shadow-app/gradle.properties`.
- **Checks.** Allowed static checks are `.venv/bin/python -m py_compile app.py`, the offline Gradle compile and test tasks, and the iOS `xcodebuild … -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

Item format: **ID / title**, then platforms, current state with evidence, what is missing, acceptance, dependencies, and the suggested model.

---

## 0. Owner decisions required first

| ID | Decision | Why it blocks work | Options |
|---|---|---|---|
| D1 | **Accounts / login** | `CLAUDE.md` says no accounts. The mobile template has a full Supabase login that is compiled but unreachable. | (a) Stay account-free and delete the template auth code. (b) Optional accounts only for a defined need: sync, backup, paid entitlement. (c) Device pairing between phone and Mac instead of accounts. |
| D2 | **Monetisation** | The template uses Stripe web checkout and Supabase subscriptions. There is no Shadow-specific pricing and no entitlement check. App Store and Play billing rules for digital goods apply to the mobile apps. | (a) Free. (b) One-time purchase of the Mac app. (c) Subscription or in-app purchase through Apple and Google billing (StoreKit / Play Billing). (d) Stripe for desktop or web only. Check the current store rules before choosing. |
| D3 | **Phones away from the Simulator / USB** | Physical iPhone and Wi-Fi Android need `SHADOW_LAN=1`. That has no device credential and conflicts with the loopback rule. | (a) Keep Simulator and USB only. (b) LAN with pairing, Mac-side approval, credentialed reads, protected transport and revoke. (c) Standalone on-device processing (separate project). |
| D4 | **Analytics / telemetry** | The PostHog template config is still in both apps. The product promises nothing leaves the Mac. | (a) No analytics; remove the keys and SDKs. (b) Opt-in, local-only diagnostics. (c) Opt-in remote analytics with a privacy policy. |
| D5 | **Distribution** | The Mac app is ad-hoc signed and depends on the source folder. Mobile bundle IDs and the icon are template or missing. | (a) Personal use only. (b) Signed and notarised Mac app with a self-contained engine. (c) App Store / Play release, which needs D2, D4 and legal pages. |
| D6 | **Interface language** | All UI is English. Lessons support English and French. | (a) English UI only. (b) Add a French UI (localisation). |

---

## 1. Login and accounts (all gated by D1)

**Current state**
- Both mobile apps open straight into Shadow Studio:
  - iOS `iosApp/iosApp/iOSApp.swift:5-9` shows `ShadowRoot()`, with a comment saying sign-in, payments and analytics are skipped.
  - Android `MainActivity.kt:21-35` shows `ShadowApp(...)`. `KmpApplication.kt` creates `authStore`, `metadataStore`, `paymentsStore` and `analytics` lazily, and nothing uses them.
  - The skip was introduced in mobile commits `63c5112` (iOS) and `b3f1cef` (Android).
- Still compiled but unreachable:
  - shared `auth/AuthStore.kt`, `AuthRepository.kt`, `AuthModels.kt` (anonymous/guest sign-in) and `DeepLink.kt`;
  - Android `auth/*` (AuthScreen, Google sign-in, password recover/reset dialogs, SaveAccountDialog), `account/AccountScreen.kt` and `nav/AppNavHost.kt`;
  - iOS `Screens/AuthScreen.swift`, `AccountScreen.swift`, `PasswordSheets.swift`, `SaveAccountSheet.swift`, `Adapters/AuthModel.swift` and `Navigation/RootView.swift`.
- Configuration is the template's:
  - `sharedLogic/.../config/SupabaseConfig.kt` points to a local Supabase for debug builds and to the template author's hosted Supabase project for release builds;
  - Google client IDs are empty (Gradle property `GOOGLE_WEB_CLIENT_ID`, iOS `Configuration/Config.xcconfig`);
  - iOS `TEAM_ID` is empty;
  - the iOS entitlements request Sign in with Apple.
- The deep link `com.devtodollars.app://login-callback` is registered in the Android manifest and iOS `Info.plist`, but nothing handles it (no `onOpenURL`, no deep-link handling in `MainActivity`).
- The desktop (engine, Mac app, browser) has no accounts at all.
- Account deletion is a stub that only shows an alert (Android `AccountScreen.kt` ~212-228, iOS `AccountScreen.swift` 103-118).

**Missing if D1 = accounts**
- **A1** (Opus/high): own backend project. Create a Shadow Supabase project, or choose another provider. Replace `SupabaseConfig` values. Move keys into build config, not source. Set the redirect allow-list. Document setup in `SETUP.md`.
- **A2** (Opus/high): auth entry point. Decide where sign-in appears (optional from Settings, never blocking local practice). Route the app through `AuthStore` without gating the Mac-engine practice loop. Handle deep links on both platforms.
- **A3** (Sonnet/medium): providers. Email/password with confirmation and password reset, Google (client IDs), and Sign in with Apple. App Store guideline 4.8 requires a privacy-focused login option, such as Sign in with Apple, when third-party login is offered on iOS.
- **A4** (Opus/high): account deletion. In-app account and data deletion, which the stores require for apps with account creation. Replace the stub.
- **A5** (Opus/high): what an account does. Sync of library, progress and takes, or only an entitlement? Any upload of audio, transcripts or recordings contradicts the privacy promise and needs explicit consent and README/UI changes.
- **A6**: the desktop side. If accounts are meant to unlock Mac features, the Mac app and engine need a sign-in, or a licence check, that works offline.

**If D1 = account-free:** **A0** (Sonnet/medium) removes the unreachable auth, account, metadata and payments code, the Supabase config, the Google and Apple sign-in settings and the deep-link registrations from both apps, plus their template tests. Keep the build green.

---

## 2. Payments and options (all gated by D2, mostly also D1)

**Current state**
- Mobile client code is written but unreachable:
  - shared `payments/PaymentsRepository.kt` and `PaymentsStore.kt`, and `metadata/MetadataStore.kt` for subscription status;
  - Android `payments/PaymentsScreen.kt` and `PaymentsViewModel.kt` (Custom Tab checkout);
  - iOS `Platform/StripeBrowser.swift`, `Screens/PaymentsScreen.swift`, `Adapters/PaymentsModel.swift` and `Logic/PendingPayment.swift`.
- Backend template in `shado mobile/supabase/`:
  - edge functions `get_stripe_url`, `stripe_webhook`, `on_user_modify`, and `_scripts/sync-stripe.ts`;
  - migration tables `customers`, `products`, `prices`, `subscriptions`, `checkout_sessions`.
- Not set up: `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SIGNING_SECRET` are not configured, and no products or prices are defined.
- Nothing in the Shadow code checks an entitlement or subscription (no paywall, no feature limits).
- The desktop has no payments or licence.

**Missing if D2 = paid**
- **P1** (owner + Opus): define plans and options. Free vs paid features, trial, price points and regions. Decide what stays free; the local practice loop should stay usable.
- **P2** (Opus/high): store billing on mobile. StoreKit 2 (iOS) and Play Billing (Android) for digital features, with purchase, restore purchases, receipt or entitlement verification, and sandbox test plans. The Stripe web checkout in the template is likely unsuitable for in-app digital goods on iOS and Android under store rules; confirm the current rules.
- **P3** (Opus/high): entitlement layer. One shared `Entitlement` source of truth (store receipts, or the Supabase subscription), with offline grace and gating of the chosen features. It must never lock users out of existing practice data.
- **P4** (Sonnet/medium): paywall and plan UI. Plan screen, upgrade entry points, restore purchases, manage subscription link, pricing copy, and legal links (terms, privacy, auto-renew text).
- **P5** (Opus/high): desktop licensing (if the Mac app is paid). Purchase path (Mac App Store or Stripe/Paddle), offline licence check and restore.
- **P6** (Sonnet/medium): Stripe backend, only if web or desktop billing is chosen. Configure keys, `sync-stripe.ts` products, webhook, customer portal, and test mode end to end.

---

## 3. Walkthrough and onboarding (not gated, except W4 by D3)

**Current state**
- No onboarding, intro carousel, first-run tutorial, coach marks, help page or FAQ exists on Mac, browser, iOS or Android.
- What exists:
  - a "Try the guided sample" entry and short first-take hints (desktop commit `2459dc7`, mobile commit `f86277a`; mobile `ShadowScreens.kt` `firstTake` at ~732/1010, iOS `ShadowViews.swift` ~484);
  - the browser's static three-step "how it works" strip (`static/index.html #howItWorks`);
  - connection help text (Android shows the `adb reverse` command; iOS explains Simulator vs physical iPhone);
  - Mac `.help()` tooltips.
- Microphone permission is requested on the first Record tap with no explanation beforehand (Android `ShadowScreens.kt` ~1012, iOS `ShadowModel.swift` ~189, Mac `Microphone.swift:22`).
- Feedback meanings ("What the feedback means") and keyboard shortcuts (Mac Space/R/arrows, browser Space/arrows) are documented only in the README.

**Missing**
- **W1** (Sonnet/medium): first-run walkthrough on Mac, browser, iOS and Android. A short skippable flow of 3–4 steps: what shadowing is, the Listen → Record → Compare loop, privacy (stays on the Mac), then the guided sample. Show it once, with "Show walkthrough again" in Settings or Help. Accessible and Reduce Motion aware.
- **W2** (Sonnet/medium): microphone priming. A one-screen explanation before the system prompt, plus a recovery path with an "Open Settings" button on iOS and Android.
- **W3** (Sonnet/medium): in-app help. "How feedback works" (scores are practice estimates), a modes explainer (Listen, Recall, Shadow), a keyboard shortcut list (Mac menu or Help, browser `?` dialog), and FAQ / troubleshooting (YouTube failures, file fallback, model download).
- **W4** (Sonnet/medium, content depends on D3): connection setup walkthrough on mobile. A step-by-step guide per path (Simulator; Android emulator or USB with `adb reverse`), with a "Test connection" step and engine status via `/api/status`.
- **W5** (Sonnet/medium): coach marks for first Practice use (phrase card, speed, record, compare, take history), shown once.

---

## 4. Settings and options

**Current state**
- **Mac** (`mac/App.swift` 18-143): practice defaults (mode, speed, repeat, Reset), microphone status, engine diagnostics with Copy Diagnostics, storage with Show Folder, and backup and restore. The theme always follows the system.
- **Browser**: no settings panel. Speed, loop and hide-text are inline controls. Defaults are not saved; only the last lesson and the import job are stored in `localStorage`. There is no dark mode CSS.
- **iOS and Android Settings**: theme, start mode, speed, loop, engine address, an About note, and the import language (remembered from the import sheet).

**Missing**
- **S1** (Sonnet/medium): browser preferences and dark mode. A compact preferences dialog (default mode, speed, loop, import language) saved in `localStorage`, a `prefers-color-scheme` dark theme, and Reset defaults.
- **S2** (Sonnet/medium): mobile Settings parity:
  - Reset defaults;
  - engine status from `/api/status` (model ready, FFmpeg) with a copyable diagnostic summary that excludes paths and tokens;
  - default import language;
  - a microphone check: a short input level test and the permission state with an Open Settings button;
  - a "Show walkthrough again" link.
- **S3** (Sonnet/medium): Mac Settings additions. Theme override (System/Light/Dark), default import language, the ElevenLabs default voice and status (today chosen only in the PDF sheet), and a keyboard shortcuts reference.
- **S4** (Opus/high): storage controls. "Delete all practice data" with strong confirmation, and optional per-lesson take cleanup. Depends on take deletion (F2). Never runs automatically.
- **S5** (Sonnet/medium; device choice is Opus): audio input and output choice on Mac (input device picker), plus a headphone hint and detection on mobile.
- **S6**: advanced options, only if needed. Wider speed range (today fixed at 0.65/0.8/1/1.15 in `mac/Store.swift:38` and mobile), Whisper model size, port in the UI, launch at login. Low priority.

---

## 5. Practice, library and progress features

- **F1** (Sonnet/medium): rename a session. There is no route and no UI on any platform; titles are set only at import. Add `PATCH /api/lesson/{id}` (title) with the same token checks, update `mac/Models.swift` and `ShadowModels.kt`, and add UI on all four clients.
- **F2** (Opus/high): delete and pin takes. There is no engine route; take audio only grows until the session is deleted. Engine route plus history UI on all clients. Keep `latest` and counts consistent, and keep backup and restore compatible.
- **F3** (Opus/high): cancel an import. There is no cancel route or button. Add safe cancellation in the single worker, with cleanup of the partial lesson folder, and recovery UI on all clients.
- **F4** (Sonnet/medium): export. Transcript export (TXT/SRT/VTT) and single-lesson export. Today only a whole-library ZIP exists.
- **F5** (Sonnet/medium): practice flow options. Auto-advance to the next phrase, a repeat count, and a pause-between-phrases mode. Loop today repeats one phrase only (`mac/Store.swift` ~312).
- **F6** (Sonnet/medium): browser parity. Waveform seek (the canvas is drawn only), word-level "Hear this part" (Mac only), the next-step suggestion, a storage readout, and an R shortcut to record.
- **F7** (Opus/high): progress over time. Daily or weekly totals, streaks, an optional daily goal, and per-phrase score trend. Reminders need notification permission on mobile and Mac, and must stay local. Scores stay framed as practice estimates.
- **F8** (Sonnet/medium): library organisation. Favourites, or folders and tags, and multi-select delete. Only once libraries grow.
- **F9** (Opus/high): import options. Paste or upload your own transcript or captions instead of transcribing, start/end trimming, and possibly other sites. YouTube rules from `CLAUDE.md` stay: no cookies, no login.
- **F10**: French support for guides. The Mouth Guide and Voice Training are English only; the Mouth Guide is hidden for French lessons (`mac/Views.swift` ~582). Needs content work.

---

## 6. Mobile parity (iOS and Android)

- **M1** (Sonnet/medium): backup and restore from the phone. `backup_local` accepts only loopback clients, which the Simulator and `adb reverse` paths satisfy, so the archive would stream to the phone. Decide whether phones should hold backups, or only show where the Mac's backups live, before building.
- **M2** (Sonnet/medium): live level and voice trace while recording. The browser has `startLive`/`sampleLive`; mobile shows nothing during a take.
- **M3** (Sonnet/medium): next-step coaching with excerpt replay ("Hear this part") as on the Mac.
- **M4**: Voice Training and the Mouth Guide on mobile. Large; the Mac uses ElevenLabs for drills. Defer unless requested.
- **M5** (Sonnet/medium): practice comfort:
  - haptics on record start and stop;
  - Now Playing / lock-screen controls for the original audio, which needs background audio modes;
  - Android audio focus handling below API 29.
- **M6** (Sonnet/medium): tablet, iPad and landscape layouts. iPad and landscape are enabled, but there is no size-class or window-size-class handling.
- **M7**: PDF narration on mobile. Out of scope by the earlier decision; it stays on the Mac.

---

## 7. Reliability, release and distribution (mostly gated by D5)

- **R1** (Opus/high): Mac app signing and notarisation. `Build Mac App.command` signs ad-hoc (`codesign --force --sign -`). Needs a Developer ID, hardened runtime, entitlements (microphone), notarisation and a DMG.
- **R2** (Opus/high): self-contained Mac app. It currently depends on the source folder (`ShadowProjectDir`), a `.venv` with Python 3.12+ and Homebrew FFmpeg at hard-coded paths (`mac/Server.swift` ~192-198). Bundle the engine, or document the requirements.
- **R3** (Sonnet/medium): updates and versioning. No update mechanism exists; the Info.plist version is fixed at 1.0. yt-dlp needs a refresh path because YouTube changes break it. The engine has no API version; clients compare only a code fingerprint (`X-Shadow-Engine`).
- **R4** (Sonnet/medium): mobile release configuration:
  - Android: release signing is a TODO (`androidApp/build.gradle.kts` ~65), `isMinifyEnabled=false`, `usesCleartextTraffic="true"` for all builds (should be debug or loopback only), and `allowBackup="true"` with no rules;
  - iOS: `TEAM_ID` is empty and the deployment target is 18.2 (consider lowering);
  - versions are 1.0 / 1 on both.
- **R5** (Sonnet/medium): identity and assets:
  - Android `applicationId` is `com.mejdi14.kmpstartupmvp`;
  - the iOS bundle ID is `com.mejdi14.kmpstartupmvp.KmpStartupMvp$(TEAM_ID)` and `PRODUCT_NAME=shadow-app`;
  - the iOS `AppIcon.appiconset` holds only `Contents.json` (no icon images);
  - Android uses default adaptive launcher icons;
  - there is no custom launch screen.
- **R6** (Sonnet/medium): mobile CI is broken. `shado mobile/.github/workflows/ci.yml` uses `working-directory: kmp`, but the project moved to `kmp-shadow-app/` (mobile commit `52bf700`). The desktop has no tests or CI at all.
- **R7**: crash and error reporting. Only the Mac engine log (`~/Library/Logs/Shadow Studio.log`) and Copy Diagnostics exist. Anything remote depends on D4.

---

## 8. Privacy, legal, accessibility and localisation

- **L1** (Sonnet/medium):
  - privacy policy and terms pages, needed for any store release and for accounts or payments;
  - an in-app About and Acknowledgements screen with licences: faster-whisper/Whisper, Silero VAD, yt-dlp, FFmpeg, pypdf, CMUdict, Voice Workshop, plus the Chimera and React Bits credits;
  - a project `LICENSE` file (not found).
- **L2** (Sonnet/medium): `PrivacyInfo.xcprivacy` for iOS (not found), the Play Data safety answers, and `NSLocalNetworkUsageDescription` if D3 allows LAN.
- **L3** (Sonnet/medium): explicit consent before ElevenLabs PDF text upload on the Mac. Today the disclosure is README and sheet text only; make it an acknowledged step.
- **L4** (Sonnet/medium; gated by D6): UI localisation. All strings are hard-coded English in Swift, HTML/JS and Kotlin. There is no `Localizable`/`.xcstrings`, and Android has only `app_name` in `strings.xml`.
- **L5** (Sonnet/medium): remaining accessibility:
  - Mac text uses fixed `.font(.system(size:))` sizes and does not scale;
  - the browser waveform and pitch charts are `aria-hidden` with no text alternative;
  - no contrast audit;
  - tablet and keyboard use on mobile.

---

## 9. Template cleanup (do after D1, D2 and D4)

- **T1** (Sonnet/medium):
  - remove the PostHog keys and SDKs (Android manifest meta-data, iOS `Info.plist` keys and the SPM package) if D4 = no analytics. Neither app initialises it today; it starts only through the unreachable template `PostHogTracker` / `AppEnvironment`;
  - remove `Greeting`/`GreetingUtil` scaffolding;
  - rename the deep-link scheme `com.devtodollars.app`;
  - update the template docs (`BOILERPLATE-NOTES.md`, `PORTING.md`, `TASKS.md`, `docs/`) or move them to an archive folder.
- **T2** (Opus/high): rename the Kotlin package `com.mejdi14.kmpstartupmvp` and the app IDs. This is a wide mechanical change; do it in one session after R5 has settled the final IDs.

---

## 10. Tests

- **Q1** (Sonnet/medium):
  - Shadow shared logic has only 3 test files (`TakeHistoryTest`, `PendingTakeTest`, `PracticeSummaryTest`), and `ShadowStore`, `ShadowApi` and `VoiceMap` have none;
  - add store tests with a fake API (imports, job recovery, take submission, drafts);
  - the template tests (auth, payments, metadata, routes) should follow the D1 and D2 outcome.
- **Q2** (Sonnet/medium): engine unit tests for the pure helpers (backup validation, take publication, sample merge) in a temporary directory, never against `data/`.
- **Q3** (owner): runtime checklists for each release (the existing handoff checklists).

---

## 11. Suggested order

1. **Decisions D1–D6** (owner). Update `CLAUDE.md`/`README.md` to match.
2. **Unblocked now:**
   1. R6 mobile CI path;
   2. W1–W3 walkthrough, microphone priming and help;
   3. S1 browser preferences and dark mode;
   4. S2 mobile Settings parity;
   5. F1 rename;
   6. F2 delete/pin takes;
   7. F3 cancel import;
   8. L1 About/licences and LICENSE;
   9. L3 ElevenLabs consent;
   10. Q1–Q2 tests.
3. **After D1/D2/D4:** A0 or A1–A6, then P1–P6, then T1–T2, L2 and R4–R5.
4. **After D5:** R1–R3 and the store submission work.
5. **Later or on demand:** F4–F10, M2–M7, S3–S6, L4–L5, W4–W5.

Carried-over rules for every brief: keep the import limits (30 min, 150 MB, 20,000 PDF characters, 30 s phrases, 34 s takes), keep jobs one at a time, keep "practice estimate" wording, and keep the loopback default unless D3 changes it. Ask before new dependencies, port changes or storage location changes.
