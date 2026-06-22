import { config as loadEnv } from 'dotenv';
import { defineConfig } from 'drizzle-kit';

// Pull-only: iris never touches the DB at runtime. drizzle-kit reads the live
// schema (after astarte's migrations have applied) and emits TypeScript types
// into app/generated/db.ts. CI fails on drift between regenerated and
// committed.
//
// DATABASE_URL is sourced from compose/.env.iris.typegen, rendered by chezmoi
// and gitignored. The file holds the iris_ro DSN and is intentionally NOT
// mounted into the iris container — iris has no runtime DB consumer; typegen
// is an operator/CI-time tool. See docs/guides/env-wiring.md.
loadEnv({ path: '../compose/.env.iris.typegen' });

export default defineConfig({
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL ?? '' },
  out: 'app/generated',
  schemaFilter: ['astarte'],
});
