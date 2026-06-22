import { useMemo, useState, useEffect, useRef } from "react";
import { AGENTS, type Agent } from "./agents-data";

// Inline SVG icons (avoids depending on a pinned lucide-react version).
type IconProps = { size?: number; className?: string };
const mk =
  (children: React.ReactNode) =>
  ({ size = 16, className }: IconProps) => (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      {children}
    </svg>
  );

const Search = mk(
  <>
    <circle cx="11" cy="11" r="8" />
    <path d="m21 21-4.35-4.35" />
  </>,
);
const X = mk(
  <>
    <path d="M18 6 6 18" />
    <path d="m6 6 12 12" />
  </>,
);
const Github = mk(
  <>
    <path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.4 5.4 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4" />
    <path d="M9 18c-4.51 2-5-2-7-2" />
  </>,
);
const Terminal = mk(
  <>
    <polyline points="4 17 10 11 4 5" />
    <line x1="12" x2="20" y1="19" y2="19" />
  </>,
);
const FileCode = mk(
  <>
    <path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z" />
    <polyline points="14 2 14 8 20 8" />
    <path d="m9 18 2-2-2-2" />
    <path d="m15 14 2 2-2 2" />
  </>,
);
const Wrench = mk(
  <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z" />,
);
const Hash = mk(
  <>
    <line x1="4" x2="20" y1="9" y2="9" />
    <line x1="4" x2="20" y1="15" y2="15" />
    <line x1="10" x2="8" y1="3" y2="21" />
    <line x1="16" x2="14" y1="3" y2="21" />
  </>,
);
const Layers = mk(
  <>
    <path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z" />
    <path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65" />
    <path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65" />
  </>,
);
const ChevronRight = mk(<path d="m9 18 6-6-6-6" />);
const CircleSlash = mk(
  <>
    <circle cx="12" cy="12" r="10" />
    <line x1="4.9" x2="19.1" y1="4.9" y2="19.1" />
  </>,
);

const REPO_URL = "https://github.com/DYAI2025/Plumbline";
const SITE_URL = "https://plumbline-website-production.up.railway.app";

// Hero assets live only under docs/assets/ but the bundle is written to both the
// repo root and docs/index.html — reference by absolute Pages URL so both resolve
// online (the video/poster are an enhancement; the band degrades gracefully).
const HERO_VIDEO_URL =
  "https://dyai2025.github.io/Plumbline/assets/plumbline-hero.mp4";
const HERO_POSTER_URL =
  "https://dyai2025.github.io/Plumbline/assets/plumbline-hero-poster.jpg";

const ExternalLink = mk(
  <>
    <path d="M15 3h6v6" />
    <path d="M10 14 21 3" />
    <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" />
  </>,
);
const Play = mk(<polygon points="6 3 20 12 6 21 6 3" />);
const ChevronDown = mk(<path d="m6 9 6 6 6-6" />);

