import { useTranslation } from 'react-i18next';
import { useLocation } from 'react-router';
import { PAGES, type PageNode } from '~/nav';

export interface BreadcrumbItem {
  to: string;
  label: string;
  current: boolean;
}

export interface BreadcrumbLevel {
  /** Siblings selectable at this level; the active one is `current`. */
  items: BreadcrumbItem[];
}

/** The active node at a level: exact match wins, else the longest path prefix. */
function pickActive(level: PageNode[], pathname: string): PageNode | undefined {
  let best: PageNode | undefined;
  for (const node of level) {
    if (node.path === pathname) return node;
    const prefix = node.path === '/' ? '/' : `${node.path}/`;
    if (pathname.startsWith(prefix) && (!best || node.path.length > best.path.length)) {
      best = node;
    }
  }
  return best;
}

/**
 * Walks the PAGES tree along the current path, producing one level per depth.
 * Each level lists that depth's siblings (for the dropdown), so navigation
 * works at every level. Flat sites yield a single level (the top-level pages).
 */
export function useBreadcrumbs(): BreadcrumbLevel[] {
  const { t } = useTranslation();
  const { pathname } = useLocation();
  // Labels come from the registry's keys (dynamic), so step outside the
  // literal-key type-safety of `t` with a plain string signature.
  const translate = t as unknown as (key: string) => string;

  const levels: BreadcrumbLevel[] = [];
  let nodes: PageNode[] | undefined = PAGES;
  while (nodes && nodes.length > 0) {
    const active = pickActive(nodes, pathname);
    if (!active) break;
    levels.push({
      items: nodes.map((node) => ({
        to: node.path,
        label: translate(node.key),
        current: node.path === active.path,
      })),
    });
    nodes = active.children;
  }
  return levels;
}
