const MENU = ['Finder'];

export default function MacFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="w-full overflow-hidden">
      <div className="mx-auto flex h-[148px] justify-center sm:h-[192px] lg:h-[240px]">
        <div className="origin-top scale-[0.6] sm:scale-[0.8] lg:scale-100">
          <div
            className="relative w-[600px] rounded-t-[16px] p-[7px]"
            style={{
              background: 'linear-gradient(180deg,#3f3f47 0%,#22222a 40%,#191920 100%)',
              boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.20)',
              maskImage:
                'linear-gradient(to bottom, #000 0%, #000 58%, rgba(0,0,0,0.4) 82%, transparent 100%)',
              WebkitMaskImage:
                'linear-gradient(to bottom, #000 0%, #000 58%, rgba(0,0,0,0.4) 82%, transparent 100%)',
            }}
          >
            <div
              className="relative overflow-hidden rounded-t-[10px]"
              style={{ height: 232 }}
            >
              <div
                className="absolute inset-0"
                style={{
                  background:
                    'radial-gradient(150% 120% at 30% -20%, #2f3a49 0%, #1a2029 40%, #0b0d12 100%)',
                }}
              />
              <div className="absolute inset-x-0 top-0 flex h-[32px] items-center justify-between bg-black/25 px-4 backdrop-blur-sm">
                <div className="flex items-center gap-3.5">
                  {MENU.map((m, i) => (
                    <span
                      key={m}
                      className={`text-[10.5px] text-white/${i === 0 ? '55' : '28'}`}
                      style={{ fontWeight: i === 0 ? 600 : 400 }}
                    >
                      {m}
                    </span>
                  ))}
                </div>
                <div className="flex items-center gap-2.5">
                  {[10, 12, 9].map((w, i) => (
                    <span
                      key={i}
                      className="block h-[9px] rounded-[2px] bg-white/20"
                      style={{ width: w }}
                    />
                  ))}
                  <span className="text-[10.5px] tabular-nums text-white/35">17:42</span>
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
