import { useTranslation } from 'react-i18next';
import { css, cx } from 'styled-system/css';
import { styled } from 'styled-system/jsx';
import { surface } from 'styled-system/recipes';
import type { Route } from './+types/_index';

export function meta(_: Route.MetaArgs) {
  return [{ title: 'iris' }];
}

// Paper surface (brown bg + paired text) with a card's border/padding.
const card = cx(
  surface({ tone: 'paper' }),
  css({ borderWidth: '1px', borderColor: 'border.default', borderRadius: 'lg', p: '6' }),
);

export default function Index() {
  const { t } = useTranslation();
  return (
    <div className={card}>
      <styled.h1 fontSize="5xl" lineHeight="1.1" mb="3">
        {t('home.title')}
      </styled.h1>
      <styled.p color="fg.muted" fontSize="lg">
        {t('home.intro')}
      </styled.p>
    </div>
  );
}
