'use client';

import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useState } from 'react';
import MacFrame from './MacFrame';
import { SourceMark } from './SourceMark';

const COLLAPSED_W = 412;
const OPEN_W = 620;

const TABS = ['Home', 'Dock', 'Sessions', 'Accounts', 'GitHub', 'Mail', 'Notes'];

const VITALS = [
  { label: 'CPU', value: '27', unit: '%', foot: 'Spotify Helper (…', fill: 0.27, tone: '#30d158' },
  { label: 'MEMORY', value: '13.6', unit: 'GB', foot: 'claude 0.6G', fill: 0.62, tone: '#30d158' },
  { label: 'TEMP', value: '48', unit: '°C', foot: 'peak 50°', fill: 0.34, tone: '#30d158' },
  { label: 'FANS', value: '2.5', unit: 'k', foot: '2 fans', fill: 0.05, tone: '#30d158' },
  { label: 'POWER', value: '10', unit: 'W', foot: 'system', fill: 0.12, tone: '#bf5af2' },
  { label: 'BATTERY', value: '100', unit: '%', foot: '2h 33m', fill: 1, tone: '#30d158' },
];

function QuickDot({ children, active, tone }: {
  children: React.ReactNode; active?: boolean; tone?: string;
}) {
  return (
    <span
      className="flex h-[26px] w-[26px] items-center justify-center rounded-full text-[11px]"
      style={{
        background: active ? tone : 'rgba(255,255,255,0.08)',
        color: active ? '#0b0b0d' : 'rgba(255,255,255,0.55)',
      }}
    >
      {children}
    </span>
  );
}

function Row({ icon, title, sub, right }: {
  icon: React.ReactNode; title: string; sub: string; right?: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-2.5 py-[7px]">
      <div className="shrink-0">{icon}</div>
      <div className="min-w-0 flex-1">
        <div className="text-[11.5px] leading-tight text-chalk">{title}</div>
        <div className="truncate text-[9.5px] leading-tight text-faint">{sub}</div>
      </div>
      {right}
    </div>
  );
}

