// Single source of truth for the site's pages, as a tree. This drives BOTH the
// route table (app/routes.ts builds from it) and the breadcrumb dropdown nav
// (via the useBreadcrumbs hook), so they can never drift apart. Pure data only
// (no React imports) so it's safe to import from the build-time routes.ts.
//
// `children` nests routes; the breadcrumb shows each level's siblings, so
// adding nested pages here lights up deeper crumbs automatically.
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
  { path: '/resume', file: 'routes/resume.tsx', key: 'nav.resume' },
  { path: '/styleguide', file: 'routes/styleguide.tsx', key: 'nav.styleguide' },
];
