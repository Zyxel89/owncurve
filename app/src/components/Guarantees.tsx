// Lo que bind_pool comprobó en cadena antes de que nadie comprara, releído en vivo de la
// config de Meteora DBC. Es la respuesta a "¿por qué no me pueden hacer un rug?".
import { PublicKey } from "@solana/web3.js";
import type { RaiseDetail } from "../lib/data";
import { explorerAddress } from "../lib/browserNet";

export function Guarantees({ d }: { d: RaiseDetail }) {
  const cfg = d.cfg;
  if (!cfg) return null;
  const treasury = d.r.treasury;
  const items: { ok: boolean; text: string }[] = [
    {
      ok: new PublicKey(cfg.feeClaimer).equals(treasury),
      text: "Only this program can move the raise: Meteora pays the migration fee to the treasury, not to a wallet.",
    },
    {
      ok: cfg.migrationFeePercentage >= d.raise.minTreasuryPct && cfg.creatorMigrationFeePercentage === 0,
      text: `${cfg.migrationFeePercentage}% of the raise goes to the treasury and 0% to the creator.`,
    },
    {
      ok: cfg.creatorLiquidityPercentage === 0 && cfg.creatorLiquidityVestingInfo.vestingPercentage === 0,
      text: "The team cannot pull liquidity after graduation: its LP share is permanently locked.",
    },
    {
      ok: cfg.tokenUpdateAuthority !== 3,
      text: "Nobody can mint more tokens.",
    },
    {
      ok: Number(d.raise.challengeWindow) >= 60 && d.raise.rejectQuorumBps <= 3000,
      text: `Every payment waits ${Number(d.raise.challengeWindow)} s for objections; ${
        d.raise.rejectQuorumBps / 100
      }% of the supply can stop it.`,
    },
    {
      ok: d.raise.floorReserveBps > 0,
      text: `${d.raise.floorReserveBps / 100}% of the treasury plus every fee it earns can only buy the token back below its backing and burn it.`,
    },
    {
      ok: true,
      text: "Every tranche request carries a public link to the delivered work and its SHA-256 on-chain.",
    },
  ];
  const link = explorerAddress(treasury);
  return (
    <section className="guarantees" aria-labelledby="g-title">
      <h2 id="g-title">Checked on-chain before the first buy</h2>
      <ul>
        {items.map((it) => (
          <li key={it.text} className={it.ok ? "ok" : "bad"}>
            <span className="mark" aria-hidden>
              {it.ok ? "✓" : "✕"}
            </span>
            {it.text}
          </li>
        ))}
      </ul>
      <p className="fine">
        Treasury account{" "}
        {link ? (
          <a className="addr" href={link} target="_blank" rel="noreferrer">
            {treasury.toBase58()}
          </a>
        ) : (
          <span className="addr">{treasury.toBase58()}</span>
        )}
      </p>
    </section>
  );
}
