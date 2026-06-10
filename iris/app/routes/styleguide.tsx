import type { Route } from "./+types/styleguide";

export function meta(_: Route.MetaArgs) {
  return [{ title: "Styleguide — iris" }];
}

export default function Styleguide() {
  return <h1>Styleguide</h1>;
}
