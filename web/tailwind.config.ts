import type { Config } from 'tailwindcss';

export default {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#08080a',
        panel: '#101014',
        raised: '#16161c',
        line: '#222229',
        chalk: '#ededf0',
        muted: '#8b8b96',
        faint: '#5d5d68',
        ember: '#ff8a34',
        gold: '#ffc44d',
        mint: '#3dd6c4',
      },
      fontFamily: {
        display: ['var(--font-display)', 'system-ui', 'sans-serif'],
        mono: ['var(--font-mono)', 'ui-monospace', 'monospace'],
      },
      letterSpacing: { tightest: '-0.045em' },
    },
  },
  plugins: [],
} satisfies Config;
