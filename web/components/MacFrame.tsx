const MENU = ['Finder', 'File', 'Edit', 'View', 'Go', 'Window', 'Help'];

export default function MacFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="w-full overflow-hidden">
      <div className="mx-auto flex h-[186px] justify-center md:h-[292px] lg:h-[400px]">
        <div className="origin-top scale-[0.86] md:scale-[0.72] lg:scale-100">
          <div
            className="relative rounded-t-[10px] p-0 md:rounded-t-[26px] md:p-[11px]"
            style={{
              maskImage:
                'linear-gradient(to bottom, #000 0%, #000 56%, rgba(0,0,0,0.35) 84%, transparent 100%)',
              WebkitMaskImage:
                'linear-gradient(to bottom, #000 0%, #000 56%, rgba(0,0,0,0.35) 84%, transparent 100%)',
            }}
          >
            <div
              className="pointer-events-none absolute inset-0 hidden rounded-t-[26px] md:block"
              style={{
                background:
                  'linear-gradient(180deg,#5b5b64 0%,#3a3a43 5%,#26262d 26%,#1c1c22 100%)',
                boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.24)',
              }}
            />

            <div
              className="relative w-[440px] overflow-hidden rounded-t-[9px] md:w-[980px] md:rounded-t-[16px]"
              style={{ height: 400 }}
            >
              <div
                className="absolute inset-0 hidden md:block"
                style={{
                  background:
                    'radial-gradient(140% 130% at 28% -25%, #33404f 0%, #1a2029 42%, #090b10 100%)',
                }}
              />
              <div
                className="pointer-events-none absolute inset-0 hidden opacity-25 md:block"
                style={{
                  background:
                    'linear-gradient(112deg, transparent 38%, rgba(255,255,255,0.10) 50%, transparent 62%)',
                }}
              />

              <div className="absolute inset-x-0 top-0 hidden h-[34px] items-center justify-between px-5 md:flex">
                <div className="flex items-center gap-4">
                  <span className="text-[11px] font-semibold text-white/55">{MENU[0]}</span>
                  {MENU.slice(1).map((m) => (
                    <span key={m} className="text-[11px] text-white/25">
                      {m}
                    </span>
                  ))}
                </div>
                <div className="flex items-center gap-3">
                  {[11, 13, 10, 12].map((w, i) => (
                    <span
                      key={i}
                      className="block h-[10px] rounded-[2px] bg-white/20"
                      style={{ width: w }}
                    />
                  ))}
                  <span className="text-[11px] tabular-nums text-white/35">17:42</span>
                </div>
              </div>

              <div className="relative h-full">{children}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
