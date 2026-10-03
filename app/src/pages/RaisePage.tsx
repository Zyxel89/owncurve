import { BN } from "@anchor-lang/core";
import { LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import { useMemo, useState } from "react";
import { OwnCurve, evidence, stateName } from "../../../scripts/lib/owncurve";
import { Guarantees } from "../components/Guarantees";
import { VaultBar, fmtLeft } from "../components/VaultBar";
import { makeBrowserNet } from "../lib/browserNet";
import { IDL, RaiseDetail, fmtSol, fmtTokens, loadRaise, readOnlyClient, usePoll } from "../lib/data";
import { useAction } from "../lib/useAction";
import { useNow } from "../lib/useNow";
import { short, useAccount } from "../lib/wallet";
import { STATE_LABEL } from "./Home";

export function RaisePage({ config }: { config: string }) {
  const acc = useAccount();
  const configKey = useMemo(() => {
    try {
      return new PublicKey(config);
    } catch {
      return null;
    }
  }, [config]);
  const reader = useMemo(() => readOnlyClient(acc.conn), [acc.conn]);
  const me = acc.signer?.publicKey ?? null;
  const { data: d, error, reload } = usePoll(
    () => (configKey ? loadRaise(reader, configKey, me) : Promise.reject(new Error("Invalid address"))),
    [reader, configKey?.toBase58(), me?.toBase58()],
    6000,
  );

  if (!configKey) return <main className="page"><p className="error">That is not a valid raise address.</p></main>;
  if (error && !d) return <main className="page"><p className="error">Could not load this raise: {error}</p></main>;
  if (!d) return <main className="page"><p className="muted">Reading the raise from the chain…</p></main>;

  const treasuryPct = d.cfg?.migrationFeePercentage ?? d.raise.minTreasuryPct;
  return (
    <main className="page raise">
      <div className="raise-head">
        <div>
          <p className="crumb">
            <a href="#/">Raises</a>
          </p>
          <h1>
            {d.name} <span className="sym">{d.symbol}</span>
          </h1>
        </div>
        <span className={`stage big ${d.state}`}>{STATE_LABEL[d.state] ?? d.state}</span>
      </div>

      <VaultBar state={d.state} raise={d.raise} curve={d.curve} treasuryPct={treasuryPct} clockSkew={d.clockSkew} />

      {d.state === "bonding" || d.state === "pending" ? (
        <dl className="figures">
          <div>
            <dt>Graduates at</dt>
            <dd>{d.curve ? fmtSol(d.curve.threshold) : "—"} SOL</dd>
          </div>
          <div>
            <dt>Goes to the treasury</dt>
            <dd>{d.curve ? fmtSol(d.curve.threshold.muln(treasuryPct).divn(100)) : "—"} SOL</dd>
          </div>
          <div>
            <dt>Kept as a price floor</dt>
            <dd>{d.raise.floorReserveBps / 100}% of the treasury</dd>
          </div>
          <div>
            <dt>Paid to the team in</dt>
            <dd>
              {Number(d.raise.milestoneCount)} tranches of{" "}
              {(d.raise.milestones as any[])
                .slice(0, Number(d.raise.milestoneCount))
                .map((m) => `${m.trancheBps / 100}%`)
                .join(", ")}
            </dd>
          </div>
        </dl>
      ) : (
        <dl className="figures">
          <div>
            <dt>Treasury holds</dt>
            <dd>{fmtSol(d.treasuryQuote)} SOL</dd>
          </div>
          <div>
            <dt>Paid to the team</dt>
            <dd>
              {fmtSol(d.raise.releasedAmount)} of {fmtSol(d.payable)} SOL
            </dd>
          </div>
          <div>
            <dt>Fees earned by the treasury</dt>
            <dd>{fmtSol(d.raise.feesCollected, 4)} SOL</dd>
          </div>
          <div>
            <dt>Treasury backing per 1,000,000 tokens</dt>
            <dd>{d.navPerMillion.toFixed(4)} SOL</dd>
          </div>
        </dl>
      )}

      <div className="columns">
        <Actions d={d} reload={reload} />
        <Guarantees d={d} />
      </div>
    </main>
  );
}

function Actions({ d, reload }: { d: RaiseDetail; reload: () => void }) {
  const acc = useAccount();
  const now = useNow(d.clockSkew);
  const act = useAction(() => {
    reload();
    acc.refreshBalance();
  });
  const [buySol, setBuySol] = useState("0.1");
  const [evUri, setEvUri] = useState("");
  const [evNote, setEvNote] = useState("");
  const evOk = /^https?:\/\/\S+$/.test(evUri.trim()) && evUri.trim().length <= 160;
  const oc = useMemo(() => (acc.signer ? new OwnCurve(makeBrowserNet(acc.conn, acc.signer), IDL) : null), [acc.conn, acc.signer]);

  const me = acc.signer?.publicKey;
  const isTeam = !!me && me.equals(d.team);
  const r = oc ? new (d.r.constructor as any)(oc, d.r.config, d.r.baseMint) : d.r;
  const nonce = Number(d.raise.proposalNonce);
  const lockedVotes = d.user?.votes.filter((v) => v.nonce < nonce) ?? [];
  const activeVote = d.user?.votes.find((v) => v.nonce === nonce);
  const nextMilestone = (d.raise.milestones as any[]).findIndex((m) => stateName(m.status) === "locked");
  const nextAmount =
    nextMilestone < 0
      ? null
      : nextMilestone === Number(d.raise.milestoneCount) - 1
        ? d.payable.sub(new BN(d.raise.releasedAmount.toString()))
        : d.payable.muln(d.raise.milestones[nextMilestone].trancheBps).divn(10_000);
  const windowOpen = d.proposal ? now < d.proposal.endsAt : false;
  const myBase = d.user?.base ?? new BN(0);
  const redeemPreview = d.circulating.isZero() ? 0 : (Number(myBase.toString()) / Number(d.circulating.toString())) * Number(d.treasuryQuote.toString());

  const buttons: JSX.Element[] = [];
  const btn = (key: string, label: string, done: string, fn: () => Promise<string | void>, primary = false) =>
    buttons.push(
      <button key={key} className={`btn ${primary ? "primary" : ""}`} disabled={!!act.busy} onClick={() => act.run(label, done, fn)}>
        {act.busy === label ? "Waiting for the network…" : label}
      </button>,
    );

  if (oc) {
    if (d.state === "bonding" && d.curve && !d.curve.complete) {
      buttons.push(
        <div key="buy" className="buy">
          <label>
            SOL to spend
            <input inputMode="decimal" value={buySol} onChange={(e) => setBuySol(e.target.value)} />
          </label>
          <button
            className="btn primary"
            disabled={!!act.busy || !(Number(buySol) > 0)}
            onClick={() =>
              act.run("Buy on the curve", `Bought ${d.symbol}.`, () =>
                oc.buy(r, new BN(Math.round(Number(buySol) * LAMPORTS_PER_SOL))),
              )
            }
          >
            {act.busy === "Buy on the curve" ? "Waiting for the network…" : `Buy ${d.symbol}`}
          </button>
        </div>,
      );
    }
    if (d.state === "bonding" && d.curve?.complete)
      btn("harvest", "Move the raise into the treasury", "The treasury is funded.", () => oc.harvest(r), true);

    if (d.state === "funded") {
      if (!d.proposal && isTeam && nextMilestone >= 0 && nextAmount) {
        const label = `Request tranche ${nextMilestone + 1} (${fmtSol(nextAmount)} SOL)`;
        buttons.push(
          <div key="propose" className="request">
            <label>
              Link to the delivered work
              <input
                type="url"
                placeholder="https://github.com/you/app/releases/tag/v1.0"
                value={evUri}
                onChange={(e) => setEvUri(e.target.value)}
              />
            </label>
            <label>
              What you shipped (its SHA-256 is stored on-chain)
              <input placeholder="Beta live: 1,200 users, audit report v1" value={evNote} onChange={(e) => setEvNote(e.target.value)} />
            </label>
            <button
              className="btn primary"
              disabled={!!act.busy || !evOk}
              onClick={() =>
                act.run(label, "Tranche requested. Holders can object until the countdown ends.", async () =>
                  oc.propose(r, undefined, await evidence(evUri.trim(), evNote)),
                )
              }
            >
              {act.busy === label ? "Waiting for the network…" : label}
            </button>
          </div>,
        );
      }
      if (d.proposal && windowOpen && myBase.gtn(0))
        btn(
          "reject",
          `Object with my ${fmtTokens(myBase)} tokens`,
          "Objection recorded. Your tokens unlock after the tranche is settled.",
          () => oc.reject(r, oc.net.payer, myBase),
        );
      if (d.proposal && !windowOpen)
        btn("finalize", `Settle tranche ${d.proposal.milestone + 1}`, "Tranche settled.", () => oc.finalize(r), true);
    }
    if (lockedVotes.length > 0)
      btn("withdraw", "Unlock my voted tokens", "Your tokens are back in your wallet.", async () => {
        let sig: string | undefined;
        for (const v of lockedVotes) sig = await oc.withdrawVote(r, oc.net.payer, v.nonce);
        return sig;
      });
    if (d.state === "liquidating" && myBase.gtn(0))
      btn(
        "redeem",
        `Redeem my tokens for ${(redeemPreview / LAMPORTS_PER_SOL).toFixed(4)} SOL`,
        "Redeemed. The SOL is in your wallet as wrapped SOL.",
        () => oc.redeem(r, oc.net.payer, myBase),
        true,
      );
    if (d.market && d.market.suggest.gtn(0))
      btn(
        "defend",
        `Buy back below backing with ${fmtSol(d.market.suggest, 4)} SOL and burn`,
        "Floor defended: the treasury bought tokens under their backing and burned them.",
        () => oc.defendFloor(r, d.market!.suggest),
        true,
      );
    if (["funded", "completed", "liquidating"].includes(d.state)) {
      if (d.curve && !d.curve.migrated)
        btn("migrate", "Graduate the pool to Meteora DAMM v2", "The token now trades on DAMM v2.", async () => (await oc.migrate(r)).sig);
      btn("fees", "Collect curve trading fees", "Fees moved into the treasury.", () => oc.collectTradingFees(r));
    }
  }

  return (
    <section className="actions" aria-labelledby="a-title">
      <h2 id="a-title">What you can do</h2>
      {d.proposal && (
        <div className="proposal">
          <p>
            <strong>Tranche {d.proposal.milestone + 1}</strong> is waiting.{" "}
            {windowOpen ? `Objections close in ${fmtLeft(d.proposal.endsAt - now)}.` : "The objection window has closed."}
          </p>
          {d.proposal.evidenceUri && (
            <p className="evidence">
              Evidence:{" "}
              <a href={d.proposal.evidenceUri} target="_blank" rel="noreferrer">
                {d.proposal.evidenceUri}
              </a>
              <br />
              <code title="SHA-256 committed on-chain with the request">sha256 {d.proposal.evidenceHash.slice(0, 16)}…</code>
            </p>
          )}
          <div className="quorum" aria-label="Objections against quorum">
            <span style={{ width: `${Math.min(100, quorumPct(d.proposal.rejectWeight, d.proposal.quorum))}%` }} />
          </div>
          <p className="fine">
            {fmtTokens(d.proposal.rejectWeight)} tokens object;{" "}
            {d.proposal.rejectWeight.gte(d.proposal.quorum)
              ? "that is enough to stop the payment and open redemptions."
              : `${fmtTokens(d.proposal.quorum)} would stop the payment and open redemptions.`}
          </p>
        </div>
      )}
      {d.market && <FloorPanel d={d} />}
      {!acc.signer && <p className="muted">Connect a wallet or use a test wallet to buy, object or redeem.</p>}
      {acc.signer && (
        <p className="fine">
          You hold {fmtTokens(myBase)} {d.symbol}
          {activeVote ? ` in your wallet and ${fmtTokens(activeVote.amount)} locked in an objection` : ""}
          {lockedVotes.length ? ` and ${fmtTokens(lockedVotes.reduce((a, v) => a.add(v.amount), new BN(0)))} ready to unlock` : ""}.{" "}
          {isTeam ? "You created this raise." : `Team: ${short(d.team)}.`}
        </p>
      )}
      <div className="buttons">{buttons}</div>
      {acc.signer && buttons.length === 0 && <p className="muted">Nothing to do right now for this wallet.</p>}
      {act.error && <p className="error" role="alert">{act.error}</p>}
      {act.done && (
        <p className="ok" role="status">
          {act.done.text}{" "}
          {act.done.link && (
            <a href={act.done.link} target="_blank" rel="noreferrer">
              View transaction
            </a>
          )}
        </p>
      )}
    </section>
  );
}

function FloorPanel({ d }: { d: RaiseDetail }) {
  const m = d.market!;
  const below = m.pricePerMillion < m.backingPerMillion;
  // escala: 0 … 2× el respaldo (el respaldo queda en el centro)
  const scale = Math.max(m.backingPerMillion * 2, m.pricePerMillion * 1.1, 1e-12);
  const pos = (v: number) => `${Math.min(100, (v / scale) * 100)}%`;
  const fmt = (v: number) => (v >= 0.01 ? v.toFixed(4) : v.toPrecision(3));
  return (
    <div className="floor-panel" aria-label="Market price against treasury backing">
      <p>
        <strong>Price floor.</strong> On Meteora DAMM v2, 1,000,000 {d.symbol} trade at <strong>{fmt(m.pricePerMillion)} SOL</strong>;
        the treasury backs them with <strong>{fmt(m.backingPerMillion)} SOL</strong>.
      </p>
      <div className="gauge">
        <span className="backing" style={{ left: pos(m.backingPerMillion) }} title="Treasury backing" />
        <span className={`price ${below ? "below" : ""}`} style={{ left: pos(m.pricePerMillion) }} title="Market price" />
      </div>
      <p className="fine">
        {below
          ? "The token trades below what the treasury holds for it. Anyone can make the treasury buy it back and burn it, which lifts the backing of every remaining token."
          : "The price is above the backing. If it ever drops below, anyone can trigger a buyback that burns the tokens."}{" "}
        Floor budget left: {fmtSol(d.floorBudget, 4)} SOL
        {Number(d.raise.tokensBurned) > 0 ? ` · ${fmtTokens(new BN(d.raise.tokensBurned.toString()))} tokens burned so far` : ""}.
      </p>
    </div>
  );
}

function quorumPct(weight: BN, quorum: BN) {
  return quorum.isZero() ? 0 : (Number(weight.toString()) / Number(quorum.toString())) * 100;
}
