import common from './en/common.json';

// All bundled locales (no runtime fetch — fine for a small, single-language
// app). Add `<lng>: { common: ... }` entries to ship more languages; switch to
// a lazy backend here if the bundle grows.
export default { en: { common } } as const;
