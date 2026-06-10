import { index, type RouteConfig, route } from '@react-router/dev/routes';

export default [
  index('routes/_index.tsx'),
  route('resume', 'routes/resume.tsx'),
  route('styleguide', 'routes/styleguide.tsx'),
  route('health', 'routes/health.tsx'),
  route('*', 'routes/$.tsx'),
] satisfies RouteConfig;
