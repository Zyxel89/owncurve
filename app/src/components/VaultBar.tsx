// El elemento central de la interfaz: la tesorería dibujada como una bóveda dividida en
// tramos. Liberado = tinta llena; propuesto = latón con cuenta atrás; bloqueado = guilloché.
import { BN } from "@anchor-lang/core";
import { stateName } from "../../../scripts/lib/owncurve";
import type { Quote } from "../../../scripts/lib/owncurve";
import { fmtAmt } from "../lib/data";
import { useNow } from "../lib/useNow";

type Props = {
  state: string;
  raise: any;
  curve: { reserve: BN; threshold: BN } | null;
  treasuryPct: number;
  clockSkew?: number;
  quote: Quote;
};

export function VaultBar({ state, raise, curve, treasuryPct, clockSkew = 0, quote }: Props) {
  const fmtSol = (v: BN) => fmtAmt(v, quote);
  const now = useNow(clockSkew);

  if (state === "pending" || state === "bonding") {
    const pct = curve ? Math.min(100, (Number(curve.reserve.toString()) / Number(curve.threshold.toString())) * 100) : 0;
    return (
      <figure className="vault" aria-label={`Bonding curve ${pct.toFixed(0)}% filled`}>
        <div className="vault-track curve">
          <div className="vault-fill" style={{ width: `${pct}%` }} />
        </div>
        <figcaption className="vault-caption">
          <span className="big">{curve ? fmtSol(curve.reserve) : "0.000"}</span>
          <span>
            of {curve ? fmtSol(curve.threshold) : "—"} {quote.symbol} raised on the curve. At graduation {treasuryPct}% moves into
            the treasury.
          </span>
        </figcaption>
      </figure>
    );
  }

  // Los tramos reparten lo cobrable; la reserva del piso nunca va al equipo.
  const fundedAll = new BN(raise.fundedAmount.toString());
  const floorBps = Number(raise.floorReserveBps ?? 0);
  const floorAmount = fundedAll.muln(floorBps).divn(10_000);
  const funded = fundedAll.sub(floorAmount);
  const width = (bps: number) => (bps * (10_000 - floorBps)) / 10_000;
  const count = Number(raise.milestoneCount);
  const ms = raise.milestones.slice(0, count) as any[];
  let paidSoFar = new BN(0);
  const segments = ms.map((m, i) => {
    const isLast = i === count - 1;
    const amount = isLast
      ? funded.sub(ms.slice(0, i).reduce((a, x) => a.add(funded.muln(x.trancheBps).divn(10_000)), new BN(0)))
      : funded.muln(m.trancheBps).divn(10_000);
    const status = stateName(m.status);
    paidSoFar = status === "released" ? paidSoFar.add(amount) : paidSoFar;
    return { i, bps: m.trancheBps as number, amount, status };
  });
  const endsAt = Number(raise.proposalEndsAt.toString());
  const left = Math.max(0, endsAt - now);

  return (
    <figure className={`vault ${state}`} aria-label="Treasury tranches">
      <div className="vault-track">
        {segments.map((s) => (
          <div
            key={s.i}
            className={`seg ${state === "liquidating" && s.status !== "released" ? "returned" : s.status}`}
            style={{ flexGrow: width(s.bps) }}
          />
        ))}
        {floorBps > 0 && <div className="seg floor" style={{ flexGrow: floorBps }} />}
      </div>
      <ol className="seg-labels">
        {segments.map((s) => (
          <li key={s.i} style={{ flexGrow: width(s.bps) }}>
            <span className="amt">{fmtSol(s.amount)} {quote.symbol}</span>
            <span className="what">
              Tranche {s.i + 1}, {s.bps / 100}%:{" "}
              {state === "liquidating" && s.status !== "released"
                ? "back to holders"
                : s.status === "released"
                  ? "paid to team"
                  : s.status === "proposed"
                    ? left > 0
                      ? `objections close in ${fmtLeft(left)}`
                      : "ready to settle"
                    : "locked"}
            </span>
          </li>
        ))}
        {floorBps > 0 && (
          <li className="floor" style={{ flexGrow: floorBps }}>
            <span className="amt">{fmtSol(floorAmount)} {quote.symbol}</span>
            <span className="what">Price floor reserve: never paid to the team</span>
          </li>
        )}
      </ol>
    </figure>
  );
}

export function fmtLeft(secs: number) {
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return m > 0 ? `${m} min ${s.toString().padStart(2, "0")} s` : `${s} s`;
}
