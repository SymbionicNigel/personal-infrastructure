import { useEffect, useState } from 'react';
import { Link, useRouteLoaderData } from 'react-router';
import { css } from 'styled-system/css';
import { Box, Container, Flex, styled } from 'styled-system/jsx';
import { BreadCrumbs } from '~/components/layout/bread-crumbs';

// The iris signature: a five-band rainbow rule drawn from the vintage palette.
const RAINBOW = ['#0288d1', '#669fb2', '#87aa7e', '#edbf02', '#e06c21'];

// Header shrinks from TALL (at the top) to SHORT over the first viewport of
// scroll; logo + title interpolate alongside.
const TALL = 132;
const SHORT = 64;

function IrisMark({ size }: { size: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 32 32"
      aria-hidden="true"
      style={{ flexShrink: 0 }}
    >
      <rect width="32" height="32" rx="7" fill="#271e16" />
      <circle cx="16" cy="16" r="14" fill="#e06c21" />
      <circle cx="16" cy="16" r="11" fill="#edbf02" />
      <circle cx="16" cy="16" r="8" fill="#87aa7e" />
      <circle cx="16" cy="16" r="5.2" fill="#669fb2" />
      <circle cx="16" cy="16" r="2.3" fill="#271e16" />
    </svg>
  );
}

export function HeaderBar() {
  const root = useRouteLoaderData('root') as { host?: string } | undefined;
  const host = root?.host ?? 'iris';

  // 0 at the top → 1 once half a viewport has been scrolled (shrinks at 2× rate).
  const [progress, setProgress] = useState(0);
  useEffect(() => {
    let raf = 0;
    const update = () => {
      raf = 0;
      setProgress(Math.min(1, window.scrollY / Math.max(1, window.innerHeight / 2)));
    };
    const onScroll = () => {
      if (!raf) raf = requestAnimationFrame(update);
    };
    update();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      if (raf) cancelAnimationFrame(raf);
    };
  }, []);

  // Round to whole pixels so the per-frame resize doesn't shimmer on subpixels.
  const height = Math.round(TALL - (TALL - SHORT) * progress);
  // Keep the mark + title filling most of the (shrinking) header height.
  const logoSize = Math.round(height * 0.85);
  const titlePx = Math.round(height * 0.78);

  return (
    <styled.header
      position="sticky"
      top="0"
      zIndex="40"
      bg="bg.default"
      borderBottomWidth="1px"
      borderColor="border.default"
    >
      <Flex height="3px" aria-hidden="true">
        {RAINBOW.map((color) => (
          <Box key={color} flex="1" style={{ backgroundColor: color }} />
        ))}
      </Flex>
      <Container maxW="5xl" px="6">
        <Flex align="center" justify="center" style={{ height: `${height}px` }}>
          <Link
            to="/"
            className={css({
              display: 'inline-flex',
              alignItems: 'center',
              gap: '3',
              color: 'fg.default',
            })}
          >
            <IrisMark size={logoSize} />
            <styled.span
              fontFamily="heading"
              lineHeight="1"
              whiteSpace="nowrap"
              style={{ fontSize: `${titlePx}px` }}
            >
              {host}
            </styled.span>
          </Link>
        </Flex>
      </Container>
      {/* Dark breadcrumb row attached to the header bottom (constant height,
          sticks with the header as the masthead shrinks). The masthead's bottom
          centering space supplies the light-brown gap above this dark row. */}
      <styled.div bg="bg.canvas">
        <Container maxW="5xl" px="6">
          <BreadCrumbs />
        </Container>
      </styled.div>
    </styled.header>
  );
}
