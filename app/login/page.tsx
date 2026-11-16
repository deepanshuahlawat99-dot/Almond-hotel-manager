'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabaseBrowser } from '@/lib/supabase';
export default function Login(){
 const router=useRouter();const [email,setEmail]=useState('');const [password,setPassword]=useState('');const [error,setError]=useState('');const [busy,setBusy]=useState(false);
 async function submit(e:React.FormEvent){e.preventDefault();setBusy(true);setError('');const {error}=await supabaseBrowser().auth.signInWithPassword({email,password});setBusy(false);if(error){setError('Login failed. Check your credentials.');return;}router.replace('/dashboard');router.refresh();}
 return <main className="loginWrap"><form onSubmit={submit} className="loginCard"><img className="loginBrandImage" src="/almond-hotel-logo.png" alt="Almond Hotel"/><h1>Hotel Management</h1><p>Private management portal</p><label>Email<input type="email" autoComplete="username" required value={email} onChange={e=>setEmail(e.target.value)}/></label><label>Password<input type="password" autoComplete="current-password" required value={password} onChange={e=>setPassword(e.target.value)}/></label>{error&&<p role="alert" className="error">{error}</p>}<button disabled={busy}>{busy?'Signing in…':'Sign in'}</button><small>Access is restricted to approved hotel staff.</small></form></main>
}