export default function NotchReplica() {
  const [open, setOpen] = useState(false);
  const [clock, setClock] = useState('');

  useEffect(() => {
    const tick = () =>
      setClock(new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }));
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
          style={{ height: 330 }}
        >
          <motion.div
            initial={{ width: COLLAPSED_W, borderRadius: 14 }}
            animate={{ width: open ? OPEN_W : COLLAPSED_W, borderRadius: open ? 22 : 14 }}
            transition={
              open
                ? { type: 'spring', duration: 0.46, bounce: 0.3 }
                : { type: 'spring', duration: 0.28, bounce: 0.02 }
            }
            className="absolute left-1/2 top-0 h-fit -translate-x-1/2 overflow-hidden bg-[#08080a]
                       shadow-[0_26px_70px_-14px_rgba(0,0,0,0.95)] ring-1 ring-white/[0.08]"
            style={{ borderTopLeftRadius: 0, borderTopRightRadius: 0 }}
          >
            <div className="flex h-[34px] items-center justify-between px-3.5">
              <div className="flex items-center gap-2">
                <SourceMark kind="claude" size={15} />
                <SourceMark kind="codex" size={15} />
              </div>
              <div className="w-[128px] shrink-0" />
              <div className="flex items-center gap-2.5">
                <span className="flex items-center gap-1.5">
                  <span className="h-[9px] w-[9px] rounded-full" style={{ background: '#0a84ff' }} />
                  <span className="font-mono text-[10.5px] tabular-nums text-chalk/90">48°</span>
                </span>
              </div>
            </div>

            <AnimatePresence initial={false}>
              {open && (
                <motion.div
                  initial={{ opacity: 0, y: -7 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, transition: { duration: 0.09 } }}
                  transition={{ type: 'spring', duration: 0.34, bounce: 0.16, delay: 0.07 }}
                  style={{ transformOrigin: 'top' }}
                  className="px-4 pb-4"
                >
                  <div className="flex items-center gap-1 pb-2.5">
                    {TABS.map((tab) => (
                      <span
                        key={tab}
                        className="flex items-center gap-1 rounded-full px-2 py-[3px] text-[10px]"
                        style={{
                          background: tab === 'Home' ? 'rgba(255,255,255,0.10)' : 'transparent',
                          color: tab === 'Home' ? '#f4f4f5' : 'rgba(255,255,255,0.38)',
                        }}
                      >
                        {tab}
                        {tab === 'Dock' && (
                          <span className="rounded-full bg-[#0a84ff] px-[4px] text-[8px] font-bold text-white">
                            2
                          </span>
                        )}
                        {tab === 'Sessions' && (
                          <span className="h-[5px] w-[5px] rounded-full bg-[#30d158]" />
                        )}
                      </span>
                    ))}
                  </div>

                  <div className="flex items-center gap-1.5 pb-3">
                    <QuickDot>▣</QuickDot>
                    <QuickDot>◍</QuickDot>
                    <QuickDot active tone="#ff9f0a">☕</QuickDot>
                    <QuickDot>◉</QuickDot>
                    <span className="mx-0.5 h-[14px] w-px bg-white/12" />
                    <QuickDot>▤</QuickDot>
                    <QuickDot active tone="#5ac8fa">{'</>'}</QuickDot>
                  </div>

                  <div className="flex items-end justify-between">
                    <div>
                      <div className="font-display text-[34px] font-medium leading-none tabular-nums">
                        {clock}
                      </div>
                      <div className="mt-1.5 text-[10.5px] text-ember" dir="rtl">
                        چهارشنبه، ۱۱ شهریور ۱۴۰۵
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="text-[11px] text-muted">Wednesday, 2 September 2026</div>
                      <div className="mt-1.5 flex justify-end gap-1.5">
                        {['W36', 'نوروز ۲۰۰', 'up 3d 12h'].map((chip) => (
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

                  <div className="mt-3 flex items-center gap-2.5 rounded-xl border border-white/[0.07] bg-white/[0.03] p-2.5">
                    <div className="h-[42px] w-[42px] shrink-0 rounded-md bg-gradient-to-br from-[#3a2f2a] to-[#171418]" />
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-[11.5px] text-chalk">Timeless (feat Playboi Carti)</div>
                      <div className="truncate text-[9.5px] text-faint">The Weeknd · Hurry Up Tomorrow</div>
                      <div className="mt-1.5 h-[2.5px] w-full rounded-full bg-white/10">
                        <div className="h-full w-[31%] rounded-full bg-[#30d158]" />
                      </div>
                    </div>
                    <span className="rounded bg-[#1db954]/15 px-1.5 py-0.5 font-mono text-[8px] text-[#1db954]">
                      SPOTIFY
                    </span>
                    <span className="flex h-[26px] w-[26px] items-center justify-center rounded-full bg-[#30d158] text-[10px] text-black">
                      ▶
                    </span>
                  </div>

                  <div className="mt-2.5 grid grid-cols-6 gap-0 rounded-xl border border-white/[0.07] bg-white/[0.03] px-3 py-2.5">
                    {VITALS.map((v, i) => (
                      <div key={v.label} className={i > 0 ? 'border-l border-white/[0.06] pl-2.5' : 'pr-2.5'}>
                        <div className="font-mono text-[7.5px] uppercase tracking-[0.12em] text-faint">
                          {v.label}
                        </div>
                        <div className="mt-0.5 flex items-baseline gap-0.5">
                          <span className="text-[15px] font-semibold leading-none tabular-nums text-chalk">
                            {v.value}
                          </span>
                          <span className="text-[8px] text-faint">{v.unit}</span>
                        </div>
                        <div className="mt-1 h-[2px] w-full rounded-full bg-white/8">
                          <div
                            className="h-full rounded-full"
                            style={{ width: `${v.fill * 100}%`, background: v.tone }}
                          />
                        </div>
                        <div className="mt-1 truncate text-[7.5px] text-faint">{v.foot}</div>
                      </div>
                    ))}
                  </div>

                  <div className="mt-2 divide-y divide-white/[0.05]">
                    <Row
                      icon={<SourceMark kind="claude" size={22} />}
                      title="Claude Code"
                      sub="148 messages in the last 3h"
                      right={
                        <div className="text-right">
                          <div className="text-[12px] font-semibold tabular-nums text-chalk">412.0K</div>
                          <div className="text-[8px] text-faint">tokens</div>
                        </div>
                      }
                    />
                    <Row
                      icon={<SourceMark kind="codex" size={22} />}
                      title="Codex Plus"
                      sub="5h limit, resets in 2h 3m, at this pace, full around 04:13"
                      right={
                        <div className="text-right">
                          <div className="flex items-baseline justify-end gap-1">
                            <span className="text-[8px] text-faint">31% wk</span>
                            <span className="text-[12px] font-semibold tabular-nums text-chalk">84%</span>
                          </div>
                          <div className="mt-1 h-[2.5px] w-[54px] rounded-full bg-white/10">
                            <div className="h-full w-[84%] rounded-full bg-[#ff9f0a]" />
                          </div>
                        </div>
                      }
                    />
                    <Row
                      icon={
                        <span className="flex h-[22px] w-[22px] items-center justify-center rounded-md bg-[#ff453a]/16 text-[10px] text-[#ff453a]">
                          {'</>'}
                        </span>
                      }
                      title="GitHub today"
                      sub="9 pushes, 2 PR opened, 3 to review"
                      right={
                        <span className="rounded-full bg-[#ff453a] px-1.5 py-[1px] text-[8px] font-bold text-white">
                          1 failing
                        </span>
                      }
                    />
                    <Row
                      icon={
                        <span className="flex h-[22px] w-[22px] items-center justify-center rounded-md bg-[#ff9f0a]/16 text-[11px]">
                          ☕
                        </span>
                      }
                      title="Keeping this Mac awake"
                      sub="Awake, 44m left"
                      right={<span className="text-[9.5px] font-semibold text-[#0a84ff]">Stop</span>}
                    />
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </motion.div>

          <div className="pointer-events-none absolute left-1/2 top-0 z-20 h-[34px] w-[120px] -translate-x-1/2 rounded-b-[14px] bg-black" />
        </div>

        <p className="pb-6 text-center font-mono text-[9.5px] uppercase tracking-[0.18em] text-white/25">
          {open ? 'expanded' : 'hover the notch'}
        </p>
      </div>
    </MacFrame>
  );
}
