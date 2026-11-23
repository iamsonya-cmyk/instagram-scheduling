-- 인스타그램 스케줄링: Supabase 초기 설정
-- Supabase 대시보드 > SQL Editor > New query 에 전체를 붙여넣고 Run 한 번만 실행하세요.
-- (이전 버전 SQL을 이미 실행했어도 그대로 다시 실행하면 새 항목이 추가돼요.)

-- 1) 작업(TASKS) 테이블
create table if not exists public.tasks (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  task_type      text not null default '',                       -- 카드뉴스 / 릴스 / 기타
  status         text not null default 'none'
                 check (status in ('none','working','done','uploaded')),
  task_date      date,                                           -- 날짜는 선택
  project_month  text not null default to_char(current_date, 'YYYY-MM'),  -- 소속 프로젝트(월)
  assignee       text not null default '',
  memo           text not null default '',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- 이전 버전 테이블이 있는 경우를 위한 보강 (새로 만든 경우에는 영향 없음)
alter table public.tasks alter column task_date drop not null;
alter table public.tasks alter column task_date drop default;
alter table public.tasks add column if not exists task_type text not null default '';
alter table public.tasks add column if not exists project_month text not null default to_char(current_date, 'YYYY-MM');
update public.tasks set project_month = to_char(task_date, 'YYYY-MM') where task_date is not null;

-- 2) 첨부파일 정보 테이블 (작업 삭제 시 함께 삭제)
create table if not exists public.task_files (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.tasks(id) on delete cascade,
  name        text not null,
  path        text not null,
  size        bigint not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists tasks_month_idx on public.tasks (project_month);
create index if not exists tasks_date_idx on public.tasks (task_date);
create index if not exists task_files_task_idx on public.task_files (task_id);

-- 3) 접근 권한: 링크를 아는 팀원이 모두 읽고 쓸 수 있는 공용 설정
alter table public.tasks enable row level security;
alter table public.task_files enable row level security;

drop policy if exists "team all tasks" on public.tasks;
create policy "team all tasks" on public.tasks
  for all using (true) with check (true);

drop policy if exists "team all task_files" on public.task_files;
create policy "team all task_files" on public.task_files
  for all using (true) with check (true);

-- 4) 첨부파일 저장소(Storage 버킷)
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', true)
on conflict (id) do nothing;

drop policy if exists "team all attachments" on storage.objects;
create policy "team all attachments" on storage.objects
  for all using (bucket_id = 'attachments') with check (bucket_id = 'attachments');

-- 5) 실시간 동기화 (여러 명이 동시에 볼 때 자동 갱신)
-- 이미 추가돼 있으면 "already member" 오류가 나는데, 무시해도 돼요.
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.task_files;
