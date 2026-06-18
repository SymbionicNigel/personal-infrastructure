// Heading-font registry for the styleguide switcher. Slugs match the CSS vars
// (--font-<slug>) + @font-face in app/styles/app.css and the files synced by
// scripts/sync-fonts.mjs. Ordered alphabetically by label.
export interface HeadingFont {
  slug: string;
  label: string;
}

export const HEADING_FONTS: HeadingFont[] = [
  { slug: 'aladin', label: 'Aladin' },
  { slug: 'freckle-face', label: 'Freckle Face' },
  { slug: 'grand-hotel', label: 'Grand Hotel' },
  { slug: 'kaushan-script', label: 'Kaushan Script' },
  { slug: 'sacramento', label: 'Sacramento' },
  { slug: 'yellowtail', label: 'Yellowtail' },
];

export const DEFAULT_HEADING_FONT = 'aladin';
