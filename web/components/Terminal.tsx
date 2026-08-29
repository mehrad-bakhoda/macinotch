'use client';

import { motion, useInView } from 'motion/react';
import { useRef } from 'react';

const LINES: { text: string; tone?: 'dim' | 'accent' }[] = [
  { text: '# push a notification from anything', tone: 'dim' },
  { text: 'notchctl "Build finished" "42 tests passed" -s claude -k success' },
  { text: '' },
  { text: '# a progress bar that updates in place', tone: 'dim' },
  { text: 'notchctl --key deploy --progress 0.4 --title "Deploying"' },
  { text: '' },
  { text: '# pipe a long command through the notch', tone: 'dim' },
  { text: 'swift build 2>&1 | notchctl watch --title "Compiling"' },
  { text: '' },
  { text: '# read everything the notch knows', tone: 'dim' },
  { text: 'curl -s localhost:9977/state | jq' },
];

export default function Terminal() {
  const ref = useRef(null);
  const inView = useInView(ref, { once: true, margin: '-80px' });

  return (
    <div
      ref={ref}
      className="overflow-hidden rounded-xl border border-line bg-panel font-mono text-[11px] leading-relaxed sm:text-[12.5px]"
    >
      <div className="flex items-center gap-2 border-b border-line px-4 py-2.5">
        <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
        <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
        <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
        <span className="ml-2 text-[11px] text-faint">notchctl</span>
      </div>
      <div className="overflow-x-auto p-4">
        {LINES.map((line, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, x: -6 }}
            animate={inView ? { opacity: 1, x: 0 } : {}}
            transition={{ delay: i * 0.055, duration: 0.3 }}
            className={
              line.tone === 'dim'
                ? 'text-faint'
                : 'whitespace-pre text-chalk'
            }
          >
            {line.text || ' '}
          </motion.div>
        ))}
      </div>
    </div>
  );
}
