import { Outlet } from 'react-router';
import { Container, styled } from 'styled-system/jsx';
import { surface } from 'styled-system/recipes';
import { HeaderBar } from '~/components/layout/header-bar';

// Shared shell for the content pages: sticky header (with breadcrumb dropdown
// nav attached) + outlet. The flex column fills the viewport so the pistachio
// <main> reaches the bottom even when content is short. The /health resource
// route and the splat 404 sit outside this layout.
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
