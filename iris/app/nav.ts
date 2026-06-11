// Single source of truth for the site's pages (a tree), driving the route table
// (routes.ts) and the breadcrumb nav (useBreadcrumbs). Pure data — no React
// imports — so the build-time routes.ts can import it.
export interface PageNode {
  /** Full URL path; '/' is the index route. */
  path: string;
  /** Route module, relative to app/. */
  file: string;
  /** i18n key (common namespace) for the label. */
  key: string;
  children?: PageNode[];
}

export const PAGES: PageNode[] = [
  { path: '/', file: 'routes/_index.tsx', key: 'nav.home' },
  { path: '/styleguide', file: 'routes/styleguide.tsx', key: 'nav.styleguide' },
];
