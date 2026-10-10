// Actividad del keeper autónomo (GitHub Actions cada 10 min), leída directamente de la cadena.
import { PublicKey } from "@solana/web3.js";
import { useMemo } from "react";
import featuredCfg from "../featured.json";
import { explorerAddress } from "../lib/browserNet";
import { IDL, PROGRAM_ID, readOnlyClient, usePoll } from "../lib/data";
import { useAccount } from "../lib/wallet";

const LABEL: Record<string, string> = {
  Harvest: "Moved a graduated raise into its treasury",
  ArmGuard: "Started a raise's ghost-team clock",
  Finalize: "Settled a tranche after its objection window",
  Observe: "Recorded the DAMM v2 price for the takeover TWAP",
  DefendFloor: "Bought back below backing and burned",
  DeclareAbandoned: "Returned a silent team's treasury to holders",
};

export const KEEPER = (featuredCfg as any).keeper as string | undefined;

type Row = { sig: string; at: number | null; actions: string[]; raises: string[]; ok: boolean };

export function Keeper() {
  const { conn } = useAccount();
  const oc = useMemo(() => readOnlyClient(conn), [conn]);
  const { data, error } = usePoll(
    async () => {
      if (!KEEPER) return null;
      const pk = new PublicKey(KEEPER);
      const [balance, sigs] = await Promise.all([conn.getBalance(pk), conn.getSignaturesForAddress(pk, { limit: 25 })]);
      const txs = await conn.getTransactions(
        sigs.map((s) => s.signature),
        { maxSupportedTransactionVersion: 0, commitment: "confirmed" },
      );
      const raisePdas = new Set<string>();
      const rows: Row[] = sigs.map((s, i) => {
        const tx = txs[i];
        const logs = tx?.meta?.logMessages ?? [];
        const actions = logs
          .map((l) => l.match(/^Program log: Instruction: (\w+)/)?.[1])
          .filter((x): x is string => !!x && x in LABEL);
        const keys = tx ? tx.transaction.message.getAccountKeys().staticAccountKeys : [];
        const raises: string[] = [];
        if (tx) {
          for (const ix of tx.transaction.message.compiledInstructions) {
            if (keys[ix.programIdIndex]?.equals(PROGRAM_ID)) {
              const k = keys[ix.accountKeyIndexes[0]]?.toBase58();
              if (k) {
                raises.push(k);
                raisePdas.add(k);
              }
            }
          }
        }
        return { sig: s.signature, at: s.blockTime ?? null, actions, raises, ok: !s.err };
      });
      // PDA del raise → su config (la dirección que usa la app)
      const list = [...raisePdas];
      const infos = list.length ? await conn.getMultipleAccountsInfo(list.map((k) => new PublicKey(k))) : [];
      const configOf = new Map<string, string>();
      infos.forEach((info, i) => {
        try {
          if (info) configOf.set(list[i], new PublicKey(oc.program.coder.accounts.decode("raise", info.data).dbcConfig).toBase58());
        } catch {
          /* formato antiguo */
        }
      });
      return { balance: balance / 1e9, rows: rows.filter((r) => r.actions.length), configOf };
    },
    [conn],
    20_000,
  );
  const ago = (t: number | null) => {
    if (!t) return "";
    const s = Math.max(0, Math.floor(Date.now() / 1000 - t));
    return s < 90 ? `${s} s ago` : s < 5400 ? `${Math.round(s / 60)} min ago` : `${Math.round(s / 3600)} h ago`;
  };
  void IDL;

  return (
    <main className="page narrow">
      <h1>Keeper</h1>
      <p className="muted">
        Holder protections should not depend on someone clicking a button. Every 10 minutes a keeper on GitHub Actions does
        every permissionless job OwnCurve has: it settles tranches whose window closed, records Meteora DAMM v2 prices for
        the takeover TWAP, buys back below backing, and returns the treasury of teams that went silent. Anyone can run the
        same keeper (<code>scripts/keeper.ts</code>); it holds no special rights.
      </p>
      {!KEEPER && <p className="muted">No keeper configured for this deployment.</p>}
      {KEEPER && (
        <p className="fine">
          Keeper wallet{" "}
          <a className="addr" href={explorerAddress(new PublicKey(KEEPER)) || "#"} target="_blank" rel="noreferrer">
            {KEEPER.slice(0, 8)}…{KEEPER.slice(-8)}
          </a>
          {data ? ` · ${data.balance.toFixed(3)} SOL for fees` : ""} ·{" "}
          <a href="https://github.com/Zyxel89/owncurve/actions/workflows/keeper.yml" target="_blank" rel="noreferrer">
            runs on GitHub Actions
          </a>
        </p>
      )}
      {error && <p className="error">{error}</p>}
      {data && data.rows.length === 0 && <p className="muted">No keeper actions yet.</p>}
      {data && data.rows.length > 0 && (
        <ul className="keeper-log">
          {data.rows.map((r) => (
            <li key={r.sig} className={r.ok ? "" : "bad"}>
              <span className="when">{ago(r.at)}</span>
              <span>
                {r.actions.map((a) => LABEL[a]).join(" · ")}
                {r.raises.map((k) =>
                  data.configOf.get(k) ? (
                    <a key={k} href={`#/raise/${data.configOf.get(k)}`}>
                      {" "}
                      (raise)
                    </a>
                  ) : null,
                )}
              </span>
              <a className="fine" href={`https://explorer.solana.com/tx/${r.sig}?cluster=devnet`} target="_blank" rel="noreferrer">
                tx
              </a>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
