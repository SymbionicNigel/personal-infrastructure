import { render } from '@testing-library/react';
import { createInstance } from 'i18next';
import type { ReactElement } from 'react';
import { I18nextProvider, initReactI18next } from 'react-i18next';
import i18nConfig from '~/i18n';
import resources from '~/locales';

// A synchronously-ready i18next instance (resources bundled) for component tests.
function makeI18n() {
  const instance = createInstance();
  instance.use(initReactI18next).init({
    ...i18nConfig,
    lng: 'en',
    resources,
    initAsync: false,
    react: { useSuspense: false },
  });
  return instance;
}

/** Render a component wrapped in a ready I18nextProvider. */
export function renderWithI18n(ui: ReactElement) {
  return render(<I18nextProvider i18n={makeI18n()}>{ui}</I18nextProvider>);
}
