// Monedas de prueba para recaudar en algo distinto de SOL: una "tUSD" (SPL clásico, como USDC)
// y una "tNVDAx" (Token-2022, como las xStocks). En devnet su autoridad de emisión es una clave
// pública a propósito (app/src/devnet-faucet.ts) para que cualquiera pueda pedir monedas de
// prueba desde la web. En mainnet se usaría la moneda real (USDC, NVDAx…) con su mint.
import {
  TOKEN_2022_PROGRAM_ID,
  TOKEN_PROGRAM_ID,
  createAssociatedTokenAccountIdempotentInstruction,
  createInitializeMint2Instruction,
  createMintToCheckedInstruction,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import { sha256 } from "@noble/hashes/sha256";
import { Keypair, PublicKey, SystemProgram, TransactionInstruction } from "@solana/web3.js";
import type { Net } from "./net";
import type { Quote } from "./owncurve";

export type TestQuoteSpec = { symbol: string; decimals: number; token2022: boolean };
export const TEST_QUOTES: TestQuoteSpec[] = [
  { symbol: "tUSD", decimals: 6, token2022: false },
  { symbol: "tNVDAx", decimals: 8, token2022: true },
];

const seeded = (label: string) => Keypair.fromSeed(sha256(new TextEncoder().encode(label)));

/** Clave de emisión de las monedas de prueba en devnet. PÚBLICA A PROPÓSITO: no vale nada. */
export const devnetFaucet = () => seeded("owncurve/devnet/test-quote-faucet/v1");
/** Mint determinista de cada moneda de prueba (misma dirección en todas las máquinas). */
export const testQuoteKeypair = (symbol: string) => seeded(`owncurve/devnet/test-quote/${symbol}/v1`);
export const testQuoteOf = (spec: TestQuoteSpec): Quote => ({
  mint: testQuoteKeypair(spec.symbol).publicKey,
  program: spec.token2022 ? TOKEN_2022_PROGRAM_ID : TOKEN_PROGRAM_ID,
  decimals: spec.decimals,
  symbol: spec.symbol,
});

/** Crea el mint (si no existe) con `authority` como autoridad de emisión. */
export async function createTestQuote(net: Net, spec: TestQuoteSpec, mintKp: Keypair, authority: PublicKey): Promise<Quote> {
  const program = spec.token2022 ? TOKEN_2022_PROGRAM_ID : TOKEN_PROGRAM_ID;
  const quote: Quote = { mint: mintKp.publicKey, program, decimals: spec.decimals, symbol: spec.symbol };
  if (await net.conn.getAccountInfo(mintKp.publicKey)) return quote;
  const space = 82;
  const lamports = await net.conn.getMinimumBalanceForRentExemption(space);
  await net.send(
    `crear moneda ${spec.symbol}`,
    [
      SystemProgram.createAccount({ fromPubkey: net.payer.publicKey, newAccountPubkey: mintKp.publicKey, space, lamports, programId: program }),
      createInitializeMint2Instruction(mintKp.publicKey, spec.decimals, authority, null, program),
    ],
    [mintKp],
  );
  return quote;
}

/** Instrucciones para emitir `uiAmount` monedas de prueba a `to` (crea su cuenta si falta). */
export function mintTestQuoteIxs(quote: Quote, authority: PublicKey, payer: PublicKey, to: PublicKey, uiAmount: number): TransactionInstruction[] {
  const ata = getAssociatedTokenAddressSync(quote.mint, to, true, quote.program);
  const amount = BigInt(Math.round(uiAmount * 10 ** quote.decimals));
  return [
    createAssociatedTokenAccountIdempotentInstruction(payer, ata, to, quote.mint, quote.program),
    createMintToCheckedInstruction(quote.mint, ata, authority, amount, quote.decimals, [], quote.program),
  ];
}
