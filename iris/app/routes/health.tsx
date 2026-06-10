// Resource route (no default export): plain 200 for Traefik + container healthchecks.
export function loader() {
  return new Response('OK', {
    status: 200,
    headers: { 'content-type': 'text/plain' },
  });
}
