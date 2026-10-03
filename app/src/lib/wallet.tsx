// Una sola "cuenta activa" para toda la app: la wallet del navegador (estándar Wallet
// Standard: Phantom, Solflare, Backpack…) o una wallet desechable guardada en este navegador.
import { WalletProvider, useWallet } from "@solana/wallet-adapter-react";
import { Connection, Keypair, LAMPORTS_PER_SOL, PublicKey, Transaction } from "@solana/web3.js";
import { ReactNode, createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { CLUSTER, RPC_URL, TxSigner, confirm } from "./browserNet";

const BURNER_KEY = "owncurve.burner.v1";

function loadBurner(): Keypair | null {
  try {
    const raw = localStorage.getItem(BURNER_KEY);
    return raw ? Keypair.fromSecretKey(Uint8Array.from(JSON.parse(raw))) : null;
  } catch {
    return null;
  }
}
function saveBurner(kp: Keypair | null) {
  try {
    if (kp) localStorage.setItem(BURNER_KEY, JSON.stringify(Array.from(kp.secretKey)));
    else localStorage.removeItem(BURNER_KEY);
  } catch {
    /* almacenamiento no disponible: la wallet vive solo en memoria */
  }
}

type Account = {
  conn: Connection;
  signer: TxSigner | null;
  kind: "browser" | "burner" | null;
  balance: number | null;
  refreshBalance: () => void;
  useBurner: () => void;
  forgetBurner: () => void;
  requestSol: () => Promise<void>;
  disconnect: () => void;
};

const Ctx = createContext<Account | null>(null);

export function AccountProvider({ children }: { children: ReactNode }) {
  return (
    <WalletProvider wallets={[]} autoConnect>
      <Inner>{children}</Inner>
    </WalletProvider>
  );
}

function Inner({ children }: { children: ReactNode }) {
  const conn = useMemo(() => new Connection(RPC_URL, "confirmed"), []);
  const adapter = useWallet();
  const [burner, setBurner] = useState<Keypair | null>(() => loadBurner());
  const [balance, setBalance] = useState<number | null>(null);
  const [tick, setTick] = useState(0);

  const signer: TxSigner | null = useMemo(() => {
    if (burner)
      return {
        publicKey: burner.publicKey,
        signTransaction: async (tx: Transaction) => {
          tx.partialSign(burner);
          return tx;
        },
      };
    if (adapter.publicKey && adapter.signTransaction)
      return { publicKey: adapter.publicKey, signTransaction: adapter.signTransaction as TxSigner["signTransaction"] };
    return null;
  }, [burner, adapter.publicKey, adapter.signTransaction]);

  useEffect(() => {
    if (!signer) return setBalance(null);
    let live = true;
    conn.getBalance(signer.publicKey).then((b) => live && setBalance(b / LAMPORTS_PER_SOL)).catch(() => {});
    const id = setInterval(() => setTick((t) => t + 1), 15_000);
    return () => {
      live = false;
      clearInterval(id);
    };
  }, [signer, conn, tick]);

  const useBurnerCb = useCallback(() => {
    const kp = loadBurner() ?? Keypair.generate();
    saveBurner(kp);
    if (adapter.connected) adapter.disconnect().catch(() => {});
    setBurner(kp);
  }, [adapter]);

  const requestSol = useCallback(async () => {
    if (!signer) return;
    try {
      const sig = await conn.requestAirdrop(signer.publicKey, 1 * LAMPORTS_PER_SOL);
      await confirm(conn, sig, "Airdrop");
    } catch (e) {
      // Muchas RPC privadas no hacen airdrops: probamos el faucet público de devnet.
      const PUBLIC = "https://api.devnet.solana.com";
      if (CLUSTER !== "devnet" || (conn as any).rpcEndpoint === PUBLIC) throw e;
      const pub = new Connection(PUBLIC, "confirmed");
      const sig = await pub.requestAirdrop(signer.publicKey, 1 * LAMPORTS_PER_SOL);
      await confirm(pub, sig, "Airdrop");
    }
    setTick((t) => t + 1);
  }, [conn, signer]);

  const value: Account = {
    conn,
    signer,
    kind: burner ? "burner" : signer ? "browser" : null,
    balance,
    refreshBalance: () => setTick((t) => t + 1),
    useBurner: useBurnerCb,
    forgetBurner: () => {
      saveBurner(null);
      setBurner(null);
    },
    requestSol,
    disconnect: () => {
      setBurner(null);
      if (adapter.connected) adapter.disconnect().catch(() => {});
    },
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAccount() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useAccount fuera de AccountProvider");
  return v;
}

export function short(k: PublicKey | string, n = 4) {
  const s = typeof k === "string" ? k : k.toBase58();
  return `${s.slice(0, n)}…${s.slice(-n)}`;
}

export { CLUSTER };
