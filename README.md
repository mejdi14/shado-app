# Shadow Studio

A personal English shadowing app that runs on this Mac. No account, API key, subscription, or cloud audio processing.

## Open it

Double-click **Start Shadow Studio.command** in Finder. It opens the studio in your browser at **http://127.0.0.1:8765**. Keep its Terminal window open while practising. Press Control-C in that window to stop.

## Mac app

Double-click **Build Mac App.command** once to create **Shadow Studio.app** in this folder. It is a native SwiftUI app (no browser or web view): the same practice loop, library, import, phrase editing and feedback, with native playback and microphone recording. Behind the scenes it starts the local Python engine from this folder (transcription, YouTube import, scoring) and stops that engine when you quit. If the browser launcher already started a matching engine, the Mac app shares it; that Terminal engine keeps running until you stop it with Control-C. Scores and your **data/** folder are identical to the browser version. Microphone access is requested the first time you record. Drag the app to the Dock or Applications; keep this folder where it is (rebuild the app if you move it). Building needs macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). If macOS blocks the app on first launch, right-click it and choose Open. If it can't start, it shows why, and the engine log is at `~/Library/Logs/Shadow Studio.log`.

The local speech model and dependencies are already installed in this folder. Keep the whole **Shadow Studio** folder together. The app listens only on this Mac. For a phone on the same Wi-Fi (no USB), you can opt in with `SHADOW_LAN=1 "./Start Shadow Studio.command"`: the engine then also answers on your local network and prints the address to type into the phone app. Anyone on that Wi-Fi could reach your lessons and recordings while it runs, so only use it on a network you trust.

## Your practice loop

1. Choose **Add a voice**, paste a YouTube video link, or upload an audio/video file. Keep imports under 30 minutes and 150 MB.
2. Wait for local transcription and automatic phrase splitting. Each sentence ending starts a new phrase, except for recognized abbreviations and initials. Longer sentences are divided into short practice chunks, usually 2–6 seconds and capped at about 8 seconds, with a short lead-in and tail where there is room. The splitter prefers a continuous quiet gap near the word boundary. At a sentence ending or when needed to keep a chunk short, it falls back to estimated word timing if there is no clear pause; those cuts may need **Edit phrase**. Music, overlapping voices and inaccurate word timestamps can still affect boundaries. The first import may take a little longer while the speech model loads.
3. Play a phrase. Adjust playback speed or turn on Loop.
4. Choose **Recall** to hide the text and practise from memory.
5. Choose **Shadow**, put on headphones, and record while the original plays. Recording stops at the end of the phrase. Other modes let you stop the recording yourself; takes are limited to 34 seconds.
6. Review feedback, replay your take, or listen to **Original → you**.
7. Use **Edit phrase** to correct transcription or adjust its start/end times. This clears the old feedback for that phrase. To redo the automatic split for a whole session (for example one imported with an older version), choose **Re-split phrases** (↻ in the browser, the session menu in the Mac and mobile apps). The audio is transcribed again, and that session's phrase edits and feedback are cleared. Your library saves sessions and their most recent feedback between launches.

A built-in Mac voice sample is included to try the workflow. It is labelled as a sample, not a real YouTuber.

## Voice Training (Mac app)

Choose **Voice Training** in the Mac sidebar to practise one voice skill before shadowing. This is a separate screen with horizontally scrollable tabs for **Pitch, Intonation, Stress, Rhythm, Pace, Pauses, Energy, Articulation, and Connected Speech**. Each tab starts with simple drills and moves toward short phrases. Every level follows **Hear → See → Try → Feedback → Try Again**; you can open any technique or level at any time.

Examples use synthesized tones for isolated pitch, energy, and rhythm patterns, and the ElevenLabs Bella voice (American English) for speech. Spoken examples are generated on first play through the Homebrew ElevenLabs CLI and saved in **data/voice-training-audio/**. First generation needs internet and uses your ElevenLabs credits; saved clips replay offline, including after restarting. The CLI uses your existing Keychain login (`elevenlabs auth login`); no key is embedded in the app. Pitch charts compare movement around your own comfortable range, rather than matching another voice’s natural pitch. Rhythm pulses follow the example or your recording timer. Pace drills ask you to hear the target first, then compare its time with your speech duration; leading and trailing silence is trimmed from your take. Pauses appear as phrase groups and timeline dividers. Energy guides use relative strength, without decibel targets or maximum-volume training.

Choose **Record your voice**, then **Stop recording**, to see feedback and replay your take. Short recordings stop automatically after 6–14 seconds, depending on the exercise. Pitch, energy, emphasis, rhythm, and pause feedback are local practice estimates. Stress and rhythm use approximate time groups and energy, not recognized syllables; pause detection can also mistake quiet sounds for gaps. Pace feedback compares overall duration; replay to check whether the pace stays steady throughout. Articulation and connected speech use a sound-activity trace and guided listening, without phoneme grading: replay your take, then choose **Sounds clear · mark practised** when you’re satisfied.

Progress is separate for each technique, with no overall voice score. A matching estimated pattern marks a level practised; you can still retry it as often as you like. Progress is saved by the local engine in **data/voice-training.json**. Training recordings and playback copies are temporary: retrying, changing levels, or leaving the screen removes them. Saved ElevenLabs source audio is kept for reuse. They are not added to shadowing sessions. Spoken examples require the ElevenLabs CLI (`brew install elevenlabs/tap/elevenlabs`) and a signed-in account. Only exercise text is sent to ElevenLabs; your microphone recordings remain local. Stopping or leaving during generation stops playback preparation, but the current request may still complete, use credits, and be saved. Listen to check that generated stress, pauses, and intonation demonstrate the requested pattern; the charts remain approximate teaching guides. To use this screen after updating, quit the Mac app, stop any engine started in Terminal, run **Build Mac App.command**, then reopen the app.

## How it sounds

Under each phrase, a single line shows the speaker's voice going up and down, with each word placed where it is spoken. Bold words are the loudest ones, which are often, but not always, the stressed words. Soft bands marked "pause" show quiet gaps of 0.15 seconds or more. While audio plays, the word being spoken is highlighted.

In the Mac app, the phrase appears once as the main practice guide. Bold words are louder in the example (an estimate, not a syllable-stress assessment), a `|` marks a detected quiet gap between words, and a small arrow shows the estimated pitch direction at the end. During example playback, the current word is highlighted. Edited phrases without word timestamps still show the complete sentence, without word-level annotations. Recall hides the sentence and its word cues.

Listen, speed, repeat and Record sit directly below the sentence, followed by a position slider. After a take, Your take and Original → you appear in the same card. Show pitch detail expands a smaller chart with the example and your live or saved take; the detailed chart does not repeat the transcript. The sidebar button beside the session title hides or shows the phrases and feedback panel. The browser version keeps its existing chart and controls.

After recording, the Mac app shows one **Try this next** suggestion beside the sentence. It first picks a word that speech recognition did not match, then a substantial overall pace difference, then a different estimated ending; otherwise it suggests a rhythm practice exercise. **Hear this part** replays the word with its neighbours or the final words when timing is available; other suggestions replay the full example. Recall keeps the flagged word hidden. These cues use the existing estimates, not phoneme or syllable analysis. Pace suggestions use the take’s duration ratio at its recording speed, independently of the chart’s fitted timeline.

In the browser, three short tips sit under the line: which words to say more strongly, where the speaker pauses, and whether the voice goes up, goes down or stays flat at the end.

While you record, your own line is drawn over the speaker's in real time from the microphone. In Shadow mode it follows the original as it plays; in Listen and Recall it starts when you start speaking. After feedback is ready, your saved take stays on the line until you record again, stretched or squeezed to the speaker's length so the two shapes line up, and the browser’s tips show how many times you paused and how your voice ended. This is analysed on this Mac and is a visual guide, not a score.

## What the feedback means

- **Word accuracy** compares the recognized words in your take with the phrase text. It can flag missing or different words. It is not a phoneme-level pronunciation grade, and speech recognition can make mistakes.
- **Pace & rhythm** estimates similarity in duration and the loudness pattern across the phrase. Shadow mode accounts for the playback speed you selected.
- **Intonation** estimates similarity in relative pitch movement. It removes each voice's median pitch, so you do not need the same natural pitch as the speaker. It shows N/A when there is too little clear voiced audio.

Scores are transparent practice heuristics, not validated assessments. Use replay to judge what you actually hear. Music, overlapping speakers, microphone quality, and background noise can affect the results. Imported audio retains background sounds; this version does not separate vocals from music.

## Privacy and storage

Audio, recordings, model files, and lesson information stay in this folder's **data/** directory. YouTube imports contact YouTube. The speech model downloads from Hugging Face once; after it is cached, uploaded files and recordings can be processed offline. No audio is sent to a transcription provider. Voice Training sends its built-in example text to ElevenLabs when generating a new spoken example; it does not send your recordings. Browser microphone permission is requested only when you click **Record a take**.

The delete button removes a session and its audio/recordings from the Mac. Deletion has an explicit confirmation dialog. Back up the **data/** folder if you want to keep your practice.

## YouTube imports

Use content you have permission to import. Links can fail because of YouTube access restrictions, unavailable videos, or changes to its download behaviour. Uploading an audio/video file is the fallback. This app does not request browser cookies or log into your YouTube account. YouTube's official API does not offer general audio extraction; see its [developer policy guide](https://developers.google.com/youtube/terms/developer-policies-guide). The local importer uses [yt-dlp](https://github.com/yt-dlp/yt-dlp), rather than the YouTube API.

## If something needs attention

- If the in-app browser cannot record, open the local address in Safari or Chrome, then grant microphone access.
- If the microphone was denied, enable it for this local address in your browser's website settings.
- If YouTube refuses a link, upload a file you can use instead.
- If the port is occupied, start with `SHADOW_PORT=8766` or stop the other copy.
- After an engine update, stop **Start Shadow Studio.command** with Control-C in its Terminal window, quit the Mac app, and reopen it. Rebuilding the Mac app does not restart an engine that was launched in Terminal. The Mac app now checks that the running engine matches this folder's current code and reports an outdated engine instead of silently reusing it. Existing lessons need **Re-split phrases** to get new boundaries; this clears their phrase edits and feedback.
- On a different Mac, the launcher needs Python 3.12+ and FFmpeg. The launcher installs Python dependencies into its own environment when needed. Its initial setup needs an internet connection.

Speech transcription uses [faster-whisper](https://github.com/SYSTRAN/faster-whisper), with the English base model. No paid services are required.

The boundary changes follow the principle described in [stable-ts gap adjustment](https://github.com/jianfch/stable-ts#gap-adjustment): use the actual non-speech gap around adjacent words, rather than treating recognition timestamps as exact audio cuts. This app uses its existing loudness analysis and bundled Silero VAD for that step; it does not install stable-ts. [WhisperX](https://github.com/m-bain/whisperX) takes a different approach, adding a separate wav2vec2 forced-alignment model for word timing. That extra model and its dependencies are not included here.

## Verification on this Mac

The ElevenLabs integration has had Swift syntax checking only, with no paid generation, playback, build, or microphone testing. Voice Training has had Python and Swift syntax checking only. It has not been built, launched, or tested with a microphone; check example playback, all nine tabs, live recording, feedback, retry, and saved per-technique progress after rebuilding. The latest sentence-boundary and engine startup changes have had Python syntax checking only. Their playback accuracy and Mac startup behavior have not been tested; the checks below describe the earlier version.

Verified local upload, audio conversion, English transcription, automatic phrase boundaries, recording analysis and replay, silence rejection, persistence, phrase correction, and comparison at slower playback speeds. Browser checks covered phrase navigation, hidden-text recall, and the import form. Microphone capture still requires your browser permission when you first use it.

A real YouTube import attempt could not connect to YouTube from this execution environment, so successful direct downloading remains unverified here. The app reports the failure and offers file upload.
# shado-app
