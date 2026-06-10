// Shared i18next config (server middleware + client hydration). English-only
// for v1; adding a language = drop in app/locales/<lng>/ and extend
// app/locales/index.ts — no other wiring needed.
export default {
  supportedLngs: ['en'],
  fallbackLng: 'en',
  defaultNS: 'common',
} as const;
