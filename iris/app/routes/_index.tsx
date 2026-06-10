import type { Route } from './+types/_index';

export function meta(_: Route.MetaArgs) {
  return [{ title: 'iris' }];
}

export default function Index() {
  return <h1>iris</h1>;
}