// Compact, on-brand cinematic header. Matches the explorer's dark terminal
// palette (#0b0c0e bg, emerald accent, mono headings, sharp corners). The
// video is a pure enhancement: respects prefers-reduced-motion (no autoplay,
// poster + click-to-play) and hides itself on load error, leaving a dark
// branded backdrop with the load-bearing wordmark / tagline / links intact.
function VideoHero() {
  const [collapsed, setCollapsed] = useState(false);
  const [videoOk, setVideoOk] = useState(true);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [playing, setPlaying] = useState(false);
  const videoRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const apply = () => setReducedMotion(mq.matches);
    apply();
    // addEventListener is the modern API; older Safari only has addListener.
    if (mq.addEventListener) mq.addEventListener("change", apply);
    else mq.addListener(apply);
    return () => {
      if (mq.removeEventListener) mq.removeEventListener("change", apply);
      else mq.removeListener(apply);
    };
  }, []);

  const autoPlay = videoOk && !reducedMotion;
  // With reduced motion we render the poster and offer an explicit click-to-play.
  const showPlayButton = videoOk && reducedMotion && !playing;

  const handlePlay = () => {
    const v = videoRef.current;
    if (!v) return;
    v.play().then(
      () => setPlaying(true),
      () => {
        /* play() can reject (e.g. blocked) — keep the poster, no broken state */
      },
    );
  };

  return (
    <section
      aria-label="Plumbline introduction"
      className="relative shrink-0 overflow-hidden border-b border-zinc-800 bg-[#0b0c0e]"
    >
      {/* Dark branded backdrop — always present, so the band looks intentional
          even if the video and poster both fail to load. */}
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-br from-[#0b0c0e] via-[#0c0f10] to-[#0e1413]" />
      {videoOk && (
        <video
          ref={videoRef}
          className={`pointer-events-none absolute inset-0 h-full w-full object-cover transition-opacity duration-700 ${
            collapsed ? "opacity-0" : "opacity-40"
          }`}
          src={HERO_VIDEO_URL}
          poster={HERO_POSTER_URL}
          autoPlay={autoPlay}
          muted
          loop
          playsInline
          preload="metadata"
          aria-label="Plumbline pipeline: Plan, Code, Test, Pause, Deploy — Plumbline catches the gap before shipping"
          onError={() => setVideoOk(false)}
        />
      )}
      {/* Legibility scrim over the video. */}
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-r from-[#0b0c0e] via-[#0b0c0ecc] to-[#0b0c0e80]" />

      <div
        className={`relative flex items-center gap-4 px-5 transition-all duration-300 ${
          collapsed ? "py-2.5" : "py-6 sm:py-8"
        }`}
      >
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2.5">
            <div className="flex h-7 w-7 shrink-0 items-center justify-center border border-emerald-800/70 bg-zinc-900 text-emerald-400">
              <Terminal size={15} />
            </div>
            <span className="font-mono text-lg font-semibold tracking-tight text-zinc-50">
              Plumbline
            </span>
          </div>

          {!collapsed && (
            <>
              <p className="mt-3 max-w-xl font-mono text-sm leading-relaxed text-emerald-300/90">
                Green tests are evidence, not proof of value.
              </p>
              <p className="mt-1.5 max-w-xl text-[13px] leading-relaxed text-zinc-400">
                A defense-in-depth Claude Code agent framework. Its one obsession:
                proving work is actually done — does it hang true?
              </p>

              <div className="mt-4 flex flex-wrap items-center gap-2">
                <a
                  href={SITE_URL}
                  target="_blank"
                  rel="noreferrer"
                  className="flex items-center gap-1.5 border border-emerald-800/70 bg-emerald-500/10 px-2.5 py-1.5 font-mono text-[11px] text-emerald-300 transition-colors hover:border-emerald-600 hover:bg-emerald-500/20"
                >
                  <ExternalLink size={12} /> project site
                </a>
                <a
                  href={REPO_URL}
                  target="_blank"
                  rel="noreferrer"
                  className="flex items-center gap-1.5 border border-zinc-700 px-2.5 py-1.5 font-mono text-[11px] text-zinc-300 transition-colors hover:border-zinc-500 hover:text-zinc-100"
                >
                  <Github size={12} /> DYAI2025/Plumbline
                </a>
              </div>
            </>
          )}
        </div>

        {showPlayButton && !collapsed && (
          <button
            onClick={handlePlay}
            aria-label="Play intro video"
            className="relative hidden shrink-0 items-center justify-center self-center border border-emerald-800/70 bg-zinc-900/70 p-4 text-emerald-400 transition-colors hover:border-emerald-600 hover:text-emerald-300 sm:flex"
          >
            <Play size={20} />
          </button>
        )}

        <button
          onClick={() => setCollapsed((c) => !c)}
          aria-label={collapsed ? "Expand intro" : "Collapse intro"}
          aria-expanded={!collapsed}
          className="absolute right-3 top-2.5 flex items-center gap-1 border border-zinc-800 bg-[#0e0f12]/80 px-1.5 py-1 font-mono text-[10px] text-zinc-500 transition-colors hover:border-zinc-600 hover:text-zinc-300"
        >
          <ChevronDown
            size={12}
            className={`transition-transform duration-300 ${collapsed ? "" : "rotate-180"}`}
          />
          {collapsed ? "intro" : "hide"}
        </button>
      </div>
    </section>
  );
}

// Category -> accent hue (border / dot). Deliberately varied, not a single ramp.
const CAT_COLOR: Record<string, string> = {
  core: "#34d399",
  github: "#38bdf8",
  "flow-nexus": "#a78bfa",
  templates: "#a1a1aa",
  consensus: "#fbbf24",
  "hive-mind": "#e879f9",
  optimization: "#22d3ee",
  sparc: "#fb7185",
  swarm: "#fb923c",
  goal: "#a3e635",
  reasoning: "#2dd4bf",
  testing: "#4ade80",
  analysis: "#facc15",
  architecture: "#818cf8",
  data: "#f472b6",
  development: "#60a5fa",
  devops: "#f87171",
  documentation: "#c084fc",
  neural: "#d946ef",
  specialized: "#fdba74",
  "(root)": "#71717a",
};
const catColor = (c: string) => CAT_COLOR[c] ?? "#71717a";

const SCHEMA_META: Record<Agent["schema"], { label: string; color: string }> = {
  standard: { label: "standard", color: "#38bdf8" },
  "claude-flow": { label: "claude-flow", color: "#a78bfa" },
  minimal: { label: "minimal", color: "#71717a" },
};

function App() {
  const [query, setQuery] = useState("");
  const [cat, setCat] = useState<string | null>(null);
  const [schema, setSchema] = useState<Agent["schema"] | null>(null);
  const [selected, setSelected] = useState<Agent | null>(null);

  const categories = useMemo(() => {
    const m = new Map<string, number>();
    for (const a of AGENTS) m.set(a.category, (m.get(a.category) ?? 0) + 1);
    return [...m.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return AGENTS.filter((a) => {
      if (cat && a.category !== cat) return false;
      if (schema && a.schema !== schema) return false;
      if (!q) return true;
      return (
        a.name.toLowerCase().includes(q) ||
        a.description.toLowerCase().includes(q) ||
        a.category.toLowerCase().includes(q) ||
        a.keywords.some((k) => k.toLowerCase().includes(q)) ||
        a.tools.some((t) => t.toLowerCase().includes(q))
      );
    });
  }, [query, cat, schema]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setSelected(null);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const activeFilters = (cat ? 1 : 0) + (schema ? 1 : 0) + (query ? 1 : 0);

  return (
    <div className="flex h-full flex-col bg-[#0b0c0e] text-zinc-300">
      {/* Cinematic video hero band (compact, collapsible) */}
      <VideoHero />

      {/* Top bar */}
      <header className="flex items-center justify-between border-b border-zinc-800 bg-[#0e0f12] px-5 py-3">
        <div className="flex items-center gap-3">
          <div className="flex h-8 w-8 items-center justify-center border border-zinc-700 bg-zinc-900 text-emerald-400">
            <Terminal size={16} />
          </div>
          <div className="leading-tight">
            <h1 className="font-mono text-sm font-semibold tracking-tight text-zinc-100">
              Plumbline
            </h1>
            <p className="text-[11px] text-zinc-500">
              {AGENTS.length} subagents · does it hang true?
            </p>
          </div>
        </div>
        <a
          href={REPO_URL}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-1.5 border border-zinc-700 px-2.5 py-1.5 font-mono text-[11px] text-zinc-400 transition-colors hover:border-zinc-500 hover:text-zinc-200"
        >
          <Github size={13} /> DYAI2025/Plumbline
        </a>
      </header>

      <div className="flex min-h-0 flex-1">
        {/* Sidebar */}
        <aside className="flex w-60 shrink-0 flex-col border-r border-zinc-800 bg-[#0c0d10]">
          <div className="border-b border-zinc-800 p-3">
            <div className="relative">
              <Search
                size={14}
                className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-zinc-600"
              />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="search name, tool, keyword…"
                className="w-full border border-zinc-800 bg-zinc-950 py-1.5 pl-8 pr-7 font-mono text-xs text-zinc-200 placeholder:text-zinc-600 focus:border-emerald-700 focus:outline-none"
              />
              {query && (
                <button
                  onClick={() => setQuery("")}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-zinc-600 hover:text-zinc-300"
                >
                  <X size={13} />
                </button>
              )}
            </div>
            <div className="mt-2 flex gap-1">
              {(Object.keys(SCHEMA_META) as Agent["schema"][]).map((s) => {
                const on = schema === s;
                return (
                  <button
                    key={s}
                    onClick={() => setSchema(on ? null : s)}
                    className="flex-1 border px-1 py-1 font-mono text-[10px] transition-colors"
                    style={{
                      borderColor: on ? SCHEMA_META[s].color : "#27272a",
                      color: on ? SCHEMA_META[s].color : "#71717a",
                      background: on ? `${SCHEMA_META[s].color}14` : "transparent",
                    }}
                  >
                    {SCHEMA_META[s].label}
                  </button>
                );
              })}
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto py-1">
            <button
              onClick={() => setCat(null)}
              className={`flex w-full items-center justify-between px-3 py-1.5 text-left font-mono text-xs transition-colors hover:bg-zinc-900 ${
                cat === null ? "bg-zinc-900 text-zinc-100" : "text-zinc-400"
              }`}
            >
              <span className="flex items-center gap-2">
                <Layers size={13} className="text-zinc-500" /> all categories
              </span>
              <span className="text-zinc-600">{AGENTS.length}</span>
            </button>
            {categories.map(([c, n]) => (
              <button
                key={c}
                onClick={() => setCat(cat === c ? null : c)}
                className={`flex w-full items-center justify-between px-3 py-1.5 text-left font-mono text-xs transition-colors hover:bg-zinc-900 ${
                  cat === c ? "bg-zinc-900 text-zinc-100" : "text-zinc-400"
                }`}
              >
                <span className="flex items-center gap-2 truncate">
                  <span
                    className="h-2 w-2 shrink-0"
                    style={{ background: catColor(c) }}
                  />
                  <span className="truncate">{c}</span>
                </span>
                <span className="text-zinc-600">{n}</span>
              </button>
            ))}
          </div>
        </aside>

        {/* Main */}
        <main className="flex min-w-0 flex-1 flex-col">
          <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-2">
            <p className="font-mono text-xs text-zinc-500">
              <span className="text-zinc-200">{filtered.length}</span> / {AGENTS.length}
              {cat && <span className="ml-2 text-zinc-400">· {cat}</span>}
              {schema && (
                <span className="ml-2" style={{ color: SCHEMA_META[schema].color }}>
                  · {SCHEMA_META[schema].label}
                </span>
              )}
            </p>
            {activeFilters > 0 && (
              <button
                onClick={() => {
                  setQuery("");
                  setCat(null);
                  setSchema(null);
                }}
                className="font-mono text-[11px] text-zinc-500 underline-offset-2 hover:text-zinc-300 hover:underline"
              >
                clear {activeFilters} filter{activeFilters > 1 ? "s" : ""}
              </button>
            )}
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto p-4">
            {filtered.length === 0 ? (
              <div className="flex h-full flex-col items-center justify-center gap-2 text-zinc-600">
                <CircleSlash size={28} />
                <p className="font-mono text-sm">no agents match</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
                {filtered.map((a) => (
                  <button
                    key={a.file}
                    onClick={() => setSelected(a)}
                    className="group flex flex-col gap-2 border border-zinc-800 bg-[#0e0f12] p-3 text-left transition-colors hover:border-zinc-600 hover:bg-[#121317]"
                    style={{ borderLeft: `2px solid ${catColor(a.category)}` }}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <span className="font-mono text-[13px] font-medium text-zinc-100">
                        {a.name}
                      </span>
                      <ChevronRight
                        size={14}
                        className="mt-0.5 shrink-0 text-zinc-700 transition-colors group-hover:text-zinc-400"
                      />
                    </div>
                    <p className="line-clamp-3 text-xs leading-relaxed text-zinc-400">
                      {a.description || "—"}
                    </p>
                    <div className="mt-auto flex flex-wrap items-center gap-1.5 pt-1 font-mono text-[10px] text-zinc-500">
                      <span
                        className="px-1.5 py-0.5"
                        style={{
                          color: catColor(a.category),
                          background: `${catColor(a.category)}14`,
                        }}
                      >
                        {a.category}
                      </span>
                      {a.type && (
                        <span className="border border-zinc-800 px-1.5 py-0.5 text-zinc-500">
                          {a.type}
                        </span>
                      )}
                      <span style={{ color: SCHEMA_META[a.schema].color }}>
                        {SCHEMA_META[a.schema].label}
                      </span>
                      {a.tools.length > 0 && (
                        <span className="ml-auto flex items-center gap-1 text-zinc-600">
                          <Wrench size={10} /> {a.tools.length}
                        </span>
                      )}
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </main>
      </div>

      {/* Detail drawer */}
      {selected && (
        <div className="fixed inset-0 z-50 flex justify-end">
          <div
            className="absolute inset-0 bg-black/60"
            onClick={() => setSelected(null)}
          />
          <div className="relative flex h-full w-full max-w-md flex-col border-l border-zinc-700 bg-[#0e0f12] shadow-2xl">
            <div
              className="flex items-start justify-between gap-3 border-b border-zinc-800 p-4"
              style={{ borderTop: `2px solid ${catColor(selected.category)}` }}
            >
              <div className="min-w-0">
                <h2 className="break-words font-mono text-base font-semibold text-zinc-100">
                  {selected.name}
                </h2>
                <p className="mt-0.5 flex items-center gap-1.5 font-mono text-[11px] text-zinc-500">
                  <FileCode size={11} /> {selected.file}
                </p>
              </div>
              <button
                onClick={() => setSelected(null)}
                className="shrink-0 border border-zinc-800 p-1.5 text-zinc-500 hover:border-zinc-600 hover:text-zinc-200"
              >
                <X size={15} />
              </button>
            </div>

            <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-4">
              <div className="flex flex-wrap gap-1.5 font-mono text-[11px]">
                <span
                  className="px-2 py-0.5"
                  style={{
                    color: catColor(selected.category),
                    background: `${catColor(selected.category)}14`,
                  }}
                >
                  {selected.category}
                </span>
                {selected.type && (
                  <span className="border border-zinc-800 px-2 py-0.5 text-zinc-400">
                    type: {selected.type}
                  </span>
                )}
                <span
                  className="px-2 py-0.5"
                  style={{
                    color: SCHEMA_META[selected.schema].color,
                    background: `${SCHEMA_META[selected.schema].color}14`,
                  }}
                >
                  {SCHEMA_META[selected.schema].label}
                </span>
                {selected.complexity && (
                  <span className="border border-zinc-800 px-2 py-0.5 text-zinc-400">
                    {selected.complexity}
                  </span>
                )}
              </div>

              <Section label="description">
                <p className="text-sm leading-relaxed text-zinc-300">
                  {selected.description || "—"}
                </p>
              </Section>

              {selected.specialization && (
                <Section label="specialization">
                  <p className="text-sm leading-relaxed text-zinc-400">
                    {selected.specialization}
                  </p>
                </Section>
              )}

              {selected.tools.length > 0 && (
                <Section label={`tools · ${selected.tools.length}`}>
                  <div className="flex flex-wrap gap-1.5">
                    {selected.tools.map((t) => (
                      <span
                        key={t}
                        className="border border-zinc-800 bg-zinc-950 px-1.5 py-0.5 font-mono text-[11px] text-zinc-400"
                      >
                        {t}
                      </span>
                    ))}
                  </div>
                </Section>
              )}

              {selected.keywords.length > 0 && (
                <Section label={`trigger keywords · ${selected.keywords.length}`}>
                  <div className="flex flex-wrap gap-1.5">
                    {selected.keywords.map((k) => (
                      <span
                        key={k}
                        className="flex items-center gap-1 px-1.5 py-0.5 font-mono text-[11px] text-zinc-400"
                        style={{ background: `${catColor(selected.category)}10` }}
                      >
                        <Hash size={9} className="text-zinc-600" />
                        {k}
                      </span>
                    ))}
                  </div>
                </Section>
              )}

              <div className="flex gap-4 border-t border-zinc-800 pt-3 font-mono text-[11px] text-zinc-600">
                <span>prompt: {selected.bodyChars.toLocaleString()} chars</span>
              </div>
            </div>

            <div className="border-t border-zinc-800 p-3">
              <a
                href={`${REPO_URL}/blob/main/${selected.file}`}
                target="_blank"
                rel="noreferrer"
                className="flex items-center justify-center gap-1.5 border border-zinc-700 py-2 font-mono text-xs text-zinc-300 transition-colors hover:border-zinc-500 hover:bg-zinc-900"
              >
                <Github size={13} /> view source on GitHub
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <section>
      <h3 className="mb-1.5 font-mono text-[10px] uppercase tracking-wider text-zinc-600">
        {label}
      </h3>
      {children}
    </section>
  );
}

export default App;
