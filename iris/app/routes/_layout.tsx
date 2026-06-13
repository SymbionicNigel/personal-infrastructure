import { Outlet } from 'react-router';
import { Container, styled } from 'styled-system/jsx';
import { surface } from 'styled-system/recipes';
import { HeaderBar } from '~/components/layout/header-bar';
import type { Route } from './+types/_layout';

// Header shows domain + TLD, agnostic to any subdomain: keep the last two labels
// (iris.example.com → example.com; localhost stays localhost). Assumes a
// single-label TLD, which covers our domain. Derived here rather than the root
// loader because only the header — which lives in this layout — needs it;
// /health and the splat 404 sit outside and don't.
export function loader({ request }: Route.LoaderArgs) {
  const host = new URL(request.url).hostname.split('.').slice(-2).join('.');
  return { host };
}

// Content shell: sticky header + outlet, in a viewport-filling flex column so
// the pistachio main reaches the bottom. /health and the splat 404 sit outside.
export default function AppLayout({ loaderData }: Route.ComponentProps) {
  return (
    <styled.div display="flex" flexDirection="column" minH="100dvh">
      <HeaderBar host={loaderData.host} />
      <styled.main flex="1" className={surface({ tone: 'pistachio' })}>
        <Container maxW="5xl" px="6">
          <styled.div pt="6" pb="16">
            <Outlet />
          </styled.div>
        </Container>
      </styled.main>
    </styled.div>
  );
}
