import http from 'node:http';
import mediasoup from 'mediasoup';
import { WebSocketServer } from 'ws';
import { createClient } from '@supabase/supabase-js';

const PORT = Number(process.env.PORT || 4000);
const ANNOUNCED_IP = (process.env.MEDIASOUP_ANNOUNCED_IP || '').trim();
const RTC_MIN_PORT = Number(process.env.MEDIASOUP_MIN_PORT || 20000);
const RTC_MAX_PORT = Number(process.env.MEDIASOUP_MAX_PORT || 20100);
const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';
const REQUIRE_AUTH = process.env.REQUIRE_SUPABASE_AUTH !== 'false';

if (!ANNOUNCED_IP) {
  console.warn(
    '⚠️ MEDIASOUP_ANNOUNCED_IP is empty. Set it to the IP/DNS reachable by clients.'
  );
}

if (RTC_MIN_PORT >= RTC_MAX_PORT) {
  throw new Error(
    `Invalid mediasoup RTP port range: ${RTC_MIN_PORT}-${RTC_MAX_PORT}`
  );
}

const supabase =
  SUPABASE_URL && SUPABASE_ANON_KEY
    ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
      })
    : null;

const mediaCodecs = [
  {
    kind: 'audio',
    mimeType: 'audio/opus',
    clockRate: 48000,
    channels: 2,
    parameters: { useinbandfec: 1, minptime: 10, stereo: 1, 'sprop-stereo': 1 }
  },
  {
    kind: 'video',
    mimeType: 'video/H264',
    clockRate: 90000,
    parameters: {
      'packetization-mode': 1,
      'profile-level-id': '42e01f',
      'level-asymmetry-allowed': 1,
      'x-google-start-bitrate': 1800,
      'x-google-max-bitrate': 8000,
      'x-google-min-bitrate': 300
    }
  },
  {
    kind: 'video',
    mimeType: 'video/VP8',
    clockRate: 90000,
    parameters: {
      'x-google-start-bitrate': 1800,
      'x-google-max-bitrate': 8000,
      'x-google-min-bitrate': 300
    }
  }
];

let worker = null;
let router = null;
let workerDied = false;

const peers = new Map();
const rooms = new Map();

function assertWorkerReady() {
  if (!worker || workerDied) {
    throw new Error('mediasoup worker is not running.');
  }

  if (!router) {
    throw new Error('mediasoup router is not ready.');
  }
}

async function createWorker() {
  console.log(
    `Starting mediasoup worker; RTP ports=${RTC_MIN_PORT}-${RTC_MAX_PORT}`
  );

  worker = await mediasoup.createWorker({
    rtcMinPort: RTC_MIN_PORT,
    rtcMaxPort: RTC_MAX_PORT,

    // Keep this at warn for normal operation.
    // If the worker crashes again, temporarily change to 'debug'.
    logLevel: 'warn',
    logTags: [
      'info',
      'ice',
      'dtls',
      'rtp',
      'rtcp',
      'bwe',
      'score',
      'srtp',
      'rtx',
    ],
  });

  workerDied = false;

  worker.on('died', (error) => {
    workerDied = true;
    console.error('=================================================');
    console.error('🔥 MEDIASOUP WORKER DIED');
    console.error('worker pid:', worker?.pid);
    console.error('worker error:', error);
    console.error(
      'All existing media transports are now invalid. Restarting server...'
    );
    console.error('=================================================');

    // Do not continue accepting requests against a dead worker.
    setTimeout(() => process.exit(1), 1500);
  });

  router = await worker.createRouter({ mediaCodecs });

  console.log(
    `✅ mediasoup worker=${worker.pid} router=${router.id}`
  );
}

async function authenticate(ws, token, requestedUserId) {
  if (!REQUIRE_AUTH) return requestedUserId;

  if (!supabase) {
    throw new Error(
      'SUPABASE_URL/SUPABASE_ANON_KEY required when auth is enabled.'
    );
  }

  if (!token) {
    throw new Error('Missing Supabase access token.');
  }

  const { data, error } = await supabase.auth.getUser(token);

  if (error || !data.user) {
    throw new Error('Invalid Supabase access token.');
  }

  if (requestedUserId && requestedUserId !== data.user.id) {
    throw new Error('userId does not match Supabase session.');
  }

  return data.user.id;
}

