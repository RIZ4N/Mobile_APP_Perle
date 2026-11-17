-- =============================================================================
-- Perle KKN — skema awal
-- Jalankan sekali di Supabase Dashboard → SQL Editor (atau `supabase db push`).
--
-- Model: satu project Supabase = satu kelompok KKN.
--   * Pendaftar pertama otomatis menjadi admin (koordinator).
--   * Pendaftar berikutnya wajib memasukkan kode kelompok (app_config.join_code).
--
-- Konvensi sinkronisasi offline (dipakai aplikasi):
--   * id dibuat di HP (uuid), sehingga baris bisa dibuat saat offline.
--   * updated_at SELALU diisi server lewat trigger → dipakai sebagai kursor pull.
--   * Hapus = soft delete (deleted_at), supaya penghapusan ikut tersinkron.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Fungsi umum
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Konfigurasi kelompok (satu baris)
-- ---------------------------------------------------------------------------
create table public.app_config (
  id boolean primary key default true check (id),
  join_code text not null default upper(substr(md5(gen_random_uuid()::text), 1, 6))
);
insert into public.app_config default values;

-- ---------------------------------------------------------------------------
-- Profil pengguna (1:1 dengan auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role text not null default 'anggota' check (role in ('admin', 'anggota')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_updated_at_idx on public.profiles (updated_at);
create trigger profiles_set_updated_at
  before insert or update on public.profiles
  for each row execute function public.set_updated_at();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

-- Membuat profil saat user mendaftar. Pendaftar pertama → admin; selain itu
-- kode kelompok di metadata pendaftaran harus cocok, kalau tidak pendaftaran
-- dibatalkan.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_first boolean;
  v_code text;
  v_name text;
begin
  -- Cegah dua pendaftar bersamaan sama-sama dianggap "pertama".
  perform pg_advisory_xact_lock(hashtext('perle_first_user'));

  select not exists (select 1 from public.profiles) into v_is_first;

  if not v_is_first then
    select join_code into v_code from public.app_config;
    if upper(trim(coalesce(new.raw_user_meta_data ->> 'join_code', ''))) <> upper(v_code) then
      raise exception 'Kode kelompok salah';
    end if;
  end if;

  v_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '');

  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(v_name, split_part(coalesce(new.email, 'Anggota'), '@', 1)),
    case when v_is_first then 'admin' else 'anggota' end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Dipanggil form pendaftaran (belum login) supaya pesan galatnya jelas.
create or replace function public.check_join_code(p_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    not exists (select 1 from public.profiles)
    or exists (
      select 1 from public.app_config
      where upper(join_code) = upper(trim(coalesce(p_code, '')))
    );
$$;

create or replace function public.regenerate_join_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh mengganti kode kelompok';
  end if;
  update public.app_config
    set join_code = upper(substr(md5(gen_random_uuid()::text), 1, 6))
    where id
    returning join_code into v_code;
  return v_code;
end;
$$;

create or replace function public.set_member_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Hanya admin yang boleh mengubah peran';
  end if;
  if p_role not in ('admin', 'anggota') then
    raise exception 'Peran tidak dikenal: %', p_role;
  end if;
  if p_role = 'anggota' and not exists (
    select 1 from public.profiles where role = 'admin' and id <> p_user_id
  ) then
    raise exception 'Harus ada minimal satu admin';
  end if;
  update public.profiles set role = p_role where id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Barang
-- ---------------------------------------------------------------------------
create table public.items (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  category text not null default 'Lainnya',
  quantity integer not null default 1 check (quantity >= 0),
  unit text not null default 'buah',
  -- ada = sudah tersedia, harus_beli = belum ada & perlu dibeli,
  -- pinjam = dipinjam dari pihak lain (harus dikembalikan)
  status text not null default 'ada' check (status in ('ada', 'harus_beli', 'pinjam')),
  source text,                 -- milik siapa / dipinjam dari mana
  carrier_id uuid references public.profiles (id) on delete set null,
  carrier_name text,           -- penanggung jawab pembawa (boleh belum punya akun)
  notes text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index items_updated_at_idx on public.items (updated_at);
create trigger items_set_updated_at
  before insert or update on public.items
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Checklist packing (dipisah dari items supaya anggota boleh mencentang tanpa
-- hak ubah data barang, dan centang tidak bentrok dengan edit barang)
-- ---------------------------------------------------------------------------
create table public.packing_checks (
  item_id uuid primary key references public.items (id) on delete cascade,
  is_packed boolean not null default false,
  packed_by uuid references public.profiles (id) on delete set null,
  packed_at timestamptz,
  updated_at timestamptz not null default now()
);
create index packing_checks_updated_at_idx on public.packing_checks (updated_at);
create trigger packing_checks_set_updated_at
  before insert or update on public.packing_checks
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Riwayat pinjam/kembali (hasil scan QR). Stok yang sedang dipinjam dihitung
-- dari log: sum(pinjam) - sum(kembali).
-- ---------------------------------------------------------------------------
create table public.loan_logs (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items (id) on delete cascade,
  action text not null check (action in ('pinjam', 'kembali')),
  quantity integer not null default 1 check (quantity > 0),
  person_name text not null check (length(trim(person_name)) > 0),
  note text,
  occurred_at timestamptz not null default now(),
  recorded_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index loan_logs_updated_at_idx on public.loan_logs (updated_at);
create index loan_logs_item_id_idx on public.loan_logs (item_id);
create trigger loan_logs_set_updated_at
  before insert or update on public.loan_logs
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Pengeluaran
-- ---------------------------------------------------------------------------
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  description text not null check (length(trim(description)) > 0),
  amount bigint not null check (amount >= 0),   -- rupiah, tanpa desimal
  category text,
  spent_on date not null default current_date,
  paid_by_name text,                            -- siapa yang menalangi
  receipt_path text,                            -- path di bucket "receipts"
  note text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index expenses_updated_at_idx on public.expenses (updated_at);
create trigger expenses_set_updated_at
  before insert or update on public.expenses
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Hak akses dasar (GRANT). Tidak ada akses untuk anon; tidak ada DELETE dari
-- aplikasi (pakai soft delete).
-- ---------------------------------------------------------------------------
revoke all on public.app_config, public.profiles, public.items,
  public.packing_checks, public.loan_logs, public.expenses
  from anon, authenticated;

grant select on public.app_config to authenticated;
grant select on public.profiles to authenticated;
grant update (full_name) on public.profiles to authenticated;
grant select, insert, update on public.items to authenticated;
grant select, insert, update on public.packing_checks to authenticated;
grant select, insert, update on public.loan_logs to authenticated;
grant select, insert, update on public.expenses to authenticated;

revoke all on function public.is_admin() from public;
revoke all on function public.handle_new_user() from public;
revoke all on function public.check_join_code(text) from public;
revoke all on function public.regenerate_join_code() from public;
revoke all on function public.set_member_role(uuid, text) from public;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.check_join_code(text) to anon, authenticated;
grant execute on function public.regenerate_join_code() to authenticated;
grant execute on function public.set_member_role(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
--   admin   : kelola semua data
--   anggota : lihat semua, centang packing, catat pinjam/kembali,
--             tambah & ubah pengeluaran/log miliknya sendiri
-- Catatan: kebijakan INSERT ikut mengizinkan admin karena aplikasi mengirim
-- perubahan dengan upsert (INSERT ... ON CONFLICT DO UPDATE).
-- ---------------------------------------------------------------------------
alter table public.app_config enable row level security;
alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.packing_checks enable row level security;
alter table public.loan_logs enable row level security;
alter table public.expenses enable row level security;

-- app_config: hanya admin yang boleh melihat kode kelompok
create policy app_config_select_admin on public.app_config
  for select to authenticated using (public.is_admin());

-- profiles
create policy profiles_select on public.profiles
  for select to authenticated using (true);
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- items
create policy items_select on public.items
  for select to authenticated using (true);
create policy items_insert_admin on public.items
  for insert to authenticated with check (public.is_admin());
create policy items_update_admin on public.items
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- packing_checks
create policy packing_select on public.packing_checks
  for select to authenticated using (true);
create policy packing_insert on public.packing_checks
  for insert to authenticated
  with check (packed_by is null or packed_by = (select auth.uid()) or public.is_admin());
create policy packing_update on public.packing_checks
  for update to authenticated
  using (true)
  with check (packed_by is null or packed_by = (select auth.uid()) or public.is_admin());

-- loan_logs
create policy loan_logs_select on public.loan_logs
  for select to authenticated using (true);
create policy loan_logs_insert on public.loan_logs
  for insert to authenticated
  with check (recorded_by = (select auth.uid()) or public.is_admin());
create policy loan_logs_update on public.loan_logs
  for update to authenticated
  using (recorded_by = (select auth.uid()) or public.is_admin())
  with check (recorded_by = (select auth.uid()) or public.is_admin());

-- expenses
create policy expenses_select on public.expenses
  for select to authenticated using (true);
create policy expenses_insert on public.expenses
  for insert to authenticated
  with check (created_by = (select auth.uid()) or public.is_admin());
create policy expenses_update on public.expenses
  for update to authenticated
  using (created_by = (select auth.uid()) or public.is_admin())
  with check (created_by = (select auth.uid()) or public.is_admin());

-- ---------------------------------------------------------------------------
-- Storage: bucket privat untuk foto struk
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

create policy receipts_select on storage.objects
  for select to authenticated using (bucket_id = 'receipts');
create policy receipts_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'receipts');
create policy receipts_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'receipts'
    and (owner_id = (select auth.uid())::text or public.is_admin())
  );
