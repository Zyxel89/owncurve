import react from "@vitejs/plugin-react";
import path from "path";
import { defineConfig } from "vite";
import { nodePolyfills } from "vite-plugin-node-polyfills";

// La app vive en app/ pero reutiliza el cliente de scripts/lib y el IDL de target/idl.
export default defineConfig({
  root: path.resolve(__dirname),
  base: "./",
  envDir: path.resolve(__dirname),
  plugins: [react(), nodePolyfills({ include: ["buffer", "crypto", "stream", "util", "process"], globals: { Buffer: true, process: true } })],
  server: { port: 5173, fs: { allow: [path.resolve(__dirname, "..")] } },
  build: { outDir: path.resolve(__dirname, "dist"), emptyOutDir: true, chunkSizeWarningLimit: 4000 },
});
