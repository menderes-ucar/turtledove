-- Recipient-specific localization for push notifications.
alter table public.profiles add column if not exists language_code text not null default 'tr';
update public.profiles set language_code='tr' where language_code is null or language_code not in ('tr','en','de','es','fr');
alter table public.profiles drop constraint if exists profiles_language_code_check;
alter table public.profiles add constraint profiles_language_code_check check (language_code in ('tr','en','de','es','fr'));
