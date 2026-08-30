'use client';

import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useState } from 'react';
import MacFrame from './MacFrame';
import { SourceMark, SOURCE_TINT } from './SourceMark';

const METRICS = [
  { value: '18%', tone: '#30d158' },
  { value: '64%', tone: '#ffd60a' },
  { value: '34°', tone: '#0a84ff' },
];

const ROWS = [
  { kind: 'claude' as const, name: 'Claude Code', detail: '412K tokens, resets in 3h 51m' },
  { kind: 'codex' as const, name: 'Codex', detail: '31.5K tokens, 12 messages' },
];

const COLLAPSED_W = 446;
const OPEN_W = 546;

export default function NotchReplica() {
  const [open, setOpen] = useState(false);
  const [clock, setClock] = useState('');

  useEffect(() => {
    const tick = () =>
      setClock(
        new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }),
      );
    tick();
    const id = setInterval(tick, 10_000);
    return () => clearInterval(id);
  }, []);

  return (
    <MacFrame>
      <div className="flex h-full flex-col">
        <div
          onMouseEnter={() => setOpen(true)}
          onMouseLeave={() => setOpen(false)}
          onClick={() => setOpen((v) => !v)}
          className="relative flex cursor-pointer justify-center"
          style={{ height: 300 }}
        >
          <motion.div
            animate={{ width: open ? OPEN_W : COLLAPSED_W, borderRadius: open ? 22 : 14 }}
            transition={
              open
                ? { type: 'spring', duration: 0.46, bounce: 0.32 }
                : { type: 'spring', duration: 0.28, bounce: 0.02 }
            }
            className="absolute top-0 h-fit overflow-hidden bg-[#08080a]
                       shadow-[0_26px_70px_-14px_rgba(0,0,0,0.95)] ring-1 ring-white/[0.08]"
            style={{ borderTopLeftRadius: 0, borderTopRightRadius: 0 }}
          >
            <div className="flex h-[32px] items-center justify-between px-4">
              <div className="flex items-center gap-3.5">
                {METRICS.map((m) => (
                  <span key={m.value} className="flex items-center gap-1.5">
                    <span
                      className="h-[9px] w-[9px] rounded-full"
                      style={{ background: m.tone }}
                    />
                    <span className="font-mono text-[10.5px] tabular-nums text-chalk/90">
                      {m.value}
                    </span>
                  </span>
                ))}
              </div>
              <div className="w-[126px] shrink-0" />
              <div className="flex items-center gap-2">
                <SourceMark kind="claude" size={16} />
                <SourceMark kind="codex" size={16} />
              </div>
            </div>

            <AnimatePresence initial={false}>
              {open && (
                <motion.div
                  initial={{ opacity: 0, y: -7, scale: 0.975 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, transition: { duration: 0.09 } }}
                  transition={{ type: 'spring', duration: 0.34, bounce: 0.18, delay: 0.09 }}
                  style={{ transformOrigin: 'top' }}
                  className="px-4 pb-4"
                >
                  <div className="flex items-end justify-between pt-1">
                    <div>
                      <div className="font-display text-[32px] font-medium leading-none tabular-nums">
                        {clock}
                      </div>
                      <div className="mt-1.5 text-[11px] text-ember" dir="rtl">
                        جمعه، ۷ شهریور ۱۴۰۵
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="text-[11px] text-muted">Friday, 29 August</div>
                      <div className="mt-1.5 flex justify-end gap-1.5">
                        {['W35', 'up 17h'].map((chip) => (
                          <span
                            key={chip}
                            className="rounded-full bg-white/[0.07] px-2 py-0.5 font-mono text-[8.5px] text-faint"
                          >
                            {chip}
                          </span>
                        ))}
                      </div>
                    </div>
                  </div>

                  <div className="mt-3.5 space-y-2 rounded-xl border border-white/[0.08] bg-white/[0.04] p-3">
                    {ROWS.map((row) => (
                      <div key={row.name} className="flex items-center gap-2.5">
                        <SourceMark kind={row.kind} size={22} />
                        <div className="min-w-0 flex-1">
                          <div className="text-[11.5px] text-chalk">{row.name}</div>
                          <div className="truncate font-mono text-[9.5px] text-faint">
                            {row.detail}
                          </div>
                        </div>
                        <div
                          className="h-[3px] w-12 rounded-full"
                          style={{ background: SOURCE_TINT[row.kind] }}
                        />
                      </div>
                    ))}
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </motion.div>

          <div className="pointer-events-none absolute left-1/2 top-0 z-20 h-[32px] w-[118px] -translate-x-1/2 rounded-b-[13px] bg-black" />
        </div>

        <p className="mt-auto pb-4 text-center font-mono text-[10px] uppercase tracking-[0.18em] text-white/25">
          {open ? 'expanded' : 'hover the notch'}
        </p>
      </div>
    </MacFrame>
  );
}
