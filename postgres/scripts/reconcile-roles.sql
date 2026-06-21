-- Declarative role and schema state for the application postgres.
-- Run on every postgres start by entrypoint.sh after pg_isready. Each
-- block is idempotent (CREATE-if-absent + ALTER to sync), so reruns are
-- safe and the script is the single source of truth for role state.
--
-- Adding a role:
--   1. Add a POSTGRES_<NAME>_PASSWORD entry to
--      .secrets/.chezmoitemplates/postgres-roles-env.
--   2. Add a `--set=<name>_password="${POSTGRES_<NAME>_PASSWORD}"`
--      binding to entrypoint.sh.
--   3. Add a DO $$ ... END $$ block below referencing :'<name>_password'.
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

-- astarte role: create-if-absent, then sync password + attributes.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'astarte') THEN
    EXECUTE format('CREATE ROLE astarte WITH LOGIN CREATEROLE PASSWORD %L', :'astarte_password');
    RAISE NOTICE 'created role astarte';
  ELSE
    EXECUTE format('ALTER ROLE astarte WITH LOGIN CREATEROLE PASSWORD %L', :'astarte_password');
  END IF;
END
$$;

-- astarte schema: owned by astarte so Alembic migrations create tables
-- under an owner astarte can manage. Created here (not by astarte) so
-- iris_ro grants below have something to attach to on a fresh DB.
CREATE SCHEMA IF NOT EXISTS astarte AUTHORIZATION astarte;

-- iris_ro role: create-if-absent, then sync password.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iris_ro') THEN
    EXECUTE format('CREATE ROLE iris_ro WITH LOGIN PASSWORD %L', :'iris_ro_password');
    RAISE NOTICE 'created role iris_ro';
  ELSE
    EXECUTE format('ALTER ROLE iris_ro WITH LOGIN PASSWORD %L', :'iris_ro_password');
  END IF;
END
$$;

-- iris_ro grants on the astarte schema. USAGE + SELECT on existing tables
-- handles tables astarte has already created; ALTER DEFAULT PRIVILEGES
-- handles every future table astarte creates (Alembic-introduced or
-- otherwise). Run as superuser, FOR ROLE astarte so the default
-- applies to tables astarte will own.
GRANT USAGE ON SCHEMA astarte TO iris_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA astarte TO iris_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE astarte IN SCHEMA astarte
  GRANT SELECT ON TABLES TO iris_ro;
