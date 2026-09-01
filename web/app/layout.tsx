import type { Metadata } from 'next';
import { Inter_Tight, JetBrains_Mono } from 'next/font/google';
import './globals.css';

const display = Inter_Tight({
  subsets: ['latin'],
  variable: '--font-display',
  display: 'swap',
});

const mono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-mono',
  display: 'swap',
});

const site = 'https://mehrad-bakhoda.github.io/macinotch';

export const metadata: Metadata = {
  metadataBase: new URL(site),
  title: {
    default: 'MacInotch, a notch utility for macOS',
    template: '%s | MacInotch',
  },
  description:
    'MacInotch turns the notch on a MacBook into a live readout of your machine, your mail, your AI usage and your repositories. Unread mail triaged and summarised on device, Codex and Claude Code limits with saved accounts you can switch between, GitHub activity, a file shelf, fan control and media, all local.',
  keywords: [
    'macos notch app',
    'switch codex accounts',
    'claude code usage',
    'codex usage tracker',
    'mail summary mac',
    'macbook notch utility',
    'dynamic island for mac',
    'notch notifications macos',
    'mac system monitor menu bar',
    'macos file shelf',
    'mac clipboard history',
    'mac fan control',
    'shamsi calendar mac',
    'macinotch',
  ],
  authors: [{ name: 'Mehrad Bakhoda', url: 'https://github.com/mehrad-bakhoda' }],
  creator: 'Mehrad Bakhoda',
  publisher: 'Mehrad Bakhoda',
  applicationName: 'MacInotch',
  category: 'technology',
  alternates: { canonical: site },
  openGraph: {
    type: 'website',
    url: site,
    siteName: 'MacInotch',
    title: 'MacInotch, a notch utility for macOS',
    description:
      'Mail triaged on device, AI usage limits, account switching, GitHub activity, vitals, a file shelf and media control, in the space your MacBook was already wasting.',
    images: [{ url: '/og.png', width: 1200, height: 630, alt: 'MacInotch' }],
    locale: 'en_US',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'MacInotch, a notch utility for macOS',
    description:
      'Mail triaged on device, AI usage limits, account switching, GitHub activity, vitals, a file shelf and media control, in the space your MacBook was already wasting.',
    images: ['/og.png'],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, 'max-image-preview': 'large' },
  },
};

const structuredData = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  name: 'MacInotch',
  applicationCategory: 'UtilitiesApplication',
  operatingSystem: 'macOS 14 or later',
  description:
    'A macOS utility that turns the MacBook notch into a live system readout, mail triage, AI usage tracker, account switcher, notification surface, file shelf and media controller.',
  url: site,
  downloadUrl: 'https://github.com/mehrad-bakhoda/macinotch/releases/latest',
  license: 'https://opensource.org/licenses/MIT',
  offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
  author: {
    '@type': 'Person',
    name: 'Mehrad Bakhoda',
    url: 'https://github.com/mehrad-bakhoda',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${mono.variable}`}>
      <body>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
        />
        {children}
      </body>
    </html>
  );
}
