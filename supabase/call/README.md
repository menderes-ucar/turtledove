# BESTIE Calls — production architecture audit

The current call surface uses the self-hosted **mediasoup SFU** path:

- Flutter connects to `MEDIASOUP_SIGNALING_URL` over WebSocket.
- Supabase Auth access token authenticates the signaling connection.
- Microphone and camera are separate producers.
- Screen sharing is a separate video producer (`source: screen`).
- If the platform returns a display audio track, it is published separately as `source: screen-audio`.
- Remote camera and remote screen are consumed independently and rendered separately.
- Supabase remains the durable call/session layer; mediasoup carries the media plane.

## Important production checks

1. The mediasoup signaling server must be deployed and reachable from the device, with `MEDIASOUP_SIGNALING_URL` configured.
2. The mediasoup server must advertise a reachable public IP and expose the configured RTP/UDP port range.
3. A TURN deployment is still recommended for difficult NAT/mobile networks if the chosen transport topology requires it.
4. Android/iOS camera and microphone permissions must exist in the final platform projects.
5. Screen sharing must be tested on real Android/iOS devices; an editor/static source audit cannot prove OS-level capture permission behavior.

## System audio during screen sharing

Video screen capture is implemented as a separate producer. Android playback/system audio is **not guaranteed** by `flutter_webrtc.getDisplayMedia()` alone. The current code only publishes a screen-audio producer when the native display stream actually returns an audio track. It does not fake system audio through the microphone.

For full Android playback capture, a native `AudioPlaybackCapture` integration with the WebRTC audio device is required. Full-device iOS background screen sharing likewise requires the appropriate ReplayKit Broadcast Extension/App Group architecture.

## Deployment note

The old call README described the legacy peer-to-peer WebRTC signaling path. That description is obsolete; this document intentionally reflects the current mediasoup implementation.
