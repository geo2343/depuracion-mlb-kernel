create table if not exists public.dep_mlb_kernel_tests (
  test_id uuid primary key default gen_random_uuid(),
  kernel_version text not null,
  agent_version text not null,
  test_name text not null,
  expected_behavior text not null,
  observed_result text not null,
  observed_code text,
  test_scope text not null default 'CONTROLLED_INFRASTRUCTURE',
  metadata jsonb not null default '{}'::jsonb,
  tested_at timestamptz not null default now()
);
alter table public.dep_mlb_kernel_tests enable row level security;

-- The live registry contains the controlled Kernel 0.3 adversarial results, including:
-- no invocation, manual owner, phase skip, missing universe, missing phase artifacts,
-- reused Drive report, missing Drive receipt, historical Drive as SPORTS_RESEARCH,
-- manual close before F10, thin/template artifact, database-derived audit,
-- and a complete controlled F0→F10 autonomous E2E PASS.
