// Test E2E de la interfaz: navegador real (Chromium) + app (Vite) + LiteSVM con los
// programas reales. Dos personas con wallets de prueba: el equipo y un holder.
//
//  equipo lanza un raise → holder compra → equipo completa la curva → tesorería financiada →
//  graduación a DAMM v2 → venta de pánico → cualquiera dispara la defensa del piso →
//  equipo pide el tramo 1 con evidencia → holder la ve y objeta con quórum → se cierra la ventana → liquidación →
//  holder desbloquea sus tokens y los redime por SOL
//
// Ejecutar: npx tsx tests/e2e/ui.e2e.ts   (SHOTS=dir guarda capturas)
import { chromium, Page } from "playwright-core";
import fs from "fs";
import path from "path";
import { createServer } from "vite";
import { startRpc } from "./rpc-server";

const CHROME = process.env.CHROME_PATH ?? "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";
const SHOTS = process.env.SHOTS;
let shotN = 0;

async function main() {
  const rpc = await startRpc(8899);
  process.env.VITE_CLUSTER = "local";
  process.env.VITE_RPC_URL = rpc.url;
  const vite = await createServer({
    configFile: path.resolve("app/vite.config.ts"),
    server: { port: 5199, strictPort: true },
    logLevel: "error",
  });
  await vite.listen();
  const appUrl = "http://localhost:5199/";
  const browser = await chromium.launch({ executablePath: CHROME });
  const errors: string[] = [];

  const person = async (name: string) => {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const page = await ctx.newPage();
    page.on("pageerror", (e) => errors.push(`${name}: ${e.message}`));
    await page.goto(appUrl);
    await page.getByRole("button", { name: "Use a test wallet" }).click();
    await page.getByRole("button", { name: "Get 1 SOL" }).waitFor();
    const secret = JSON.parse((await page.evaluate(() => localStorage.getItem("owncurve.burner.v1")))!);
    const { Keypair } = await import("@solana/web3.js");
    const pk = Keypair.fromSecretKey(Uint8Array.from(secret)).publicKey;
    rpc.svm.airdrop(pk, 5_000_000_000n);
    const kp = Keypair.fromSecretKey(Uint8Array.from(secret));
    return { page, pk, kp };
  };
  const shot = async (page: Page, name: string) => {
    if (!SHOTS) return;
    fs.mkdirSync(SHOTS, { recursive: true });
    await page.screenshot({ path: `${SHOTS}/${String(++shotN).padStart(2, "0")}-${name}.png`, fullPage: true });
  };
  const ok = async (page: Page, text: RegExp | string) => {
    await page.getByRole("status").filter({ hasText: text }).waitFor({ timeout: 30_000 });
  };
  const step = (s: string) => console.log(`  ✔ ${s}`);

  try {
    const team = await person("equipo");
    const holder = await person("holder");
    await shot(team.page, "inicio-vacio");
    // El botón de airdrop de la wallet de prueba funciona contra la red
    await team.page.getByRole("button", { name: "Get 1 SOL" }).click();
    await team.page.getByText("1 devnet SOL added.").waitFor();
    step("wallets de prueba creadas y fondeadas");

    // 1. Lanzar
    await team.page.getByRole("link", { name: "Launch a raise" }).first().click();
    await team.page.getByLabel("Name").fill("Lighthouse Labs");
    await team.page.getByLabel("Symbol").fill("light");
    await shot(team.page, "formulario");
    await team.page.getByRole("button", { name: "Launch raise" }).click();
    await team.page.getByRole("heading", { name: /Lighthouse Labs/ }).waitFor({ timeout: 30_000 });
    const raiseUrl = team.page.url();
    await team.page.getByText("On the curve").first().waitFor();
    step(`raise lanzado: ${raiseUrl.split("/").pop()}`);
    await shot(team.page, "raise-en-curva");

    // 2. Holder compra, luego el equipo completa la curva
    await holder.page.goto(raiseUrl);
    await holder.page.getByLabel("SOL to spend").fill("0.2");
    await holder.page.getByRole("button", { name: "Buy LIGHT" }).click();
    await ok(holder.page, "Bought LIGHT.");
    step("holder compró 0.2 SOL");
    await team.page.getByLabel("SOL to spend").fill("0.5");
    await team.page.getByRole("button", { name: "Buy LIGHT" }).click();
    await ok(team.page, "Bought LIGHT.");
    await team.page.getByRole("button", { name: "Move the raise into the treasury" }).click();
    await ok(team.page, "The treasury is funded.");
    await team.page.getByText("Paying in tranches").first().waitFor();
    step("curva completa y tesorería financiada desde la interfaz");
    await shot(team.page, "tesoreria-financiada");

    // 3. Graduación a DAMM v2, venta de pánico y defensa del piso desde la interfaz
    await team.page.getByRole("button", { name: "Graduate the pool to Meteora DAMM v2" }).click();
    await ok(team.page, "The token now trades on DAMM v2.");
    await team.page.getByText("Price floor.").waitFor({ timeout: 30_000 });
    await panicSell(rpc.url, team.kp, raiseUrl.split("/").pop()!);
    await team.page.reload();
    await team.page.getByRole("button", { name: /Buy back below backing/ }).click();
    await ok(team.page, "Floor defended");
    await team.page.getByText(/tokens burned so far/).waitFor({ timeout: 30_000 });
    step("graduado a DAMM v2; tras una venta de pánico la tesorería recompró bajo el respaldo y quemó");
    await shot(team.page, "piso-defendido");

    // 4. El equipo pide el tramo 1 con evidencia; el holder la ve y objeta
    const evidenceUrl = "https://github.com/lighthouse/app/releases/tag/v0.1";
    await team.page.getByLabel("Link to the delivered work").fill(evidenceUrl);
    await team.page.getByLabel(/What you shipped/).fill("Beta live with 1,200 users");
    await team.page.getByRole("button", { name: /Request tranche 1/ }).click();
    await ok(team.page, "Tranche requested.");
    await holder.page.reload();
    await holder.page.getByRole("link", { name: evidenceUrl }).waitFor({ timeout: 30_000 });
    await holder.page.getByRole("button", { name: /Object with my/ }).click();
    await ok(holder.page, "Objection recorded.");
    step("tramo 1 pedido con evidencia (enlace + sha256 en cadena) y objetado por el holder");
    await shot(holder.page, "objecion");

    // 5. Pasa la ventana: se liquida
    rpc.svm && (await fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "owncurve_warp", params: [61] }) }));
    await team.page.reload();
    await team.page.getByRole("button", { name: "Settle tranche 1" }).click();
    await ok(team.page, "Tranche settled.");
    await team.page.getByText("Holders redeeming").first().waitFor();
    step("ventana cerrada: el raise pasó a liquidación");
    await shot(team.page, "liquidacion");

    // 6. El holder desbloquea y redime
    await holder.page.reload();
    await holder.page.getByRole("button", { name: "Unlock my voted tokens" }).click();
    await ok(holder.page, "Your tokens are back");
    await holder.page.getByRole("button", { name: /Redeem my tokens for/ }).click();
    await ok(holder.page, "Redeemed.");
    step("el holder redimió sus tokens por SOL");
    await shot(holder.page, "redimido");

    // 6b. Un raise en otra moneda: tUSD (como USDC), con su faucet de prueba
    await team.page.goto(appUrl + "#/new");
    await team.page.getByLabel("Name").fill("Harbor Coop");
    await team.page.getByLabel("Symbol").fill("hbr");
    await team.page.getByLabel("Currency to raise in").selectOption({ label: "tUSD · test USD stablecoin" });
    await team.page.getByLabel("tUSD the curve raises before graduating").fill("100");
    await team.page.getByRole("button", { name: "Launch raise" }).click();
    await team.page.getByRole("heading", { name: /Harbor Coop/ }).waitFor({ timeout: 30_000 });
    await team.page.getByText("of 100.000 tUSD raised on the curve").waitFor();
    await team.page.getByRole("button", { name: /Get 1,000 tUSD/ }).click();
    await ok(team.page, "1,000 tUSD added");
    await team.page.getByLabel("tUSD to spend").fill("120");
    await team.page.getByRole("button", { name: "Buy HBR" }).click();
    await ok(team.page, "Bought HBR.");
    await team.page.getByRole("button", { name: "Move the raise into the treasury" }).click();
    await ok(team.page, "The treasury is funded.");
    await team.page.getByText("80.000 tUSD").first().waitFor();
    step("raise en tUSD: faucet de prueba, compra, tesorería financiada en tUSD");
    await shot(team.page, "raise-tusd");

    // 6. La lista de inicio refleja el estado, aunque haya un raise de una versión vieja
    //    del programa (como el de la F1 en devnet, 8 bytes más corto).
    const { Keypair, PublicKey } = await import("@solana/web3.js");
    const idl = JSON.parse(fs.readFileSync("target/idl/owncurve.json", "utf8"));
    const disc = Buffer.from(idl.accounts.find((a: any) => a.name === "Raise").discriminator);
    const legacy = Keypair.generate().publicKey;
    rpc.svm.setAccount(legacy, { lamports: 10_000_000, data: Buffer.concat([disc, Buffer.alloc(227)]), owner: new PublicKey(idl.address), executable: false });
    await fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "getAccountInfo", params: [legacy.toBase58()] }) });
    await team.page.goto(appUrl);
    await team.page.getByRole("cell", { name: /Lighthouse Labs/ }).waitFor();
    await team.page.getByText("Holders redeeming").first().waitFor();
    step("la lista de raises muestra el raise en liquidación");
    await shot(team.page, "inicio-con-raise");

    // Vista móvil
    await team.page.setViewportSize({ width: 390, height: 844 });
    await team.page.goto(raiseUrl);
    await team.page.getByRole("heading", { name: /Lighthouse Labs/ }).waitFor();
    await shot(team.page, "movil-raise");

    if (errors.length) throw new Error("Errores de JavaScript en la página:\n" + errors.join("\n"));
    console.log("\n  E2E OK: el ciclo completo funciona desde la interfaz.");
  } catch (e) {
    if (SHOTS) {
      for (const [i, pg] of browser.contexts().flatMap((c) => c.pages()).entries())
        await pg.screenshot({ path: `${SHOTS}/fallo-${i}.png`, fullPage: true }).catch(() => {});
    }
    throw e;
  } finally {
    await browser.close();
    await vite.close();
    rpc.server.close();
  }
}

