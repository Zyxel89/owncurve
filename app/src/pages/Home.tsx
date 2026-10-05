import { useMemo } from "react";
import featuredCfg from "../featured.json";
import study from "../study.json";
import { RaiseRow, listRaises, readOnlyClient, usePoll } from "../lib/data";

const fmt = (v: number) => v.toLocaleString("en-US", { minimumFractionDigits: 3, maximumFractionDigits: 3 });
import { useAccount } from "../lib/wallet";

const STATE_LABEL: Record<string, string> = {
  pending: "Not launched",
  bonding: "On the curve",
  funded: "Paying in tranches",
  liquidating: "Holders redeeming",
  completed: "Fully paid",
};

export function Home() {
  const { conn } = useAccount();
  const oc = useMemo(() => readOnlyClient(conn), [conn]);
  const { data: rows, error } = usePoll(() => listRaises(oc), [oc], 10_000);
  const featured = (featuredCfg.featured as { config: string; label: string; blurb: string }[])
    .map((f) => ({ ...f, row: rows?.find((r) => r.config === f.config) }))
    .filter((f): f is typeof f & { row: RaiseRow } => !!f.row);
  const featuredSet = new Set(featured.map((f) => f.config));
  const testTeams = new Set(featuredCfg.testTeams as string[]);
  const rest = (rows ?? []).filter((r) => !featuredSet.has(r.config));
  const earlier = rest.filter((r) => testTeams.has(r.team));
  const others = rest.filter((r) => !testTeams.has(r.team));

  return (
    <main className="page">
      <section className="lede">
        <h1>Token launches where the money waits for the work.</h1>
        <p>
          OwnCurve sends what a Meteora bonding curve raises into an on-chain treasury. The team is paid one milestone
          at a time, and holders can stop a payment and take their share back.
        </p>
        <div className="lede-buttons">
          <a className="btn primary" href="#/new">
            Launch a raise
          </a>
          <a className="btn" href="#/scan">
            Rug-check a Meteora token
          </a>
        </div>
      </section>

      <section className="stats" aria-label="Meteora DBC on mainnet today">
        <div>
          <strong>{study.unlockedLpPct}%</strong>
          <span>
            of {(study.launches / 1e6).toFixed(2)}M Meteora DBC launches let someone withdraw the graduated liquidity.
            OwnCurve: <b>0%</b>.
          </span>
        </div>
        <div>
          <strong>{study.allFourPct}%</strong>
          <span>meet the four basic holder guarantees. Every OwnCurve raise meets them, checked on-chain.</span>
        </div>
        <div>
          <strong>{study.feeToWalletPct}%</strong>
          <span>
            pay a graduation fee straight to a wallet. OwnCurve sends it to a treasury that pays per milestone.{" "}
            <a href="https://github.com/Zyxel89/owncurve/blob/main/docs/MAINNET-STUDY.md" target="_blank" rel="noreferrer">
              Mainnet study
            </a>
          </span>
        </div>
      </section>

      <section aria-labelledby="ledger-title" className="ledger">
        <h2 id="ledger-title">Raises</h2>
        {error && <p className="error">Could not read raises from the network: {error}</p>}
        {!rows && !error && <p className="muted">Reading raises from the chain…</p>}
        {rows && rows.length === 0 && (
          <p className="muted">
            No raises yet. <a href="#/new">Launch the first one</a>.
          </p>
        )}
        {rows && rows.length > 0 && (
          <>
            {featured.length > 0 && (
              <div className="featured">
                {featured.map(({ row, label, blurb }) => (
                  <a key={row.config} className="feature" href={`#/raise/${row.config}`}>
                    <span className="kicker">{label}</span>
                    <strong>
                      {row.name} <span className="muted">{row.symbol}</span>
                    </strong>
                    <span className="blurb">{blurb}</span>
                    <span className="meta">
                      <span className={`stage ${row.state}`}>{STATE_LABEL[row.state] ?? row.state}</span>
                      <span>
                        {fmt(row.funded)} {row.quote} raised · {fmt(row.treasury)} {row.quote} in treasury
                      </span>
                    </span>
                  </a>
                ))}
              </div>
            )}
            {others.length > 0 ? (
              <RaiseTable rows={others} />
            ) : (
              <p className="muted">
                No other raises yet. <a href="#/new">Launch one</a> with a test wallet.
              </p>
            )}
            {earlier.length > 0 && (
              <details className="earlier">
                <summary>Earlier test raises by the OwnCurve team ({earlier.length})</summary>
                <RaiseTable rows={earlier} />
              </details>
            )}
          </>
        )}
      </section>
    </main>
  );
}

function RaiseTable({ rows }: { rows: RaiseRow[] }) {
  return (
    <table>
      <thead>
        <tr>
          <th scope="col">Token</th>
          <th scope="col">Stage</th>
          <th scope="col" className="num">
            Raised into treasury
          </th>
          <th scope="col" className="num">
            Treasury now
          </th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <tr key={r.config} onClick={() => (location.hash = `#/raise/${r.config}`)}>
            <td>
              <a href={`#/raise/${r.config}`}>
                <strong>{r.name}</strong> <span className="muted">{r.symbol}</span>
              </a>
            </td>
            <td>
              <span className={`stage ${r.state}`}>{STATE_LABEL[r.state] ?? r.state}</span>
              {r.progress !== null && (
                <span className="mini-track" aria-label={`${Math.round(r.progress * 100)}% of the curve`}>
                  <span style={{ width: `${r.progress * 100}%` }} />
                </span>
              )}
            </td>
            <td className="num">{r.funded > 0 ? `${fmt(r.funded)} ${r.quote}` : "—"}</td>
            <td className="num">{r.treasury > 0 ? `${fmt(r.treasury)} ${r.quote}` : "—"}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export { STATE_LABEL };
