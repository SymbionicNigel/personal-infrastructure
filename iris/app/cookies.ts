import { createCookie } from 'react-router';

// Persists the styleguide heading-font choice so it's restored server-side
// (read in the root loader, rendered onto <html data-heading-font>), mirroring
// the locale cookie. Not httpOnly — the switcher writes it from the client.
export const headingFontCookie = createCookie('heading-font', {
  path: '/',
  sameSite: 'lax',
  secure: process.env.NODE_ENV === 'production',
  maxAge: 60 * 60 * 24 * 365,
});
