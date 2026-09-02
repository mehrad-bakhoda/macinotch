import Backdrop from '@/components/Backdrop';
import NotchReplica from '@/components/NotchReplica';
import Shots from '@/components/Shots';
import Terminal from '@/components/Terminal';

const REPO = 'https://github.com/mehrad-bakhoda/macinotch';
const BASE = process.env.GITHUB_ACTIONS === 'true' ? '/macinotch' : '';

const CAPABILITIES: [string, string, string][] = [
  ['Vitals', 'CPU, memory, temperature, fans, power, battery, disk, network', 'sparklines, and the process behind each spike'],
  ['Mail', 'Unread mail, triaged and summarised on device', 'reply, or have the first draft written for you'],
  ['Meetings', 'Records a call, transcribes and writes it up', 'decisions, actions and open questions, all on the machine'],
  ['Dictation', 'Hold a key, speak, and it becomes a note', 'with a live waveform, transcribed locally'],
  ['Work', 'Hours per project, a streak and a year of days', 'measured from your own session transcripts'],
  ['AI limits', 'Codex limits as Codex reports them, five hour and weekly', 'the pace you are burning them and when they run out'],
  ['Accounts', 'Several Codex and Claude Code sign ins in the keychain', 'switch without logging in again'],
  ['GitHub', 'Pushes, pull requests, reviews waiting, failing workflows', 'a contribution graph, and a chime when CI breaks'],
  ['Dock', 'File shelf with named piles, clipboard history', 'AirDrop, zip, screenshots and recordings caught automatically'],
  ['Fans', 'Live RPM per fan, and timed boosts through a root helper', 'clamped, deadlined, and reverted above 90 degrees'],
  ['Keep awake', 'A coffee cup that fills, steams and holds off sleep', 'draining as the time runs down'],
  ['Control strip', 'Drag across the notch for volume or brightness', 'the one strip of screen no window covers'],
  ['Captions', 'Live captions for whatever the Mac is playing', 'transcribed locally, kept nowhere'],
  ['Calendars', 'Gregorian, Shamsi in Farsi, Hijri, plus events and reminders', 'join links, and a meeting mode that mutes the room'],
  ['Media', 'Spotify and Apple Music', 'artwork, scrubbing, transport, volume'],
  ['Alerts', 'Disk filling, a process pinning a core, throttling, VPN', 'each fires once and rearms when it clears'],
  ['Notify', 'CLI, HTTP endpoint, URL scheme', 'progress, sticky states, action buttons'],
];

function Section({
  index,
  title,
  lede,
  children,
}: {
  index: string;
  title: string;
  lede?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="rule py-14 md:py-20">
      <div className="shell">
        <div className="grid min-w-0 gap-6 md:grid-cols-[190px_1fr] md:gap-10">
          <div>
            <div className="kicker">{index}</div>
            <h2 className="mt-2.5 font-display text-[22px] font-semibold tracking-tightest sm:text-[26px]">
              {title}
            </h2>
            {lede && <p className="mt-2 max-w-[420px] text-[14px] text-muted md:max-w-[240px]">{lede}</p>}
          </div>
          <div className="min-w-0">{children}</div>
        </div>
      </div>
    </section>
  );
}

