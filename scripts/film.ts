// OwnCurve film director: records the pitch video from the live site with a headless browser, frame by
// frame, with a smooth cursor, burned-in English subtitles and title cards. No screen capture, so a slow
// machine only takes longer: the video never stutters.
//
//   SITE=https://zyxel89.github.io/owncurve/ OUT=~/videos/owncurve-pitch.mp4 npx tsx scripts/film.ts
//
// Optional: PRESENTER="Name · Country"  MAINNET_ADDR=<a mainnet DBC config/pool/token>  FPS=30
// Writes OUT (H.264 1920x1080) and OUT with .srt (the same subtitles, for YouTube captions).
import { chromium, Browser, Locator, Page } from "playwright-core";
import { spawn } from "child_process";
import fs from "fs";

const SITE = (process.env.SITE ?? "https://zyxel89.github.io/owncurve/").replace(/#.*$/, "");
const OUT = process.env.OUT ?? `${process.env.HOME}/videos/owncurve-pitch.mp4`;
const FPS = Number(process.env.FPS ?? 30);
const PRESENTER = process.env.PRESENTER ?? "";
const MAINNET_ADDR = process.env.MAINNET_ADDR ?? "FbKf76ucsQssF7XZBuzScdJfugtsSKwZFYztKsMEhWZM";
const VW = 1600;
const VH = 900; // ×1.2 = 1920x1080

// ───────────────────────────── overlay (cursor, subtitles, fades, cards) ─────────────────────────────
const OVERLAY = `
(() => {
  const css = \`
    html { scroll-behavior: auto !important; scrollbar-width: none; }
    html::-webkit-scrollbar, body::-webkit-scrollbar { display: none; }
    #oc-cursor { position: fixed; left: 0; top: 0; width: 26px; height: 26px; z-index: 2147483646; pointer-events: none;
      transform: translate(-100px, -100px); transition: none; filter: drop-shadow(0 2px 3px rgba(0,0,0,.35)); }
    #oc-cursor.down svg { transform: scale(.82); transform-origin: 3px 3px; }
    #oc-cap { position: fixed; left: 50%; bottom: 46px; transform: translateX(-50%); max-width: 1180px; z-index: 2147483645;
      pointer-events: none; padding: 14px 26px; border-radius: 12px; background: rgba(12,18,16,.86); color: #fff;
      font: 600 27px/1.38 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; text-align: center; letter-spacing: .1px;
      box-shadow: 0 6px 28px rgba(0,0,0,.28); opacity: 0; }
    #oc-cap.on { opacity: 1; }
    #oc-fade { position: fixed; inset: 0; background: #0d1512; z-index: 2147483647; pointer-events: none; opacity: 0; }
    #oc-card { position: fixed; inset: 0; z-index: 2147483644; display: none; place-items: center; text-align: center;
      background: radial-gradient(1200px 600px at 50% 30%, #1d3a31 0%, #0d1512 70%); color: #eef4f1;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
    #oc-card.on { display: grid; }
    #oc-card.on ~ #oc-cursor { display: none; }
    #oc-card h1 { font-size: 92px; margin: 0 0 10px; letter-spacing: -2px; font-weight: 800; }
    #oc-card h1 span { color: #7fd6b0; }
    #oc-card h2 { font-size: 38px; margin: 0 0 30px; font-weight: 500; color: #cfe3da; }
    #oc-card p { font-size: 26px; margin: 8px 0; color: #a9c2b8; }
    #oc-card .big { font-size: 46px; color: #eef4f1; font-weight: 700; margin: 0 0 24px; }
    #oc-card .tag { display: inline-block; margin-top: 26px; padding: 8px 18px; border: 1px solid #3f6b5c; border-radius: 999px; font-size: 22px; color: #9fd8bf; }
  \`;
  const ensure = () => {
    if (!document.body) return;
    if (!document.getElementById("oc-style")) {
      const s = document.createElement("style"); s.id = "oc-style"; s.textContent = css; document.head.appendChild(s);
    }
    for (const id of ["oc-card", "oc-cap", "oc-fade", "oc-cursor"]) {
      if (!document.getElementById(id)) {
        const d = document.createElement("div"); d.id = id;
        if (id === "oc-cursor") d.innerHTML = '<svg width="26" height="26" viewBox="0 0 26 26"><path d="M3 2 L3 21 L8.2 16.2 L11.6 23.6 L14.9 22.1 L11.6 14.9 L18.6 14.6 Z" fill="#fff" stroke="#111" stroke-width="1.6" stroke-linejoin="round"/></svg>';
        document.body.appendChild(d);
      }
    }
  };
  window.__oc = {
    ensure,
    cursor(x, y, down) { ensure(); const c = document.getElementById("oc-cursor"); c.style.transform = "translate(" + x + "px," + y + "px)"; c.classList.toggle("down", !!down); },
    cap(t) { ensure(); const c = document.getElementById("oc-cap"); c.textContent = t || ""; c.classList.toggle("on", !!t); },
    fade(a) { ensure(); document.getElementById("oc-fade").style.opacity = String(a); },
    card(html) { ensure(); const c = document.getElementById("oc-card"); c.innerHTML = html || ""; c.classList.toggle("on", !!html); },
  };
  document.addEventListener("DOMContentLoaded", ensure);
})();
`;

// ───────────────────────────── recorder ─────────────────────────────
type Cue = { start: number; end: number; text: string };

class Film {
  frames = 0;
  cues: Cue[] = [];
  private open: { start: number; text: string } | null = null;
  cx = VW * 0.62;
  cy = VH * 0.55;
  private ff = spawn(
    "ffmpeg",
    ["-loglevel", "error", "-y", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "mjpeg", "-i", "-",
     "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-shortest",
     "-vf", "scale=1920:1080:flags=lanczos,format=yuv420p", "-c:v", "libx264", "-preset", "medium", "-crf", "18",
     "-r", String(FPS), "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", OUT],
    { stdio: ["pipe", "inherit", "inherit"] },
  );
  private done = new Promise<number>((res) => this.ff.on("close", (c) => res(c ?? 1)));
  constructor(public page: Page) {}

  sec = () => this.frames / FPS;
  private async write(buf: Buffer, times = 1) {
    for (let i = 0; i < times; i++) {
      if (!this.ff.stdin.write(buf)) await new Promise((r) => this.ff.stdin.once("drain", r));
      this.frames++;
    }
  }
  private async shot() {
    await this.page.evaluate(() => (window as any).__oc?.ensure());
    return this.page.screenshot({ type: "jpeg", quality: 92, scale: "device", animations: "allow", caret: "hide" });
  }
  async frame(times = 1) {
    await this.write(await this.shot(), times);
  }
  /** Still frames: one capture, repeated. */
  async hold(s: number) {
    await this.frame(Math.max(1, Math.round(s * FPS)));
  }
  /** Real time: keep capturing until `until()` is true (or maxS), at least minS. */
  async live(until: () => Promise<boolean>, maxS = 30, minS = 0.6) {
    const t0 = Date.now();
    for (;;) {
      const buf = await this.shot();
      const elapsed = (Date.now() - t0) / 1000;
      await this.write(buf); // one frame per capture: slow waits come out a little sped up
      if (elapsed >= minS && (await until().catch(() => false))) return true;
      if (elapsed > maxS) return false;
    }
  }
  async cap(text: string) {
    if (this.open) this.cues.push({ ...this.open, end: this.frames });
    this.open = text ? { start: this.frames, text } : null;
    await this.page.evaluate((t) => (window as any).__oc.cap(t), text);
  }
  async card(html: string | null) {
    await this.page.evaluate((h) => (window as any).__oc.card(h), html);
  }
  async fade(to: number, s = 0.35) {
    const n = Math.max(2, Math.round(s * FPS));
    const from = await this.page.evaluate(() => Number(document.getElementById("oc-fade")?.style.opacity || 0));
    for (let i = 1; i <= n; i++) {
      await this.page.evaluate((a) => (window as any).__oc.fade(a), from + ((to - from) * i) / n);
      await this.frame();
    }
  }
  private async setCursor(x: number, y: number, down = false) {
    this.cx = x;
    this.cy = y;
    await this.page.evaluate(([a, b, d]) => (window as any).__oc.cursor(a, b, d), [x, y, down] as [number, number, boolean]);
    await this.page.mouse.move(x, y).catch(() => {});
  }
  async glide(x: number, y: number, s = 0.8) {
    const n = Math.max(2, Math.round(s * FPS));
    const [x0, y0] = [this.cx, this.cy];
    for (let i = 1; i <= n; i++) {
      const t = ease(i / n);
      await this.setCursor(x0 + (x - x0) * t, y0 + (y - y0) * t);
      await this.frame();
    }
  }
  async scrollTo(y: number, s = 1.2) {
    const y0 = await this.page.evaluate(() => window.scrollY);
    const max = await this.page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight);
    const y1 = Math.max(0, Math.min(max, y));
    if (Math.abs(y1 - y0) < 4) return;
    const n = Math.max(2, Math.round(s * FPS));
    for (let i = 1; i <= n; i++) {
      await this.page.evaluate((v) => window.scrollTo(0, v), y0 + (y1 - y0) * ease(i / n));
      await this.frame();
    }
  }
  /** Scroll so the element sits at `at` (0 top … 1 bottom) of the viewport. */
  async show(loc: Locator, at = 0.42, s = 1.2) {
    const box = await loc.boundingBox();
    if (!box) return;
    const sy = await this.page.evaluate(() => window.scrollY);
    const target = sy + box.y + Math.min(box.height, VH * 0.8) / 2 - VH * at;
    await this.scrollTo(target, s);
  }
  async point(loc: Locator, s = 0.7, dx = 0.5, dy = 0.5) {
    const box = await loc.boundingBox();
    if (!box) return;
    await this.glide(box.x + box.width * dx, box.y + Math.min(box.height, 120) * dy, s);
  }
  async click(loc: Locator) {
    await this.point(loc, 0.6);
    await this.setCursor(this.cx, this.cy, true);
    await this.frame(4);
    await loc.click();
    await this.setCursor(this.cx, this.cy, false);
    await this.frame(2);
  }
  async type(loc: Locator, text: string) {
    await loc.click();
    await loc.fill("");
    for (const ch of text) {
      await this.page.keyboard.type(ch);
      await this.frame(1);
    }
  }
  async finish() {
    await this.cap("");
    this.ff.stdin.end();
    const code = await this.done;
    if (code !== 0) throw new Error(`ffmpeg exited with ${code}`);
    fs.writeFileSync(OUT.replace(/\.mp4$/, "") + ".srt", srt(this.cues));
  }
}

