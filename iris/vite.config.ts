import { reactRouter } from '@react-router/dev/vite';
import { defineConfig } from 'vite';

// Panda runs through PostCSS (see postcss.config.cjs); Vite 8 resolves the
// tsconfig `paths` aliases natively via resolve.tsconfigPaths.
export default defineConfig({
  plugins: [reactRouter()],
  resolve: {
    tsconfigPaths: true,
  },
});
