create table if not exists public.conversation_topics (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('conversation','joke')),
  slug text not null unique,
  prompt_tr text not null,
  prompt_en text not null,
  prompt_de text not null,
  prompt_es text not null,
  prompt_fr text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_topic_progress (
  topic_id uuid not null references public.conversation_topics(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_asked boolean not null default false,
  answer text,
  answered_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (topic_id,user_id)
);

alter table public.conversation_topics enable row level security;
alter table public.conversation_topic_progress enable row level security;
create policy "conversation topics readable by signed in users" on public.conversation_topics for select to authenticated using (true);
create policy "users add their own conversation topics" on public.conversation_topics for insert to authenticated with check (created_by=auth.uid());
create policy "users read their own topic progress" on public.conversation_topic_progress for select to authenticated using (user_id=auth.uid());
create policy "users insert their own topic progress" on public.conversation_topic_progress for insert to authenticated with check (user_id=auth.uid());
create policy "users update their own topic progress" on public.conversation_topic_progress for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

insert into public.conversation_topics (category,slug,prompt_tr,prompt_en,prompt_de,prompt_es,prompt_fr) values
('conversation','personality-type','Şu tip insan mısın?','What kind of person are you?','Was für ein Mensch bist du?','¿Qué tipo de persona eres?','Quel genre de personne es-tu ?'),
('conversation','toothpaste','Diş macununu ortasından mı sıkarsın, altından mı?','Do you squeeze toothpaste from the middle or the bottom?','Drückst du die Zahnpasta in der Mitte oder von unten?','¿Aprietas la pasta de dientes desde el centro o desde abajo?','Tu presses le dentifrice au milieu ou par le bas ?'),
('conversation','perfect-day','Hiçbir sorumluluğun olmasa mükemmel gününü nasıl geçirirdin?','If you had no responsibilities, how would you spend your perfect day?','Wenn du keine Verpflichtungen hättest, wie würdest du deinen perfekten Tag verbringen?','Si no tuvieras responsabilidades, ¿cómo pasarías tu día perfecto?','Si tu n’avais aucune responsabilité, comment passerais-tu ta journée parfaite ?'),
('conversation','childhood-memory','Çocukluğundan en komik anın ne?','What is your funniest childhood memory?','Was ist deine lustigste Kindheitserinnerung?','¿Cuál es tu recuerdo más gracioso de la infancia?','Quel est ton souvenir d’enfance le plus drôle ?'),
('conversation','small-things','Seni küçük şeylerle mutlu eden şeyler neler?','What small things make you happy?','Welche kleinen Dinge machen dich glücklich?','¿Qué pequeñas cosas te hacen feliz?','Quelles petites choses te rendent heureux ?'),
('conversation','dream-trip','Birlikte gitmek isteyeceğin hayalindeki yer neresi?','Where is your dream place to visit together?','Welchen Traumort würdest du gern gemeinsam besuchen?','¿Cuál es el lugar de tus sueños para visitar juntos?','Quel endroit de rêve aimerais-tu visiter ensemble ?'),
('conversation','comfort-food','Kötü bir günün sonunda seni en çok hangi yemek rahatlatır?','Which food comforts you most after a bad day?','Welches Essen tröstet dich nach einem schlechten Tag am meisten?','¿Qué comida te reconforta más después de un mal día?','Quel plat te réconforte le plus après une mauvaise journée ?'),
('conversation','superpower','Bir süper gücün olsa hangisini seçerdin?','If you could have one superpower, which would you choose?','Wenn du eine Superkraft hättest, welche würdest du wählen?','Si pudieras tener un superpoder, ¿cuál elegirías?','Si tu pouvais avoir un super-pouvoir, lequel choisirais-tu ?'),
('joke','knock-knock','Kapıyı kim çalıyor? — Komik bir “Kim o?” şakası uydur.','Who is knocking? — Make up a funny knock-knock joke.','Wer klopft? — Erfinde einen lustigen Klopf-Klopf-Witz.','¿Quién llama? — Inventa un chiste de “toc toc”.','Qui frappe ? — Invente une blague de « toc toc ».') on conflict (slug) do nothing;
