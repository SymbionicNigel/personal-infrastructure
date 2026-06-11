import { useTranslation } from 'react-i18next';
import { isRouteErrorResponse, Link } from 'react-router';
import { css } from 'styled-system/css';
import { Box, Flex, styled } from 'styled-system/jsx';

const RAINBOW = ['#0288d1', '#669fb2', '#87aa7e', '#edbf02', '#e06c21'];

const backHome = css({
  display: 'inline-flex',
  alignItems: 'center',
  px: '5',
  py: '2.5',
  fontWeight: 'medium',
  color: 'vintage.bg',
  bg: 'vintage.primary',
  borderRadius: 'md',
  transition: 'opacity 0.15s ease',
  _hover: { opacity: 0.9 },
});

/**
 * Branded full-page error/404 view. Drop into any route's ErrorBoundary:
 *   export function ErrorBoundary({ error }: Route.ErrorBoundaryProps) {
 *     return <ErrorPage error={error} />;
 *   }
 */
export function ErrorPage({ error }: { error: unknown }) {
  const { t } = useTranslation();
  const is404 = isRouteErrorResponse(error) && error.status === 404;

  let title = t('notFound.title');
  let message = t('notFound.message');
  let stack: string | undefined;

  if (!is404) {
    if (isRouteErrorResponse(error)) {
      title = String(error.status);
      message = error.statusText || 'Something went wrong.';
    } else {
      title = 'Error';
      message = 'Something went wrong.';
      if (import.meta.env.DEV && error instanceof Error) {
        message = error.message;
        stack = error.stack;
      }
    }
  }

  return (
    <Flex
      direction="column"
      align="center"
      justify="center"
      minH="100dvh"
      gap="6"
      px="6"
      textAlign="center"
    >
      <Flex gap="1.5" aria-hidden="true">
        {RAINBOW.map((color) => (
          <Box
            key={color}
            width="8"
            height="1.5"
            borderRadius="full"
            style={{ backgroundColor: color }}
          />
        ))}
      </Flex>
      <styled.h1 fontFamily="heading" fontSize="9xl" lineHeight="1" color="vintage.primary">
        {title}
      </styled.h1>
      <styled.p fontSize="lg" color="fg.muted" maxW="md">
        {message}
      </styled.p>
      <Link to="/" className={backHome}>
        Back home
      </Link>
      {stack && (
        <styled.pre
          mt="4"
          maxW="3xl"
          overflowX="auto"
          textAlign="left"
          fontSize="xs"
          color="fg.subtle"
        >
          <code>{stack}</code>
        </styled.pre>
      )}
    </Flex>
  );
}
