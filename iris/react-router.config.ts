import type { Config } from '@react-router/dev/config';

export default {
  // SSR on by default; per-route clientLoader/clientAction opt into the client.
  ssr: true,
  // Opt into the v8 defaults now (greenfield app, no dependence on the old
  // behavior) so the dev/build/typecheck logs stay free of future-flag warnings.
  future: {
    v8_middleware: true,
    v8_passThroughRequests: true,
    v8_splitRouteModules: true,
    v8_trailingSlashAwareDataRequests: true,
    v8_viteEnvironmentApi: true,
  },
} satisfies Config;
