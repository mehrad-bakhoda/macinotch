export default function MacFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="w-full overflow-hidden">
      <div className="mx-auto flex h-[236px] justify-center sm:h-[310px] lg:h-[404px]">
        <div className="origin-top scale-[0.55] sm:scale-[0.73] lg:scale-100">
          <div className="relative w-[640px]">
            <div
              className="rounded-[22px] p-[10px]"
              style={{
                background:
                  'linear-gradient(160deg,#4a4a52 0%,#2a2a31 18%,#1c1c22 55%,#33333b 100%)',
                boxShadow:
                  '0 30px 70px -20px rgba(0,0,0,0.85), inset 0 1px 0 rgba(255,255,255,0.16)',
              }}
            >
              <div
                className="relative overflow-hidden rounded-[13px] bg-[#050507]"
                style={{ height: 386, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.07)' }}
              >
                <div
                  className="absolute inset-0"
                  style={{
                    background:
                      'radial-gradient(120% 90% at 50% -20%, #23303b 0%, #131820 42%, #08090d 100%)',
                  }}
                />
                <div
                  className="pointer-events-none absolute inset-0 opacity-40"
                  style={{
                    background:
                      'linear-gradient(115deg, transparent 42%, rgba(255,255,255,0.07) 50%, transparent 58%)',
                  }}
                />
                <div className="relative h-full">{children}</div>
              </div>
            </div>

            <div className="relative mx-auto h-[11px] w-[694px] -translate-x-[27px] rounded-b-[9px]"
                 style={{
                   background:
                     'linear-gradient(180deg,#3a3a42 0%,#26262c 40%,#171a1e 100%)',
                   boxShadow: '0 16px 26px -12px rgba(0,0,0,0.9)',
                 }}>
              <div className="absolute left-1/2 top-0 h-[4px] w-[86px] -translate-x-1/2 rounded-b-[4px] bg-black/45" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
