-- Run on existing v1 databases; for new projects run schema.sql then this file.
-- Room allocations are serialized with a FOR UPDATE lock during reservation/check-in.
alter table public.bookings add column if not exists arrival_date date;
alter table public.bookings add column if not exists departure_date date;
update public.bookings set arrival_date=(check_in at time zone 'Asia/Kolkata')::date where arrival_date is null;
update public.bookings set departure_date=greatest(arrival_date+1, coalesce((check_out at time zone 'Asia/Kolkata')::date+1,arrival_date+1)) where departure_date is null;
alter table public.bookings alter column arrival_date set not null;
alter table public.bookings alter column departure_date set not null;
alter table public.bookings add constraint booking_date_order check(departure_date>arrival_date);
create index if not exists booking_dates_idx on public.bookings(room_id,arrival_date,departure_date);

create table if not exists public.booking_guests (
 id uuid primary key default gen_random_uuid(),
 booking_id uuid not null references public.bookings(id) on delete cascade,
 full_name text not null check(length(trim(full_name))>0),
 id_type text not null check(id_type in ('aadhaar','passport','driving_licence','voter_id','other')),
 document_path text,
 created_at timestamptz not null default now(),
 unique(id,booking_id)
);
create index if not exists guest_booking_idx on public.booking_guests(booking_id);
alter table public.booking_guests enable row level security;
create policy booking_guests_read on public.booking_guests for select to authenticated using(public.is_staff());
-- No direct writes; guest details are created by verified RPC, and file pointers by secure RPC.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('guest-ids','guest-ids',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;
-- Every object path is booking_id/guest_id/filename. No anonymous access.
create policy guest_ids_select on storage.objects for select to authenticated
using(bucket_id='guest-ids' and public.is_staff());
create policy guest_ids_insert on storage.objects for insert to authenticated
with check(bucket_id='guest-ids' and public.is_staff() and exists(
 select 1 from public.booking_guests g where g.id::text=split_part(name,'/',2)
 and g.booking_id::text=split_part(name,'/',1)));
create policy guest_ids_remove on storage.objects for delete to authenticated
using(bucket_id='guest-ids' and public.is_owner());

-- RPCs purposely do not accept created_by. It is always auth.uid().
create or replace function public.create_hotel_booking(
 p_room_id bigint,p_guest_name text,p_guest_phone text,p_rate numeric,
 p_arrival date,p_departure date,p_reserve boolean,p_guests jsonb default '[]'::jsonb,p_notes text default ''
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_room public.rooms%rowtype; v_id uuid; v_g jsonb; v_count integer;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 if nullif(trim(p_guest_name),'') is null or p_rate is null or p_rate<0 then raise exception 'Invalid guest/rate'; end if;
 if p_arrival is null or p_departure is null or p_departure<=p_arrival then raise exception 'Departure must follow arrival'; end if;
 if p_arrival < (now() at time zone 'Asia/Kolkata')::date then raise exception 'Arrival cannot be in the past'; end if;
 select * into v_room from public.rooms where id=p_room_id for update;
 if not found or v_room.status in ('maintenance','cleaning') then raise exception 'Room unavailable for booking'; end if;
 if not p_reserve and (p_arrival<>(now() at time zone 'Asia/Kolkata')::date or v_room.status<>'available') then raise exception 'Immediate check-in requires an available room today'; end if;
 if p_reserve and v_room.status='reserved' then raise exception 'Room manually blocked'; end if;
 if exists (select 1 from public.bookings b where b.room_id=p_room_id and b.status in ('reserved','checked_in')
 and b.arrival_date<p_departure and p_arrival<b.departure_date) then raise exception 'Booking dates overlap an existing stay'; end if;
 -- An occupied room can be reserved for dates after its expected departure; actual check-in checks again.
 if not p_reserve and (jsonb_typeof(p_guests)<>'array' or jsonb_array_length(p_guests)<1 or jsonb_array_length(p_guests)>12) then raise exception 'Add 1 to 12 guests with ID types'; end if;
 insert into public.bookings(room_id,guest_name,guest_phone,nightly_rate,notes,arrival_date,departure_date,status,created_by,check_in)
 values(p_room_id,trim(p_guest_name),nullif(trim(p_guest_phone),''),p_rate,p_notes,p_arrival,p_departure,
 case when p_reserve then 'reserved' else 'checked_in' end,(select auth.uid()),
 case when p_reserve then p_arrival::timestamp at time zone 'Asia/Kolkata' else now() end)
 returning id into v_id;
 if not p_reserve then
   for v_g in select value from jsonb_array_elements(p_guests) loop
     if nullif(trim(v_g->>'name'),'') is null or coalesce(v_g->>'id_type','') not in ('aadhaar','passport','driving_licence','voter_id','other') then raise exception 'Each guest needs a name and ID type'; end if;
     insert into public.booking_guests(booking_id,full_name,id_type) values(v_id,trim(v_g->>'name'),v_g->>'id_type');
   end loop;
   update public.rooms set status='occupied' where id=p_room_id;
 end if;
 return v_id;
end; $$;

create or replace function public.arrive_reserved_booking(p_booking_id uuid,p_guests jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_booking public.bookings%rowtype; v_room public.rooms%rowtype; v_g jsonb;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 select * into v_booking from public.bookings where id=p_booking_id;
 if not found or v_booking.status<>'reserved' then raise exception 'Booking is not a pending reservation'; end if;
 select * into v_room from public.rooms where id=v_booking.room_id for update;
 select * into v_booking from public.bookings where id=p_booking_id for update;
 if v_booking.status<>'reserved' or v_room.status<>'available' then raise exception 'Room not ready'; end if;
 if (now() at time zone 'Asia/Kolkata')::date < v_booking.arrival_date then raise exception 'Arrival date has not started'; end if;
 if (now() at time zone 'Asia/Kolkata')::date >= v_booking.departure_date then raise exception 'Booking expired; change dates before check-in'; end if;
 if jsonb_typeof(p_guests)<>'array' or jsonb_array_length(p_guests)<1 or jsonb_array_length(p_guests)>12 then raise exception 'Add 1 to 12 guests'; end if;
 for v_g in select value from jsonb_array_elements(p_guests) loop
   if nullif(trim(v_g->>'name'),'') is null or coalesce(v_g->>'id_type','') not in ('aadhaar','passport','driving_licence','voter_id','other') then raise exception 'Each guest needs a name and ID type'; end if;
   insert into public.booking_guests(booking_id,full_name,id_type) values(v_booking.id,trim(v_g->>'name'),v_g->>'id_type');
 end loop;
 update public.bookings set status='checked_in',check_in=now() where id=v_booking.id;
 update public.rooms set status='occupied' where id=v_booking.room_id;
end; $$;

create or replace function public.cancel_hotel_reservation(p_booking_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 update public.bookings set status='cancelled' where id=p_booking_id and status='reserved';
 if not found then raise exception 'No pending reservation'; end if;
end; $$;

create or replace function public.set_guest_document(p_guest_id uuid,p_path text)
returns void language plpgsql security definer set search_path='' as $$
declare v_guest public.booking_guests%rowtype;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 select * into v_guest from public.booking_guests where id=p_guest_id for update;
 if not found then raise exception 'Guest missing'; end if;
 if split_part(p_path,'/',1)<>v_guest.booking_id::text or split_part(p_path,'/',2)<>v_guest.id::text then raise exception 'Invalid path'; end if;
 if not exists(select 1 from storage.objects where bucket_id='guest-ids' and name=p_path) then raise exception 'Document missing'; end if;
 update public.booking_guests set document_path=p_path where id=p_guest_id;
end; $$;
-- The old check-in RPC allows check-in without any guest ID; remove it.
revoke all on function public.check_in_guest(bigint,text,text,numeric,text) from authenticated;
drop function if exists public.check_in_guest(bigint,text,text,numeric,text);
revoke all on function public.create_hotel_booking(bigint,text,text,numeric,date,date,boolean,jsonb,text) from public;
revoke all on function public.arrive_reserved_booking(uuid,jsonb) from public;
revoke all on function public.cancel_hotel_reservation(uuid) from public;
revoke all on function public.set_guest_document(uuid,text) from public;
grant execute on function public.create_hotel_booking(bigint,text,text,numeric,date,date,boolean,jsonb,text) to authenticated;
grant execute on function public.arrive_reserved_booking(uuid,jsonb) to authenticated;
grant execute on function public.cancel_hotel_reservation(uuid) to authenticated;
grant execute on function public.set_guest_document(uuid,text) to authenticated;
