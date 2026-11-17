-- Uji aturan pendaftaran & RLS. Setiap pelanggaran memunculkan EXCEPTION
-- sehingga psql (ON_ERROR_STOP=1) berhenti dengan kode keluar bukan nol.

-- Pembantu: jalankan SQL sebagai user tertentu dan pastikan DITOLAK.
create function pg_temp.expect_denied(p_label text, p_sql text) returns void
language plpgsql as $$
declare
  v_rows bigint;
begin
  begin
    execute p_sql;
    get diagnostics v_rows = row_count;
  exception when others then
    raise notice 'ok (ditolak): % — %', p_label, sqlerrm;
    return;
  end;
  if v_rows = 0 then
    raise notice 'ok (0 baris): %', p_label;
    return;
  end if;
  raise exception 'SEHARUSNYA DITOLAK: %', p_label;
end;
$$;

create function pg_temp.login(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
end;
$$;

-- ---------------------------------------------------------------- pendaftaran
do $$
declare
  v_code text;
  v_admin uuid := '00000000-0000-0000-0000-00000000000a';
  v_member uuid := '00000000-0000-0000-0000-00000000000b';
  v_member2 uuid := '00000000-0000-0000-0000-00000000000c';
begin
  -- Pendaftar pertama → admin, tanpa kode.
  if not public.check_join_code(null) then
    raise exception 'pendaftar pertama harus lolos tanpa kode';
  end if;
  insert into auth.users (id, email, raw_user_meta_data)
    values (v_admin, 'koor@example.com', '{"full_name": "Koor Perle"}');
  if (select role from public.profiles where id = v_admin) <> 'admin' then
    raise exception 'pendaftar pertama harus admin';
  end if;

  select join_code into v_code from public.app_config;

  -- Pendaftar kedua tanpa kode / kode salah → ditolak.
  if public.check_join_code('SALAH1') then
    raise exception 'kode salah harus ditolak check_join_code';
  end if;
  begin
    insert into auth.users (id, email, raw_user_meta_data)
      values (v_member, 'a@example.com', '{"full_name": "Anggota A", "join_code": "SALAH1"}');
    raise exception 'pendaftaran dengan kode salah harus gagal';
  exception when others then
    if sqlerrm <> 'Kode kelompok salah' then raise; end if;
  end;

  -- Kode benar (huruf kecil + spasi) → anggota.
  insert into auth.users (id, email, raw_user_meta_data)
    values (v_member, 'a@example.com',
      jsonb_build_object('full_name', 'Anggota A', 'join_code', ' ' || lower(v_code) || ' '));
  insert into auth.users (id, email, raw_user_meta_data)
    values (v_member2, 'b@example.com', jsonb_build_object('join_code', v_code));
  if (select role from public.profiles where id = v_member) <> 'anggota' then
    raise exception 'pendaftar kedua harus anggota';
  end if;
  if (select full_name from public.profiles where id = v_member2) <> 'b' then
    raise exception 'nama bawaan harus diambil dari email';
  end if;
end;
$$;

-- ------------------------------------------------------------------ sbg admin
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
set role authenticated;

insert into public.items (id, name, status, created_by)
  values ('10000000-0000-0000-0000-000000000001', 'Kompor portable', 'ada',
          '00000000-0000-0000-0000-00000000000a');
-- upsert (jalur yang dipakai aplikasi)
insert into public.items (id, name, quantity, status)
  values ('10000000-0000-0000-0000-000000000001', 'Kompor portable', 2, 'pinjam')
  on conflict (id) do update set quantity = excluded.quantity, status = excluded.status;

do $$
begin
  if (select count(*) from public.app_config) <> 1 then
    raise exception 'admin harus bisa melihat kode kelompok';
  end if;
  if (select updated_at <= created_at from public.items
      where id = '10000000-0000-0000-0000-000000000001') then
    raise exception 'updated_at harus diperbarui trigger';
  end if;
end;
$$;

-- ---------------------------------------------------------------- sbg anggota
reset role;
select pg_temp.login('00000000-0000-0000-0000-00000000000b');
set role authenticated;

do $$
begin
  if (select count(*) from public.items) <> 1 then
    raise exception 'anggota harus bisa melihat barang';
  end if;
  if (select count(*) from public.app_config) <> 0 then
    raise exception 'anggota tidak boleh melihat kode kelompok';
  end if;
  if (select count(*) from public.profiles) <> 3 then
    raise exception 'anggota harus bisa melihat daftar anggota';
  end if;
end;
$$;

select pg_temp.expect_denied('anggota menambah barang',
  $$insert into public.items (name) values ('Barang gelap')$$);
select pg_temp.expect_denied('anggota mengubah barang',
  $$update public.items set name = 'x'$$);
select pg_temp.expect_denied('anggota menghapus barang',
  $$delete from public.items$$);
select pg_temp.expect_denied('anggota menaikkan peran sendiri',
  $$update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000b'$$);
select pg_temp.expect_denied('anggota mengubah nama orang lain',
  $$update public.profiles set full_name = 'x' where id = '00000000-0000-0000-0000-00000000000a'$$);
select pg_temp.expect_denied('anggota memanggil set_member_role',
  $$select public.set_member_role('00000000-0000-0000-0000-00000000000b', 'admin')$$);
select pg_temp.expect_denied('anggota mengganti kode kelompok',
  $$select public.regenerate_join_code()$$);

-- Yang BOLEH dilakukan anggota
update public.profiles set full_name = 'Anggota A (baru)'
  where id = '00000000-0000-0000-0000-00000000000b';

insert into public.packing_checks (item_id, is_packed, packed_by, packed_at)
  values ('10000000-0000-0000-0000-000000000001', true,
          '00000000-0000-0000-0000-00000000000b', now())
  on conflict (item_id) do update
    set is_packed = excluded.is_packed, packed_by = excluded.packed_by, packed_at = excluded.packed_at;

insert into public.loan_logs (id, item_id, action, quantity, person_name, recorded_by)
  values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
          'pinjam', 1, 'Pak RT', '00000000-0000-0000-0000-00000000000b');

insert into public.expenses (id, description, amount, created_by)
  values ('30000000-0000-0000-0000-000000000001', 'Gas 3 kg', 22000,
          '00000000-0000-0000-0000-00000000000b');
update public.expenses set amount = 23000 where id = '30000000-0000-0000-0000-000000000001';

select pg_temp.expect_denied('anggota mencatat log atas nama orang lain',
  $$insert into public.loan_logs (item_id, action, person_name, recorded_by)
    values ('10000000-0000-0000-0000-000000000001', 'pinjam', 'x',
            '00000000-0000-0000-0000-00000000000a')$$);
select pg_temp.expect_denied('anggota mencatat pengeluaran atas nama orang lain',
  $$insert into public.expenses (description, amount, created_by)
    values ('x', 1, '00000000-0000-0000-0000-00000000000a')$$);

insert into storage.objects (bucket_id, name, owner_id)
  values ('receipts', '30000000-0000-0000-0000-000000000001/1.jpg',
          '00000000-0000-0000-0000-00000000000b');

-- ------------------------------------------------------------ anggota lainnya
reset role;
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
set role authenticated;

select pg_temp.expect_denied('anggota lain mengubah pengeluaran orang',
  $$update public.expenses set amount = 1$$);
select pg_temp.expect_denied('anggota lain mengubah log orang',
  $$update public.loan_logs set quantity = 99$$);
select pg_temp.expect_denied('anggota lain menghapus struk orang',
  $$delete from storage.objects$$);
-- upsert atas baris milik orang lain (jalur aplikasi) juga harus gagal
select pg_temp.expect_denied('anggota lain meng-upsert pengeluaran orang',
  $$insert into public.expenses (id, description, amount, created_by)
    values ('30000000-0000-0000-0000-000000000001', 'x', 1,
            '00000000-0000-0000-0000-00000000000c')
    on conflict (id) do update set amount = excluded.amount$$);
-- tetapi boleh membatalkan centang packing orang lain
update public.packing_checks set is_packed = false, packed_by = null, packed_at = null;

-- ------------------------------------------------------- admin atas data orang
reset role;
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
set role authenticated;

-- admin meng-upsert pengeluaran milik anggota (soft delete)
insert into public.expenses (id, description, amount, created_by, deleted_at)
  values ('30000000-0000-0000-0000-000000000001', 'Gas 3 kg', 23000,
          '00000000-0000-0000-0000-00000000000b', now())
  on conflict (id) do update set deleted_at = excluded.deleted_at;
update public.loan_logs set deleted_at = now();
select public.set_member_role('00000000-0000-0000-0000-00000000000b', 'admin');
select public.set_member_role('00000000-0000-0000-0000-00000000000b', 'anggota');
select pg_temp.expect_denied('admin terakhir diturunkan',
  $$select public.set_member_role('00000000-0000-0000-0000-00000000000a', 'anggota')$$);

do $$
declare
  v_old text;
  v_new text;
begin
  select join_code into v_old from public.app_config;
  v_new := public.regenerate_join_code();
  if v_new = v_old or length(v_new) <> 6 then
    raise exception 'kode kelompok harus berganti';
  end if;
end;
$$;

-- ------------------------------------------------------------------ sbg anon
reset role;
select pg_temp.login(null);
set role anon;
select pg_temp.expect_denied('anon membaca barang', $$select * from public.items$$);
select pg_temp.expect_denied('anon membaca profil', $$select * from public.profiles$$);
select pg_temp.expect_denied('anon membaca kode', $$select * from public.app_config$$);
select public.check_join_code('apa saja');
reset role;

select 'SEMUA UJI RLS LULUS' as hasil;
