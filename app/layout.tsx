import './style.css';
export const metadata = { title:'Almond Hotel | Rooms & Hotel Management', description:'Official Almond Hotel website and private hotel management portal', icons:{icon:'/favicon.png'}, manifest:'/manifest.webmanifest' };
export default function RootLayout({children}:{children:React.ReactNode}) { return <html lang="en"><body>{children}</body></html>; }
