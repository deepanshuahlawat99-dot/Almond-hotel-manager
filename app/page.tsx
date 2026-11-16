import Link from 'next/link';

const whatsapp = process.env.NEXT_PUBLIC_HOTEL_WHATSAPP?.replace(/\D/g, '') || '';
const email = process.env.NEXT_PUBLIC_HOTEL_EMAIL || '';
const address = process.env.NEXT_PUBLIC_HOTEL_ADDRESS || 'Ramgarh';

export default function Home() {
  const contactHref = whatsapp ? `https://wa.me/${whatsapp}?text=${encodeURIComponent('Hello Almond Hotel, I would like to enquire about room availability.')}` : email ? `mailto:${email}?subject=${encodeURIComponent('Room enquiry - Almond Hotel')}` : '';
  return <div className="publicSite">
    <header className="publicNav"><Link href="/" className="publicBrand"><img src="/almond-hotel-logo.png" alt="Almond Hotel" /></Link><nav aria-label="Website navigation"><a href="#about">About</a><a href="#stay">Our hotel</a><a href="#contact">Contact</a><Link href="/login" className="navStaff">Staff login</Link></nav></header>
    <main>
      <section className="heroPublic"><div className="heroInner"><div className="eyebrowPublic">WELCOME TO ALMOND HOTEL</div><img className="heroLogo" src="/almond-hotel-logo.png" alt="Almond Hotel logo" /><div className="goldRule"/><h1>Make room for a better stay.</h1><p>Welcome to Almond Hotel, Ramgarh. Reach out to our team to enquire about rooms and your upcoming visit.</p><div className="heroActions"><a href="#contact" className="goldButton">Contact the hotel <span aria-hidden="true">↗</span></a><Link href="/login" className="ghostButton">Management portal</Link></div></div></section>
      <section id="about" className="publicSection centeredPublic"><span className="sectionEyebrow">THE ALMOND HOTEL</span><h2>A warm welcome awaits.</h2><p>Planning your visit? Contact our team directly for current availability, room categories and prices. We look forward to welcoming you.</p></section>
      <section id="stay" className="publicSplit"><div className="publicSplitArt"><div className="monogramFrame"><img src="/almond-hotel-emblem.png" alt="Almond Hotel emblem" /></div></div><div className="publicSplitCopy"><span className="sectionEyebrow">YOUR STAY</span><h2>Every stay begins with a welcome.</h2><p>For room availability, stay dates, standard rates and any special requests, contact the hotel team. Room prices and confirmation are provided directly by the hotel.</p><a href="#contact" className="textGoldLink">Ask about rooms →</a></div></section>
      <section id="contact" className="publicContact"><span className="sectionEyebrow">GET IN TOUCH</span><h2>Plan your visit to Almond Hotel.</h2><p>Location: {address}</p>{contactHref?<a className="goldButton" href={contactHref} target={whatsapp?'_blank':undefined} rel={whatsapp?'noopener noreferrer':undefined}>Enquire about a room ↗</a>:<p className="contactNotice">Online enquiries will be enabled once the hotel phone number or email is added to the website settings.</p>}</section>
    </main><footer className="publicFooter"><img src="/almond-hotel-logo.png" alt="Almond Hotel"/><div><span>© {new Date().getFullYear()} Almond Hotel</span><Link href="/login">Staff access</Link></div></footer>
  </div>;
}
