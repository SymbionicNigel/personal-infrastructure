import { useEffect, useState } from 'react';
import { Link } from 'react-router';
import { sva } from 'styled-system/css';
import { Box, Container, Flex, styled } from 'styled-system/jsx';
import { BreadCrumbs } from '~/components/layout/bread-crumbs';

// The iris signature: a five-band rainbow rule drawn from the vintage palette.
const RAINBOW = ['#0288d1', '#669fb2', '#87aa7e', '#edbf02', '#e06c21'];

// Display-only: capitalize the first character of every dot-separated label
// (example.com → Example.Com). The host stays raw in the loader.
export function titleCaseHost(host: string): string {
  return host
    .split('.')
    .map((label) => (label ? label[0].toUpperCase() + label.slice(1) : label))
    .join('.');
}

// Masthead geometry as a Panda slot recipe: `base` is the phone size, `md` the
// desktop size (default breakpoints — no panda.config change). The row height
// interpolates --mh-tall → --mh-short by --mh-progress, the only runtime value,
// which JS sets from scroll; logo + title derive from that height in CSS.
const masthead = sva({
  slots: ['root', 'row', 'link', 'logo', 'title'],
  base: {
    root: {
      '--mh-tall': { base: '88px', md: '132px' },
      '--mh-short': { base: '56px', md: '64px' },
      '--mh-h': 'calc(var(--mh-tall) - (var(--mh-tall) - var(--mh-short)) * var(--mh-progress))',
      position: 'sticky',
      top: '0',
      zIndex: '40',
      bg: 'bg.default',
      borderBottomWidth: '1px',
      borderColor: 'border.default',
    },
    row: {
      display: 'flex',
      alignItems: 'center',
      // Left-aligned on phones (per design), centered from md up.
      justifyContent: { base: 'flex-start', md: 'center' },
      minWidth: '0',
      // minHeight (not height) so the masthead can grow when the icon + title
      // wrap to two lines on a narrow screen rather than overflowing.
      minHeight: 'var(--mh-h)',
      // Pull back half the Container's px="6" gutter on phones so the icon sits
      // near the edge with a little padding; restored to aligned-with-content
      // from md up.
      marginLeft: { base: '-3', md: '0' },
    },
    link: {
      display: 'inline-flex',
      alignItems: 'center',
      // Wrap the icon + title as whole units when they don't fit one line; the
      // title keeps white-space:nowrap so the domain text itself never breaks.
      flexWrap: 'wrap',
      gap: '3',
      minWidth: '0',
      color: 'fg.default',
    },
    logo: { boxSize: 'calc(var(--mh-h) * 0.85)', flexShrink: 0 },
    title: {
      fontFamily: 'heading',
      lineHeight: '1',
      whiteSpace: 'nowrap',
      // Proportional to the masthead height so it tracks the icon; sits at 0.78×
      // the row height at both breakpoints (which differ via --mh-tall/short).
      fontSize: 'calc(var(--mh-h) * 0.78)',
    },
  },
});

function IrisMark({ className }: { className?: string }) {
  return (
    <Box className={className}>
      <svg
        viewBox="0 0 32 32"
        aria-hidden="true"
        style={{ width: '100%', height: '100%', display: 'block' }}
      >
        <rect width="32" height="32" rx="7" fill="#271e16" />
        <circle cx="16" cy="16" r="14" fill="#e06c21" />
        <circle cx="16" cy="16" r="11" fill="#edbf02" />
        <circle cx="16" cy="16" r="8" fill="#87aa7e" />
        <circle cx="16" cy="16" r="5.2" fill="#669fb2" />
        <circle cx="16" cy="16" r="2.3" fill="#271e16" />
      </svg>
    </Box>
  );
}

export function HeaderBar({ host }: { host: string }) {
  const title = titleCaseHost(host);
  const ui = masthead();

  // 0 at the top → 1 once half a viewport has scrolled (shrinks at 2× rate).
  // Client-only; SSR seeds 0 (tall), corrected on mount.
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

  return (
    <header className={ui.root} style={{ '--mh-progress': progress } as React.CSSProperties}>
      <Flex height="3px" aria-hidden="true">
        {RAINBOW.map((color) => (
          <Box key={color} flex="1" style={{ backgroundColor: color }} />
        ))}
      </Flex>
      <Container maxW="5xl" px="6">
        <div className={ui.row}>
          <Link to="/" className={ui.link}>
            <IrisMark className={ui.logo} />
            <span className={ui.title}>{title}</span>
          </Link>
        </div>
      </Container>
      {/* Dark breadcrumb row attached to the header bottom (constant height,
          sticks with the header as the masthead shrinks). The masthead's bottom
          centering space supplies the light-brown gap above this dark row. */}
      <styled.div bg="bg.canvas">
        <Container maxW="5xl" px="6">
          <BreadCrumbs />
        </Container>
      </styled.div>
    </header>
  );
}
