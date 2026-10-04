// F2 · Tests de integración de OwnCurve contra los binarios reales de Meteora (DBC + DAMM v2)
// en LiteSVM. Cada test arranca un validador limpio.
//
// Ejecutar:  CLUSTER=local npx tsx --test tests/owncurve.test.ts
import { BN } from "@anchor-lang/core";
import { SwapMode } from "@meteora-ag/dynamic-bonding-curve-sdk";
import { Keypair, LAMPORTS_PER_SOL } from "@solana/web3.js";
import assert from "node:assert/strict";
import { test } from "node:test";
import { loadIdl, makeNet } from "../scripts/lib/net";
import { DEFAULT_PARAMS, OwnCurve, Raise, RaiseParams, evidence, sha256, stateName } from "../scripts/lib/owncurve";

process.env.CLUSTER = "local";

// ------------------------------------------------------------------ utilidades
async function setup(params: Partial<RaiseParams> = {}) {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  return { net, oc, p: { ...DEFAULT_PARAMS, ...params } };
}

/** Raise lanzado y validado (estado "bonding"). */
async function bondingRaise(params: Partial<RaiseParams> = {}) {
  const s = await setup(params);
  const { configKp } = await s.oc.createRaise(s.p);
  const { raise: r } = await s.oc.launchPool(configKp.publicKey);
  return { ...s, r };
}

/** Raise con la curva completa y el migration fee ya en la tesorería (estado "funded"). */
async function fundedRaise(params: Partial<RaiseParams> = {}) {
  const s = await bondingRaise(params);
  await s.oc.buyToComplete(s.r);
  await s.oc.harvest(s.r);
  return s;
}

async function expectError(p: Promise<unknown>, name: string) {
  try {
    await p;
  } catch (e: any) {
    const text = `${e.message}\n${(e.logs ?? []).join("\n")}`;
    assert.match(text, new RegExp(name), `se esperaba ${name}, llegó:\n${text.slice(-600)}`);
    return;
  }
  assert.fail(`se esperaba el error ${name} y la transacción pasó`);
}

const raiseOf = (r: Raise) => r.fetch();
const n = (v: any) => new BN(v.toString());

/** Tokens con derecho sobre la tesorería, igual que el programa: suministro − tokens de la tesorería. */
async function circulating(oc: OwnCurve, r: Raise) {
  return (await oc.mintSupply(r.baseMint)).sub(await oc.tokenBalance(r.treasuryBase));
}

// ------------------------------------------------------------------ flujo feliz
test("2.4 flujo feliz: la tesorería se financia y los 3 tramos se liberan al equipo (menos la reserva del piso)", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const fundedAll = n((await raiseOf(r)).fundedAmount);
  assert.ok(fundedAll.eq(new BN(p.threshold * LAMPORTS_PER_SOL).muln(p.treasuryPct).divn(100)), "80% del umbral");
  const reserve = fundedAll.muln(p.floorReserveBps).divn(10_000);
  const funded = fundedAll.sub(reserve); // lo que el equipo puede cobrar en tramos

  const teamQuote = r.quoteAta(net.payer.publicKey);
  let paid = new BN(0);
  for (let i = 0; i < p.tranchesBps.length; i++) {
    await oc.propose(r);
    await net.advanceTime(p.challengeSecs + 1);
    const before = await oc.tokenBalance(teamQuote);
    await oc.finalize(r);
    const got = (await oc.tokenBalance(teamQuote)).sub(before);
    const isLast = i === p.tranchesBps.length - 1;
    const expected = isLast ? funded.sub(paid) : funded.muln(p.tranchesBps[i]).divn(10_000);
    assert.ok(got.eq(expected), `tramo ${i + 1}: recibido ${got} esperado ${expected}`);
    paid = paid.add(got);
  }
  const raise = await raiseOf(r);
  assert.equal(stateName(raise.state), "completed");
  assert.ok(n(raise.releasedAmount).eq(funded), "todo lo cobrable fue liberado, ni un lamport más");
  assert.ok((await oc.tokenBalance(r.treasuryQuote)).gte(reserve), "la reserva del piso sigue en la tesorería");
});

