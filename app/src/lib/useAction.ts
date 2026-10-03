import { useCallback, useState } from "react";
import { explainError, explorerTx } from "./browserNet";

export type ActionState = { busy: string | null; error: string | null; done: { text: string; link: string } | null };

/** Ejecuta una acción on-chain mostrando progreso, el resultado con enlace o un error legible. */
export function useAction(onDone?: () => void) {
  const [s, setS] = useState<ActionState>({ busy: null, error: null, done: null });
  const run = useCallback(
    async (label: string, doneText: string, fn: () => Promise<string | void>) => {
      setS({ busy: label, error: null, done: null });
      try {
        const sig = await fn();
        setS({ busy: null, error: null, done: { text: doneText, link: sig ? explorerTx(sig) : "" } });
        onDone?.();
      } catch (e) {
        console.error(e);
        setS({ busy: null, error: explainError(e), done: null });
      }
    },
    [onDone],
  );
  return { ...s, run };
}
