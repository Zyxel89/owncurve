// OwnCurve film director: records the pitch video from the live site with a headless browser, frame by
// frame, with a smooth cursor, burned-in English subtitles and title cards. No screen capture, so a slow
// machine only takes longer: the video never stutters.
//
//   SITE=https://zyxel89.github.io/owncurve/ OUT=~/videos/owncurve-pitch.mp4 npx tsx scripts/film.ts
//
// Optional: PRESENTER="Name · Country"  MAINNET_ADDR=<a mainnet DBC config/pool/token>  FPS=30
// Writes OUT (H.264 1920x1080) and OUT with .srt (the same subtitles, for YouTube captions).
import { chromium, Browser, BrowserContext, Locator, Page } from "playwright-core";
import { Connection } from "@solana/web3.js";
import { scanLaunch } from "./lib/scan";
import { spawn, spawnSync } from "child_process";
import fs from "fs";

const SITE = (process.env.SITE ?? "https://zyxel89.github.io/owncurve/").replace(/#.*$/, "");
const MODE = (process.env.MODE ?? "pitch") as "pitch" | "demo" | "intro";
const OUT = process.env.OUT ?? `${process.env.HOME}/videos/owncurve-${MODE}.mp4`;
const FPS = Number(process.env.FPS ?? 30);
const PRESENTER = process.env.PRESENTER ?? "";
const MAINNET_ADDR_ENV = process.env.MAINNET_ADDR ?? "";
let MAINNET_ADDR = MAINNET_ADDR_ENV || "FbKf76ucsQssF7XZBuzScdJfugtsSKwZFYztKsMEhWZM";
// Optional private RPCs: the page keeps calling the public endpoints it was built with, and the recorder
// forwards those calls here (never shown on screen). Avoids public-RPC rate limits while filming.
const DEVNET_RPC = process.env.DEVNET_RPC ?? "";
const MAINNET_RPC = process.env.MAINNET_RPC ?? "";
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
    #oc-card { position: fixed; inset: 0; z-index: 2147483644; pointer-events: none; display: none; place-items: center; text-align: center;
      background: radial-gradient(1200px 600px at 50% 30%, #1d3a31 0%, #0d1512 70%); color: #eef4f1;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
    #oc-card.on { display: grid; }
    #oc-card.on ~ #oc-cursor { display: none; }
    #oc-card h1 { font-size: 92px; margin: 0 0 10px; letter-spacing: -2px; font-weight: 800; }
    #oc-card h1 span { color: #7fd6b0; }
    #oc-card h2 { font-size: 38px; margin: 0 0 30px; font-weight: 500; color: #cfe3da; }
    #oc-card p { font-size: 26px; margin: 8px 0; color: #a9c2b8; }
    #oc-card .big { font-size: 46px; color: #eef4f1; font-weight: 700; margin: 0 0 24px; }
    #oc-card .term { width: 1280px; text-align: left; background: #0b0f0e; border: 1px solid #2c4a40; border-radius: 14px;
      box-shadow: 0 20px 60px rgba(0,0,0,.45); overflow: hidden; margin-bottom: 150px; }
    #oc-card .term .bar { padding: 10px 16px; background: #15201c; color: #8fb3a5; font: 500 17px/1.2 ui-monospace, "DejaVu Sans Mono", monospace; }
    #oc-card .term pre { margin: 0; padding: 18px 22px; height: 520px; overflow: hidden; color: #d8e6df;
      font: 17px/1.5 ui-monospace, "DejaVu Sans Mono", Menlo, monospace; white-space: pre-wrap; word-break: break-all; }
    #oc-card .term .p { color: #7fd6b0; } #oc-card .term .ok { color: #8be0a4; } #oc-card .term .bad { color: #ff8f8f; }
    #oc-card .term .c { color: #6f8f83; } #oc-card .term .k { color: #f0c674; } #oc-card .term .hl { background: rgba(127,214,176,.14); display: inline-block; width: 100%; }
    #oc-card .arch { display: grid; grid-template-columns: 260px 520px 380px; gap: 34px; align-items: center; text-align: left; }
    #oc-card .col { display: grid; gap: 16px; }
    #oc-card .box { border: 1px solid #3f6b5c; border-radius: 12px; padding: 14px 18px; background: rgba(255,255,255,.03); font-size: 19px; line-height: 1.4; color: #cfe3da; transition: none; }
    #oc-card .box b { display: block; font-size: 22px; color: #eef4f1; margin-bottom: 4px; }
    #oc-card .box code { font: 16px ui-monospace, "DejaVu Sans Mono", monospace; color: #9fd8bf; }
    #oc-card .box.on { border-color: #7fd6b0; background: rgba(127,214,176,.13); box-shadow: 0 0 0 2px rgba(127,214,176,.35); }
    #oc-card .core { padding: 22px; } #oc-card .core .sub { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 12px; }
    #oc-card .core .sub span { border: 1px dashed #3f6b5c; border-radius: 8px; padding: 8px 10px; font-size: 16px; }
    #oc-card .arrow { color: #7fd6b0; font-size: 34px; text-align: center; }
    #oc-card .lst { text-align: left; max-width: 1120px; margin: 0 auto; }
    #oc-card .lst p { font-size: 30px; line-height: 1.45; color: #cfe3da; margin: 0 0 18px; padding-left: 34px; position: relative; opacity: .28; }
    #oc-card .lst p.on { opacity: 1; } #oc-card .lst p::before { content: "→"; position: absolute; left: 0; color: #7fd6b0; }
    #oc-card .eyebrow { font-size: 22px; letter-spacing: 3px; text-transform: uppercase; color: #7fd6b0; margin-bottom: 18px; }
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
  for (let attempt = 0; !(await page.locator("a.feature").first().isVisible().catch(() => false)); attempt++) {
    if (attempt >= 3) return false;
    if (attempt === 0) await route(page, "#/");
    else {
      log(`  … raises not loaded, reloading (${attempt})`);
      await page.reload({ waitUntil: "domcontentloaded" });
      await page.evaluate(() => (window as any).__oc.fade(1));
    }
    if (await visible(page.locator("a.feature"), 40_000)) break;
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


// ───────────────────────────── the technical demo ─────────────────────────────
const esc = (t: string) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
type Facts = { tests: string[]; mcp: string[]; program: string[]; programId: string };

/** Lines of `pub fn name` in lib.rs with its doc comment, trimmed to `max` lines. */
function rustFn(name: string, max = 24, skip = 0) {
  const src = fs.readFileSync("programs/owncurve/src/lib.rs", "utf8").split("\n");
  let i = src.findIndex((l) => l.includes(`pub fn ${name}(`));
  if (i < 0) return [];
  let start = i;
  while (start > 0 && src[start - 1].trim().startsWith("///")) start--;
  const body = src.slice(start, i + 1 + skip + max);
  const ind = Math.min(...body.filter((l) => l.trim()).map((l) => l.match(/^ */)![0].length));
  return body.map((l) => l.slice(ind)).slice(0, max + (i - start) + 1);
}
const rustHtml = (lines: string[], hl: RegExp[] = []) =>
  lines
    .map((l) => {
      let h = esc(l);
      if (/^\s*\/\/\//.test(l) || /^\s*\/\//.test(l)) h = `<span class="c">${h}</span>`;
      else h = h.replace(/\b(pub fn|require!|require_keys_eq!|let|mut|if|Ok|emit!)\b/g, '<span class="k">$1</span>');
      return hl.some((r) => r.test(l)) ? `<span class="hl">${h}</span>` : h;
    })
    .join("\n");
const term = (title: string, html: string) => `<div class="term"><div class="bar">● ● ●  ${esc(title)}</div><pre>${html}</pre></div>`;

async function showCode(f: Film, title: string, lines: string[], hl: RegExp[], caps: [string, number][]) {
  if (!lines.length) return;
  await f.card(term(title, rustHtml(lines, hl)));
  await f.fade(0, 0.3);
  for (const [c, s] of caps) {
    await f.cap(c);
    await f.hold(s);
  }
  await f.cap("");
  await f.fade(1, 0.3);
}
async function showTerm(f: Film, title: string, lines: string[], caps: [string, number][], reveal = 3) {
  if (!lines.length) return;
  const n = lines.length;
  await f.card(term(title, ""));
  await f.fade(0, 0.3);
  await f.cap(caps[0][0]);
  const per = Math.max(1, Math.round((reveal * FPS) / n));
  for (let i = 1; i <= n; i++) {
    const shown = lines.slice(Math.max(0, i - 24), i).join("\n");
    await f.card(term(title, shown));
    await f.frame(per);
  }
  await f.hold(Math.max(0.5, caps[0][1] - reveal));
  for (const [c, s] of caps.slice(1)) {
    await f.cap(c);
    await f.hold(s);
  }
  await f.cap("");
  await f.fade(1, 0.3);
}

function gatherFacts(): Facts {
  const strip = (t: string) => t.replace(/\x1b\[[0-9;]*m/g, "");
  const idl = JSON.parse(fs.readFileSync("target/idl/owncurve.json", "utf8"));
  const programId: string = idl.address;
  // 1 · integration tests on the real Meteora binaries
  let tests: string[] = [];
  if (process.env.SKIP_TESTS !== "1") {
    log("running the integration tests for the terminal scene…");
    const r = spawnSync("npx", ["tsx", "--test", "--test-reporter=spec", "tests/owncurve.test.ts"], {
      env: { ...process.env, CLUSTER: "local" }, encoding: "utf8", timeout: 600_000, maxBuffer: 50e6,
    });
    const out = strip(`${r.stdout ?? ""}\n${r.stderr ?? ""}`).split("\n").filter((l) => !/bigint/.test(l));
    const cases = out.filter((l) => /^\s*[✔✖]/.test(l)).map((l) => l.replace(/\s*\(\d+(\.\d+)?ms\)\s*$/, "").trimEnd());
    const summary = out.filter((l) => /^ℹ (tests|pass|fail|duration_ms)/.test(l));
    if (cases.length)
      tests = [`<span class="p">$</span> npm test        <span class="c"># Anchor program + real Meteora DBC and DAMM v2 binaries in LiteSVM</span>`, "",
        ...cases.map((l) => (/✖/.test(l) ? `<span class="bad">${esc(l)}</span>` : `<span class="ok">${esc(l.slice(0, 2))}</span>${esc(l.slice(2))}`)), "",
        ...summary.map((l) => `<span class="ok">${esc(l)}</span>`)];
    log(`tests: ${cases.length} cases`);
  }
  // 2 · program on devnet
  let program: string[] = [];
  const ps = spawnSync("solana", ["program", "show", programId, "--url", DEVNET_RPC || "https://api.devnet.solana.com"], { encoding: "utf8", timeout: 60_000 });
  if (ps.status === 0 && ps.stdout)
    program = [`<span class="p">$</span> solana program show ${programId} --url devnet`, "", ...strip(ps.stdout).trim().split("\n").map(esc)];
  return { tests, mcp: [], program, programId };
}

async function gatherMcp(configG: string | null): Promise<string[]> {
  try {
    const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
    const { StdioClientTransport } = await import("@modelcontextprotocol/sdk/client/stdio.js");
    const client = new Client({ name: "owncurve-demo", version: "1.0.0" });
    await client.connect(
      new StdioClientTransport({
        command: "npx",
        args: ["tsx", "scripts/mcp.ts"],
        env: { ...(process.env as Record<string, string>), CLUSTER: "devnet", RPC_URL: DEVNET_RPC || "https://api.devnet.solana.com" },
        stderr: "ignore",
      }),
    );
    const { tools } = await client.listTools();
    const lines = [
      `<span class="c"># any MCP client (Claude, Cursor…) → the OwnCurve MCP server, on devnet</span>`,
      `<span class="p">→</span> tools/list`,
      `<span class="ok">←</span> ${tools.length} tools: ${esc(tools.map((t: any) => t.name.replace("owncurve_", "")).join(", "))}`,
      "",
    ];
    const target = configG;
    if (target) {
      lines.push(`<span class="p">→</span> owncurve_show { config: "${target.slice(0, 10)}…" }`);
      const res: any = await client.callTool({ name: "owncurve_show", arguments: { config: target } });
      const txt = res?.content?.[0]?.text ?? "";
      let obj: any = null;
      try { obj = JSON.parse(txt); } catch {}
      const pick = obj
        ? {
            name: obj.name, symbol: obj.symbol, state: obj.state,
            milestones: (obj.milestones ?? []).map((m: any) => `${m.index} · ${m.pct}% · ${m.status}${m.evidenceSha256 ? ` · sha256 ${m.evidenceSha256.slice(0, 16)}…` : ""}`),
            treasury: obj.backing?.treasury, backingPerMillionTokens: obj.backing?.perMillionTokens,
            proposal: obj.proposal ?? null,
            budget: obj.budget ? { perPeriod: obj.budget.perPeriod, availableNow: obj.budget.availableNow, advancedOnNextTranche: obj.budget.advancedOnNextTranche } : null,
            bedrock: obj.guard?.bedrock ? { premiumPct: obj.guard.bedrock.premiumPct, twapReady: obj.guard.bedrock.twapReady } : null,
            can: obj.can,
          }
        : null;
      const json = JSON.stringify(pick ?? obj ?? txt, null, 2).split("\n").slice(0, 30);
      lines.push(...json.map((l) => `<span class="ok">←</span> ${esc(l)}`));
      lines.push("", `<span class="c"># write tools (buy, object, redeem, tender_offer…) only simulate unless confirm: true</span>`);
    }
    await client.close();
    return lines;
  } catch (e: any) {
    log(`! MCP scene skipped: ${String(e?.message ?? e).slice(0, 100)}`);
    return [];
  }
}

async function demo(f: Film, facts: Facts) {
  const page = f.page;
  // 0 · Title
  await f.card(`<div><h1>Own<span>Curve</span></h1><h2>Technical demo · how it works on-chain</h2><p>Anchor program · Meteora DBC + DAMM v2 · Solana devnet</p>${PRESENTER ? `<p>${PRESENTER}</p>` : ""}</div>`);
  await f.fade(0, 0.01);
  await f.hold(4);
  await f.fade(1, 0.35);

  // 1 · Architecture
  log("architecture");
  const arch = (on: string[]) => `<div class="arch">
    <div class="col">
      <div class="box ${on.includes("team") ? "on" : ""}"><b>Team</b>launches, requests tranches with evidence</div>
      <div class="box ${on.includes("holders") ? "on" : ""}"><b>Holders</b>buy, object, redeem</div>
      <div class="box ${on.includes("keeper") ? "on" : ""}"><b>Keeper</b>every 10 min, permissionless</div>
      <div class="box ${on.includes("agents") ? "on" : ""}"><b>AI agents</b>MCP server · Agent Skill</div>
    </div>
    <div class="box core ${on.includes("core") ? "on" : ""}"><b>OwnCurve program</b>Anchor · 19 instructions · <code>${esc(facts.programId.slice(0, 8))}…</code>
      <div class="sub"><span>Raise PDA<br>milestones · votes</span><span>Treasury PDA<br>holds the raise</span><span>Guard PDA<br>TWAP · ghost team</span><span>Budget PDA<br>monthly advance</span></div>
    </div>
    <div class="col">
      <div class="box ${on.includes("dbc") ? "on" : ""}"><b>Meteora DBC</b>fee_claimer = treasury PDA<br><code>withdraw_migration_fee</code><br><code>claim_trading_fee</code> · <code>partner_withdraw_surplus</code></div>
      <div class="box ${on.includes("damm") ? "on" : ""}"><b>Meteora DAMM v2</b>LP locked to the treasury<br><code>claim_position_fee</code> · <code>swap</code><br>reads <code>sqrt_price</code> for the TWAP</div>
    </div></div>`;
  const steps: [string[], string, number][] = [
    [["core"], "One Anchor program holds each raise. Its treasury PDA is the DBC config's fee_claimer and leftover_receiver.", 5.2],
    [["core", "dbc"], "At graduation it pulls the migration fee, trading fees and surplus by CPI into DBC, signed by the PDA.", 5.2],
    [["core", "damm"], "After migration to DAMM v2 the LP is locked to the treasury. LP fees and floor buybacks are CPIs into DAMM v2.", 5.6],
    [["core", "team", "holders"], "Teams are paid per milestone; holders can object with quorum and redeem the treasury.", 4.6],
    [["core", "keeper", "agents"], "Every protection is permissionless: a public keeper and AI agents can drive it.", 4.4],
  ];
  await f.card(arch([]));
  await f.fade(0, 0.3);
  for (const [on, c, s] of steps) {
    await f.card(arch(on));
    await f.cap(c);
    await f.hold(s);
  }
  await f.cap("");
  await f.fade(1, 0.3);

  // 2 · bind_pool code
  log("code: bind_pool");
  await showCode(f, "programs/owncurve/src/lib.rs · bind_pool", rustFn("bind_pool", 34).filter((l) => l.trim() !== ""), [/fee_claimer|leftover_receiver|creator_migration_fee|creator_liquidity|token_update_authority|pool.creator/], [
    ["Before the first buy, bind_pool checks the Meteora DBC config on-chain.", 3.6],
    ["The fees must go to the treasury PDA, 0% to the creator, no unlockable LP and no mint authority — or the raise never opens.", 5.2],
  ]);

  // 3 · Launch form
  log("launch form");
  await route(page, "#/new");
  await page.evaluate(() => window.scrollTo(0, 0));
  await visible(page.locator("h1", { hasText: "Launch a raise" }), 20_000);
  await page.waitForTimeout(800);
  await f.card(null);
  await f.fade(0, 0.3);
  await f.cap("Launching a raise: currency (SOL, a stablecoin or a tokenized stock), milestones, objection window and quorum…");
  const legends = page.locator("form legend");
  await f.glide(VW * 0.4, VH * 0.4, 0.8);
  await f.hold(2.4);
  const nLeg = await legends.count();
  for (let i = 1; i < nLeg; i++) {
    if (i === 2) await f.cap("…and the holder protections: price floor reserve, ghost-team timeout, buyout premium and a monthly budget.");
    await f.show(legends.nth(i), 0.18, 1.3);
    await f.point(legends.nth(i), 0.6, 0.1);
    await f.hold(2.0);
  }
  await f.cap("");
  await f.fade(1, 0.3);

  // 4 · Evidence-backed tranches
  log("code: propose_release");
  await f.card(null);
  await showCode(f, "programs/owncurve/src/lib.rs · propose_release", rustFn("propose_release", 30).filter((l) => l.trim() !== ""), [/evidence_hash|evidence_uri|proposal_ends_at/], [
    ["Each tranche request commits a public evidence link and its SHA-256 on-chain, and opens an objection window.", 5.0],
    ["Holders lock tokens to object. With quorum the payment stops, the raise liquidates and every holder redeems pro rata.", 5.2],
  ]);

  // 5 · Bedrock clause: page + code
  log("raise: Bedrock clause");
  const okE = await openFeatured(f, "Bedrock clause", false);
  await settle(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await f.card(null);
  await f.fade(0, 0.3);
  if (okE) {
    const row = page.locator(".guard-row", { hasText: "Bedrock clause" });
    await f.cap("Raise E on devnet: taken over through the on-chain Bedrock clause.");
    if (await row.count()) {
      await f.show(row, 0.42, 1.1);
      await f.point(row.locator("strong").first(), 0.7, 0.2);
    }
    await f.hold(3.4);
    await f.cap("");
    await f.fade(1, 0.3);
  }
  await showCode(f, "programs/owncurve/src/lib.rs · observe", rustFn("observe", 20).filter((l) => l.trim() !== ""), [/damm_price_q64|observe_interval_secs|observations\[head\]/], [
    ["observe() reads sqrt_price straight from the DAMM v2 pool account — owner and mints checked — into a 16-slot ring buffer.", 5.6],
  ]);
  await showCode(f, "programs/owncurve/src/lib.rs · tender_offer", rustFn("tender_offer", 24).filter((l) => l.trim() !== ""), [/twap_q64|buyout_price|required|BuyoutAboveMax/], [
    ["tender_offer(): the acquirer deposits until every circulating token redeems at TWAP × (1 + premium).", 5.2],
    ["Then holders are paid out pro rata and the acquirer becomes the team. There is no other way to take over.", 4.4],
  ]);

  // 6 · Floor defended
  log("raise: floor defended");
  const okA = await openFeatured(f, "floor defended", false);
  await settle(page);
  await f.card(null);
  const fp = page.locator(".floor-panel");
  if (okA && (await fp.count())) {
    const sy = await page.evaluate(() => window.scrollY);
    const box = await fp.boundingBox();
    if (box) await page.evaluate((v) => window.scrollTo(0, v), sy + box.y - VH * 0.3);
    await f.fade(0, 0.3);
    await f.cap("defend_floor: when DAMM v2 trades below the treasury's backing, anyone makes the treasury buy by CPI swap and burn.");
    await f.point(fp.locator(".gauge"), 0.8);
    await f.hold(4.4);
    await f.cap("");
    await f.fade(1, 0.3);
  }

  // 7 · Agents (MCP)
  log("MCP");
  await showTerm(f, "MCP · owncurve server (stdio) · devnet", facts.mcp, [
    ["AI agents: the OwnCurve MCP server exposes every operation as a tool, with the same rules as the program.", 6.0],
    ["An agent can read a raise, audit the tranche evidence and simulate an objection before asking its user to confirm.", 4.6],
  ], 4);

  // 8 · Tests
  log("tests");
  await showTerm(f, "npm test", facts.tests, [
    [`${facts.tests.filter((l) => l.includes("✔")).length} integration tests run the real Meteora DBC and DAMM v2 programs inside LiteSVM.`, 6.4],
    ["Plus CLI, MCP, keeper, scanner and mainnet-study tests, and a browser end-to-end test of the whole flow.", 3.8],
  ], 4.5);

  // 9 · Deployed program
  log("program on devnet");
  await showTerm(f, "solana program show", facts.program, [
    ["Live on devnet. security.txt and the IDL are on-chain, and scripts/verify.sh rebuilds and matches the deployed binary.", 5.2],
  ], 1.5);

  // 10 · Keeper
  log("keeper");
  await route(page, "#/keeper");
  await visible(page.locator(".keeper-log li"), 30_000);
  await page.evaluate(() => window.scrollTo(0, 0));
  await f.card(null);
  await f.fade(0, 0.3);
  await f.cap("The keeper's real transactions on devnet, from GitHub Actions every 10 minutes: settle, observe, defend_floor…");
  const first = page.locator(".keeper-log li").first();
  if (await first.count()) await f.point(first, 0.9, 0.25);
  await f.hold(1.6);
  await f.glide(f.cx, f.cy + 180, 1.6);
  await f.hold(1.4);

  // 11 · Close
  await f.cap("");
  await f.fade(1, 0.4);
  await f.card(`<div><p class="big">Ownership coins, enforced by code on Meteora.</p>
    <p>Open source · MIT · try it on devnet with a test wallet</p>
    <span class="tag">zyxel89.github.io/owncurve · github.com/Zyxel89/owncurve</span></div>`);
  await f.fade(0, 0.4);
  await f.hold(5);
  await f.fade(1, 0.5);
}


// ───────────────────────────── the intro pitch (≤ 2 min: who, what, why us) ─────────────────────────────
async function intro(f: Film) {
  const page = f.page;
  const NAME = process.env.INTRO_NAME ?? "Oscar Gonzalez Santiesteban";
  const FROM = process.env.INTRO_FROM ?? "Bolivia";
  const list = (eyebrow: string, title: string, items: string[], on: number) =>
    `<div><div class="eyebrow">${esc(eyebrow)}</div><p class="big">${esc(title)}</p><div class="lst">${items.map((t, i) => `<p class="${i <= on ? "on" : ""}">${esc(t)}</p>`).join("")}</div></div>`;

  // 0 · Who
  await f.card(`<div><div class="eyebrow">Colosseum · Meteora DBC track</div><h1 style="font-size:76px">Hi, I'm ${esc(NAME.split(" ")[0])}.</h1><h2>${esc(NAME)} · Rust &amp; Web3 engineer · ${esc(FROM)}</h2><p>I built <b style="color:#7fd6b0">OwnCurve</b> for this hackathon, on my own.</p></div>`);
  await f.fade(0, 0.01);
  await f.hold(5.5);
  await f.fade(1, 0.35);

  // 1 · What
  await f.card(`<div><div class="eyebrow">What I'm building</div><h1>Own<span>Curve</span></h1><h2>Ownership coins on Meteora's Dynamic Bonding Curve</h2><p>The money a launch raises sits in an on-chain treasury. The team is paid one milestone at a time.<br>Holders keep rights that a program enforces, not a promise.</p></div>`);
  await f.fade(0, 0.35);
  await f.hold(7);
  await f.fade(1, 0.35);
  await f.card(null);

  // 2 · The problem, on the live app
  await route(page, "#/");
  await page.evaluate(() => window.scrollTo(0, 0));
  await settle(page);
  const stats = page.locator("section.stats");
  if (await stats.count()) {
    const sy = await page.evaluate(() => window.scrollY);
    const box = await stats.boundingBox();
    if (box) await page.evaluate((v) => window.scrollTo(0, v), sy + box.y - VH * 0.3);
  }
  await f.fade(0, 0.35);
  await f.cap("The problem: I read all 1.7 million Meteora DBC launches on mainnet. In 63.6% of them, someone can pull the liquidity after graduation.");
  if (await stats.count()) await f.point(stats.locator(":scope > div").nth(0).locator("strong"), 0.9, 0.12);
  await f.hold(4.6);
  await f.cap("Only 1 in 10 meets four basic holder guarantees. Holders put money in and get no say over it.");
  if (await stats.count()) await f.point(stats.locator(":scope > div").nth(1).locator("strong"), 0.8, 0.12);
  await f.hold(4.2);
  await f.cap("");
  await f.fade(1, 0.3);

  // 3 · The product, live on devnet
  const okA = await openFeatured(f, "floor defended", false);
  await settle(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await f.fade(0, 0.3);
  if (okA) {
    const vault = page.locator("figure.vault");
    await f.cap("OwnCurve, live on devnet: this raise paid its team in three evidence-backed milestones and kept a price floor.");
    await f.point(vault.locator(".vault-track"), 0.9, 0.35);
    await f.hold(4.4);
    await f.cap("");
    await f.fade(1, 0.3);
  }
  const okE = await openFeatured(f, "Bedrock clause", false);
  await settle(page);
  if (okE) {
    const row = page.locator(".guard-row", { hasText: "Bedrock clause" });
    if (await row.count()) {
      const sy = await page.evaluate(() => window.scrollY);
      const box = await row.boundingBox();
      if (box) await page.evaluate((v) => window.scrollTo(0, v), sy + box.y - VH * 0.35);
    }
    await f.fade(0, 0.3);
    await f.cap("Holders can stop a payment and take their share back, and nobody can take the project over without paying them TWAP + 30%.");
    if (await row.count()) await f.point(row.locator("strong").first(), 0.9, 0.25);
    await f.hold(4.8);
    await f.cap("");
    await f.fade(1, 0.3);
  }
  await f.card(null);

  // 4 · Why me
  const why = [
    "I write Rust smart contracts and protocol code for a living.",
    "I built all of OwnCurve here: an Anchor program with CPIs into Meteora DBC and DAMM v2, the web app, a keeper, an MCP server and 31 tests on the real Meteora binaries.",
    "I measured the problem first: every rule in the program answers a failure I found in real mainnet launches.",
  ];
  for (let i = 0; i < why.length; i++) {
    await f.card(list("Why me", "Why I'm the one to build this", why, i));
    if (i === 0) await f.fade(0, 0.35);
    await f.hold(i === 1 ? 6.2 : 4.4);
  }
  await f.fade(1, 0.35);

  // 5 · Why now / next
  const now = [
    "Meteora launched Bedrock to protect holders of ownership coins with legal agreements. OwnCurve enforces the same promises in code.",
    "DBC is the launch primitive most Solana launchpads already use, so any of them can turn this on for their creators.",
    "Next: an audit, mainnet, and the first launchpad integration.",
  ];
  for (let i = 0; i < now.length; i++) {
    await f.card(list("Why now", "Ownership coins, enforced by code", now, i));
    if (i === 0) await f.fade(0, 0.35);
    await f.hold(i === 2 ? 3.6 : 5.0);
  }
  await f.fade(1, 0.35);

  // 6 · Close
  await f.card(`<div><h1>Own<span>Curve</span></h1><h2>Thanks for watching.</h2><p>Live demo, code and the full technical walkthrough:</p><span class="tag">zyxel89.github.io/owncurve · github.com/Zyxel89/owncurve</span></div>`);
  await f.fade(0, 0.4);
  await f.hold(4.5);
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

/** Forward the page's calls to public Solana RPCs to the private ones, adding CORS headers. */
async function forwardRpc(ctx: BrowserContext, hosts: string[], target: string) {
  if (!target) return;
  await ctx.route(
    (u) => hosts.includes(u.hostname),
    async (r) => {
      const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "POST, GET, OPTIONS" };
      if (r.request().method() === "OPTIONS") return r.fulfill({ status: 204, headers: cors });
      for (let i = 0; ; i++) {
        try {
          const res = await r.fetch({ url: target, headers: { "content-type": "application/json" } });
          if (res.status() === 429 && i < 4) {
            await new Promise((x) => setTimeout(x, 800 * (i + 1)));
            continue;
          }
          return r.fulfill({ status: res.status(), body: await res.body(), headers: { ...cors, "content-type": "application/json" } });
        } catch (e) {
          if (i >= 3) return r.abort().catch(() => {});
          await new Promise((x) => setTimeout(x, 800));
        }
      }
    },
  );
}

/** A real mainnet launch that fails OwnCurve's rules, checked before filming (from the mainnet study). */
async function pickMainnet() {
  const cands: string[] = [];
  if (MAINNET_ADDR_ENV) cands.push(MAINNET_ADDR_ENV);
  try {
    const study = JSON.parse(fs.readFileSync("docs/mainnet-study.json", "utf8"));
    for (const c of study.topConfigs ?? [])
      if (!c.feeClaimerIsProgram && c.migrationFeePct > 0 || c.unlockedLpPct > 0 || c.mintAuthorityKept || c.creatorShareOfFeePct > 0) cands.push(c.address);
  } catch {}
  const conn = new Connection(MAINNET_RPC || "https://solana-rpc.publicnode.com", "confirmed");
  for (const a of cands.slice(0, 12)) {
    try {
      const r = await scanLaunch(conn, a);
      log(`mainnet ${a.slice(0, 8)}… grade ${r.grade}`);
      if (!["A+", "A", "B"].includes(r.grade)) return a;
    } catch (e: any) {
      log(`mainnet ${a.slice(0, 8)}… ${String(e?.message ?? e).slice(0, 80)}`);
    }
  }
  log("! no mainnet launch with a bad grade found; using the default address");
  return MAINNET_ADDR;
}

async function main() {
  fs.mkdirSync(OUT.replace(/\/[^/]*$/, ""), { recursive: true });
  const browser = await launch();
  const ctx = await browser.newContext({ viewport: { width: VW, height: VH }, deviceScaleFactor: 1.2, colorScheme: "light" });
  await ctx.addInitScript(OVERLAY);
  await forwardRpc(ctx, ["api.devnet.solana.com"], DEVNET_RPC);
  await forwardRpc(ctx, ["solana-rpc.publicnode.com", "solana.drpc.org", "api.mainnet-beta.solana.com"], MAINNET_RPC);
  log(`devnet RPC: ${DEVNET_RPC ? "private (forwarded)" : "public"} · mainnet RPC: ${MAINNET_RPC ? "private (forwarded)" : "public"}`);
  let facts: Facts | null = null;
  if (MODE === "pitch") {
    MAINNET_ADDR = await pickMainnet();
    log(`rug check uses ${MAINNET_ADDR}`);
  } else if (MODE === "demo") {
    facts = gatherFacts();
    let featuredG: string | null = null;
    try {
      const fj = JSON.parse(fs.readFileSync("app/src/featured.json", "utf8"));
      featuredG = (fj.featured ?? []).find((x: any) => /budget/i.test(x.label))?.config ?? fj.featured?.[0]?.config ?? null;
    } catch {}
    facts.mcp = await gatherMcp(featuredG);
  }
  const page = await ctx.newPage();
  console.log(`  site ${SITE}`);
  await page.goto(SITE, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.evaluate(() => (window as any).__oc.fade(1));
  if (!(await visible(page.locator("a.feature"), 60_000))) log("! featured raises did not load (RPC busy?) — raise scenes will be skipped");
  await settle(page);
  const f = new Film(page);
  const t0 = Date.now();
  if (MODE === "pitch") await pitch(f);
  else if (MODE === "intro") await intro(f);
  else await demo(f, facts!);
  await f.finish();
  await browser.close();
  console.log(`  ✔ ${OUT} · ${f.sec().toFixed(1)} s of video · rendered in ${((Date.now() - t0) / 60000).toFixed(1)} min`);
  if (f.sec() > 180) console.log("  ! longer than 3 min: tell Claude so it can tighten it");
}

main().catch((e) => {
  console.error(`  ✘ ${e?.message ?? e}`);
  process.exit(1);
});
