import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { css, cx } from 'styled-system/css';
import { Box, Stack, styled, Wrap } from 'styled-system/jsx';
import { surface } from 'styled-system/recipes';
import { headingFontCookie } from '~/cookies';
import { DEFAULT_HEADING_FONT, HEADING_FONTS } from '~/fonts';
import type { Route } from './+types/styleguide';

export function meta(_: Route.MetaArgs) {
  return [{ title: 'Styleguide — iris' }];
}

const card = cx(
  surface({ tone: 'paper' }),
  css({ borderWidth: '1px', borderColor: 'border.default', borderRadius: 'lg', p: '6' }),
);

const sectionTitle = css({
  fontFamily: 'body',
  fontWeight: 'semibold',
  fontSize: 'xl',
  mb: '1',
});

const fontButton = css({
  px: '4',
  py: '3',
  fontSize: '2xl',
  lineHeight: '1',
  color: 'fg.default',
  bg: 'bg.subtle',
  borderWidth: '1px',
  borderColor: 'border.default',
  borderRadius: 'md',
  cursor: 'pointer',
  transition: 'border-color 0.15s ease, color 0.15s ease, background 0.15s ease',
  _hover: { borderColor: 'vintage.primary', bg: 'bg.muted' },
});

const fontButtonActive = css({
  borderColor: 'vintage.primary',
  color: 'vintage.primary',
  boxShadow: '0 0 0 1px var(--colors-vintage-primary)',
});

const copyButton = css({
  fontSize: 'xs',
  fontFamily: 'mono',
  px: '2',
  py: '1',
  borderWidth: '1px',
  borderColor: 'border.default',
  borderRadius: 'sm',
  cursor: 'pointer',
  bg: 'bg.muted',
  color: 'fg.muted',
  _hover: { borderColor: 'vintage.primary', color: 'vintage.primary' },
});


// Web features we use that aren't yet on-by-default in every modern browser.
// Each entry pairs a `CSS.supports` probe with per-browser enable instructions
// so the page can show live status and a one-click pref copy when relevant.
// Display strings (name, usedFor) live in the locale files under
// `styleguide.features.<id>.{name,usedFor}` so they stay translatable.
const BROWSER_FEATURES = [
  {
    id: 'scroll-driven-animations',
    supportsQuery: '(animation-timeline: scroll()) and (animation-range: 0% 100%)',
    firefoxPref: 'layout.css.scroll-driven-animations.enabled',
  },
] as const;

// Sourced from the `vintage.*` Panda tokens via CSS variables so the displayed
// hex always matches the actual token value — no manual sync.
const PALETTE = [
  'bg',
  'paper',
  'ink',
  'primary',
  'pistachio',
  'warning',
  'error',
  'info',
  'success',
  'divider',
] as const;

function rgbStringToHex(rgb: string): string {
  const m = rgb.match(/\d+/g);
  if (!m) return rgb;
  return `#${m
    .slice(0, 3)
    .map((n) => Number(n).toString(16).padStart(2, '0'))
    .join('')}`;
}

