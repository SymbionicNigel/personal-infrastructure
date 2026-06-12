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
  // Header shows domain + TLD, agnostic to any subdomain: keep the last two
  // labels (iris.example.com → example.com; localhost stays localhost). Assumes
  // a single-label TLD, which covers our domain.
  const host = new URL(request.url).hostname.split('.').slice(-2).join('.');
  const headingFont =
    ((await headingFontCookie.parse(request.headers.get('Cookie'))) as string | null) ??
    DEFAULT_HEADING_FONT;
  return data(
    { locale, host, headingFont },
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

export default function App({ loaderData }: Route.ComponentProps) {
  const { i18n } = useTranslation();
  // Keep the client i18next instance in sync with the server-detected locale.
  useEffect(() => {
    if (i18n.language !== loaderData.locale) i18n.changeLanguage(loaderData.locale);
  }, [loaderData.locale, i18n]);
  return <Outlet />;
}

export function ErrorBoundary({ error }: Route.ErrorBoundaryProps) {
  return <ErrorPage error={error} />;
}
