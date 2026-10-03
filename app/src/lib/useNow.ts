import { useEffect, useState } from "react";

/** Hora actual en segundos Unix (ajustada al reloj de la cadena con `skew`), cada segundo. */
export function useNow(skew = 0) {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(id);
  }, []);
  return now + skew;
}
