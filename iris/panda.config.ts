import { defineConfig } from '@pandacss/dev';
import { createPreset } from '@park-ui/panda-preset';
import cyan from '@park-ui/panda-preset/colors/cyan';
import sand from '@park-ui/panda-preset/colors/sand';

// Park UI preset supplies the component recipes + accent/gray scales; the
// vintage palette is layered on as tokens + semantic overrides.
export default defineConfig({
  preflight: true,
  presets: [createPreset({ accentColor: cyan, grayColor: sand, radius: 'sm' })],
  include: ['./app/**/*.{ts,tsx}'],
  exclude: [],
  jsxFramework: 'react',
  outdir: 'styled-system',
  theme: {
    extend: {
      tokens: {
        colors: {
          vintage: {
            bg: { value: '#271e16' },
            paper: { value: '#31281d' },
            primary: { value: '#669fb2' },
            secondary: { value: '#87aa7e' },
            pistachio: { value: '#87aa7e' },
            ink: { value: '#1c3a4a' },
            warning: { value: '#edbf02' },
            error: { value: '#e06c21' },
            info: { value: '#0288d1' },
            success: { value: '#005427' },
            divider: { value: '#2f201b' },
          },
        },
        fonts: {
          heading: { value: 'var(--font-heading)' },
          body: { value: 'var(--font-body)' },
          mono: { value: 'var(--font-mono)' },
        },
      },
      semanticTokens: {
        colors: {
          // Repaint Park UI's surface + border tokens with the vintage palette.
          bg: {
            canvas: { value: '{colors.vintage.bg}' },
            default: { value: '{colors.vintage.paper}' },
            // Cards + elevated surfaces stay in the warm-brown family (vs Park
            // UI's sand), with steps between them for hover/elevation contrast.
            subtle: { value: '#3a3024' },
            muted: { value: '#443829' },
            emphasized: { value: '#4e422f' },
          },
          border: {
            default: { value: '{colors.vintage.divider}' },
          },
          fg: {
            warning: { value: '{colors.vintage.warning}' },
            error: { value: '{colors.vintage.error}' },
            success: { value: '{colors.vintage.success}' },
          },
        },
      },
      recipes: {
        // Pick a surface tone and its readable text color comes paired — no
        // need to set `bg` + `color` together at every usage.
        surface: {
          className: 'surface',
          description: 'A background surface paired with its readable text color.',
          base: {},
          variants: {
            tone: {
              canvas: { bg: 'bg.canvas', color: 'fg.default' },
              paper: { bg: 'bg.default', color: 'fg.default' },
              pistachio: { bg: 'vintage.pistachio', color: 'vintage.ink' },
            },
          },
          defaultVariants: { tone: 'paper' },
        },
      },
    },
  },
});
