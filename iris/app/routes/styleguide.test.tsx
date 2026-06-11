import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, test } from 'vitest';
import { HEADING_FONTS } from '~/fonts';
import { renderWithI18n } from '~/test-utils';
import Styleguide from './styleguide';

test('renders a switcher button for every heading font', () => {
  renderWithI18n(<Styleguide />);
  expect(screen.getAllByRole('button')).toHaveLength(HEADING_FONTS.length);
});

test('selecting a font marks it pressed and applies it to <html>', async () => {
  renderWithI18n(<Styleguide />);
  const sacramento = screen.getByRole('button', { name: 'Sacramento' });

  await userEvent.click(sacramento);

  expect(sacramento).toHaveAttribute('aria-pressed', 'true');
  expect(document.documentElement.dataset.headingFont).toBe('sacramento');
});
