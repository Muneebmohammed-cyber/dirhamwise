-- DirhamWise · Mess groups (shared grocery budget)
-- Run once in Supabase → SQL Editor. Safe to re-run.

create extension if not exists pgcrypto;

create table if not exists public.mess_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  code text not null unique,
  currency text not null default 'AED',
  monthly_budget numeric(12,2) not null default 0 check (monthly_budget >= 0),
  cycle_day int not null default 1 check (cycle_day between 1 and 28),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.mess_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.mess_groups(id) on delete cascade,
  user_id uuid not null default auth.uid(),
  name text not null check (char_length(name) between 1 and 40),
  role text not null default 'member' check (role in ('admin','member')),
  active boolean not null default true,
  joined_at timestamptz not null default now(),
  unique (group_id, user_id)
);

create table if not exists public.mess_expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.mess_groups(id) on delete cascade,
  paid_by uuid not null references public.mess_members(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0 and amount < 1000000),
  item text not null default '' check (char_length(item) <= 80),
  category text not null default 'Groceries' check (char_length(category) <= 40),
  shop text not null default '' check (char_length(shop) <= 60),
  note text not null default '' check (char_length(note) <= 200),
  spent_on date not null default current_date,
  split_among uuid[] not null default '{}',
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists mess_expenses_group_date on public.mess_expenses (group_id, spent_on desc);

create table if not exists public.mess_settlements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.mess_groups(id) on delete cascade,
  from_member uuid not null references public.mess_members(id) on delete restrict,
  to_member uuid not null references public.mess_members(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0 and amount < 1000000),
  paid_on date not null default current_date,
  note text not null default '' check (char_length(note) <= 200),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  check (from_member <> to_member)
);
create index if not exists mess_settlements_group on public.mess_settlements (group_id, paid_on desc);

