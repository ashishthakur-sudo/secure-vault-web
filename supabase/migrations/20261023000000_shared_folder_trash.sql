alter table public.shared_files
  add column if not exists deleted_at timestamptz;

create index if not exists shared_files_deleted_at_created_at_idx
  on public.shared_files (deleted_at, created_at desc);