// ------------------------------------------------------------------ hitos con evidencia
test("2.7 cada tramo se pide con evidencia: el enlace y su hash quedan en cadena", async () => {
  const { oc, r } = await fundedRaise();
  const ev = await evidence("https://github.com/acme/app/releases/tag/v0.1", "commit 4f2a9c1: beta shipped");
  await oc.propose(r, undefined, ev);
  const raise = await raiseOf(r);
  assert.equal(raise.proposalEvidenceUri, ev.uri);
  assert.deepEqual(Array.from(raise.milestones[0].evidenceHash), await sha256("commit 4f2a9c1: beta shipped"));
});

test("2.7 propose_release sin evidencia falla", async () => {
  const { oc, r } = await fundedRaise();
  await expectError(oc.propose(r, undefined, { uri: "  ", hash: new Array(32).fill(0) }), "InvalidEvidence");
  await expectError(oc.propose(r, undefined, { uri: "https://x.io/" + "a".repeat(200), hash: new Array(32).fill(0) }), "InvalidEvidence");
});

// ------------------------------------------------------------------ piso de precio
/** Raise graduado en DAMM v2 cuyo precio de mercado cae por debajo del respaldo de la tesorería. */
async function crashedRaise() {
  const s = await fundedRaise();
  await s.oc.migrate(s.r);
  const mine = await s.oc.tokenBalance(s.r.baseAta(s.net.payer.publicKey));
  await s.oc.dammSell(s.r, mine.muln(6).divn(10)); // venta de pánico: 60% de lo que tiene el equipo
  return s;
}

test("2.8 defend_floor: con el precio por debajo del respaldo, la tesorería recompra y quema", async () => {
  const { oc, r } = await crashedRaise();
  const st = await oc.dammState(r);
  const before = await oc.backing(r);
  assert.ok(st!.price < before.perUnit, `precio ${st!.price} < respaldo ${before.perUnit}`);
  const amount = await oc.suggestDefend(r);
  assert.ok(amount.gtn(0), "hay algo que defender");
  const supply = await oc.mintSupply(r.baseMint);
  await oc.defendFloor(r, amount);
  const raise = await raiseOf(r);
  const burned = n(raise.tokensBurned);
  assert.ok(n(raise.floorSpent).eq(amount), "floor_spent registra lo gastado");
  assert.ok(burned.gtn(0) && (await oc.mintSupply(r.baseMint)).eq(supply.sub(burned)), "lo recomprado se quema");
  const after = await oc.backing(r);
  assert.ok(after.perUnit > before.perUnit, `el respaldo por token sube: ${before.perUnit} → ${after.perUnit}`);
  assert.ok((await oc.dammState(r))!.price > st!.price, "el precio de mercado sube");
});

test("2.8 defend_floor no recompra por encima del respaldo", async () => {
  const { oc, r } = await fundedRaise();
  await oc.migrate(r);
  const st = await oc.dammState(r);
  const b = await oc.backing(r);
  if (st!.price >= b.perUnit) {
    await expectError(oc.defendFloor(r, new BN(1_000_000)), "Slippage|NothingToDefend|0x");
  } else {
    // si el precio de graduación ya estuviera por debajo, una compra grande lo cruzaría
    await expectError(oc.defendFloor(r, await oc.floorBudget(r)), "Slippage|NothingToDefend|0x");
  }
});

test("2.8 defend_floor no puede gastar más que su presupuesto (reserva + comisiones)", async () => {
  const { oc, r } = await crashedRaise();
  const budget = await oc.floorBudget(r);
  await expectError(oc.defendFloor(r, budget.addn(1)), "FloorBudgetExceeded");
});

test("2.8 init_raise limita la reserva del piso a ≤ 50%", async () => {
  const s = await setup({ floorReserveBps: 5001 });
  await expectError(s.oc.createRaise(s.p), "InvalidGovernance");
});