-- helpers (security definer so policies don't recurse)
create or replace function public.mess_is_member(g uuid) returns boolean
language sql security definer stable set search_path = public, extensions as $$
  select exists (select 1 from mess_members where group_id = g and user_id = auth.uid() and active)
$$;
create or replace function public.mess_is_admin(g uuid) returns boolean
language sql security definer stable set search_path = public, extensions as $$
  select exists (select 1 from mess_members where group_id = g and user_id = auth.uid() and active and role = 'admin')
$$;
create or replace function public.mess_member_in_group(m uuid, g uuid) returns boolean
language sql security definer stable set search_path = public, extensions as $$
  select exists (select 1 from mess_members where id = m and group_id = g)
$$;

-- create a group: caller becomes admin
create or replace function public.mess_create_group(p_name text, p_member_name text, p_budget numeric default 0, p_currency text default 'AED', p_cycle_day int default 1)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare g uuid; c text; tries int := 0;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  loop
    c := upper(substr(translate(encode(gen_random_bytes(8), 'base64'), '+/=0O1Il', 'ABCDEFGH'), 1, 6));
    exit when not exists (select 1 from mess_groups where code = c);
    tries := tries + 1; if tries > 20 then raise exception 'Could not create a code'; end if;
  end loop;
  insert into mess_groups (name, code, currency, monthly_budget, cycle_day, created_by)
    values (trim(p_name), c, coalesce(p_currency,'AED'), greatest(coalesce(p_budget,0),0), least(greatest(coalesce(p_cycle_day,1),1),28), auth.uid())
    returning id into g;
  insert into mess_members (group_id, user_id, name, role) values (g, auth.uid(), trim(p_member_name), 'admin');
  return g;
end $$;

-- join with an invite code (re-joining reactivates your old membership)
create or replace function public.mess_join_group(p_code text, p_member_name text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare g uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select id into g from mess_groups where code = upper(trim(p_code));
  if g is null then raise exception 'No mess found with that code'; end if;
  insert into mess_members (group_id, user_id, name) values (g, auth.uid(), trim(p_member_name))
    on conflict (group_id, user_id) do update set active = true, name = excluded.name;
  return g;
end $$;

-- new invite code (admin)
create or replace function public.mess_new_code(p_group uuid) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare c text;
begin
  if not mess_is_admin(p_group) then raise exception 'Only the mess admin can do this'; end if;
  loop
    c := upper(substr(translate(encode(gen_random_bytes(8), 'base64'), '+/=0O1Il', 'ABCDEFGH'), 1, 6));
    exit when not exists (select 1 from mess_groups where code = c);
  end loop;
  update mess_groups set code = c where id = p_group; return c;
end $$;

revoke all on function public.mess_create_group(text,text,numeric,text,int) from public;
revoke all on function public.mess_join_group(text,text) from public;
revoke all on function public.mess_new_code(uuid) from public;
grant execute on function public.mess_create_group(text,text,numeric,text,int) to authenticated;
grant execute on function public.mess_join_group(text,text) to authenticated;
grant execute on function public.mess_new_code(uuid) to authenticated;
grant execute on function public.mess_is_member(uuid), public.mess_is_admin(uuid), public.mess_member_in_group(uuid,uuid) to authenticated;

-- row level security
alter table public.mess_groups enable row level security;
alter table public.mess_members enable row level security;
alter table public.mess_expenses enable row level security;
alter table public.mess_settlements enable row level security;

drop policy if exists g_sel on public.mess_groups;      create policy g_sel on public.mess_groups for select to authenticated using (mess_is_member(id));
drop policy if exists g_upd on public.mess_groups;      create policy g_upd on public.mess_groups for update to authenticated using (mess_is_admin(id)) with check (mess_is_admin(id));
drop policy if exists g_del on public.mess_groups;      create policy g_del on public.mess_groups for delete to authenticated using (mess_is_admin(id));

drop policy if exists m_sel on public.mess_members;     create policy m_sel on public.mess_members for select to authenticated using (mess_is_member(group_id));
drop policy if exists m_upd on public.mess_members;     create policy m_upd on public.mess_members for update to authenticated
  using (user_id = auth.uid() or mess_is_admin(group_id)) with check (mess_is_member(group_id) or user_id = auth.uid());

drop policy if exists e_sel on public.mess_expenses;    create policy e_sel on public.mess_expenses for select to authenticated using (mess_is_member(group_id));
drop policy if exists e_ins on public.mess_expenses;    create policy e_ins on public.mess_expenses for insert to authenticated
  with check (mess_is_member(group_id) and created_by = auth.uid() and mess_member_in_group(paid_by, group_id));
drop policy if exists e_upd on public.mess_expenses;    create policy e_upd on public.mess_expenses for update to authenticated
  using (mess_is_member(group_id) and (created_by = auth.uid() or mess_is_admin(group_id))) with check (mess_member_in_group(paid_by, group_id));
drop policy if exists e_del on public.mess_expenses;    create policy e_del on public.mess_expenses for delete to authenticated
  using (mess_is_member(group_id) and (created_by = auth.uid() or mess_is_admin(group_id)));

drop policy if exists s_sel on public.mess_settlements; create policy s_sel on public.mess_settlements for select to authenticated using (mess_is_member(group_id));
drop policy if exists s_ins on public.mess_settlements; create policy s_ins on public.mess_settlements for insert to authenticated
  with check (mess_is_member(group_id) and created_by = auth.uid() and mess_member_in_group(from_member, group_id) and mess_member_in_group(to_member, group_id));
drop policy if exists s_del on public.mess_settlements; create policy s_del on public.mess_settlements for delete to authenticated
  using (mess_is_member(group_id) and (created_by = auth.uid() or mess_is_admin(group_id)));

grant select, delete on public.mess_groups to authenticated;
revoke update on public.mess_members, public.mess_expenses, public.mess_groups from authenticated;
grant select on public.mess_members to authenticated;
grant update (name, active) on public.mess_members to authenticated;
grant update (name, monthly_budget, currency, cycle_day) on public.mess_groups to authenticated;
grant select, insert, delete on public.mess_expenses, public.mess_settlements to authenticated;
grant update (paid_by, amount, item, category, shop, note, spent_on, split_among) on public.mess_expenses to authenticated;

-- admin can promote / demote members
create or replace function public.mess_set_role(p_member uuid, p_role text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g uuid;
begin
  select group_id into g from mess_members where id = p_member;
  if g is null or not mess_is_admin(g) then raise exception 'Only the mess admin can do this'; end if;
  if p_role not in ('admin','member') then raise exception 'Invalid role'; end if;
  update mess_members set role = p_role where id = p_member;
end $$;
revoke all on function public.mess_set_role(uuid,text) from public;
grant execute on function public.mess_set_role(uuid,text) to authenticated;

-- live updates
do $$ begin
  begin alter publication supabase_realtime add table public.mess_expenses; exception when others then null; end;
  begin alter publication supabase_realtime add table public.mess_settlements; exception when others then null; end;
  begin alter publication supabase_realtime add table public.mess_members; exception when others then null; end;
  begin alter publication supabase_realtime add table public.mess_groups; exception when others then null; end;
end $$;
