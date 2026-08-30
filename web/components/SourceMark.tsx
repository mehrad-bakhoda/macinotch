type Kind = 'claude' | 'codex';

const TINT: Record<Kind, string> = {
  claude: '#e08a63',
  codex: '#19c39c',
};

const LABEL: Record<Kind, string> = {
  claude: 'Claude',
  codex: 'ChatGPT and Codex',
};

const BASE = process.env.NEXT_PUBLIC_BASE_PATH ?? '';

export function SourceMark({
  kind,
  size = 20,
  muted = false,
}: {
  kind: Kind;
  size?: number;
  muted?: boolean;
}) {
  return (
    <img
      src={`${BASE}/marks/${kind}.png`}
      alt={LABEL[kind]}
      width={size}
      height={size}
      loading="lazy"
      draggable={false}
      className="shrink-0 select-none"
      style={{
        width: size,
        height: size,
        filter: muted ? 'grayscale(1)' : undefined,
        opacity: muted ? 0.45 : 1,
      }}
    />
  );
}

export const SOURCE_TINT = TINT;
