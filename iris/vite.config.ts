import { reactRouter } from '@react-router/dev/vite';
import { defineConfig } from 'vite';

// Panda runs through PostCSS (see postcss.config.cjs); Vite 8 resolves the
// tsconfig `paths` aliases natively via resolve.tsconfigPaths.
export default defineConfig({
  plugins: [reactRouter()],
  resolve: {
    tsconfigPaths: true,
  },
  // Match the prod/compose port (react-router-serve defaults to 3000) instead
  // of Vite's 5173, so local dev and the container line up.
  server: {
    port: 3000,
    strictPort: true,
  },
});
