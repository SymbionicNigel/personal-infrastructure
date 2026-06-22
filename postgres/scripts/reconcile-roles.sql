-- Declarative role and schema state for the application postgres.
-- Run on every postgres start by entrypoint.sh after pg_isready. Each
-- block is idempotent (CREATE-if-absent + ALTER to sync), so reruns are
-- safe and the script is the single source of truth for role state.
--
-- Pattern: a DO block creates the role at-most-once (suppressing
-- duplicate_object); a following ALTER ROLE always syncs attributes +
-- password. The password lives in an ALTER (not the CREATE) so it can
-- use psql's :'name' substitution -- which does NOT happen inside
-- dollar-quoted strings, so the create path can't reference it.
--
-- Adding a role:
--   1. Add a POSTGRES_<NAME>_PASSWORD entry to
--      .secrets/.chezmoitemplates/postgres-roles-env.
--   2. Add a `--set=<name>_password="${POSTGRES_<NAME>_PASSWORD}"`
--      binding to entrypoint.sh.
--   3. Add a create-then-alter pair below referencing :'<name>_password'.
--
-- Roles owned here:
--   astarte  Owns the `astarte` schema (convention: each service that
--            owns a schema names it after itself). CREATEROLE so the
--            app can spin up per-tenant roles via ALTER ROLE / CREATE
--            ROLE later if multi-tenant routing grows beyond a flat
--            catalog. LOGIN so astarte can connect for Alembic + the
--            runtime DSN.
--   iris_ro  SELECT-only on the `astarte` schema. LOGIN so drizzle-kit
--            (operator's machine, not the iris container) can pull
--            the live schema for TypeScript codegen.
--
-- ON_ERROR_STOP is set by the invoking script (entrypoint.sh passes
-- --set=ON_ERROR_STOP=1), so any error here aborts the entire pass.

-- astarte role
DO $$ BEGIN
  CREATE ROLE astarte WITH LOGIN CREATEROLE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER ROLE astarte WITH LOGIN CREATEROLE PASSWORD :'astarte_password';

-- astarte schema: owned by astarte so Alembic migrations create tables
-- under an owner astarte can manage. Created here (not by astarte) so
-- iris_ro grants below have something to attach to on a fresh DB.
CREATE SCHEMA IF NOT EXISTS astarte AUTHORIZATION astarte;

-- iris_ro role
DO $$ BEGIN
  CREATE ROLE iris_ro WITH LOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER ROLE iris_ro WITH LOGIN PASSWORD :'iris_ro_password';

-- iris_ro grants on the astarte schema. USAGE + SELECT on existing tables
-- handles tables astarte has already created; ALTER DEFAULT PRIVILEGES
-- handles every future table astarte creates (Alembic-introduced or
-- otherwise). Run as superuser, FOR ROLE astarte so the default
-- applies to tables astarte will own.
GRANT USAGE ON SCHEMA astarte TO iris_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA astarte TO iris_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE astarte IN SCHEMA astarte
  GRANT SELECT ON TABLES TO iris_ro;
