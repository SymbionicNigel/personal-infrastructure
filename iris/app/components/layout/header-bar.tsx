import { Link } from 'react-router';
import { sva } from 'styled-system/css';
import { Box, Container, Flex, styled } from 'styled-system/jsx';
import { BreadCrumbs } from '~/components/layout/bread-crumbs';

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
// interpolates --mh-tall → --mh-short by --mh-progress; a scroll-driven CSS
// animation moves --mh-progress 0→1 over the first half-viewport of scroll.
// Logo + title derive from that height in CSS.
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
      // Decorative shrink. Browsers without scroll-driven animations (Firefox)
      // keep --mh-progress at its registered 0 and render the tall masthead.
      '@supports ((animation-timeline: scroll()) and (animation-range: 0% 100%))':
        {
          animation: 'iris-mh-shrink auto linear both',
          animationTimeline: 'scroll(block root)',
          animationRange: '0 50vh',
        },
      '@media (prefers-reduced-motion: reduce)': {
        animation: 'none',
      },
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
        <rect width="32" height="32" rx="7" style={{ fill: 'var(--colors-vintage-bg)' }} />
        <circle cx="16" cy="16" r="14" style={{ fill: 'var(--colors-vintage-error)' }} />
        <circle cx="16" cy="16" r="11" style={{ fill: 'var(--colors-vintage-warning)' }} />
        <circle cx="16" cy="16" r="8" style={{ fill: 'var(--colors-vintage-secondary)' }} />
        <circle cx="16" cy="16" r="5.2" style={{ fill: 'var(--colors-vintage-primary)' }} />
        <circle cx="16" cy="16" r="2.3" style={{ fill: 'var(--colors-vintage-bg)' }} />
      </svg>
    </Box>
  );
}

export function HeaderBar({ host }: { host: string }) {
  const title = titleCaseHost(host);
  const ui = masthead();

  return (
    <header className={ui.root}>
      {/* The iris signature: a five-band rainbow rule from the vintage palette. */}
      <Flex height="3px" aria-hidden="true">
        <Box flex="1" bg="vintage.info" />
        <Box flex="1" bg="vintage.primary" />
        <Box flex="1" bg="vintage.secondary" />
        <Box flex="1" bg="vintage.warning" />
        <Box flex="1" bg="vintage.error" />
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
