import { Menu } from '@ark-ui/react/menu';
import { Portal } from '@ark-ui/react/portal';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router';
import { css, cx } from 'styled-system/css';
import { styled } from 'styled-system/jsx';
import { useBreadcrumbs } from '~/hooks/use-breadcrumbs';

const trigger = css({
  display: 'inline-flex',
  alignItems: 'center',
  gap: '1',
  px: '2',
  py: '0',
  borderRadius: 'sm',
  color: 'fg.muted',
  cursor: 'pointer',
  transition: 'color 0.15s ease, background 0.15s ease',
  _hover: { color: 'fg.default', bg: 'bg.subtle' },
  '&[data-state="open"]': { color: 'fg.default', bg: 'bg.subtle' },
});

const triggerCurrent = css({ color: 'fg.default', fontWeight: 'medium' });

const content = css({
  minWidth: '44',
  py: '1',
  bg: 'bg.default',
  borderWidth: '1px',
  borderColor: 'border.default',
  borderRadius: 'md',
  boxShadow: 'lg',
  zIndex: '50',
  _focusVisible: { outline: 'none' },
});

const item = css({
  display: 'flex',
  alignItems: 'center',
  mx: '1',
  px: '2.5',
  py: '1.5',
  fontSize: 'sm',
  borderRadius: 'sm',
  color: 'fg.muted',
  cursor: 'pointer',
  '&[data-highlighted]': { bg: 'bg.subtle', color: 'fg.default' },
  '&[data-current]': { color: 'vintage.primary', fontWeight: 'medium' },
});

/**
 * Breadcrumb trail where every level is a dropdown of that level's siblings —
 * the site's primary navigation. Trail + siblings come from the PAGES tree via
 * useBreadcrumbs. The negative left margin offsets the first trigger's padding
 * so its text aligns flush with the page content below.
 */
export function BreadCrumbs() {
  const { pathname } = useLocation();
  const navigate = useNavigate();
  const levels = useBreadcrumbs();

  // Close any open dropdown on scroll — Ark only repositions on scroll, which
  // re-anchors to the shrinking header every frame and visibly jitters.
  const [openCrumb, setOpenCrumb] = useState<string | null>(null);
  useEffect(() => {
    const close = () => setOpenCrumb(null);
    window.addEventListener('scroll', close, { passive: true });
    return () => window.removeEventListener('scroll', close);
  }, []);

  if (levels.length === 0) return null;

  return (
    <styled.nav aria-label="Breadcrumb" py="3" ml="-2">
      <styled.ol display="flex" alignItems="center" gap="1" listStyleType="none" fontSize="sm">
        {levels.map((level, i) => {
          const active = level.items.find((entry) => entry.current) ?? level.items[0];
          const isLast = i === levels.length - 1;
          return (
            <styled.li key={active.to} display="inline-flex" alignItems="center" gap="1">
              <Menu.Root
                open={openCrumb === active.to}
                onOpenChange={(details) => setOpenCrumb(details.open ? active.to : null)}
                positioning={{ placement: 'bottom-start', gutter: 4 }}
                onSelect={(details) => {
                  if (details.value !== pathname) navigate(details.value);
                }}
              >
                <Menu.Trigger className={cx(trigger, isLast && triggerCurrent)}>
                  {active.label}
                  <ChevronDown size={14} aria-hidden="true" />
                </Menu.Trigger>
                <Portal>
                  <Menu.Positioner>
                    <Menu.Content className={content}>
                      {level.items.map((entry) => (
                        <Menu.Item
                          key={entry.to}
                          value={entry.to}
                          className={item}
                          data-current={entry.current ? '' : undefined}
                        >
                          {entry.label}
                        </Menu.Item>
                      ))}
                    </Menu.Content>
                  </Menu.Positioner>
                </Portal>
              </Menu.Root>
              {!isLast && (
                <ChevronRight
                  size={14}
                  aria-hidden="true"
                  className={css({ color: 'fg.subtle' })}
                />
              )}
            </styled.li>
          );
        })}
      </styled.ol>
    </styled.nav>
  );
}
