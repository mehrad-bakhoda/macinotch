export default function MacFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="w-full overflow-hidden">
      <div className="mx-auto flex h-[184px] justify-center sm:h-[240px] lg:h-[300px]">
        <div className="origin-top scale-[0.6] sm:scale-[0.8] lg:scale-100">
          <div
            className="relative w-[600px]"
            style={{
              maskImage:
                'linear-gradient(to bottom, #000 0%, #000 62%, rgba(0,0,0,0.35) 84%, transparent 100%)',
              WebkitMaskImage:
                'linear-gradient(to bottom, #000 0%, #000 62%, rgba(0,0,0,0.35) 84%, transparent 100%)',
            }}
          >
            <div
              className="rounded-t-[20px] px-[9px] pt-[9px]"
              style={{
                background:
                  'linear-gradient(180deg,#54545d 0%,#3a3a43 6%,#26262d 24%,#1d1d23 100%)',
                boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.22)',
              }}
            >
              <div
                className="relative overflow-hidden rounded-t-[12px] bg-[#050507]"
                style={{ height: 296 }}
              >
                <div
                  className="absolute inset-0"
                  style={{
                    background:
                      'radial-gradient(130% 100% at 50% -30%, #26313d 0%, #141a22 45%, #08090d 100%)',
                  }}
                />
                <div
                  className="pointer-events-none absolute inset-0 opacity-30"
                  style={{
                    background:
                      'linear-gradient(118deg, transparent 40%, rgba(255,255,255,0.08) 50%, transparent 60%)',
                  }}
                />
                <div className="relative h-full">{children}</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
