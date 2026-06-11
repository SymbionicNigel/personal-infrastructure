import { index, layout, type RouteConfig, route } from '@react-router/dev/routes';
import { PAGES } from './nav';

// Content pages are generated from the shared PAGES registry (see app/nav.ts),
// so the route table and the breadcrumb nav can never drift apart.
export default [
  layout(
    'routes/_layout.tsx',
    PAGES.map((page) => (page.path === '/' ? index(page.file) : route(page.path, page.file))),
  ),
  route('health', 'routes/health.tsx'),
  route('*', 'routes/$.tsx'),
] satisfies RouteConfig;
