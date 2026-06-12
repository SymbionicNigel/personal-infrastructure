import { initReactI18next } from 'react-i18next';
import { createCookie } from 'react-router';
import { createI18nextMiddleware } from 'remix-i18next/middleware';
import i18n from '~/i18n';
import resources from '~/locales';
import 'i18next';

export const localeCookie = createCookie('lng', {
  path: '/',
  sameSite: 'lax',
  secure: process.env.NODE_ENV === 'production',
  httpOnly: true,
});

export const [i18nextMiddleware, getLocale, getInstance] = createI18nextMiddleware({
  detection: {
    supportedLanguages: [...i18n.supportedLngs],
    fallbackLanguage: i18n.fallbackLng,
    cookie: localeCookie,
  },
  i18next: { ...i18n, resources },
  plugins: [initReactI18next],
});

declare module 'i18next' {
  interface CustomTypeOptions {
    defaultNS: 'common';
    resources: (typeof resources)['en'];
  }
}
