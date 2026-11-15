# Almond Hotel — Branded Website + Private Management App

**This is the deployable web application, not the offline demo.** Once connected to your own Supabase project and deployed to Vercel, your records persist in PostgreSQL and are available across authorized devices. No room data from previous browser demos is automatically transferred. The app starts with zero rooms: enter your actual 21 rooms and add more whenever necessary.

## Two destinations, one Next.js deployment
- **Public hotel website** at `/`: fully branded using your supplied Almond Hotel emblem and wordmark, with welcome section and contact/enquiry action. Configure `NEXT_PUBLIC_HOTEL_WHATSAPP` (international number, digits only) or `NEXT_PUBLIC_HOTEL_EMAIL` to enable the contact button. No online reservation or payment requests are captured on the public page.
- **Private management app** at `/login` and `/dashboard`: same logo on login and dashboard, with rooms, bookings, IDs, expenses, reports and staff access.
- **App-style installation**: `manifest.webmanifest` and branded icons allow "Add to Home Screen" on compatible browsers after hosting. This is an installable web app, **not a native App Store / Play Store binary**. A true offline mode is not implemented; the management app requires a network connection to Supabase.
- **No fictitious guest-facing rates or hotel phone number** are published. Configure the correct public contact information before sharing the website.

## Included
- Secure email/password sign-in with owner and staff role controls. No public signup.
- Editable room number/name/category/base price; add more rooms whenever necessary.
- Separate negotiated nightly rate for every booking.
- Check-ins for 1–20 guests with individual ID details and private JPEG/PNG/PDF file uploads (up to 5 MB each). File uploads take place in **Guest IDs** after the booking is created. Authorized staff can open short-lived, signed view links; owners can delete ID files.
- Advance room reservations, overlap checks, arrival, cancellation, check-out, cleaning status.
- Record reservation deposits, other payments, operating expenses, and export daily cash CSV.
- Access controls enforced in PostgreSQL with row-level security and protected database functions.

## Setup: about 5 steps (an owner must do this once)
1. Create a Supabase project: https://supabase.com/dashboard. In SQL Editor, run these three files **in order**, each once on a fresh database: `supabase/schema.sql`, `supabase/upgrade_v2.sql`, `supabase/003_final_hardening.sql`.
2. In Supabase **Authentication > Users**, create the owner user using your own email and a strong password. Copy their User UUID; then run this SQL in SQL Editor, replacing the UUID:
   ```sql
   insert into public.profiles (id, role) values ('YOUR-OWNER-UUID', 'owner');
   ```
   Turn off open user signup in Supabase Auth settings. Staff accounts must be explicitly created and given a `staff` role in `profiles` by the owner using the SQL Editor.
3. Copy `.env.example` to `.env.local` and fill the project's `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` from Supabase Project Settings → API. **Never put a service-role key in browser environment variables.**
4. Install Node.js 20+ and run `npm install && npm run dev` in this folder to run locally. Visit `http://localhost:3000` for the public site and `http://localhost:3000/login` to sign in as the owner.
5. To publish on the web: push this folder to your own **private GitHub repository** and import the project at https://vercel.com/new. Set the same two environment variables on Vercel, deploy, and use the generated HTTPS address. Verify login on a phone and laptop before entering live customer records.

## First day workflow
- Sign in as owner → **Rooms** → Add each of the 21 real room names/numbers and standard prices. Add more later via **Add room**. You can edit existing rooms later. Avoid importing fake room numbers.
- **Guest register** → Select available room → enter primary guest, other guests, negotiated rate and checkout date → submit.
- **Guest IDs** → Select each person → upload their corresponding ID file; view it only through secure expiring links.
- **Advance bookings** → Enter arrival/departure and guest details; create reservation. Reserve a future stay even if the room is currently occupied, provided dates do not overlap.
- **Payments** → Record cash/UPI/card, including advances for reserved stays. **Expenses** → Record spending. **Daily reports** → Download CSV.

## Important real-world limitations
- App source is provided; it **is not hosted or connected to your accounts** until you complete setup. ChatGPT cannot create your Supabase/Vercel accounts or deploy on your behalf without authorized access.
- This package has not been end-to-end verified against your live Supabase instance. Test with dummy guests and ID images first. Guest IDs are sensitive: establish a lawful collection basis, a privacy notice, access rules and a deletion/retention policy before handling real IDs.
- Advance reservation payments are logged manually; no payment gateway, WhatsApp sending or automated confirmations are built in.
- Reports are recorded cash flow, **not** invoiced revenue, taxes, GST, or accounting profit. Report date uses Asia/Kolkata.
- Balance is an estimate using rounded-up 24-hour periods. Confirm your checkout time, GST and billing rules before treating totals as final bills.
- PostgreSQL record persistence does not automatically imply backups. Configure Supabase backups and periodically test restore procedures.
- For full production use, also complete a prelaunch checklist for role permissions, concurrency, backup/restore, ID deletion, file access, check-in/check-out rules and guest-data compliance.

## Security
RLS is enabled for the hotel data, and the guest ID storage bucket is private. Each staff member must have an authorized profile. Do not share login credentials. Use MFA where supported and delete departed staff accounts. Some security guarantees require validating your Supabase Auth and Storage project configuration after deployment.

## Brand assets
`public/almond-hotel-logo.png` is the logo created from the photo you supplied. It is used on the public website, staff login and private app. Replace with your own master artwork later if you have a vector original. `public/almond-hotel-emblem.png` is the small emblem version.
