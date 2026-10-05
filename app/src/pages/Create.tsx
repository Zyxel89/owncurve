import { Keypair, PublicKey } from "@solana/web3.js";
import { FormEvent, useState } from "react";
import { DEFAULT_PARAMS, OwnCurve } from "../../../scripts/lib/owncurve";
import { explainError, makeBrowserNet } from "../lib/browserNet";
import { IDL, KNOWN_QUOTES } from "../lib/data";
import { useAccount } from "../lib/wallet";

const METADATA_URI =
  "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json";

export function Create() {
  const acc = useAccount();
  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [target, setTarget] = useState("0.5");
  const [quoteSel, setQuoteSel] = useState(KNOWN_QUOTES[0].mint.toBase58());
  const [customMint, setCustomMint] = useState("");
  const known = KNOWN_QUOTES.find((q) => q.mint.toBase58() === quoteSel);
  const sym = known?.symbol ?? "tokens";
  const pickQuote = (v: string) => {
    setQuoteSel(v);
    const q = KNOWN_QUOTES.find((k) => k.mint.toBase58() === v);
    setTarget(q?.symbol === "SOL" ? "0.5" : q?.decimals === 8 ? "1" : "100");
  };
  let customOk = true;
  if (quoteSel === "custom") {
    try {
      new PublicKey(customMint.trim());
    } catch {
      customOk = false;
    }
  }
  const [treasury, setTreasury] = useState("80");
  const [tranches, setTranches] = useState("30, 30, 40");
  const [windowSecs, setWindowSecs] = useState("60");
  const [quorum, setQuorum] = useState("10");
  const [floor, setFloor] = useState("20");
  const [silentMin, setSilentMin] = useState("5");
  const [premium, setPremium] = useState("30");
  const [twapSecs, setTwapSecs] = useState("120");
  const [step, setStep] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const trancheList = tranches
    .split(/[,\s]+/)
    .filter(Boolean)
    .map(Number);
  const trancheSum = trancheList.reduce((a, b) => a + b, 0);
  const formError =
    trancheList.some((t) => !Number.isFinite(t) || t <= 0) || trancheSum !== 100 || trancheList.length > 5
      ? "Tranches must be 1 to 5 positive numbers that add up to 100."
      : Number(treasury) < 50 || Number(treasury) > 99
        ? "Send between 50% and 99% of the raise to the treasury."
        : Number(windowSecs) < 60
          ? "Give holders at least 60 seconds to object."
          : Number(quorum) <= 0 || Number(quorum) > 30
            ? "The quorum must be between 1% and 30% of the supply."
            : !(Number(floor) >= 0 && Number(floor) <= 50)
              ? "Keep between 0% and 50% of the treasury as a price floor."
              : !(Number(silentMin) >= 1)
                ? "The ghost-team switch needs at least 1 minute."
                : !(Number(premium) >= 10 && Number(premium) <= 100)
                  ? "The takeover premium must be between 10% and 100%."
                  : !(Number(twapSecs) >= 60)
                    ? "The TWAP window must be at least 60 seconds."
            : !(Number(target) > 0)
              ? `Set how much ${sym} the curve should raise.`
              : !customOk
                ? "Paste a valid token mint address."
              : null;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!acc.signer || formError) return;
    setError(null);
    try {
      const oc = new OwnCurve(makeBrowserNet(acc.conn, acc.signer), IDL);
      const configKp = Keypair.generate();
      const baseMintKp = Keypair.generate();
      const quote =
        quoteSel === "custom" ? await oc.quoteInfo(new PublicKey(customMint.trim())) : KNOWN_QUOTES.find((q) => q.mint.toBase58() === quoteSel)!;
      const params = {
        ...DEFAULT_PARAMS,
        quote,
        threshold: Number(target),
        treasuryPct: Math.round(Number(treasury)),
        tranchesBps: trancheList.map((t) => Math.round(t * 100)),
        challengeSecs: Math.round(Number(windowSecs)),
        quorumBps: Math.round(Number(quorum) * 100),
        floorReserveBps: Math.round(Number(floor) * 100),
        guard: {
          inactivitySecs: Math.round(Number(silentMin) * 60),
          buyoutPremiumBps: Math.round(Number(premium) * 100),
          twapWindowSecs: Math.round(Number(twapSecs)),
        },
      };
      setStep("Creating the raise and its Meteora curve (1 of 2)…");
      await oc.createRaise(params, configKp);
      setStep("Opening the curve and checking it on-chain (2 of 2)…");
      await oc.launchPool(configKp.publicKey, baseMintKp, undefined, true, {
        name: name.trim(),
        symbol: symbol.trim().toUpperCase(),
        uri: METADATA_URI,
      });
      acc.refreshBalance();
      location.hash = `#/raise/${configKp.publicKey.toBase58()}`;
    } catch (err) {
      console.error(err);
      setError(explainError(err));
    } finally {
      setStep(null);
    }
  };

  return (
    <main className="page narrow">
      <h1>Launch a raise</h1>
      <p className="muted">
        Your token trades on a Meteora bonding curve. When the curve graduates, the share you choose goes to a treasury
        that pays you one tranche at a time.
      </p>
      <form className="form" onSubmit={submit}>
        <fieldset>
          <legend>Token</legend>
          <label>
            Name
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={32} required placeholder="Lighthouse Labs" />
          </label>
          <label>
            Symbol
            <input value={symbol} onChange={(e) => setSymbol(e.target.value)} maxLength={10} required placeholder="LIGHT" />
          </label>
        </fieldset>
        <fieldset>
          <legend>Raise</legend>
          <label>
            Currency to raise in
            <select value={quoteSel} onChange={(e) => pickQuote(e.target.value)}>
              {KNOWN_QUOTES.map((q) => (
                <option key={q.mint.toBase58()} value={q.mint.toBase58()}>
                  {q.label}
                </option>
              ))}
              <option value="custom">Another token (paste its mint)</option>
            </select>
            <small>
              Any SPL or Token-2022 token works, e.g. USDC or an xStock on mainnet. On devnet, the test tokens come with a
              faucet on the raise page.
            </small>
          </label>
          {quoteSel === "custom" && (
            <label>
              Token mint address
              <input value={customMint} onChange={(e) => setCustomMint(e.target.value)} placeholder="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" />
            </label>
          )}
          <label>
            {sym === "tokens" ? "Amount" : sym} the curve raises before graduating
            <input inputMode="decimal" value={target} onChange={(e) => setTarget(e.target.value)} />
          </label>
          <label>
            Share that goes to the treasury (%)
            <input inputMode="numeric" value={treasury} onChange={(e) => setTreasury(e.target.value)} />
          </label>
          <label>
            Tranches (% of the treasury, in order)
            <input value={tranches} onChange={(e) => setTranches(e.target.value)} />
            <small>Add up to 100. Now: {trancheSum}.</small>
          </label>
        </fieldset>
        <fieldset>
          <legend>Holder protection</legend>
          <label>
            Seconds holders have to object to each tranche
            <input inputMode="numeric" value={windowSecs} onChange={(e) => setWindowSecs(e.target.value)} />
          </label>
          <label>
            Supply that can stop a tranche (%)
            <input inputMode="decimal" value={quorum} onChange={(e) => setQuorum(e.target.value)} />
          </label>
          <label>
            Treasury kept as a price floor (%)
            <input inputMode="decimal" value={floor} onChange={(e) => setFloor(e.target.value)} />
            <small>Never paid to the team. If the token trades below its backing, it buys tokens back and burns them.</small>
          </label>
          <label>
            Return the treasury to holders if the team is silent for (minutes)
            <input inputMode="decimal" value={silentMin} onChange={(e) => setSilentMin(e.target.value)} />
            <small>Minutes on devnet so you can try it; on mainnet this would be weeks.</small>
          </label>
          <label>
            Takeover premium over the TWAP (%)
            <input inputMode="decimal" value={premium} onChange={(e) => setPremium(e.target.value)} />
            <small>Meteora Bedrock's clause, enforced by the program: taking the project over means paying every holder this much over the market price.</small>
          </label>
          <label>
            TWAP window (seconds)
            <input inputMode="numeric" value={twapSecs} onChange={(e) => setTwapSecs(e.target.value)} />
          </label>
        </fieldset>
        {formError && <p className="error">{formError}</p>}
        {error && <p className="error">{error}</p>}
        {step && <p className="progress">{step}</p>}
        <button className="btn primary" disabled={!acc.signer || !!formError || !!step}>
          {acc.signer ? (step ? "Launching…" : "Launch raise") : "Connect a wallet to launch"}
        </button>
      </form>
    </main>
  );
}
