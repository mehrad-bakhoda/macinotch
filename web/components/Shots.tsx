'use client';

import { motion } from 'motion/react';
import { useState } from 'react';

type Shot = { file: string; label: string; blurb: string };

const SHOTS: Shot[] = [
  {
    file: 'home',
    label: 'Home',
    blurb:
      'Clock and three calendars, weather, a timer, now playing, vitals with '
      + 'sparklines and the process behind each spike, plus Claude Code and '
      + 'Codex usage.',
  },
  {
    file: 'sessions',
    label: 'Sessions',
    blurb:
      'Recent Claude Code and Codex sessions per project, with message counts, '
      + 'token spend and a live dot for whatever is running now.',
  },
  {
    file: 'dock-files',
    label: 'Dock',
    blurb:
      'A file shelf with named piles, AirDrop and zip in one click, and new '
      + 'screenshots caught automatically.',
  },
  {
    file: 'notes',
    label: 'Notes',
    blurb:
      'Sticky notes backed by plain markdown files in a folder you choose, so '
      + 'they stay editable in anything else.',
  },
];

export default function Shots({ base }: { base: string }) {
  const [active, setActive] = useState(0);
  const [broken, setBroken] = useState<Record<string, boolean>>({});
  const shot = SHOTS[active];

  return (
    <div className="grid gap-5 md:grid-cols-[190px_1fr] md:gap-8">
      <div className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-1 md:mx-0 md:flex-col md:overflow-visible md:px-0 md:pb-0">
        {SHOTS.map((s, i) => (
          <button
            key={s.file}
            onClick={() => setActive(i)}
            className={`relative shrink-0 rounded-lg px-3 py-2 text-left font-mono text-[11px] transition-colors ${
              i === active ? 'text-chalk' : 'text-faint hover:text-muted'
            }`}
          >
            {i === active && (
              <motion.span
                layoutId="shot-pill"
                className="absolute inset-0 rounded-lg border border-line bg-raised"
                transition={{ type: 'spring', duration: 0.34, bounce: 0.2 }}
              />
            )}
            <span className="relative">
              <span className="text-faint">{String(i + 1).padStart(2, '0')}</span>{' '}
              {s.label}
            </span>
          </button>
        ))}
      </div>

      <div>
        <motion.div
          key={shot.file}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.32, ease: [0.22, 1, 0.36, 1] }}
          className="overflow-hidden rounded-xl border border-line bg-panel"
        >
          {broken[shot.file] ? (
            <div className="flex aspect-[16/11] flex-col items-center justify-center gap-2 px-6 text-center">
              <span className="font-mono text-[11px] text-faint">
                shots/{shot.file}.png
              </span>
              <span className="text-[13px] text-muted">
Screenshot not available
              </span>
            </div>
          ) : (
            <img
              src={`${base}/shots/${shot.file}.png`}
              alt={`MacInotch ${shot.label}`}
              onError={() => setBroken((b) => ({ ...b, [shot.file]: true }))}
              className="w-full"
              loading="lazy"
            />
          )}
        </motion.div>
        <p className="mt-3 text-[14px] text-muted">{shot.blurb}</p>
      </div>
    </div>
  );
}