test("2.1 comisiones de trading de la curva van a la tesorería", async () => {
  const { oc, r } = await fundedRaise();
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.collectTradingFees(r);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  const raise = await raiseOf(r);
  assert.ok(delta.gtn(0), "la tesorería recibió comisiones");
  assert.ok(n(raise.feesCollected).eq(delta), "fees_collected registra lo cobrado");
});

test("2.1 excedente: la curva no deja pasarse del umbral; collect_surplus cobra lo que haya, una sola vez", async () => {
  const { oc, r } = await bondingRaise();
  const c0 = await oc.curve(r);
  await oc.buy(r, c0.threshold.muln(9).divn(10)); // ~90% de la curva
  const c1 = await oc.curve(r);
  // Una compra exacta que rebasaría el umbral se rechaza: el precio no puede pasar el de graduación.
  await expectError(
    oc.buy(r, c1.threshold.sub(c1.reserve).add(c0.threshold.divn(20)), undefined, SwapMode.ExactIn),
    "Insufficient Liquidity|InsufficientLiquidity",
  );
  await oc.buyToComplete(r);
  await oc.harvest(r);
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.collectSurplus(r);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  assert.ok(delta.gten(0));
  assert.ok(n((await raiseOf(r)).feesCollected).eq(delta), "fees_collected registra el excedente (0 con esta curva)");
  await expectError(oc.collectSurplus(r), "SurplusHasBeenWithdraw");
});

test("2.1 tras migrar a DAMM v2, la tesorería cobra las comisiones de su posición de LP", async () => {
  const { oc, r } = await fundedRaise();
  const { nftMints } = await oc.migrate(r);
  const pos = await oc.treasuryPosition(r, nftMints);
  await oc.dammBuy(r, new BN(0.2 * LAMPORTS_PER_SOL));
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.claimLpFees(r, pos);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  assert.ok(delta.gtn(0), "comisiones de LP en SOL para la tesorería");
  assert.ok(n((await raiseOf(r)).feesCollected).eq(delta));
});

// ------------------------------------------------------------------ rechazo y liquidación
test("2.5 rechazo con quórum → liquidación → redención proporcional al NAV", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const voter = Keypair.generate();
  await net.fund(voter.publicKey, LAMPORTS_PER_SOL);
  const circ = await circulating(oc, r);
  const stake = circ.muln(p.quorumBps + 500).divn(10_000); // quórum + 5%
  await oc.transferBase(r, net.payer, voter.publicKey, stake);

  await oc.propose(r);
  const nonce = (await raiseOf(r)).proposalNonce;
  await oc.reject(r, voter, stake);
  assert.ok((await oc.tokenBalance(r.baseAta(voter.publicKey))).isZero(), "tokens bloqueados en escrow");
  await net.advanceTime(p.challengeSecs + 1);
  await oc.finalize(r);
  assert.equal(stateName((await raiseOf(r)).state), "liquidating");
  assert.ok((await oc.tokenBalance(r.quoteAta(net.payer.publicKey))).isZero(), "el equipo no cobró nada");

  await oc.withdrawVote(r, voter, nonce);
  assert.ok((await oc.tokenBalance(r.baseAta(voter.publicKey))).eq(stake), "votos devueltos");

  const tq = await oc.tokenBalance(r.treasuryQuote);
  const c2 = await circulating(oc, r);
  const expected = stake.mul(tq).div(c2);
  const supplyBefore = await oc.mintSupply(r.baseMint);
  await oc.redeem(r, voter, stake);
  assert.ok((await oc.tokenBalance(r.quoteAta(voter.publicKey))).eq(expected), "pago = tokens × NAV / circulante");
  assert.ok((await oc.mintSupply(r.baseMint)).eq(supplyBefore.sub(stake)), "los tokens se queman");
});

