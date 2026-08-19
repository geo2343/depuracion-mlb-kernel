create table if not exists kernel_runs (
  id uuid primary key default gen_random_uuid(),
  run_id text unique not null,
  status text not null default 'NEW',
  created_at timestamptz not null default now()
);

create table if not exists kernel_events (
  id bigint generated always as identity primary key,
  run_id text not null,
  event_type text not null,
  task_id text,
  game_id text,
  payload jsonb not null default '{}'::jsonb,
  prev_hash text,
  event_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists kernel_events_run_id_idx on kernel_events(run_id, id);
