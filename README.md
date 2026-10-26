# Shadow Studio

A personal English shadowing app that runs on this Mac. No account, API key, subscription, or cloud audio processing.

## Open it

Double-click **Start Shadow Studio.command** in Finder. It opens the studio in your browser at **http://127.0.0.1:8765**. Keep its Terminal window open while practising. Press Control-C in that window to stop.

The local speech model and dependencies are already installed in this folder. Keep the whole **Shadow Studio** folder together. The app listens only on this Mac.

## Your practice loop

1. Choose **Add a voice**, paste a YouTube video link, or upload an audio/video file. Keep imports under 30 minutes and 150 MB.
2. Wait for local transcription and automatic phrase splitting. The first import may take a little longer while the speech model loads.
3. Play a phrase. Adjust playback speed or turn on Loop.
4. Choose **Recall** to hide the text and practise from memory.
5. Choose **Shadow**, put on headphones, and record while the original plays. Recording stops at the end of the phrase. Other modes let you stop the recording yourself; takes are limited to 34 seconds.
6. Review feedback, replay your take, or listen to **Original → you**.
7. Use **Edit phrase** to correct transcription or adjust its start/end times. This clears the old feedback for that phrase. Your library saves sessions and their most recent feedback between launches.

A built-in Mac voice sample is included to try the workflow. It is labelled as a sample, not a real YouTuber.

## What the feedback means

- **Word accuracy** compares the recognized words in your take with the phrase text. It can flag missing or different words. It is not a phoneme-level pronunciation grade, and speech recognition can make mistakes.
- **Pace & rhythm** estimates similarity in duration and the loudness pattern across the phrase. Shadow mode accounts for the playback speed you selected.
- **Intonation** estimates similarity in relative pitch movement. It removes each voice's median pitch, so you do not need the same natural pitch as the speaker. It shows N/A when there is too little clear voiced audio.

Scores are transparent practice heuristics, not validated assessments. Use replay to judge what you actually hear. Music, overlapping speakers, microphone quality, and background noise can affect the results. Imported audio retains background sounds; this version does not separate vocals from music.

## Privacy and storage

Audio, recordings, model files, and lesson information stay in this folder's **data/** directory. YouTube imports contact YouTube. The speech model downloads from Hugging Face once; after it is cached, uploaded files and recordings can be processed offline. No audio is sent to a transcription provider. Browser microphone permission is requested only when you click **Record a take**.

The delete button removes a session and its audio/recordings from the Mac. Deletion has an explicit confirmation dialog. Back up the **data/** folder if you want to keep your practice.

## YouTube imports

Use content you have permission to import. Links can fail because of YouTube access restrictions, unavailable videos, or changes to its download behaviour. Uploading an audio/video file is the fallback. This app does not request browser cookies or log into your YouTube account. YouTube's official API does not offer general audio extraction; see its [developer policy guide](https://developers.google.com/youtube/terms/developer-policies-guide). The local importer uses [yt-dlp](https://github.com/yt-dlp/yt-dlp), rather than the YouTube API.

## If something needs attention

- If the in-app browser cannot record, open the local address in Safari or Chrome, then grant microphone access.
- If the microphone was denied, enable it for this local address in your browser's website settings.
- If YouTube refuses a link, upload a file you can use instead.
- If the port is occupied, start with `SHADOW_PORT=8766` or stop the other copy.
- On a different Mac, the launcher needs Python 3.12+ and FFmpeg. The launcher installs Python dependencies into its own environment when needed. Its initial setup needs an internet connection.

Speech transcription uses [faster-whisper](https://github.com/SYSTRAN/faster-whisper), with the English base model. No paid services are required.

## Verification on this Mac

Verified local upload, audio conversion, English transcription, automatic phrase boundaries, recording analysis and replay, silence rejection, persistence, phrase correction, and comparison at slower playback speeds. Browser checks covered phrase navigation, hidden-text recall, and the import form. Microphone capture still requires your browser permission when you first use it.

A real YouTube import attempt could not connect to YouTube from this execution environment, so successful direct downloading remains unverified here. The app reports the failure and offers file upload.
# shado-app