/** Venta de pánico directa contra el RPC (no hay botón de vender en la app). */
async function panicSell(rpcUrl: string, team: import("@solana/web3.js").Keypair, config: string) {
  const { Connection, PublicKey, Transaction } = await import("@solana/web3.js");
  const { loadIdl } = await import("../../scripts/lib/net");
  const { OwnCurve, Raise } = await import("../../scripts/lib/owncurve");
  const conn = new Connection(rpcUrl, "confirmed");
  const net: any = {
    cluster: "local",
    conn,
    payer: team,
    explorer: (s: string) => s,
    advanceTime: async () => {},
    fund: async () => {},
    send: async (_l: string, ixs: any[], signers: any[]) => {
      const tx = new Transaction().add(...ixs);
      tx.feePayer = team.publicKey;
      tx.recentBlockhash = (await conn.getLatestBlockhash()).blockhash;
      tx.sign(team, ...signers.filter((k) => !k.publicKey.equals(team.publicKey)));
      return conn.sendRawTransaction(tx.serialize());
    },
  };
  const oc = new OwnCurve(net, loadIdl());
  const raise = await (oc.program.account as any).raise.fetch(
    PublicKey.findProgramAddressSync([Buffer.from("raise"), new PublicKey(config).toBuffer()], oc.programId)[0],
  );
  const r = new Raise(oc, new PublicKey(config), new PublicKey(raise.baseMint));
  const mine = await oc.tokenBalance(r.baseAta(team.publicKey));
  await oc.dammSell(r, mine.muln(6).divn(10));
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`\n  ✘ ${e.message ?? e}`);
    process.exit(1);
  });
