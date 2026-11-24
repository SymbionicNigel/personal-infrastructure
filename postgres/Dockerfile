# Custom postgres image: timescale/timescaledb + the reconcile wrapper that
# applies postgres/scripts/reconcile-roles.sql on every container start.
# See postgres/scripts/entrypoint.sh for the wrapper's rationale and
# docs/guides/env-wiring.md for the env contract.
#
# Why a custom image instead of a bind-mount: the production target is
# Dokploy, which renders the compose YAML on the server with no access
# to the repo's `postgres/scripts/` directory. Baking the scripts into
# the image keeps prod and dev on the same mechanism.

FROM timescale/timescaledb:2.32.1-pg17@sha256:2f5e6969faa5cd7f4b075d65f124e30dc50d456b7b807e5c1acd9d51ba7df51c

COPY scripts/entrypoint.sh /scripts/entrypoint.sh
COPY scripts/reconcile-roles.sql /scripts/reconcile-roles.sql
RUN chmod +x /scripts/entrypoint.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["postgres"]