export default function Styleguide() {
  const { t } = useTranslation();
  const [active, setActive] = useState(DEFAULT_HEADING_FONT);
  // Resolved hex per palette token, probed from the live CSS vars. Re-runs on
  // every render and only commits state when a value changes — that way HMR
  // token swaps (Panda config edits) propagate into the caption after one
  // extra render, without a polling loop.
  const [paletteHex, setPaletteHex] = useState<Record<string, string>>({});
  useEffect(() => {
    const probe = document.createElement('div');
    document.body.appendChild(probe);
    const next: Record<string, string> = {};
    for (const name of PALETTE) {
      probe.style.color = `var(--colors-vintage-${name})`;
      next[name] = rgbStringToHex(getComputedStyle(probe).color);
    }
    document.body.removeChild(probe);
    setPaletteHex((prev) => {
      const same =
        Object.keys(next).length === Object.keys(prev).length &&
        Object.keys(next).every((k) => prev[k] === next[k]);
      return same ? prev : next;
    });
  });

  // null while SSR / before mount; per-feature true/false after we probe.
  const [featureSupport, setFeatureSupport] = useState<Record<string, boolean> | null>(null);
  // 'unknown' until detection runs (covers SSR + browsers we don't single out).
  const [browser, setBrowser] = useState<'firefox' | 'chromium' | 'edge' | 'unknown'>('unknown');
  // Bottom-left toast that briefly confirms a clipboard write. Keyed so re-
  // copying the same string still re-triggers the auto-dismiss timer.
  const [toast, setToast] = useState<{ text: string; key: number } | null>(null);
  useEffect(() => {
    if (!toast) return;
    const id = setTimeout(() => setToast(null), 1800);
    return () => clearTimeout(id);
  }, [toast]);
  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard?.writeText(text);
      setToast({ text, key: Date.now() });
    } catch {
      // Clipboard write can reject (insecure context, permissions); stay quiet.
    }
  };

  // Reflect the font already applied site-wide (rendered onto <html> from the
  // cookie in the root loader).
  useEffect(() => {
    setActive(document.documentElement.dataset.headingFont ?? DEFAULT_HEADING_FONT);
  }, []);

  // Feature-detect (SSR has no window.CSS / navigator; jsdom lacks
  // CSS.supports). Anything unknowable counts as "unsupported" — fine because
  // the UI just nudges users to enable a flag, never the other way around.
  // Re-probes on every render so HMR additions to BROWSER_FEATURES propagate;
  // state is only committed when the map actually changes.
  useEffect(() => {
    const supports =
      typeof CSS !== 'undefined' && typeof CSS.supports === 'function'
        ? (q: string) => CSS.supports(q)
        : () => false;
    const next = Object.fromEntries(
      BROWSER_FEATURES.map((f) => [f.id, supports(f.supportsQuery)]),
    );
    setFeatureSupport((prev) => {
      if (prev === null) return next;
      const sameKeys =
        Object.keys(next).length === Object.keys(prev).length &&
        Object.keys(next).every((k) => prev[k] === next[k]);
      return sameKeys ? prev : next;
    });
    const ua = navigator.userAgent;
    const detected = /firefox/i.test(ua)
      ? 'firefox'
      : /edg\//i.test(ua)
        ? 'edge'
        : /chrome|chromium/i.test(ua)
          ? 'chromium'
          : 'unknown';
    setBrowser((prev) => (prev === detected ? prev : detected));
  });

  // Browsers block direct web-page navigation to about:/chrome:/edge: URLs, so
  // the button copies the URL to the clipboard and the user pastes it into the
  // address bar — the only honest UX here.
  const configUrl =
    browser === 'firefox'
      ? 'about:config'
      : browser === 'edge'
        ? 'edge://flags'
        : browser === 'chromium'
          ? 'chrome://flags'
          : null;

  const choose = (slug: string) => {
    setActive(slug);
    // Apply live, and persist via cookie so it's restored SSR-side next load.
    document.documentElement.dataset.headingFont = slug;
    headingFontCookie.serialize(slug).then((cookie) => {
      // biome-ignore lint/suspicious/noDocumentCookie: cross-browser cookie write; CookieStore lacks Safari/Firefox support
      document.cookie = cookie;
    });
  };

  return (
    <Stack gap="10">
      <Box>
        <styled.h1 fontSize="5xl" lineHeight="1.1" mb="2">
          {t('styleguide.title')}
        </styled.h1>
        <styled.p fontSize="lg" maxW="2xl">
          {t('styleguide.intro')}
        </styled.p>
      </Box>

      <styled.section className={card}>
        <styled.h2 className={sectionTitle}>{t('styleguide.headingFont')}</styled.h2>
        <styled.p color="fg.muted" fontSize="sm" mb="4">
          {t('styleguide.headingFontIntro')}
        </styled.p>
        <Wrap gap="3" role="group" aria-label="Heading font">
          {HEADING_FONTS.map((font) => (
            <button
              key={font.slug}
              type="button"
              onClick={() => choose(font.slug)}
              aria-pressed={active === font.slug}
              className={cx(fontButton, active === font.slug && fontButtonActive)}
              style={{ fontFamily: `var(--font-${font.slug})` }}
            >
              {font.label}
            </button>
          ))}
        </Wrap>
      </styled.section>

      <styled.section className={card}>
        <styled.h2 className={sectionTitle} mb="4">
          {t('styleguide.palette')}
        </styled.h2>
        <Wrap gap="4">
          {PALETTE.map((name) => (
            <Box key={name} width="28">
              <Box
                height="16"
                borderRadius="md"
                borderWidth="1px"
                borderColor="border.default"
                style={{ backgroundColor: `var(--colors-vintage-${name})` }}
              />
              <styled.p mt="2" fontSize="sm" fontWeight="medium">
                {name}
              </styled.p>
              <styled.p fontSize="xs" color="fg.muted" fontFamily="mono">
                {paletteHex[name] ?? '…'}
              </styled.p>
            </Box>
          ))}
        </Wrap>
      </styled.section>

      <styled.section className={card}>
        <styled.h2 className={sectionTitle} mb="1">
          {t('styleguide.browserFeatures.title')}
        </styled.h2>
        <styled.p color="fg.muted" fontSize="sm" mb="6">
          {t('styleguide.browserFeatures.intro')}
          {configUrl && (
            <>
              {' '}
              {t('styleguide.browserFeatures.configHintPrefix')}{' '}
              <styled.code fontFamily="mono" color="fg.default">
                {configUrl}
              </styled.code>{' '}
              {t('styleguide.browserFeatures.configHintSuffix')}
            </>
          )}
        </styled.p>
        {/* Each row has a top divider; the trailing border on the outer wrapper
            closes the list. Adjacent rows share the same hairline — no dupes. */}
        <Box borderBottomWidth="1px" borderColor="border.default">
          {BROWSER_FEATURES.map((f) => {
            const supported = featureSupport?.[f.id] ?? null;
            const showFirefoxHint = browser === 'firefox' && supported === false;
            const statusWord = t(
              `styleguide.status.${
                supported === null ? 'detecting' : supported ? 'on' : 'off'
              }`,
            );
            const statusToken =
              supported === null
                ? 'fg.muted'
                : supported
                  ? 'vintage.success'
                  : 'vintage.error';
            const statusVar = `var(--colors-${statusToken.replace('.', '-')})`;
            const copy = (
              <button
                type="button"
                onClick={() => copyToClipboard(f.firefoxPref)}
                className={copyButton}
              >
                ⧉ {t('styleguide.copy')}
              </button>
            );

            return (
              <Box
                key={f.id}
                pt="3"
                pb="4"
                borderTopWidth="1px"
                borderColor="border.default"
              >
                {/* Title row with dotted ledger leader between title and chip. */}
                <Box display="flex" alignItems="baseline" gap="3">
                  <styled.span fontWeight="medium">
                    {t(`styleguide.features.${f.id}.name`)}
                  </styled.span>
                  <Box
                    flex="1"
                    borderBottomWidth="2px"
                    borderBottomStyle="dotted"
                    borderColor="border.default"
                    minW="8"
                  />
                  <Box
                    display="inline-flex"
                    alignItems="center"
                    gap="2"
                    borderWidth="1px"
                    borderRadius="sm"
                    px="2.5"
                    py="1.5"
                    style={{
                      borderColor: statusVar,
                      // Soft tint of the status colour over the card paper so
                      // the chip lifts off the surface without going opaque.
                      backgroundColor: `color-mix(in srgb, ${statusVar} 15%, var(--colors-bg-default))`,
                    }}
                  >
                    <Box
                      width="2"
                      height="2"
                      borderRadius="full"
                      style={{ backgroundColor: statusVar }}
                    />
                    <styled.span
                      fontSize="xs"
                      fontWeight="bold"
                      textTransform="uppercase"
                      letterSpacing="wider"
                      lineHeight="1"
                      style={{ color: statusVar }}
                    >
                      {statusWord}
                    </styled.span>
                  </Box>
                </Box>

                <styled.p mt="2" fontSize="sm" color="fg.muted">
                  {t(`styleguide.features.${f.id}.usedFor`)}
                </styled.p>

                {/* Firefox-only pref hint: indented arrow + dark code-canvas
                    slot containing the pref name and the copy button. */}
                {showFirefoxHint && (
                  <Box mt="3" pl="6" display="flex" alignItems="center" gap="2">
                    <styled.span color="fg.muted" lineHeight="1">
                      ⤷
                    </styled.span>
                    <Box
                      flex="1"
                      bg="bg.canvas"
                      borderRadius="sm"
                      px="3"
                      py="2"
                      display="flex"
                      alignItems="center"
                      gap="3"
                      minW="0"
                    >
                      <styled.code fontFamily="mono" fontSize="sm" flex="1" minW="0" overflow="hidden" textOverflow="ellipsis" whiteSpace="nowrap">
                        {f.firefoxPref}
                      </styled.code>
                      {copy}
                    </Box>
                  </Box>
                )}
              </Box>
            );
          })}
        </Box>
      </styled.section>

      {toast && (
        <Box
          key={toast.key}
          position="fixed"
          bottom="6"
          left="6"
          zIndex="50"
          px="4"
          py="3"
          borderRadius="md"
          borderWidth="1px"
          borderColor="vintage.primary"
          bg="bg.default"
          boxShadow="lg"
          display="flex"
          alignItems="center"
          gap="3"
          maxW="sm"
          role="status"
          aria-live="polite"
          animation="iris-toast-in 1800ms ease-out forwards"
        >
          <styled.span fontSize="sm" color="vintage.primary" fontWeight="medium">
            {t('styleguide.copied')}
          </styled.span>
          <styled.code fontFamily="mono" fontSize="xs" color="fg.muted" overflow="hidden" textOverflow="ellipsis" whiteSpace="nowrap" minW="0">
            {toast.text}
          </styled.code>
        </Box>
      )}

      <styled.section className={card}>
        <styled.h2 className={sectionTitle} mb="4">
          {t('styleguide.type')}
        </styled.h2>
        <Stack gap="4">
          <styled.p fontFamily="heading" fontSize="6xl" lineHeight="1">
            {t('styleguide.typeDisplay')}
          </styled.p>
          <styled.p fontSize="md" color="fg.muted" maxW="2xl">
            {t('styleguide.typeBody')}
          </styled.p>
          <styled.code fontFamily="mono" fontSize="sm" color="fg.muted">
            const mono = "ui-monospace, SFMono-Regular, Menlo";
          </styled.code>
        </Stack>
      </styled.section>
    </Stack>
  );
}
