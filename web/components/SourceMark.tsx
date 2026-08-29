type Kind = 'claude' | 'codex';

const TINT: Record<Kind, string> = {
  claude: '#e08a63',
  codex: '#19c39c',
};

export function SourceMark({ kind, size = 20 }: { kind: Kind; size?: number }) {
  const tint = TINT[kind];
  return (
    <span
      className="grid shrink-0 place-items-center rounded-[30%]"
      style={{
        width: size,
        height: size,
        background: `${tint}2e`,
        boxShadow: `inset 0 0 0 1px ${tint}59`,
      }}
    >
      <svg
        width={size * 0.58}
        height={size * 0.58}
        viewBox="0 0 24 24"
        fill="none"
        aria-hidden
      >
        {kind === 'claude' ? (
          <path
            d="M12 2.4v19.2M4.2 6.9l15.6 10.2M19.8 6.9L4.2 17.1"
            stroke={tint}
            strokeWidth="2.6"
            strokeLinecap="round"
          />
        ) : (
          <>
            <path
              d="M5.6 8.6 2.9 12l2.7 3.4M18.4 8.6 21.1 12l-2.7 3.4"
              stroke={tint}
              strokeWidth="2.3"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
            <path
              d="M13.9 5.4 10.1 18.6"
              stroke={tint}
              strokeWidth="2.3"
              strokeLinecap="round"
            />
          </>
        )}
      </svg>
    </span>
  );
}

export const SOURCE_TINT = TINT;
