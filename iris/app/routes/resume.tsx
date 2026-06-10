import type { Route } from './+types/resume';

export function meta(_: Route.MetaArgs) {
  return [{ title: 'Resume — iris' }];
}

export default function Resume() {
  return <h1>Resume</h1>;
}
