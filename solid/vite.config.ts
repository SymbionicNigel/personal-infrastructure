import solid from "solid-start/vite";
import { defineConfig } from "vite";
import suidPlugin from '@suid/vite-plugin';

export default defineConfig({
  plugins: [suidPlugin(), solid({ ssr: false })],
  ssr: { external: ["@prisma/client"] },
});
