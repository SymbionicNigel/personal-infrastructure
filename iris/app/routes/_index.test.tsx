import { screen } from '@testing-library/react';
import { expect, test } from 'vitest';
import { renderWithI18n } from '~/test-utils';
import Index from './_index';

test('home page renders the title heading', () => {
  renderWithI18n(<Index />);
  expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('iris');
});
