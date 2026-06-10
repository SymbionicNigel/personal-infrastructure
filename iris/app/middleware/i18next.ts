import { initReactI18next } from 'react-i18next';
import { createCookie } from 'react-router';
import { createI18nextMiddleware } from 'remix-i18next/middleware';
import i18n from '~/i18n';
import resources from '~/locales';
import 'i18next';

// Persists the detected/selected locale across requests.
export const localeCookie = createCookie('lng', {
  path: '/',
  sameSite: 'lax',
  secure: process.env.NODE_ENV === 'production',
  httpOnly: true,
});

// Runs on every request: detects the locale (cookie → Accept-Language →
// fallback) and exposes it + a configured i18next instance via router context.
export const [i18nextMiddleware, getLocale, getInstance] = createI18nextMiddleware({
  detection: {
    supportedLanguages: [...i18n.supportedLngs],
    fallbackLanguage: i18n.fallbackLng,
    cookie: localeCookie,
  },
  i18next: { ...i18n, resources },
  plugins: [initReactI18next],
});

// Type-safety for the `t` function, using `en` as the source of truth.
declare module 'i18next' {
  interface CustomTypeOptions {
    defaultNS: 'common';
    resources: (typeof resources)['en'];
  }
}
