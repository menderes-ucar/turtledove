# Android system audio during screen sharing

The current official `flutter_webrtc` capture path does not expose Android playback audio as a WebRTC audio track. Passing `audio: true` to `getDisplayMedia()` does not guarantee system audio; the upstream issue documents that Android needs native `AudioPlaybackCapture` plus WebRTC audio-device mixing.

A production implementation must modify/fork the WebRTC Android audio device module so microphone PCM and `AudioPlaybackCapture` PCM are mixed before being sent through the existing WebRTC audio sender. Do **not** fake this with a second Flutter audio player or microphone recording: that would not deliver the phone's playback stream to the peer reliably.

Reference implementation discussion:
https://github.com/flutter-webrtc/flutter-webrtc/issues/2088

This release patch intentionally leaves the existing stable WebRTC signaling/media architecture untouched rather than introducing an untested native fork.
