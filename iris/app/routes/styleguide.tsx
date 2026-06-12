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

const PALETTE = [
  { name: 'bg', hex: '#271e16' },
  { name: 'paper', hex: '#31281d' },
  { name: 'ink', hex: '#1c3a4a' },
  { name: 'primary', hex: '#669fb2' },
  { name: 'pistachio', hex: '#87aa7e' },
  { name: 'warning', hex: '#edbf02' },
  { name: 'error', hex: '#e06c21' },
  { name: 'info', hex: '#0288d1' },
  { name: 'success', hex: '#005427' },
];

export default function Styleguide() {
  const { t } = useTranslation();
  const [active, setActive] = useState(DEFAULT_HEADING_FONT);

  // Reflect the font already applied site-wide (rendered onto <html> from the
  // cookie in the root loader).
  useEffect(() => {
    setActive(document.documentElement.dataset.headingFont ?? DEFAULT_HEADING_FONT);
  }, []);

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
          Pick a face — it sets the heading font across the whole site (and is remembered).
        </styled.p>
        <Wrap gap="3">
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
          Palette
        </styled.h2>
        <Wrap gap="4">
          {PALETTE.map((color) => (
            <Box key={color.name} width="28">
              <Box
                height="16"
                borderRadius="md"
                borderWidth="1px"
                borderColor="border.default"
                style={{ backgroundColor: color.hex }}
              />
              <styled.p mt="2" fontSize="sm" fontWeight="medium">
                {color.name}
              </styled.p>
              <styled.p fontSize="xs" color="fg.muted" fontFamily="mono">
                {color.hex}
              </styled.p>
            </Box>
          ))}
        </Wrap>
      </styled.section>

      <styled.section className={card}>
        <styled.h2 className={sectionTitle} mb="4">
          Type
        </styled.h2>
        <Stack gap="4">
          <styled.p fontFamily="heading" fontSize="6xl" lineHeight="1">
            The visible link
          </styled.p>
          <styled.p fontSize="md" color="fg.muted" maxW="2xl">
            Body copy is set in Space Grotesk — the quick brown fox jumps over the lazy dog.
            0123456789
          </styled.p>
          <styled.code fontFamily="mono" fontSize="sm" color="fg.muted">
            const mono = "ui-monospace, SFMono-Regular, Menlo";
          </styled.code>
        </Stack>
      </styled.section>
    </Stack>
  );
}
