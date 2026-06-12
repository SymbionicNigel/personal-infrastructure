import { expect, test } from 'vitest';
import { DEFAULT_HEADING_FONT, HEADING_FONTS } from './fonts';

test('the default heading font exists in the registry', () => {
  expect(HEADING_FONTS.map((font) => font.slug)).toContain(DEFAULT_HEADING_FONT);
});

test('heading-font slugs are unique', () => {
  const slugs = HEADING_FONTS.map((font) => font.slug);
  expect(new Set(slugs).size).toBe(slugs.length);
});
