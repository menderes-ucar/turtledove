# BESTIE Watch Together media patch

## What this patch fixes

- The production CallScreen uses `MediasoupCallClient` instead of the old `RTCPeerConnection` call path.
- Camera and screen are separate mediasoup producers.
- Remote screen is selected by producer source, not by track arrival order.
- Screen share targets 1920x1080 @ 60 FPS; Android may still deliver a lower actual capture rate when the device capturer/encoder cannot provide 60 FPS.
- Screen producer bitrate is raised to 8 Mbps.
- The mediasoup transport outgoing bitrate budget is raised from 8 Mbps to 20 Mbps so a 6.5 Mbps camera + 8 Mbps screen producer is not forced through an 8 Mbps shared ceiling.
- Stopping screen share closes both `screen` and `screen-audio` producers.

## Important: system/video audio

The Dart `getDisplayMedia({'audio': true})` call does NOT guarantee Android playback/system audio. The stock flutter_webrtc Android implementation creates a screen video track and does not add an Android AudioPlaybackCapture track to that stream. Therefore this patch can forward a screen-audio track if the platform actually provides one, but it cannot manufacture the missing Android playback track.

For Android 10+, production system-audio sharing requires an AudioPlaybackCapture -> WebRTC audio-device integration. A 2026 flutter-webrtc issue documents a working community fork that modifies the Android audio device module to capture and mix playback audio with microphone PCM:
https://github.com/mohamedxblac/webrtc_mediaprojection

Do not claim system audio is fixed until that native WebRTC audio-device fork (or an equivalent native implementation) is integrated and tested.

## Server restart

After replacing `mediasoup-server/server.js`, restart the Node server so the new transport bandwidth budget and codec limits are active.
