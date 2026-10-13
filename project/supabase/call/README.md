# BESTIE Calls

The call implementation uses WebRTC for media and Supabase Realtime Broadcast for signaling.

## Media model

- Microphone is enabled by default.
- Camera is optional per user.
- Screen sharing is optional per user.
- Camera and screen can be enabled together.
- Turning camera/screen off does not end the audio call.

## TURN

STUN is included for development. Production deployments should configure a TURN server in `.env`:

```env
TURN_URL=turn:your-turn-host:3478
TURN_USERNAME=...
TURN_CREDENTIAL=...
```

For a real production deployment, do not commit TURN credentials to source control.

## Supabase Realtime authorization

The current Flutter implementation uses a pair-specific Realtime topic. For production, make the channel private and add Realtime Authorization policies so only the two paired users can read/write `realtime.messages` for that topic. Supabase documents private Broadcast authorization under Realtime Authorization.

## iOS screen sharing

`getDisplayMedia()` is used for screen capture. The flutter_webrtc project supports in-app capture on iOS without a Broadcast Upload Extension. Full-device/background screen sharing on iOS requires an iOS Broadcast Upload Extension and App Group configuration in Xcode.