async function createTransport(peer, direction) {
  assertWorkerReady();

  if (direction !== 'send' && direction !== 'recv') {
    throw new Error(
      `Invalid transport direction "${direction}". Expected "send" or "recv".`
    );
  }

  console.log(
    `➡️ CREATE TRANSPORT peer=${peer.userId} direction=${direction}`
  );

  try {
    const transport = await router.createWebRtcTransport({
      listenInfos: [
        {
          protocol: 'udp',
          ip: '0.0.0.0',
          ...(ANNOUNCED_IP
            ? { announcedAddress: ANNOUNCED_IP }
            : {}),
        },
        {
          protocol: 'tcp',
          ip: '0.0.0.0',
          ...(ANNOUNCED_IP
            ? { announcedAddress: ANNOUNCED_IP }
            : {}),
        },
      ],

      enableUdp: true,
      enableTcp: true,
      preferUdp: true,

      // Enough headroom for a 1080p/60 camera stream.
      initialAvailableOutgoingBitrate: 8_000_000,

      appData: {
        peerId: peer.id,
        userId: peer.userId,
        direction,
      },
    });

    peer.transports.set(transport.id, transport);

    transport.on('dtlsstatechange', (state) => {
      console.log(
        `DTLS state peer=${peer.userId} transport=${transport.id} state=${state}`
      );

      if (state === 'failed' || state === 'closed') {
        try {
          transport.close();
        } catch {}
      }
    });

    transport.on('icestatechange', (state) => {
      console.log(
        `ICE state peer=${peer.userId} transport=${transport.id} state=${state}`
      );
    });

    transport.on('sctpstatechange', (state) => {
      console.log(
        `SCTP state peer=${peer.userId} transport=${transport.id} state=${state}`
      );
    });

    transport.on('close', () => {
      peer.transports.delete(transport.id);
      console.log(
        `🔴 transport closed peer=${peer.userId} id=${transport.id}`
      );
    });

    console.log(
      `✅ TRANSPORT CREATED id=${transport.id} direction=${direction}`
    );

    return transport;
  } catch (error) {
    console.error(
      `🔥 CREATE TRANSPORT FAILED peer=${peer.userId} direction=${direction}`
    );
    console.error(error);
    throw error;
  }
}

function send(ws, payload) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(payload));
  }
}

function broadcast(room, exceptPeerId, payload) {
  for (const peerId of room.peerIds) {
    if (peerId === exceptPeerId) continue;

    const peer = peers.get(peerId);
    if (peer) send(peer.ws, payload);
  }
}

