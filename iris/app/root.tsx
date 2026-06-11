import { useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import {
  data,
  isRouteErrorResponse,
  Links,
  Meta,
  Outlet,
  Scripts,
  ScrollRestoration,
} from 'react-router';

import type { Route } from './+types/root';
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

// Detects the locale on every request and exposes it via router context.
export const middleware = [i18nextMiddleware];

export async function loader({ context, request }: Route.LoaderArgs) {
  const locale = getLocale(context);
  // Host drives the header title (localhost in dev, iris.<tld> in prod).
  const host = new URL(request.url).hostname;
  return data(
    { locale, host },
    { headers: { 'Set-Cookie': await localeCookie.serialize(locale) } },
  );
}

export function Layout({ children }: { children: React.ReactNode }) {
  const { i18n } = useTranslation();
  return (
    // `className="dark"` keeps Park UI's dark scales active (dark-only this round).
    <html lang={i18n.language} dir={i18n.dir(i18n.language)} className="dark">
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
  let message = 'Oops!';
  let details = 'An unexpected error occurred.';
  let stack: string | undefined;

  if (isRouteErrorResponse(error)) {
    message = error.status === 404 ? '404' : 'Error';
    details =
      error.status === 404 ? 'The requested page could not be found.' : error.statusText || details;
  } else if (import.meta.env.DEV && error && error instanceof Error) {
    details = error.message;
    stack = error.stack;
  }

  return (
    <main>
      <h1>{message}</h1>
      <p>{details}</p>
      {stack && (
        <pre>
          <code>{stack}</code>
        </pre>
      )}
    </main>
  );
}
