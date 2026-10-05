// Escáner: pega cualquier token o pool de Meteora DBC (mainnet o devnet) y mira qué garantías
// tienen sus holders, con las mismas reglas que OwnCurve impone en cadena.
import { Connection } from "@solana/web3.js";
import { FormEvent, useState } from "react";
import featuredCfg from "../featured.json";
import { PROGRAM_ID } from "../lib/data";
import { RPC_URL } from "../lib/browserNet";
import { ScanResult, scanLaunch } from "../../../scripts/lib/scan";

const NETS = {
  mainnet: { label: "Solana mainnet", rpc: "https://api.mainnet-beta.solana.com", explorer: (a: string) => `https://solscan.io/account/${a}` },
  devnet: { label: "Solana devnet", rpc: RPC_URL, explorer: (a: string) => `https://explorer.solana.com/address/${a}?cluster=devnet` },
} as const;
type NetName = keyof typeof NETS;

const initial = () => {
  const q = new URLSearchParams(location.hash.split("?")[1] ?? "");
  return { addr: q.get("a") ?? "", net: (q.get("net") as NetName) ?? "mainnet" };
};

export function Scan() {
  const init = initial();
  const [net, setNet] = useState<NetName>(init.net in NETS ? init.net : "mainnet");
  const [rpc, setRpc] = useState<string>(NETS[init.net in NETS ? init.net : "mainnet"].rpc);
  const [addr, setAddr] = useState(init.addr);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [res, setRes] = useState<ScanResult | null>(null);

  const pickNet = (n: NetName) => {
    setNet(n);
    setRpc(NETS[n].rpc);
    setRes(null);
  };
  const run = async (e?: FormEvent, a = addr, n = net, url = rpc) => {
    e?.preventDefault();
    setBusy(true);
    setError(null);
    setRes(null);
    try {
      const r = await scanLaunch(new Connection(url, "confirmed"), a, PROGRAM_ID);
      setRes(r);
      history.replaceState(null, "", `#/scan?net=${n}&a=${a.trim()}`);
    } catch (err: any) {
      setError(String(err?.message ?? err).replace(/^Error: /, ""));
    } finally {
      setBusy(false);
    }
  };
  const demo = (featuredCfg.featured as { config: string }[])[0]?.config;

  return (
    <main className="page narrow">
      <h1>Rug check</h1>
      <p className="muted">
        Paste any token, Meteora DBC pool or config. We read its launch settings straight from the chain and check the
        four things OwnCurve enforces: where the raise goes at graduation, the creator's cut, whether liquidity can be
        pulled, and whether more tokens can be minted.
      </p>
      <form className="form scan-form" onSubmit={run}>
        <label>
          Network
          <select value={net} onChange={(e) => pickNet(e.target.value as NetName)}>
            {Object.entries(NETS).map(([k, v]) => (
              <option key={k} value={k}>
                {v.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          Token mint, DBC pool or config address
          <input value={addr} onChange={(e) => setAddr(e.target.value)} placeholder="Paste an address" required />
        </label>
        <details>
          <summary>RPC</summary>
          <label>
            RPC URL (looking up by token mint needs an RPC that allows getProgramAccounts)
            <input value={rpc} onChange={(e) => setRpc(e.target.value)} />
          </label>
        </details>
        <div className="scan-buttons">
          <button className="btn primary" disabled={busy || !addr.trim()}>
            {busy ? "Reading the chain…" : "Check"}
          </button>
          {demo && (
            <button
              type="button"
              className="btn quiet"
              onClick={() => {
                setAddr(demo);
                pickNet("devnet");
                void run(undefined, demo, "devnet", NETS.devnet.rpc);
              }}
            >
              Try an OwnCurve raise
            </button>
          )}
        </div>
      </form>
      {error && <p className="error" role="alert">{error}</p>}
      {res && (
        <section className="scan-result" aria-label="Result">
          <div className={`grade g-${res.grade.replace("+", "plus")}`} aria-label={`Grade ${res.grade}`}>
            {res.grade}
          </div>
          <div>
            <p className="scan-summary">
              {res.ownCurve
                ? "This launch is an OwnCurve raise: the raise sits in an on-chain treasury and holders keep their rights."
                : res.checks.every((c) => c.ok)
                  ? "No red flags in the launch settings."
                  : `${res.checks.filter((c) => !c.ok).length} red flag${res.checks.filter((c) => !c.ok).length > 1 ? "s" : ""} in the launch settings.`}
            </p>
            <ul className="scan-checks">
              {res.checks.map((c) => (
                <li key={c.id} className={c.ok ? (c.warn ? "warn" : "ok") : "bad"}>
                  <span className="mark" aria-hidden>
                    {c.ok ? (c.warn ? "!" : "✓") : "✕"}
                  </span>
                  <span>
                    <strong>{c.title}</strong>
                    <br />
                    <small>{c.detail}</small>
                  </span>
                </li>
              ))}
            </ul>
            <p className="fine">
              Raised in {res.quote}
              {res.curve
                ? ` · ${res.curve.raised.toLocaleString("en-US", { maximumFractionDigits: 2 })} of ${res.curve.threshold.toLocaleString("en-US", { maximumFractionDigits: 2 })} ${res.quote} on the curve${res.curve.migrated ? " · graduated" : ""}`
                : ""}
              {" · "}
              <a href={NETS[net].explorer(res.config)} target="_blank" rel="noreferrer">
                config
              </a>
              {res.pool && (
                <>
                  {" · "}
                  <a href={NETS[net].explorer(res.pool)} target="_blank" rel="noreferrer">
                    pool
                  </a>
                </>
              )}
              {res.ownCurve && net === "devnet" && (
                <>
                  {" · "}
                  <a href={`#/raise/${res.config}`}>open the raise</a>
                </>
              )}
            </p>
          </div>
        </section>
      )}
    </main>
  );
}
