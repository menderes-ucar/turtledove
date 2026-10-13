# BESTIE self-hosted mediasoup server

This is the free/open-source media SFU layer for BESTIE. It does not use a hosted video provider.

## Requirements
- Node.js 20+
- A public IPv4/IPv6 address for production
- UDP ports 20000-20100 forwarded to the server
- TCP 20000-20100 as fallback
- `SUPABASE_URL` and `SUPABASE_ANON_KEY`
- `MEDIASOUP_ANNOUNCED_IP` set to the public IP/DNS-reachable address

## Start
```bash
npm install
npm start
```

For production, put the WebSocket endpoint behind TLS (`wss://`) with nginx/Caddy and keep the RTP port range reachable.

## Quality profiles
The Flutter client requests:
- Camera: 1920x1080 up to 60fps, simulcast layers, up to 6.5 Mbps on the top layer.
- Screen: 1280x720 up to 30fps, simulcast layers, up to 5.5 Mbps on the top layer.
- Microphone: Opus stereo/FEC.

The server itself does not artificially cap a call to 480p/15fps.

## TURN
mediasoup's ICE-Lite server can work directly over UDP/TCP when the advertised address is reachable. For restrictive carrier/NAT networks, add a self-hosted coturn server and pass its ICE server configuration into the Flutter transports. TURN is optional and is also open-source, but it increases bandwidth because traffic is relayed.

## System audio
The SFU carries any audio track that the Flutter platform capture API provides. Android playback/system audio requires MediaProjection + AudioPlaybackCapture support; iOS full-screen system capture requires ReplayKit/Broadcast Upload Extension. mediasoup itself is not the OS capture API.
