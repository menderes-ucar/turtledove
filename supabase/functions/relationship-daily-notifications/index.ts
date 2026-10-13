import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const url = Deno.env.get('SUPABASE_URL')!
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(url, serviceKey)

const templates: Record<string, { streakTitle: string; streakBody: string; summaryTitle: string; summaryBody: (n: number) => string }> = {
  tr: { streakTitle: '🔥 Streak’in devam ediyor', streakBody: 'Bugün birlikte bir aktivite yaparak serinizi koruyun.', summaryTitle: '❤️ Bugün Biz hazır', summaryBody: (n) => `Bugün birlikte ${n} aktivite yaptınız.` },
  en: { streakTitle: '🔥 Keep your streak going', streakBody: 'Do something together today to keep your streak alive.', summaryTitle: '❤️ Today, Us is ready', summaryBody: (n) => `You shared ${n} activities today.` },
  de: { streakTitle: '🔥 Haltet eure Serie am Laufen', streakBody: 'Macht heute etwas zusammen, um eure Serie zu erhalten.', summaryTitle: '❤️ Heute, wir ist bereit', summaryBody: (n) => `Ihr hattet heute ${n} gemeinsame Aktivitäten.` },
  es: { streakTitle: '🔥 Mantengan su racha', streakBody: 'Hagan algo juntos hoy para mantener su racha.', summaryTitle: '❤️ Hoy, nosotros está listo', summaryBody: (n) => `Hoy tuvieron ${n} actividades compartidas.` },
  fr: { streakTitle: '🔥 Gardez votre série', streakBody: 'Faites une activité ensemble aujourd’hui pour conserver votre série.', summaryTitle: '❤️ Aujourd’hui, nous est prêt', summaryBody: (n) => `Vous avez eu ${n} activités partagées aujourd’hui.` },
}


Deno.serve(async () => {
  const today = new Date().toISOString().slice(0, 10)
  const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10)
  const { data: rows, error } = await supabase.from('relationship_daily_activity').select('user_id,partner_id').eq('activity_day', yesterday)
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 })

  const uniquePairs = new Map<string, { user_id: string; partner_id: string }>()
  for (const row of rows ?? []) uniquePairs.set(`${row.user_id}:${row.partner_id}`, row)

  let created = 0
  for (const pair of uniquePairs.values()) {
    const { data: todayRow } = await supabase.from('relationship_daily_activity')
      .select('message_count,photo_count,video_count,game_count,interaction_count,completed_task_count')
      .eq('user_id', pair.user_id).eq('partner_id', pair.partner_id).eq('activity_day', today).maybeSingle()

    const totalToday = todayRow
      ? Number(todayRow.message_count ?? 0) + Number(todayRow.photo_count ?? 0) + Number(todayRow.video_count ?? 0) + Number(todayRow.game_count ?? 0) + Number(todayRow.interaction_count ?? 0) + Number(todayRow.completed_task_count ?? 0)
      : 0

    const { data: profile } = await supabase.from('profiles').select('language_code').eq('id', pair.user_id).maybeSingle()
    const lang = templates[profile?.language_code ?? 'en'] ? (profile?.language_code ?? 'en') : 'en'
    const t = templates[lang]
    const kind = totalToday > 0 ? 'today_us' : 'relationship_streak'
    const eventKey = `${kind}:${today}:${pair.user_id}:${pair.partner_id}`
    const title = totalToday > 0 ? t.summaryTitle : t.streakTitle
    const body = totalToday > 0 ? t.summaryBody(totalToday) : t.streakBody

    const { data: notificationId, error: insertError } = await supabase.rpc('create_system_relationship_notification', {
      p_user_id: pair.user_id, p_title: title, p_body: body, p_type: kind,
      p_data: { event_key: eventKey, action: 'open_us', type: kind },
    })
    if (insertError || !notificationId) continue
    try {
      await fetch(`${url}/functions/v1/send-push-notification`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${serviceKey}` },
        body: JSON.stringify({ notification_id: notificationId }),
      })
    } catch (_) {}
    created++
  }
  return new Response(JSON.stringify({ date: today, created }), { headers: { 'Content-Type': 'application/json' } })
})
