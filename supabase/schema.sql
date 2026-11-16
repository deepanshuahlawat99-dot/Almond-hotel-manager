-- Run once in Supabase SQL Editor. All hotel data is isolated behind RLS.
create extension if not exists pgcrypto;
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, role text not null check(role in ('owner','staff')), created_at timestamptz not null default now());
create table public.rooms (id bigint generated always as identity primary key, number text not null unique, category text not null default 'Standard', base_rate numeric(12,2) not null default 0 check(base_rate>=0), status text not null default 'available' check(status in ('available','occupied','reserved','cleaning','maintenance')), created_at timestamptz not null default now());
create table public.bookings (id uuid primary key default gen_random_uuid(), room_id bigint not null references public.rooms(id), guest_name text not null, guest_phone text, check_in timestamptz not null default now(), check_out timestamptz, nightly_rate numeric(12,2) not null check(nightly_rate>=0), status text not null default 'checked_in' check(status in ('reserved','checked_in','checked_out','cancelled')), notes text, created_by uuid references auth.users(id), created_at timestamptz not null default now(), constraint valid_stay check(check_out is null or check_out>check_in));
create unique index one_active_booking_per_room on public.bookings(room_id) where status='checked_in';
create table public.payments (id uuid primary key default gen_random_uuid(), booking_id uuid not null references public.bookings(id), amount numeric(12,2) not null check(amount>0), method text not null check(method in ('cash','upi','card','bank','other')), paid_at timestamptz not null default now(), created_by uuid references auth.users(id));
create table public.expenses (id uuid primary key default gen_random_uuid(), category text not null, description text not null, amount numeric(12,2) not null check(amount>0), spent_at timestamptz not null default now(), created_by uuid references auth.users(id));
create index bookings_room_idx on public.bookings(room_id);
create index bookings_created_idx on public.bookings(created_at);
create index payments_paid_idx on public.payments(paid_at);
create index expenses_spent_idx on public.expenses(spent_at);
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles where id=(select auth.uid()) and role in ('owner','staff')); $$;
create or replace function public.is_owner() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles where id=(select auth.uid()) and role='owner'); $$;
revoke all on function public.is_staff() from public; revoke all on function public.is_owner() from public;
grant execute on function public.is_staff() to authenticated; grant execute on function public.is_owner() to authenticated;
alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.bookings enable row level security;
alter table public.payments enable row level security;
alter table public.expenses enable row level security;
create policy profiles_read on public.profiles for select to authenticated using (id=(select auth.uid()) or public.is_owner());
create policy rooms_read on public.rooms for select to authenticated using (public.is_staff());
create policy rooms_write on public.rooms for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy bookings_read on public.bookings for select to authenticated using (public.is_staff());
create policy bookings_insert on public.bookings for insert to authenticated with check (public.is_staff() and created_by=(select auth.uid()));
create policy bookings_update on public.bookings for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy payments_read on public.payments for select to authenticated using (public.is_staff());
create policy payments_insert on public.payments for insert to authenticated with check (public.is_staff() and created_by=(select auth.uid()));
create policy expenses_read on public.expenses for select to authenticated using (public.is_staff());
create policy expenses_insert on public.expenses for insert to authenticated with check (public.is_staff() and created_by=(select auth.uid()));
-- Atomic check-in / checkout keeps room and booking state consistent.
create or replace function public.check_in_guest(p_room_id bigint,p_guest_name text,p_guest_phone text,p_rate numeric,p_notes text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare v_room public.rooms%rowtype; v_booking uuid;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 if nullif(trim(p_guest_name),'') is null or p_rate is null or p_rate<0 then raise exception 'Invalid guest or rate'; end if;
 select * into v_room from public.rooms where id=p_room_id for update;
 if not found or v_room.status<>'available' then raise exception 'Room is not available'; end if;
 insert into public.bookings(room_id,guest_name,guest_phone,nightly_rate,notes,created_by) values(p_room_id,trim(p_guest_name),nullif(trim(p_guest_phone),''),p_rate,p_notes,(select auth.uid())) returning id into v_booking;
 update public.rooms set status='occupied' where id=p_room_id;
 return v_booking;
end; $$;
create or replace function public.check_out_guest(p_booking_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_booking public.bookings%rowtype;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 select * into v_booking from public.bookings where id=p_booking_id for update;
 if not found or v_booking.status<>'checked_in' then raise exception 'No active booking'; end if;
 update public.rooms set status='cleaning' where id=v_booking.room_id;
 update public.bookings set status='checked_out',check_out=now() where id=p_booking_id;
end; $$;
revoke all on function public.check_in_guest(bigint,text,text,numeric,text) from public;
revoke all on function public.check_out_guest(uuid) from public;
grant execute on function public.check_in_guest(bigint,text,text,numeric,text) to authenticated;
grant execute on function public.check_out_guest(uuid) to authenticated;
-- Prevent direct booking mutations from bypassing room-state synchronization.
revoke insert,update,delete on public.bookings from authenticated;
-- Room status transitions remain owner-only via rooms_write policy.
-- Create the FIRST owner in Supabase Authentication > Users, then run:
-- insert into public.profiles(id,role) values ('REPLACE-WITH-AUTH-USER-UUID','owner');
-- Add staff users via Authentication > Users and insert their UUIDs with role 'staff'.
-- Add actual room numbers in SQL Editor (example only):
-- insert into public.rooms(number,category,base_rate) values ('101','Standard',1200),('102','Deluxe',1800);
