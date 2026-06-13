import { useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import {
  data,
  Links,
  Meta,
  Outlet,
  Scripts,
  ScrollRestoration,
  useRouteLoaderData,
} from 'react-router';

import type { Route } from './+types/root';
import { ErrorPage } from './components/error-page';
import { headingFontCookie } from './cookies';
import { DEFAULT_HEADING_FONT } from './fonts';
import { getLocale, i18nextMiddleware, localeCookie } from './middleware/i18next';
import './styles/app.css';

export const links: Route.LinksFunction = () => [
  { rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml' },
  // Preload the two default faces (body + default heading); other heading
  // fonts load on demand when switched on /styleguide. Fonts are CORS-fetched,
  // so the preload needs crossOrigin to match and avoid a double request.
  {
    rel: 'preload',
    href: '/fonts/space-grotesk.woff2',
    as: 'font',
    type: 'font/woff2',
    crossOrigin: 'anonymous',
  },
  {
    rel: 'preload',
    href: '/fonts/yellowtail.woff2',
    as: 'font',
    type: 'font/woff2',
    crossOrigin: 'anonymous',
  },
];

export const middleware = [i18nextMiddleware];

export async function loader({ context, request }: Route.LoaderArgs) {
  const locale = getLocale(context);
  const headingFont =
    ((await headingFontCookie.parse(request.headers.get('Cookie'))) as string | null) ??
    DEFAULT_HEADING_FONT;
  return data(
    { locale, headingFont },
    { headers: { 'Set-Cookie': await localeCookie.serialize(locale) } },
  );
}

export function Layout({ children }: { children: React.ReactNode }) {
  const { i18n } = useTranslation();
  // Heading font is restored from the cookie (root loader) and rendered onto
  // <html> so it's correct on first paint — no flash, no inline script.
  const rootData = useRouteLoaderData('root') as { headingFont?: string } | undefined;
  return (
    // `className="dark"` activates Park UI's dark scales.
    <html
      lang={i18n.language}
      dir={i18n.dir(i18n.language)}
      className="dark"
      data-heading-font={rootData?.headingFont ?? DEFAULT_HEADING_FONT}
    >
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Meta />
        <Links />
      </head>
      <body>
        {children}
        <ScrollRestoration />
        <Scripts />
      </body>
    </html>
  );
}

// The masthead's five-band rainbow; the scrollbar thumb (--iris-scroll-color)
// travels along it as the page scrolls — blue at the top → orange at the bottom.
const SCROLL_BANDS = ['#0288d1', '#669fb2', '#87aa7e', '#edbf02', '#e06c21'];

function hexToRgb(hex: string): [number, number, number] {
  return [
    Number.parseInt(hex.slice(1, 3), 16),
    Number.parseInt(hex.slice(3, 5), 16),
    Number.parseInt(hex.slice(5, 7), 16),
  ];
}

// Interpolate the bands by scroll progress (0 → 1).
function scrollbarColor(progress: number): string {
  const t = Math.min(1, Math.max(0, progress)) * (SCROLL_BANDS.length - 1);
  const i = Math.min(SCROLL_BANDS.length - 2, Math.floor(t));
  const f = t - i;
  const a = hexToRgb(SCROLL_BANDS[i]);
  const b = hexToRgb(SCROLL_BANDS[i + 1]);
  const mix = (x: number, y: number) => Math.round(x + (y - x) * f);
  return `rgb(${mix(a[0], b[0])}, ${mix(a[1], b[1])}, ${mix(a[2], b[2])})`;
}

export default function App({ loaderData }: Route.ComponentProps) {
  const { i18n } = useTranslation();
  // Keep the client i18next instance in sync with the server-detected locale.
  useEffect(() => {
    if (i18n.language !== loaderData.locale) i18n.changeLanguage(loaderData.locale);
  }, [loaderData.locale, i18n]);

  // Shift the scrollbar thumb through the rainbow as the page scrolls.
  useEffect(() => {
    const root = document.documentElement;
    let raf = 0;
    const update = () => {
      raf = 0;
      const max = root.scrollHeight - window.innerHeight;
      root.style.setProperty(
        '--iris-scroll-color',
        scrollbarColor(max > 0 ? window.scrollY / max : 0),
      );
    };
    const onScroll = () => {
      if (!raf) raf = requestAnimationFrame(update);
    };
    update();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
      if (raf) cancelAnimationFrame(raf);
    };
  }, []);

  return <Outlet />;
}

export function ErrorBoundary({ error }: Route.ErrorBoundaryProps) {
  return <ErrorPage error={error} />;
}
