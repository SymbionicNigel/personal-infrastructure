// Heading-font registry for the styleguide switcher. Slugs match the CSS vars
// (--font-<slug>) + @font-face in app/styles/app.css and the files synced by
// scripts/sync-fonts.mjs. Ordered with the default first.
export interface HeadingFont {
  slug: string;
  label: string;
}

export const HEADING_FONTS: HeadingFont[] = [
  { slug: 'yellowtail', label: 'Yellowtail' },
  { slug: 'sacramento', label: 'Sacramento' },
  { slug: 'kaushan-script', label: 'Kaushan Script' },
  { slug: 'grand-hotel', label: 'Grand Hotel' },
  { slug: 'aladin', label: 'Aladin' },
  { slug: 'freckle-face', label: 'Freckle Face' },
];

export const DEFAULT_HEADING_FONT = 'yellowtail';
