import enCommon from './en/common.json';
import frCommon from './fr/common.json';

// All bundled locales. Add `<lng>: { common: ... }` to ship more languages.
export default {
  en: { common: enCommon },
  fr: { common: frCommon },
} as const;
