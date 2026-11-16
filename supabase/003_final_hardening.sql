-- Run after schema.sql and upgrade_v2.sql on a new Supabase project.
-- Revoke legacy check-in RPC: it bypasses required per-person guest ID records.
revoke all on function public.check_in_guest(bigint,text,text,numeric,text) from authenticated;
-- Keep already issued grants from lingering; prohibit unapproved calls.
drop function if exists public.check_in_guest(bigint,text,text,numeric,text);
-- Avoid allowing arbitrary room state 'reserved': reservations are date-scoped bookings.
update public.rooms set status='available' where status='reserved';
-- Document ownership: staff may read/upload; only owner may remove documents.
create policy guest_documents_owner_delete on storage.objects
 for delete to authenticated using (bucket_id='guest-ids' and public.is_owner());
-- Allow refunds/corrections only through administrator-controlled workflows (not provided in UI).
-- Guard against changing physical room status while a guest is checked in.
create or replace function public.prevent_occupied_room_edits() returns trigger
 language plpgsql set search_path='' as $$
begin
 if old.status='occupied' and new.status<>'occupied' and exists
 (select 1 from public.bookings where room_id=old.id and status='checked_in')
 then raise exception 'Check out the guest before changing this room status'; end if;
 return new;
end $$;
drop trigger if exists trg_prevent_occupied_room_edits on public.rooms;
create trigger trg_prevent_occupied_room_edits before update of status on public.rooms
 for each row execute function public.prevent_occupied_room_edits();
-- Fix the legacy checkout workflow to ensure the trigger stays consistent:
-- The booking is closed first and the room is then moved to cleaning, atomically.
create or replace function public.check_out_guest(p_booking_id uuid) returns void
 language plpgsql security definer set search_path='' as $$
declare v_booking public.bookings%rowtype;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 select * into v_booking from public.bookings where id=p_booking_id for update;
 if not found or v_booking.status<>'checked_in' then raise exception 'No active booking'; end if;
 perform 1 from public.rooms where id=v_booking.room_id for update;
 update public.bookings set status='checked_out',check_out=now() where id=p_booking_id;
 update public.rooms set status='cleaning' where id=v_booking.room_id;
end $$;
revoke all on function public.check_out_guest(uuid) from public;
grant execute on function public.check_out_guest(uuid) to authenticated;
-- Record individual guest document paths only via private Supabase Storage.
-- Rooms are created and edited by owner in the application. No fake room data is seeded.