export default function Home() {
  return (
    <main className="noise relative">
      <header className="sticky top-0 z-50 border-b border-line bg-ink/85 backdrop-blur-xl">
        <div className="shell flex h-14 items-center gap-4 sm:gap-8">
          <a href="#top" className="flex items-center gap-2.5 font-display font-semibold">
            <span className="relative h-[19px] w-[19px] rounded-[5px] bg-gradient-to-br from-[#2b2b33] to-[#0f0f13] ring-1 ring-inset ring-white/10">
              <span className="absolute left-1/2 top-0 h-[5px] w-[9px] -translate-x-1/2 rounded-b-[3px] bg-gradient-to-b from-gold to-ember" />
            </span>
            MacInotch
          </a>
          <nav className="ml-auto flex gap-4 font-mono text-[11px] text-faint sm:gap-6 sm:text-[11.5px]">
            <a href="#install" className="hidden hover:text-chalk sm:inline">install</a>
            <a href="#look" className="hover:text-chalk">screens</a>
            <a href="#ai" className="hover:text-chalk">ai</a>
            <a href={REPO} className="hover:text-chalk">github</a>
          </nav>
        </div>
      </header>

      <div id="top" className="relative overflow-hidden">
        <Backdrop />
        <div className="shell relative pb-14 pt-16 sm:pt-20 md:pt-28">
          <div>
            <div className="max-w-[620px]">
              <div className="kicker">macOS utility, MIT licensed</div>
              <h1 className="mt-4 font-display text-[clamp(36px,9vw,76px)] font-semibold leading-[0.98] tracking-tightest">
                The notch was
                <br />
                dead space.
                <br />
                <span className="text-ember">Not any more.</span>
              </h1>
              <p className="mt-5 max-w-[460px] text-[15.5px] leading-relaxed text-muted sm:text-[17px]">
                Live system vitals, notifications, a file shelf, clipboard
                history and media control, in the strip of screen your MacBook
                was already giving away to the camera.
              </p>

              <div className="mt-7 flex flex-wrap items-center gap-3">
                <a
                  href={`${REPO}/releases/latest`}
                  className="flex-1 rounded-xl bg-gradient-to-b from-gold to-ember px-6 py-3 text-center font-display text-[15px] font-semibold text-[#1a1004] transition hover:brightness-110 sm:flex-none"
                >
                  Download for macOS
                </a>
                <a
                  href={REPO}
                  className="flex-1 rounded-xl border border-line bg-panel px-6 py-3 text-center font-display text-[15px] font-medium transition hover:border-faint sm:flex-none"
                >
                  Source on GitHub
                </a>
              </div>
              <p className="mt-4 font-mono text-[11.5px] text-faint">
                macOS 14+ · Apple silicon and Intel · no telemetry
              </p>
            </div>

          </div>
          <div className="mt-14">
            <NotchReplica />
          </div>
        </div>
      </div>

      <Section
        index="01 / Install"
        title="Two minutes."
        lede="Download a build, or compile it yourself with the Command Line Tools."
        >
        <div className="min-w-0 space-y-6">
          <pre className="overflow-x-auto rounded-xl border border-line bg-panel p-4 font-mono text-[11px] leading-relaxed sm:text-[12.5px]">
            <span className="text-faint"># after downloading the release</span>
            {'\n'}xattr -dr com.apple.quarantine /Applications/MacInotch.app
          </pre>
          <pre className="overflow-x-auto rounded-xl border border-line bg-panel p-4 font-mono text-[11px] leading-relaxed sm:text-[12.5px]">
            <span className="text-faint"># or build it from source</span>
            {'\n'}git clone {REPO}.git
            {'\n'}cd macinotch
            {'\n'}swift build -c release
          </pre>
          <p className="text-[14px] text-muted">
            It runs as a menu bar accessory with no Dock icon. A first run guide
            covers the optional permissions, and it works without any of them.
          </p>
        </div>
      </Section>

      <Section index="02 / Screens" title="What it looks like." lede="Real captures, not mockups.">
        <div id="look">
          <Shots base={BASE} />
        </div>
      </Section>

      <Section
        index="03 / AI"
        title="Track Claude and Codex."
        lede="Both assistants, read straight off your own machine."
      >
        <div id="ai" className="min-w-0 space-y-5">
          <p className="text-[15px] leading-relaxed text-muted">
            MacInotch reads the transcripts Claude Code and Codex already write
            locally, so it can show what you have spent without an API key,
            a login, or anything leaving your machine.
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            {[
              ['Usage limits', 'Codex limits exactly as Codex reports them, five hour and weekly, with a chime when one resets. Claude Code publishes no quota, so it shows a local token tally.'],
              ['Session browser', 'Recent sessions per project, message counts, token spend, and a live dot for whatever is running now.'],
              ['Several accounts', 'Save more than one Codex or Claude Code sign in, each keeping its own usage and reset time, and swap between them in a click. The one you are not using tells you when its window frees up.'],
              ['Presence', 'Whether Claude, Claude Code or Codex is running, shown beside the notch at a glance.'],
              ['Hooks', 'A one line installer wires Claude Code so the notch pulses when it needs you and chimes when it finishes.'],
            ].map(([title, body]) => (
              <div key={title} className="rounded-xl border border-line bg-panel p-4">
                <div className="font-display text-[14px] font-semibold">{title}</div>
                <p className="mt-1.5 text-[13.5px] leading-relaxed text-muted">{body}</p>
              </div>
            ))}
          </div>
          <p className="font-mono text-[11.5px] text-faint">
            Counts are read from local transcripts, so they are your own tally
            rather than a figure from the provider.
          </p>
        </div>
      </Section>

      <Section index="03b / Weight" title="What it costs to run." lede="Measured on the machine it was built on, not estimated.">
        <div className="grid gap-3 sm:grid-cols-3">
          {[
            ['3.9 MB', 'to download'],
            ['10 MB', 'installed'],
            ['~110 MB', 'dirty memory at rest'],
            ['~1%', 'of a twelve core machine at rest'],
          ].map(([value, label]) => (
            <div key={label} className="rounded-xl border border-line bg-panel p-4">
              <div className="font-display text-[22px] font-semibold tabular-nums">{value}</div>
              <div className="mt-1 text-[13px] text-muted">{label}</div>
            </div>
          ))}
        </div>
        <p className="mt-3 font-mono text-[11.5px] leading-relaxed text-faint">
          Resident memory reads higher because the language and speech models macOS
          provides are mapped in rather than copied. Processor use is quoted against
          a single core the way the system reports it, so thirteen percent of one
          core is close to one percent of a twelve core machine. Readers of the
          session transcripts keep their place and parse only what has arrived
          since, so files that have not changed cost nothing to look at again.
          Macs without a notch, an Air or anything on an external display, get a
          rounded bar in the same place.
        </p>
      </Section>

      <Section index="04 / Everything" title="The full surface." lede="All of it optional, all of it switchable.">
        <div className="divide-y divide-line border-y border-line">
          {CAPABILITIES.map(([tag, what, detail]) => (
            <div key={tag} className="grid gap-1.5 py-4 sm:grid-cols-[92px_1fr] sm:gap-6">
              <div className="font-mono text-[11px] uppercase tracking-[0.16em] text-ember">
                {tag}
              </div>
              <div>
                <div className="text-[14.5px] text-chalk">{what}</div>
                <div className="mt-0.5 text-[13px] text-faint">{detail}</div>
              </div>
            </div>
          ))}
        </div>
      </Section>

      <Section index="05 / Scripting" title="Drive it from anything." lede="A CLI, a loopback endpoint and a URL scheme.">
        <div className="min-w-0 space-y-5">
          <Terminal />
          <p className="text-[14px] text-muted">
            The HTTP endpoint is bound to 127.0.0.1 only. There is also a
            <span className="font-mono text-chalk"> macinotch://</span> URL
            scheme, so Shortcuts, Raycast and Stream Deck can drive it without
            the CLI.
          </p>
        </div>
      </Section>

      <footer className="rule py-14">
        <div className="shell flex flex-wrap items-center gap-x-5 gap-y-3 font-mono text-[11.5px] text-faint">
          <span>© 2026 Mehrad Bakhoda</span>
          <a href={`${REPO}/blob/main/LICENSE`} className="hover:text-chalk">MIT</a>
          <a href={REPO} className="hover:text-chalk">github</a>
          <a href={`${REPO}/issues`} className="hover:text-chalk">issues</a>
          <a href={`${REPO}/releases`} className="hover:text-chalk">releases</a>
        </div>
      </footer>
    </main>
  );
}