async function handle(ws, msg) {
  const peer = ws._peer;
  const action = msg.action;

  console.log(
    `📨 signaling action=${action} requestId=${msg.requestId ?? '-'}`
  );

  if (action === 'join') {
    if (peer) {
      throw new Error('Already joined.');
    }

    const userId = await authenticate(
      ws,
      msg.token || ws._token,
      msg.userId
    );

    const callId = String(msg.callId || '');

    if (!callId) {
      throw new Error('callId is required.');
    }

    let room = rooms.get(callId);

    // Reject before creating the peer so a failed third join does not
    // leave an orphan peer in the maps.
    if (room && room.peerIds.size >= 2) {
      throw new Error('This call already has two media participants.');
    }

    const id = `${userId}:${callId}:${Math.random()
      .toString(36)
      .slice(2)}`;

    const state = {
      id,
      userId,
      callId,
      ws,
      transports: new Map(),
      producers: new Map(),
      consumers: new Map(),
    };

    if (!room) {
      room = {
        callId,
        peerIds: new Set(),
      };
      rooms.set(callId, room);
    }

    ws._peer = state;
    peers.set(id, state);
    room.peerIds.add(id);

    console.log(
      `🟢 JOIN user=${userId} call=${callId} peersInRoom=${room.peerIds.size}`
    );

    send(ws, {
      event: 'joined',
      peerId: id,
      rtpCapabilities: router.rtpCapabilities,
    });

    // Tell the newly joined peer about producers that already exist.
    for (const otherId of room.peerIds) {
      if (otherId === id) continue;

      const other = peers.get(otherId);
      if (!other) continue;

      for (const producer of other.producers.values()) {
        send(ws, {
          event: 'producerAvailable',
          producerId: producer.id,
          peerId: other.userId,
          source: producer.appData?.source || 'camera',
        });
      }
    }

    return;
  }

  if (!peer) {
    throw new Error('Join first.');
  }

  switch (action) {
    case 'routerRtpCapabilities': {
      assertWorkerReady();

      send(ws, {
        requestId: msg.requestId,
        rtpCapabilities: router.rtpCapabilities,
      });
      return;
    }

    case 'createWebRtcTransport': {
      const transport = await createTransport(
        peer,
        msg.direction
      );

      send(ws, {
        requestId: msg.requestId,
        transport: {
          id: transport.id,
          iceParameters: transport.iceParameters,
          iceCandidates: transport.iceCandidates,
          dtlsParameters: transport.dtlsParameters,
          sctpParameters: transport.sctpParameters,
        },
      });
      return;
    }

    case 'connectWebRtcTransport': {
      const transport = peer.transports.get(msg.transportId);

      if (!transport) {
        throw new Error('Transport not found.');
      }

      await transport.connect({
        dtlsParameters: msg.dtlsParameters,
      });

      console.log(
        `🔗 TRANSPORT CONNECTED peer=${peer.userId} id=${transport.id}`
      );

      send(ws, {
        requestId: msg.requestId,
        ok: true,
      });
      return;
    }

    case 'restartIce': {
      const transport = peer.transports.get(msg.transportId);

      if (!transport) {
        throw new Error('Transport not found.');
      }

      const iceParameters = await transport.restartIce();

      send(ws, {
        requestId: msg.requestId,
        iceParameters,
      });
      return;
    }

    case 'produce': {
      const transport = peer.transports.get(msg.transportId);

      if (!transport) {
        throw new Error('Send transport not found.');
      }

      if (msg.kind !== 'audio' && msg.kind !== 'video') {
        throw new Error(`Invalid producer kind: ${msg.kind}`);
      }

      const producer = await transport.produce({
        kind: msg.kind,
        rtpParameters: msg.rtpParameters,
        appData: {
          ...(msg.appData || {}),
          userId: peer.userId,
        },
      });

      peer.producers.set(producer.id, producer);

      console.log(
        `🎥 PRODUCER peer=${peer.userId} kind=${msg.kind} id=${producer.id} source=${producer.appData?.source || 'camera'}`
      );

      producer.on('transportclose', () => {
        peer.producers.delete(producer.id);
      });

      producer.on('close', () => {
        peer.producers.delete(producer.id);

        const room = rooms.get(peer.callId);

        if (room) {
          broadcast(room, peer.id, {
            event: 'producerClosed',
            producerId: producer.id,
          });
        }
      });

      const room = rooms.get(peer.callId);

      if (room) {
        broadcast(room, peer.id, {
          event: 'producerAvailable',
          producerId: producer.id,
          peerId: peer.userId,
          source: producer.appData?.source || 'camera',
        });
      }

      send(ws, {
        requestId: msg.requestId,
        producerId: producer.id,
      });

      return;
    }

    case 'consume': {
      const transport = peer.transports.get(msg.transportId);

      if (!transport) {
        throw new Error('Receive transport not found.');
      }

      const producerPeer = [...peers.values()].find((p) =>
        p.producers.has(msg.producerId)
      );

      if (!producerPeer) {
        throw new Error('Producer not found.');
      }

      if (
        !router.canConsume({
          producerId: msg.producerId,
          rtpCapabilities: msg.rtpCapabilities,
        })
      ) {
        throw new Error('Client cannot consume this producer.');
      }

      const consumer = await transport.consume({
        producerId: msg.producerId,
        rtpCapabilities: msg.rtpCapabilities,
        paused: true,
        appData: {
          userId: producerPeer.userId,
          source:
            producerPeer.producers.get(msg.producerId)?.appData
              ?.source || 'camera',
        },
      });

      peer.consumers.set(consumer.id, consumer);

      console.log(
        `📺 CONSUMER peer=${peer.userId} producer=${msg.producerId} consumer=${consumer.id} kind=${consumer.kind}`
      );

      consumer.on('transportclose', () => {
        peer.consumers.delete(consumer.id);
      });

      consumer.on('producerclose', () => {
        peer.consumers.delete(consumer.id);

        send(ws, {
          event: 'producerClosed',
          producerId: msg.producerId,
        });
      });

      send(ws, {
        requestId: msg.requestId,
        id: consumer.id,
        producerId: msg.producerId,
        peerId: producerPeer.userId,
        kind: consumer.kind,
        rtpParameters: consumer.rtpParameters,
        appData: consumer.appData,
      });

      return;
    }

    case 'resumeConsumer': {
      const consumer = peer.consumers.get(msg.consumerId);

      if (!consumer) {
        throw new Error('Consumer not found.');
      }

      await consumer.resume();

      console.log(
        `▶️ CONSUMER RESUMED peer=${peer.userId} consumer=${consumer.id}`
      );

      return;
    }

    case 'pauseProducer': {
      const producer = peer.producers.get(msg.producerId);

      if (producer) {
        await producer.pause();
      }

      return;
    }

    case 'resumeProducer': {
      const producer = peer.producers.get(msg.producerId);

      if (producer) {
        await producer.resume();
      }

      return;
    }

    case 'readyToConsume':
      return;

    default:
      throw new Error(`Unknown action: ${action}`);
  }
}