const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const ts = (f: number) => {
  const ms = Math.round((f / FPS) * 1000);
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(Math.floor(ms / 1000) % 60)},${p(ms % 1000, 3)}`;
};
const srt = (cues: Cue[]) => cues.filter((c) => c.end > c.start).map((c, i) => `${i + 1}\n${ts(c.start)} --> ${ts(c.end)}\n${c.text}\n`).join("\n");

// ───────────────────────────── helpers on the app ─────────────────────────────
const log = (m: string) => console.log(`  ${m}`);
async function visible(loc: Locator, timeout = 45_000) {
  try {
    await loc.first().waitFor({ state: "visible", timeout });
    return true;
  } catch {
    return false;
  }
}
async function route(page: Page, hash: string) {
  await page.evaluate((h) => (location.hash = h), hash);
  await page.waitForTimeout(250);
}
/** Open a featured raise from the home page; returns false if it is not there. */
async function openFeatured(f: Film, label: string, onCamera = true) {
  const page = f.page;
  if (!(await page.locator("a.feature").first().isVisible().catch(() => false))) {
    await route(page, "#/");
    if (!(await visible(page.locator("a.feature")))) return false;
  }
  const card = page.locator("a.feature", { hasText: label }).first();
  if (!(await card.count())) return false;
  if (onCamera) {
    await f.show(card, 0.45, 1.0);
    await f.point(card, 0.6, 0.3, 0.4);
    await f.hold(0.6);
    await f.click(card);
  } else await card.click();
  return visible(page.locator("figure.vault"), 45_000);
}
async function settle(page: Page) {
  // wait until "Reading…" placeholders are gone and the network is quiet
  await page.waitForLoadState("networkidle", { timeout: 15_000 }).catch(() => {});
  for (let i = 0; i < 40; i++) {
    const loading = await page.getByText(/Reading (raises|the chain)…/).count();
    if (!loading) break;
    await page.waitForTimeout(500);
  }
  await page.waitForTimeout(600);
}

// ───────────────────────────── the pitch ─────────────────────────────
async function pitch(f: Film) {
  const page = f.page;
  const presenter = PRESENTER ? `<p>${PRESENTER}</p>` : "";

  // 0 · Title
  await f.card(
    `<div><h1>Own<span>Curve</span></h1><h2>Ownership coins on Meteora's Dynamic Bonding Curve</h2>${presenter}<span class="tag">Colosseum · Best use of Meteora DBC</span></div>`,
  );
  await f.fade(0, 0.01);
  await f.hold(4.5);
  await f.fade(1, 0.4);
  await f.card(null);
  await page.evaluate(() => window.scrollTo(0, 0));
  await f.fade(0, 0.4);

  // 1 · The problem
  log("home");
  await f.cap("Token launches raise real money. On most of them, holders have no say in what happens to it.");
  await f.glide(VW * 0.38, VH * 0.36, 1.2);
  await f.hold(4.2);
  const stats = page.locator("section.stats");
  if (await visible(stats, 5000)) {
    await f.show(stats, 0.45, 1.4);
    const s = stats.locator(":scope > div");
    await f.cap("We read every Meteora DBC launch on Solana mainnet: 1.7 million of them.");
    await f.point(s.nth(0).locator("strong"), 0.8, 0.12);
    await f.hold(3.2);
    await f.cap("In 63.6% of them, someone can withdraw the liquidity after the token graduates.");
    await f.hold(4.0);
    await f.cap("Only 1 in 10 meets four basic holder guarantees.");
    await f.point(s.nth(1).locator("strong"), 0.8, 0.12);
    await f.hold(3.0);
    await f.cap("Where there is a graduation fee, it almost always lands in a wallet.");
    await f.point(s.nth(2).locator("strong"), 0.8, 0.12);
    await f.hold(3.0);
  }

  // 2 · Bedrock vs code
  const cmp = page.locator("section.compare");
  if (await visible(cmp, 5000)) {
    log("comparison");
    await f.cap("Meteora launched Bedrock to protect holders with lawyers. We think code should do it.");
    await f.show(cmp.locator("h2"), 0.1, 1.8);
    await f.point(cmp.locator("thead th").nth(1), 0.8);
    await f.hold(2.6);
    const row = (t: string) => cmp.locator("tbody tr", { hasText: t }).locator("td").first();
    await f.cap("With OwnCurve, holders — not a few reviewers — can stop a payment to the team.");
    await f.point(row("Who can stop a payment"), 0.8);
    await f.hold(2.6);
    await f.cap("And nobody can take the project over without paying every holder a fair price.");
    await f.point(row("Takeover must pay"), 0.8);
    await f.hold(2.8);
  }

  // 3 · How it works: floor defended
  await f.cap("");
  await f.fade(1, 0.35);
  await f.card(`<div><p class="big">How it works</p><p>Live on Solana devnet · every number read from the chain</p></div>`);
  await f.fade(0, 0.3);
  await f.hold(2.0);
  await f.fade(1, 0.3);
  await f.card(null);
  await route(page, "#/");
  await page.evaluate(() => window.scrollTo(0, 0));
  log("raise: floor defended");
  const okA = (await visible(page.locator("a.feature"), 45_000)) && (await openFeatured(f, "floor defended", false));
  await settle(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await f.fade(0, 0.35);
  if (okA) {
    const vault = page.locator("figure.vault");
    await f.cap("OwnCurve turns a DBC launch into an ownership coin. The raise goes into an on-chain treasury.");
    await f.show(vault, 0.4, 1.0);
    await f.point(vault.locator(".vault-track"), 0.8, 0.3);
    await f.hold(3.0);
    await f.cap("The team is paid one milestone at a time. This team shipped three milestones and was paid three times.");
    const labels = vault.locator(".seg-labels li:not(.floor)");
    const n = await labels.count();
    for (let i = 0; i < n; i++) {
      await f.point(labels.nth(i), 0.5, 0.4, 0.3);
      await f.hold(1.2);
    }
    const floorSeg = vault.locator(".seg-labels li.floor");
    if (await floorSeg.count()) {
      await f.cap("Part of the treasury is a price floor. It is never paid to the team.");
      await f.point(floorSeg, 0.6, 0.4, 0.3);
      await f.hold(2.8);
    }
    const g = page.locator("section.guarantees");
    if (await g.count()) {
      await f.cap("Before the first buy, the program checks the launch on-chain: no wallet takes the raise, no liquidity can be pulled.");
      await f.show(g, 0.45, 1.0);
      await f.point(g.locator("li").first(), 0.6, 0.3);
      await f.glide(f.cx, f.cy + 120, 1.6);
      await f.hold(1.6);
    }
    const fp = page.locator(".floor-panel");
    if (await fp.count()) {
      await f.cap("After a panic sell, anyone made the treasury buy tokens back below their backing — and burn them.");
      await f.show(fp, 0.45, 1.0);
      await f.point(fp.locator(".gauge"), 0.7);
      await f.hold(3.6);
    }
  }

  // 4 · Holders said no / team went silent
  for (const [label, text] of [
    ["holders said no", "Holders can stop a payment. Here they objected with quorum: the team got nothing, and every holder can take their share back."],
    ["team went silent", "If the team goes silent, the treasury goes back to the holders. Anyone can trigger it; no one has to ask."],
  ] as const) {
    log(`raise: ${label}`);
    await f.cap("");
    await f.fade(1, 0.3);
    const ok = await openFeatured(f, label, false);
    await settle(page);
    await page.evaluate(() => window.scrollTo(0, 0));
    await f.fade(0, 0.3);
    if (!ok) continue;
    await f.cap(text);
    const vault = page.locator("figure.vault");
    await f.show(vault, 0.4, 0.8);
    await f.point(vault.locator(".seg-labels li").first(), 0.7, 0.4, 0.3);
    await f.hold(2.2);
    const gp = page.locator(".guard-row", { hasText: label === "team went silent" ? "Ghost-team" : "Bedrock" });
    if (label === "team went silent" && (await gp.count())) {
      await f.show(gp, 0.45, 1.0);
      await f.point(gp.locator("strong").first(), 0.6, 0.2);
      await f.hold(2.6);
    } else await f.hold(2.4);
  }

  // 5 · Bedrock clause on-chain
  log("raise: Bedrock clause");
  await f.cap("");
  await f.fade(1, 0.3);
  const okE = await openFeatured(f, "Bedrock clause", false);
  await settle(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await f.fade(0, 0.3);
  if (okE) {
    const row = page.locator(".guard-row", { hasText: "Bedrock clause" });
    await f.cap("Bedrock's takeover clause, as code: a takeover must pay every holder the on-chain TWAP + 30%.");
    if (await row.count()) {
      await f.show(row, 0.45, 1.2);
      await f.point(row.locator("strong").first(), 0.7, 0.2);
      await f.hold(3.4);
      await f.cap("The price comes from Meteora DAMM v2 itself. Here the acquirer paid, and every token redeems at that price.");
      await f.glide(f.cx + 160, f.cy + 30, 1.2);
      await f.hold(3.0);
    } else await f.hold(4);
  }

  // 6 · Rug check
  log("rug check");
  await f.cap("");
  await f.fade(1, 0.3);
  await route(page, "#/scan");
  await page.evaluate(() => window.scrollTo(0, 0));
  await f.fade(0, 0.3);
  const input = page.locator('input[placeholder="Paste an address"]');
  if (await visible(input, 10_000)) {
    const sel = page.locator("select").first();
    await sel.selectOption("mainnet").catch(() => {});
    await f.cap("Rug check: paste any Meteora DBC launch, from mainnet, and see what holders are promised.");
    await f.point(input, 0.8, 0.3);
    await f.type(input, MAINNET_ADDR);
    await f.click(page.getByRole("button", { name: "Check" }));
    const got = await f.live(async () => (await page.locator(".scan-result .grade, .error").count()) > 0, 40);
    if (got && (await page.locator(".scan-result .grade").count())) {
      const res = page.locator(".scan-result");
      await f.cap("A real mainnet launch, graded on the four rules OwnCurve enforces.");
      await f.show(res, 0.42, 1.0);
      await f.point(res.locator(".grade"), 0.6);
      await f.hold(2.4);
      await f.glide(f.cx + 260, f.cy + 150, 1.4);
      await f.hold(1.4);
      const tryBtn = page.getByRole("button", { name: "Try an OwnCurve raise" });
      if (await tryBtn.count()) {
        await f.scrollTo(0, 0.9);
        await f.cap("An OwnCurve raise passes every check.");
        await f.click(tryBtn);
        await f.live(async () => /A\+/.test((await page.locator(".scan-result .grade").textContent().catch(() => "")) ?? ""), 30);
        const res2 = page.locator(".scan-result");
        await f.show(res2, 0.42, 1.0);
        await f.point(res2.locator(".grade"), 0.6);
        await f.hold(2.6);
      }
    } else log("! rug check gave no result (RPC busy?) — scene kept short");
  }

  // 7 · More currencies, budget, keeper
  log("currencies + keeper");
  await f.cap("");
  await f.fade(1, 0.3);
  await route(page, "#/");
  await visible(page.locator("a.feature"), 45_000);
  await settle(page);
  const stable = page.locator("a.feature", { hasText: "stablecoin" }).first();
  if (await stable.count()) {
    const sy = await page.evaluate(() => window.scrollY);
    const box = await stable.boundingBox();
    if (box) await page.evaluate((v) => window.scrollTo(0, v), sy + box.y - VH * 0.14);
  }
  await f.fade(0, 0.3);
  if (await stable.count()) {
    await f.cap("Raises work in SOL, in a stablecoin, or in a tokenized stock.");
    await f.point(stable, 0.7, 0.3, 0.3);
    await f.hold(1.6);
    const stock = page.locator("a.feature", { hasText: "tokenized stock" }).first();
    if (await stock.count()) {
      await f.point(stock, 0.7, 0.3, 0.3);
      await f.hold(1.6);
    }
    const live = page.locator("a.feature", { hasText: "budget" }).first();
    if (await live.count()) {
      await f.cap("Teams can draw a capped monthly budget, as an advance on their next milestone.");
      await f.show(live, 0.3, 0.9);
      await f.point(live, 0.7, 0.3, 0.3);
      await f.hold(2.4);
    }
  }
  await f.cap("");
  await f.fade(1, 0.3);
  await route(page, "#/keeper");
  await visible(page.locator(".keeper-log li"), 30_000);
  await page.evaluate(() => window.scrollTo(0, 0));
  await f.fade(0, 0.3);
  await f.cap("A public keeper runs every 10 minutes: it settles payments, records prices and protects holders. No humans needed.");
  const firstRun = page.locator(".keeper-log li").first();
  if (await firstRun.count()) await f.point(firstRun, 0.9, 0.25);
  await f.hold(1.4);
  await f.glide(f.cx, f.cy + 160, 1.4);
  await f.hold(1.6);

  // 8 · Close
  await f.cap("");
  await f.fade(1, 0.4);
  await f.card(
    `<div><p class="big">Any launchpad on Meteora can offer ownership coins.</p>
      <p>AI agents can guard holders too, through the OwnCurve MCP server.</p>
      <p>Next: audit · mainnet · Bedrock launchpads</p>
      <span class="tag">zyxel89.github.io/owncurve · github.com/Zyxel89/owncurve</span></div>`,
  );
  await f.fade(0, 0.4);
  await f.hold(6);
  await f.fade(1, 0.5);
}

async function launch(): Promise<Browser> {
  const args = ["--hide-scrollbars", "--force-color-profile=srgb", "--disable-gpu"];
  try {
    return await chromium.launch({ args, executablePath: process.env.CHROME_PATH || undefined });
  } catch (e) {
    for (const p of ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome", "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"]) {
      if (fs.existsSync(p)) return chromium.launch({ args, executablePath: p });
    }
    throw e;
  }
}

async function main() {
  fs.mkdirSync(OUT.replace(/\/[^/]*$/, ""), { recursive: true });
  const browser = await launch();
  const ctx = await browser.newContext({ viewport: { width: VW, height: VH }, deviceScaleFactor: 1.2, colorScheme: "light" });
  await ctx.addInitScript(OVERLAY);
  const page = await ctx.newPage();
  console.log(`  site ${SITE}`);
  await page.goto(SITE, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.evaluate(() => (window as any).__oc.fade(1));
  if (!(await visible(page.locator("a.feature"), 60_000))) log("! featured raises did not load (RPC busy?) — raise scenes will be skipped");
  await settle(page);
  const f = new Film(page);
  const t0 = Date.now();
  await pitch(f);
  await f.finish();
  await browser.close();
  console.log(`  ✔ ${OUT} · ${f.sec().toFixed(1)} s of video · rendered in ${((Date.now() - t0) / 60000).toFixed(1)} min`);
  if (f.sec() > 180) console.log("  ! longer than 3 min: tell Claude so it can tighten it");
}

main().catch((e) => {
  console.error(`  ✘ ${e?.message ?? e}`);
  process.exit(1);
});
