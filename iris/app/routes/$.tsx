import type { Route } from "./+types/$";

export function loader() {
  // Render the branded 404 with a real 404 status via the ErrorBoundary.
  throw new Response("Not Found", { status: 404 });
}

export function meta(_: Route.MetaArgs) {
  return [{ title: "404 — iris" }];
}

export default function Splat() {
  return null;
}
