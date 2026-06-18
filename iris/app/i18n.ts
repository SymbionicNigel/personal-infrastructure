// Shared i18next config (server + client). Add a language by dropping in
// app/locales/<lng>/ and extending app/locales/index.ts.
export default {
  supportedLngs: ['en', 'fr'],
  fallbackLng: 'en',
  defaultNS: 'common',
} as const;
