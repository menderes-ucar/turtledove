import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json' },
})

function base64url(input: string) {
  return btoa(input).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToArrayBuffer(pem: string) {
  const clean = pem.replace(/-----BEGIN PRIVATE KEY-----/g, '').replace(/-----END PRIVATE KEY-----/g, '').replace(/\s/g, '')
  const binary = atob(clean)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

async function getAccessToken(projectId: string, email: string, privateKey: string) {
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const now = Math.floor(Date.now() / 1000)
  const claim = base64url(JSON.stringify({
    iss: email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToArrayBuffer(privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  )
  const signingInput = `${header}.${claim}`
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput),
  )
  const sigBytes = new Uint8Array(signature)
  let sigBinary = ''
  for (const b of sigBytes) sigBinary += String.fromCharCode(b)
  const jwt = `${signingInput}.${base64url(sigBinary)}`

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  if (!response.ok) throw new Error(`Google OAuth failed: ${response.status} ${await response.text()}`)
  const data = await response.json()
  return data.access_token as string
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'POST required' }, 405)
  try {
    const { notification_id } = await req.json()
    if (!notification_id) return json({ error: 'notification_id is required' }, 400)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const projectId = Deno.env.get('FCM_PROJECT_ID')!
    const email = Deno.env.get('FCM_CLIENT_EMAIL')!
    const privateKey = Deno.env.get('FCM_PRIVATE_KEY')!.replace(/\\n/g, '\n')

    const admin = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } })
    const { data: notification, error: nError } = await admin
      .from('notifications').select('*').eq('id', notification_id).single()
    if (nError) throw nError

    const { data: tokens, error: tError } = await admin
      .from('device_tokens').select('token').eq('user_id', notification.user_id)
    if (tError) throw tError
    if (!tokens?.length) return json({ sent: 0, reason: 'no_device_tokens' })

    const accessToken = await getAccessToken(projectId, email, privateKey)
    let sent = 0
    const type = notification.type?.toString() ?? ''
    const baseData = Object.fromEntries(
      Object.entries({
        ...(notification.data ?? {}),
        type,
        title: notification.title,
        body: notification.body,
        notification_id: notification.id,
      }).map(([k, v]) => [k, String(v)]),
    )

    for (const row of tokens) {
      // Calls are data-only so Android's background handler can issue a
      // full-screen local call notification instead of a normal tray item.
      const message: Record<string, unknown> = {
        token: row.token,
        data: baseData,
        android: {
          priority: 'high',
          // A call invitation is intentionally data-only. This lets the
          // Flutter background handler create the full-screen call notification
          // instead of Android treating it as an ordinary tray notification.
          ...((type === 'call' || type === 'call_end')
            ? { ttl: '30s', direct_boot_ok: true }
            : { notification: { channel_id: 'bestie_notifications_v3', sound: 'default' } }),
        },
        apns: {
          headers: type === 'call'
            ? { 'apns-priority': '10' }
            : { 'apns-priority': '10' },
          payload: { aps: type === 'call' ? { 'content-available': 1, sound: 'default' } : { sound: 'default' } },
        },
      }

      if (type !== 'call' && type !== 'call_end') {
        message.notification = { title: notification.title, body: notification.body }
      }

      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message }),
      })
      if (response.ok) sent++
      else {
        const text = await response.text()
        console.error('FCM send failed', row.token, response.status, text)
        if (response.status === 404 || response.status === 400) {
          await admin.from('device_tokens').delete().eq('token', row.token)
        }
      }
    }
    return json({ sent, total: tokens.length, type })
  } catch (e) {
    console.error(e)
    return json({ error: String(e) }, 500)
  }
})
