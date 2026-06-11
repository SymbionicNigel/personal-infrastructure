import { index, layout, type RouteConfig, route } from '@react-router/dev/routes';
import { PAGES } from './nav';

// Content routes are generated from the shared PAGES registry (app/nav.ts).
export default [
  layout(
    'routes/_layout.tsx',
    PAGES.map((page) => (page.path === '/' ? index(page.file) : route(page.path, page.file))),
  ),
  route('health', 'routes/health.tsx'),
  route('*', 'routes/$.tsx'),
] satisfies RouteConfig;
