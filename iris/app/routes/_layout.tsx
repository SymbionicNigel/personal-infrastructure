import { Outlet } from 'react-router';
import { Container, styled } from 'styled-system/jsx';
import { surface } from 'styled-system/recipes';
import { HeaderBar } from '~/components/layout/header-bar';

// Content shell: sticky header + outlet, in a viewport-filling flex column so
// the pistachio main reaches the bottom. /health and the splat 404 sit outside.
export default function AppLayout() {
  return (
    <styled.div display="flex" flexDirection="column" minH="100dvh">
      <HeaderBar />
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
