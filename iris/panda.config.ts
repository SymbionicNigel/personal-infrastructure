import { defineConfig } from "@pandacss/dev";
import { createPreset } from "@park-ui/panda-preset";
import cyan from "@park-ui/panda-preset/colors/cyan";
import sand from "@park-ui/panda-preset/colors/sand";

// Park UI preset supplies the component recipes + accent/gray scales; the
// salvaged 60s vintage palette (from the old solid/ themes) is layered on top
// as raw tokens + semantic overrides for the page surfaces and status colors.
export default defineConfig({
  preflight: true,
  presets: [createPreset({ accentColor: cyan, grayColor: sand, radius: "sm" })],
  include: ["./app/**/*.{ts,tsx}"],
  exclude: [],
  jsxFramework: "react",
  outdir: "styled-system",
  theme: {
    extend: {
      tokens: {
        colors: {
          vintage: {
            bg: { value: "#271e16" },
            paper: { value: "#31281d" },
            primary: { value: "#669fb2" },
            secondary: { value: "#87aa7e" },
            warning: { value: "#edbf02" },
            error: { value: "#e06c21" },
            info: { value: "#0288d1" },
            success: { value: "#005427" },
            divider: { value: "#2f201b" },
          },
        },
        fonts: {
          heading: { value: "var(--font-heading)" },
          body: { value: "var(--font-body)" },
          mono: { value: "var(--font-mono)" },
        },
      },
      semanticTokens: {
        colors: {
          // Repaint Park UI's surface + border tokens with the vintage palette
          // (dark-only this round, so flat values apply to both color modes).
          bg: {
            canvas: { value: "{colors.vintage.bg}" },
            default: { value: "{colors.vintage.paper}" },
          },
          border: {
            default: { value: "{colors.vintage.divider}" },
          },
          // Status colors map onto the salvaged warning/error/info/success.
          fg: {
            warning: { value: "{colors.vintage.warning}" },
            error: { value: "{colors.vintage.error}" },
            success: { value: "{colors.vintage.success}" },
          },
        },
      },
    },
  },
});
