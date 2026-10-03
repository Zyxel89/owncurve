import { useEffect, useState } from "react";
import { Header } from "./components/Header";
import { Create } from "./pages/Create";
import { Home } from "./pages/Home";
import { RaisePage } from "./pages/RaisePage";
import { AccountProvider } from "./lib/wallet";

function useHashRoute() {
  const [hash, setHash] = useState(() => location.hash || "#/");
  useEffect(() => {
    const on = () => {
      setHash(location.hash || "#/");
      window.scrollTo(0, 0);
    };
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  return hash;
}

export function App() {
  const hash = useHashRoute();
  const raise = hash.match(/^#\/raise\/([1-9A-HJ-NP-Za-km-z]{32,44})$/);
  return (
    <AccountProvider>
      <Header />
      {hash === "#/new" ? <Create /> : raise ? <RaisePage config={raise[1]} /> : <Home />}
      <footer className="foot">
        <p>
          OwnCurve runs on Meteora's Dynamic Bonding Curve and DAMM v2. Open source, MIT licensed. Built for the Colosseum
          Crypto World's Fair.
        </p>
      </footer>
    </AccountProvider>
  );
}