function cleanupPeer(peer) {
  if (!peer) return;

  console.log(
    `🧹 CLEANUP user=${peer.userId} call=${peer.callId}`
  );

  for (const consumer of peer.consumers.values()) {
    try {
      consumer.close();
    } catch {}
  }

  for (const producer of peer.producers.values()) {
    try {
      producer.close();
    } catch {}
  }

  for (const transport of peer.transports.values()) {
    try {
      transport.close();
    } catch {}
  }

  peer.consumers.clear();
  peer.producers.clear();
  peer.transports.clear();

  peers.delete(peer.id);

  const room = rooms.get(peer.callId);

  if (room) {
    room.peerIds.delete(peer.id);

    if (room.peerIds.size === 0) {
      rooms.delete(peer.callId);
    }
  }
}

process.on('uncaughtException', (error) => {
  console.error('🔥 UNCAUGHT EXCEPTION');
  console.error(error);
});

process.on('unhandledRejection', (reason) => {
  console.error('🔥 UNHANDLED REJECTION');
  console.error(reason);
});

await createWorker();

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, {
      'content-type': 'application/json',
      'cache-control': 'no-store',
    });

    res.end(
      JSON.stringify({
        ok: true,
        workerPid: worker?.pid ?? null,
        workerDied,
        routerReady: Boolean(router),
        rooms: rooms.size,
        peers: peers.size,
        rtpPorts: {
          min: RTC_MIN_PORT,
          max: RTC_MAX_PORT,
        },
        announcedIp: ANNOUNCED_IP || null,
      })
    );

    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

const wss = new WebSocketServer({
  server,
  maxPayload: 2 * 1024 * 1024,
});

wss.on('connection', (ws, req) => {
  try {
    const url = new URL(
      req.url,
      `http://${req.headers.host || 'localhost'}`
    );

    const authorization = req.headers.authorization;

    const headerToken =
      authorization &&
      authorization.startsWith('Bearer ')
        ? authorization.slice('Bearer '.length).trim()
        : null;

    const queryToken = url.searchParams.get('token');

    ws._token = headerToken || queryToken || null;

    console.log(
      `🔌 WebSocket connected auth=${Boolean(ws._token)}`
    );
  } catch (error) {
    console.error(
      'WebSocket authentication header parsing failed:',
      error
    );
    ws._token = null;
  }

  ws.on('message', async (raw) => {
    let msg = null;

    try {
      msg = JSON.parse(raw.toString());
      await handle(ws, msg);
    } catch (error) {
      console.error('❌ signaling error:', error);

      send(ws, {
        requestId: msg?.requestId ?? null,
        error: error?.message || String(error),
      });
    }
  });

  ws.on('close', () => cleanupPeer(ws._peer));

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    cleanupPeer(ws._peer);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('=================================================');
  console.log(`🚀 BESTIE mediasoup signaling listening on :${PORT}`);
  console.log(`🎯 RTP ports ${RTC_MIN_PORT}-${RTC_MAX_PORT}`);
  console.log(`🌐 announced IP ${ANNOUNCED_IP || '(not set)'}`);
  console.log(`🔐 Supabase auth ${REQUIRE_AUTH ? 'ON' : 'OFF'}`);
  console.log('=================================================');
});
