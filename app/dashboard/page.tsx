import { redirect } from 'next/navigation';
import { supabaseServer } from '@/lib/server';
import Dashboard from '@/components/Dashboard';
export default async function Page(){const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');const {data:profile}=await db.from('profiles').select('role').eq('id',user.id).single();if(!profile)return <main className="center"><h2>Account not authorized</h2><p>Ask the hotel owner to assign your staff role.</p></main>;return <Dashboard role={profile.role} email={user.email||''}/>;}