test("2.5 un rechazo por debajo del quórum no bloquea el tramo", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const voter = Keypair.generate();
  await net.fund(voter.publicKey, LAMPORTS_PER_SOL);
  const stake = (await circulating(oc, r)).muln(p.quorumBps - 200).divn(10_000);
  await oc.transferBase(r, net.payer, voter.publicKey, stake);
  await oc.propose(r);
  await oc.reject(r, voter, stake);
  await net.advanceTime(p.challengeSecs + 1);
  await oc.finalize(r);
  const raise = await raiseOf(r);
  assert.equal(stateName(raise.state), "funded");
  assert.ok(n(raise.releasedAmount).gtn(0), "el tramo 1 se liberó");
});

// ------------------------------------------------------------------ seguridad
test("2.6 bind_pool rechaza una config DBC cuyo fee_claimer no es la tesorería", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, feeClaimer: s.net.payer.publicKey });
  await expectError(s.oc.launchPool(configKp.publicKey), "FeeClaimerNotTreasury");
});

test("2.6 bind_pool rechaza una config que comparte el migration fee con el creador", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, creatorMigrationFeePct: 10 });
  await expectError(s.oc.launchPool(configKp.publicKey), "CreatorMigrationFeeNotZero");
});

test("2.6 bind_pool rechaza una config que deja LP desbloqueado al creador (rug de liquidez)", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, creatorUnlockedLpPct: 20 });
  await expectError(s.oc.launchPool(configKp.publicKey), "CreatorLpNotLocked");
});

test("2.6 init_raise impone límites de gobernanza: ventana ≥ 60 s, quórum ≤ 30%, tesorería ≥ 50%", async () => {
  const s = await setup();
  await expectError(s.oc.createRaise({ ...s.p, challengeSecs: 5 }), "InvalidGovernance");
  await expectError(s.oc.createRaise({ ...s.p, quorumBps: 5000 }), "InvalidGovernance");
  await expectError(s.oc.createRaise({ ...s.p, treasuryPct: 40 }), "InvalidGovernance");
});

test("2.6 nadie fuera del programa puede retirar el migration fee de DBC", async () => {
  const { oc, net, r } = await bondingRaise();
  await oc.buyToComplete(r);
  const attacker = Keypair.generate();
  await net.fund(attacker.publicKey, LAMPORTS_PER_SOL);
  const tx = await oc.dbc.partner.partnerWithdrawMigrationFee({ pool: r.pool, sender: attacker.publicKey });
  await expectError(net.send("ataque", tx.instructions, [attacker]), "NotPermitToDoThisAction");
  await oc.harvest(r); // el camino legítimo sigue funcionando
  assert.equal(stateName((await raiseOf(r)).state), "funded");
});

test("2.6 harvest no se puede ejecutar dos veces", async () => {
  const { oc, r } = await fundedRaise();
  await expectError(oc.harvest(r), "InvalidState");
});

test("2.6 harvest antes de completar la curva falla en DBC", async () => {
  const { oc, r } = await bondingRaise();
  await expectError(oc.harvest(r), "NotPermitToDoThisAction");
});

test("2.6 solo el equipo puede proponer un tramo", async () => {
  const { oc, net, r } = await fundedRaise();
  const attacker = Keypair.generate();
  await net.fund(attacker.publicKey, LAMPORTS_PER_SOL);
  await expectError(oc.propose(r, attacker), "NotTeam");
});

test("2.6 ventanas: no se finaliza antes de tiempo ni se vota fuera de plazo", async () => {
  const { oc, net, r, p } = await fundedRaise();
  await oc.propose(r);
  await expectError(oc.finalize(r), "ChallengeWindowOpen");
  await net.advanceTime(p.challengeSecs + 1);
  await expectError(oc.reject(r, net.payer, new BN(1_000_000)), "ChallengeWindowClosed");
});

test("2.6 no se puede redimir si el raise no está en liquidación", async () => {
  const { oc, net, r } = await fundedRaise();
  await expectError(oc.redeem(r, net.payer, new BN(1_000_000)), "InvalidState");
});

