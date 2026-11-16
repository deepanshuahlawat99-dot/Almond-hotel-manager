-- Run AFTER schema.sql for existing projects. New projects run schema.sql then this file.
create table if not exists public.booking_guests (
 id uuid primary key default gen_random_uuid(), booking_id uuid not null references public.bookings(id) on delete cascade,
 full_name text not null check(length(trim(full_name))>0), id_type text not null check(id_type in ('aadhaar','passport','driving_licence','voter_id','other')),
 id_last_four text, created_at timestamptz not null default now()
);
create index if not exists booking_guests_booking_idx on public.booking_guests(booking_id);
alter table public.booking_guests enable row level security;
create policy guest_ids_read on public.booking_guests for select to authenticated using (public.is_staff());
-- Only controlled RPCs create guest rows; staff cannot directly change identity records.
revoke insert,update,delete on public.booking_guests from authenticated;
alter table public.bookings add column if not exists expected_checkout timestamptz;
alter table public.bookings add column if not exists guest_count integer not null default 1 check(guest_count between 1 and 20);
create index if not exists bookings_reservation_idx on public.bookings(room_id,check_in,expected_checkout) where status in ('reserved','checked_in');
-- The original schema grants direct booking reads but not mutations. New operations are transactional.
create or replace function public.create_hotel_booking(
 p_room_id bigint,p_guest_name text,p_guest_phone text,p_rate numeric,p_notes text,
 p_arrival timestamptz,p_departure timestamptz,p_guests jsonb,p_checkin boolean default false
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_room public.rooms%rowtype; v_booking uuid; v_guest jsonb; v_count integer; v_start timestamptz;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 v_count:=jsonb_array_length(p_guests);
 if v_count<1 or v_count>20 or p_guests is null then raise exception 'Enter 1 to 20 guests'; end if;
 if nullif(trim(p_guest_name),'') is null or p_rate is null or p_rate<0 then raise exception 'Invalid booking'; end if;
 v_start:=case when p_checkin then now() else p_arrival end;
 if v_start is null or p_departure is null or p_departure<=v_start then raise exception 'Departure must be after arrival'; end if;
 if not p_checkin and p_arrival<now()-interval '5 minutes' then raise exception 'Advance booking must be in the future'; end if;
 select * into v_room from public.rooms where id=p_room_id for update;
 if not found or v_room.status='maintenance' then raise exception 'Room unavailable'; end if;
 if p_checkin and v_room.status<>'available' then raise exception 'Room must be available for immediate check-in'; end if;
 if exists(select 1 from public.bookings b where b.room_id=p_room_id and b.status in ('reserved','checked_in')
  and tstzrange(b.check_in,coalesce(b.expected_checkout,'infinity'::timestamptz),'[)') && tstzrange(v_start,p_departure,'[)'))
 then raise exception 'Room already booked for those dates'; end if;
 for v_guest in select value from jsonb_array_elements(p_guests) loop
  if nullif(trim(v_guest->>'full_name'),'') is null or coalesce(v_guest->>'id_type','') not in ('aadhaar','passport','driving_licence','voter_id','other')
  then raise exception 'Every guest needs a name and ID type'; end if;
 end loop;
 insert into public.bookings(room_id,guest_name,guest_phone,nightly_rate,notes,check_in,expected_checkout,guest_count,status,created_by)
 values(p_room_id,trim(p_guest_name),nullif(trim(p_guest_phone),''),p_rate,p_notes,v_start,p_departure,v_count,
 case when p_checkin then 'checked_in' else 'reserved' end,(select auth.uid())) returning id into v_booking;
 for v_guest in select value from jsonb_array_elements(p_guests) loop
  insert into public.booking_guests(booking_id,full_name,id_type,id_last_four)
  values(v_booking,trim(v_guest->>'full_name'),v_guest->>'id_type',nullif(right(coalesce(v_guest->>'id_last_four',''),4),''));
 end loop;
 if p_checkin then update public.rooms set status='occupied' where id=p_room_id; end if;
 return v_booking;
end; $$;
create or replace function public.arrive_reserved_guest(p_booking_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_booking public.bookings%rowtype; v_room public.rooms%rowtype;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 select * into v_booking from public.bookings where id=p_booking_id;
 if not found or v_booking.status<>'reserved' then raise exception 'Not a reservation'; end if;
 select * into v_room from public.rooms where id=v_booking.room_id for update;
 select * into v_booking from public.bookings where id=p_booking_id for update;
 if v_booking.status<>'reserved' or v_room.status<>'available' then raise exception 'Room is not available'; end if;
 if now()>v_booking.expected_checkout then raise exception 'Reservation has expired'; end if;
 if exists(select 1 from public.bookings where room_id=v_booking.room_id and status='checked_in') then raise exception 'Room already occupied'; end if;
 update public.bookings set status='checked_in',check_in=now() where id=p_booking_id;
 update public.rooms set status='occupied' where id=v_booking.room_id;
end; $$;
create or replace function public.cancel_reserved_guest(p_booking_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 update public.bookings set status='cancelled' where id=p_booking_id and status='reserved';
 if not found then raise exception 'No active reservation'; end if;
end; $$;
revoke all on function public.create_hotel_booking(bigint,text,text,numeric,text,timestamptz,timestamptz,jsonb,boolean) from public;
revoke all on function public.arrive_reserved_guest(uuid) from public;
revoke all on function public.cancel_reserved_guest(uuid) from public;
grant execute on function public.create_hotel_booking(bigint,text,text,numeric,text,timestamptz,timestamptz,jsonb,boolean) to authenticated;
grant execute on function public.arrive_reserved_guest(uuid) to authenticated;
grant execute on function public.cancel_reserved_guest(uuid) to authenticated;
-- Private guest ID document storage. Each file path begins with its guest UUID.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('guest-ids','guest-ids',false,5242880,array['image/jpeg','image/png','application/pdf']) on conflict(id) do nothing;
create policy guest_documents_read on storage.objects for select to authenticated using (
 bucket_id='guest-ids' and public.is_staff() and exists(select 1 from public.booking_guests g where g.id::text=(storage.foldername(name))[1])
);
create policy guest_documents_upload on storage.objects for insert to authenticated with check (
 bucket_id='guest-ids' and public.is_staff() and exists(select 1 from public.booking_guests g where g.id::text=(storage.foldername(name))[1])
);
-- No update/delete policy: ID documents are immutable to staff; retention handled by owner via admin workflow.
