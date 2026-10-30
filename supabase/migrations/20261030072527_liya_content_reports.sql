create table public.liya_content_reports (
  id uuid primary key,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  media_id text not null references public.liya_example_media(id),
  target_type text not null check (target_type in ('profile','post','video')),
  reason text not null check (reason in ('Sexual content','Harassment','Discrimination','Incorrect content','Other')),
  created_at timestamptz not null default now()
);
alter table public.liya_content_reports enable row level security;
revoke all on public.liya_content_reports from public, anon, authenticated;
grant select, insert on public.liya_content_reports to authenticated;
create policy liya_reports_read_own on public.liya_content_reports for select to authenticated using (reporter_id = (select auth.uid()));
create policy liya_reports_insert_own on public.liya_content_reports for insert to authenticated with check (reporter_id = (select auth.uid()));