test("2.6 init_raise rechaza tramos que no suman 100%", async () => {
  const s = await setup();
  await expectError(s.oc.createRaise({ ...s.p, tranchesBps: [5000, 4000] }), "InvalidMilestones");
});

// ------------------------------------------------------------------ otras monedas (USDC / xStocks)
import { TEST_QUOTES, createTestQuote, mintTestQuoteIxs } from "../scripts/lib/quotes";

for (const spec of TEST_QUOTES) {
  test(`2.9 raise en ${spec.symbol} (${spec.token2022 ? "Token-2022, como las xStocks" : "SPL, como USDC"}): tramos, piso y redención`, async () => {
    const net = await makeNet();
    const oc = new OwnCurve(net, loadIdl());
    const quote = await createTestQuote(net, spec, Keypair.generate(), net.payer.publicKey);
    const fund = (to: Keypair, ui: number) => net.send("emitir", mintTestQuoteIxs(quote, net.payer.publicKey, net.payer.publicKey, to.publicKey, ui), []);
    await fund(net.payer, 10_000);
    const p = { ...DEFAULT_PARAMS, threshold: 100, quote };
    const { configKp } = await oc.createRaise(p);
    const { raise: r } = await oc.launchPool(configKp.publicKey);
    assert.ok(r.quoteMint.equals(quote.mint) && r.quoteProgram.equals(quote.program));
    const loaded = await Raise.load(oc, configKp.publicKey);
    assert.ok(loaded.quoteMint.equals(quote.mint) && loaded.quoteProgram.equals(quote.program), "Raise.load lee la moneda");

    await oc.buyToComplete(r);
    await oc.harvest(r);
    const funded = n((await raiseOf(r)).fundedAmount);
    assert.ok(funded.eq(new BN(100 * 10 ** spec.decimals).muln(p.treasuryPct).divn(100)), `80 ${spec.symbol} en la tesorería`);

    // piso: migrar, venta de pánico, recompra y quema
    await oc.migrate(r);
    const mine = await oc.tokenBalance(r.baseAta(net.payer.publicKey));
    await oc.dammSell(r, mine.muln(6).divn(10));
    const before = await oc.backing(r);
    const amount = await oc.suggestDefend(r);
    assert.ok(amount.gtn(0));
    await oc.defendFloor(r, amount);
    assert.ok((await oc.backing(r)).perUnit > before.perUnit, "el respaldo sube");

    // tramo 1 pagado en la moneda del raise
    const teamQuote = r.quoteAta(net.payer.publicKey);
    const t0 = await oc.tokenBalance(teamQuote);
    await oc.propose(r);
    await net.advanceTime(p.challengeSecs + 1);
    await oc.finalize(r);
    const payable = funded.sub(funded.muln(p.floorReserveBps).divn(10_000));
    assert.ok((await oc.tokenBalance(teamQuote)).sub(t0).eq(payable.muln(p.tranchesBps[0]).divn(10_000)), "tramo 1 en la moneda");

    // tramo 2 rechazado con quórum → redención en la moneda
    const voter = Keypair.generate();
    await net.fund(voter.publicKey, LAMPORTS_PER_SOL);
    const stake = (await circulating(oc, r)).muln(p.quorumBps + 500).divn(10_000);
    await oc.transferBase(r, net.payer, voter.publicKey, stake);
    await oc.propose(r);
    const nonce = (await raiseOf(r)).proposalNonce;
    await oc.reject(r, voter, stake);
    await net.advanceTime(p.challengeSecs + 1);
    await oc.finalize(r);
    assert.equal(stateName((await raiseOf(r)).state), "liquidating");
    await oc.withdrawVote(r, voter, nonce);
    await oc.redeem(r, voter, stake);
    assert.ok((await oc.tokenBalance(r.quoteAta(voter.publicKey))).gtn(0), `el holder cobra en ${spec.symbol}`);
  });
}
