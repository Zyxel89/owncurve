import { useWallet } from "@solana/wallet-adapter-react";
import { WalletReadyState } from "@solana/wallet-adapter-base";
import { useEffect, useState } from "react";
import { CLUSTER, short, useAccount } from "../lib/wallet";
import { explainError } from "../lib/browserNet";

export function Header() {
  const acc = useAccount();
  const adapter = useWallet();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [faucetHelp, setFaucetHelp] = useState(false);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!msg) return;
    const id = setTimeout(() => setMsg(null), 6000);
    return () => clearTimeout(id);
  }, [msg]);
  const installed = adapter.wallets.filter((w) => w.readyState === WalletReadyState.Installed);

  const airdrop = async () => {
    setBusy(true);
    setMsg(null);
    setFaucetHelp(false);
    try {
      await acc.requestSol();
      setMsg("1 devnet SOL added.");
    } catch (e) {
      console.warn("airdrop", explainError(e));
      setFaucetHelp(true);
    } finally {
      setBusy(false);
    }
  };

  return (
    <header className="masthead">
      <div className="masthead-row">
        <a href="#/" className="wordmark" aria-label="OwnCurve home">
          Own<span>Curve</span>
        </a>
        <nav className="nav">
          <a href="#/">Raises</a>
          <a href="#/new">Launch a raise</a>
        </nav>
        <div className="account">
          <span className="network" title="All transactions use this network">
            {CLUSTER === "devnet" ? "Solana devnet" : "Local validator"}
          </span>
          {acc.signer ? (
            <>
              <span className="who">
                <strong>{short(acc.signer.publicKey)}</strong>
                <span>{acc.balance === null ? "…" : `${acc.balance.toFixed(3)} SOL`}</span>
              </span>
              {acc.kind === "burner" && (
                <button className="btn quiet" onClick={airdrop} disabled={busy}>
                  {busy ? "Requesting…" : "Get 1 SOL"}
                </button>
              )}
              <button className="btn quiet" onClick={acc.disconnect}>
                Disconnect
              </button>
            </>
          ) : (
            <>
              {installed.map((w) => (
                <button key={w.adapter.name} className="btn" onClick={() => adapter.select(w.adapter.name)}>
                  Connect {w.adapter.name}
                </button>
              ))}
              <button className="btn quiet" onClick={acc.useBurner} title="A throwaway key kept in this browser">
                Use a test wallet
              </button>
            </>
          )}
        </div>
      </div>
      {msg && <p className="flash">{msg}</p>}
      {faucetHelp && acc.signer && (
        <div className="flash faucet" role="alert">
          <span>The automatic devnet faucet is busy. Get free devnet SOL for this test wallet in two steps:</span>
          <button
            className="btn quiet"
            onClick={() => {
              navigator.clipboard?.writeText(acc.signer!.publicKey.toBase58()).then(() => setCopied(true));
            }}
          >
            {copied ? "Address copied" : "1. Copy my address"}
          </button>
          <a className="btn quiet" href="https://faucet.solana.com" target="_blank" rel="noreferrer">
            2. Open faucet.solana.com
          </a>
          <button className="btn quiet" aria-label="Close" onClick={() => setFaucetHelp(false)}>
            ✕
          </button>
        </div>
      )}
    </header>
  );
}
