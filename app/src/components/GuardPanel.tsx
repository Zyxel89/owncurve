// Protecciones que funcionan solas: equipo fantasma y cláusula Bedrock en cadena.
import type { RaiseDetail } from "../lib/data";
import { fmtAmt } from "../lib/data";
import { BASE_DECIMALS } from "../../../scripts/lib/owncurve";
import { fmtLeft } from "./VaultBar";
import { useNow } from "../lib/useNow";

export function GuardPanel({ d }: { d: RaiseDetail }) {
  const g = d.guard;
  const now = useNow(d.clockSkew);
  if (!g && !d.budget) return null;
  const b = d.budget;
  const perM = (unitsPerAtom: number) => (unitsPerAtom * 10 ** BASE_DECIMALS * 1_000_000) / 10 ** d.quote.decimals;
  const fmt = (v: number) => (v >= 0.01 ? v.toFixed(4) : v.toPrecision(3));
  const sym = d.quote.symbol;
  const left = g?.abandonableAt ? g.abandonableAt - now : null;
  const pendingTranche = !!d.proposal;
  return (
    <div className="guard-panel" aria-label="Holder protections that run on their own">
      <h3>Protections that run on their own</h3>
      {b && (
        <div className="guard-row">
          <span className="guard-name">Operating budget</span>
          <p>
            The team may draw {fmtAmt(b.monthly, d.quote)} {d.quote.symbol} every {fmtLeft(b.periodSecs)} between milestones, as an
            advance on its next tranche (never more than that tranche). Drawn so far: {fmtAmt(b.drawnTotal, d.quote)}{" "}
            {d.quote.symbol}
            {b.advancedUnsettled.gtn(0) ? `, of which ${fmtAmt(b.advancedUnsettled, d.quote)} will be deducted from tranche ${b.nextTranche + 1}` : ""}.
            It stops the moment holders reject a tranche or the team goes silent.
          </p>
        </div>
      )}
      {g && (<>
      <div className="guard-row">
        <span className="guard-name">Ghost-team switch</span>
        <p>
          {g.abandoned ? (
            <strong>The team went silent: the treasury was returned to holders.</strong>
          ) : g.armedAt === 0 ? (
            <>Starts when the treasury is funded. Then, if the team goes {fmtLeft(g.inactivitySecs)} without requesting a tranche, anyone can return the treasury to holders.</>
          ) : d.state !== "funded" ? (
            <>Not needed in this stage.</>
          ) : pendingTranche ? (
            <>Paused: a tranche request is open. The clock restarts when its window closes.</>
          ) : left !== null && left > 0 ? (
            <>
              If the team requests nothing in <strong>{fmtLeft(left)}</strong>, anyone can return the treasury to holders.
            </>
          ) : (
            <strong>The team has been silent too long: anyone can return the treasury to holders now.</strong>
          )}
        </p>
      </div>
      <div className="guard-row">
        <span className="guard-name">Bedrock clause, on-chain</span>
        <p>
          {g.acquired ? (
            <strong>
              Taken over by {g.acquirer.toBase58().slice(0, 4)}…{g.acquirer.toBase58().slice(-4)}: every holder redeems at ≥ {fmt(perM(g.buyoutPrice))}{" "}
              {sym} per 1,000,000 tokens.
            </strong>
          ) : (
            <>
              Nobody can take this project over without paying every holder the {Math.round(g.twapWindowSecs / 60) || 1}-min TWAP{" "}
              <strong>+{g.buyoutPremiumBps / 100}%</strong>.{" "}
              {g.twapReady ? (
                <>
                  TWAP {fmt(perM(g.twap))} {sym} → buyout {fmt(perM(g.buyoutPrice))} {sym} per 1,000,000 tokens; a takeover deposits{" "}
                  {fmtAmt(g.buyoutDeposit, d.quote)} {sym}.
                </>
              ) : (
                <>
                  TWAP: {g.observationsInWindow} price observations recorded from Meteora DAMM v2 (needs 3 spanning half the window).
                </>
              )}
            </>
          )}
        </p>
      </div>
      </>)}
    </div>
  );
}
