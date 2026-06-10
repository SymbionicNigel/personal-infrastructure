import { defineConfig } from "@pandacss/dev";

// Minimal config so `panda codegen` (the prepare hook) succeeds on install.
// Park UI preset + salvaged palette tokens are layered on in a later step.
export default defineConfig({
  preflight: true,
  include: ["./app/**/*.{ts,tsx}"],
  exclude: [],
  jsxFramework: "react",
  outdir: "styled-system",
});
