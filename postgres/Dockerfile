# Custom postgres image: timescale/timescaledb + the reconcile wrapper that
# applies postgres/scripts/reconcile-roles.sql on every container start.
# See postgres/scripts/entrypoint.sh for the wrapper's rationale and
# docs/guides/env-wiring.md for the env contract.
#
# Why a custom image instead of a bind-mount: the production target is
# Dokploy, which renders the compose YAML on the server with no access
# to the repo's `postgres/scripts/` directory. Baking the scripts into
# the image keeps prod and dev on the same mechanism.

FROM timescale/timescaledb:latest-pg17

COPY scripts/entrypoint.sh /scripts/entrypoint.sh
COPY scripts/reconcile-roles.sql /scripts/reconcile-roles.sql
RUN chmod +x /scripts/entrypoint.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["postgres"]
