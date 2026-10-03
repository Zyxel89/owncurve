import { useMemo } from "react";
import { fmtSol, listRaises, readOnlyClient, usePoll } from "../lib/data";
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

  return (
    <main className="page">
      <section className="lede">
        <h1>Token launches where the money waits for the work.</h1>
        <p>
          OwnCurve sends what a Meteora bonding curve raises into an on-chain treasury. The team is paid one milestone
          at a time, and holders can stop a payment and take their share back.
        </p>
        <a className="btn primary" href="#/new">
          Launch a raise
        </a>
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
                  <td className="num">{r.fundedSol > 0 ? `${fmtSol(r.fundedSol * 1e9)} SOL` : "—"}</td>
                  <td className="num">{r.treasurySol > 0 ? `${fmtSol(r.treasurySol * 1e9)} SOL` : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </main>
  );
}

export { STATE_LABEL };
