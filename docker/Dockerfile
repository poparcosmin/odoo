# PAFF Odoo runtime image
# Versiune pinned + digest SHA pentru imutabilitate garantată.
#
# DO NOT edit manual aici fără verificare digest. Folosește:
#   ./scripts/update-odoo.sh --target <version>
#
# Update procedure: docs/runbooks/upgrade.md
# Pinning policy:   docs/adr/0002-upstream-pinning-policy.md

# TODO la primul build: înlocuiește <PIN-AT-FIRST-BUILD> cu output-ul real:
#   docker pull odoo:19.0
#   docker inspect odoo:19.0 | jq -r '.[0].RepoDigests[0]'
ARG ODOO_VERSION=19.0
ARG ODOO_DIGEST=sha256:PIN-AT-FIRST-BUILD-VEZI-RUNBOOK

FROM odoo:${ODOO_VERSION}@${ODOO_DIGEST}

USER root

# Dependencies suplimentare PAFF (verificate cu /vibe-debt-audit)
# uuid-utils: generare UUID v7 pentru chei externe stabile
# qrcode[pil]: QR pe facturi e-Factura SPV
RUN pip install --no-cache-dir --break-system-packages \
      uuid-utils \
      "qrcode[pil]"

# Aplicare patches (Layer 2 din Three-Layer Isolation)
# Vezi patches/README.md pentru convenția NNNN-titlu.patch
COPY patches/ /opt/paff-patches/
COPY docker/entrypoint.sh /opt/paff-entrypoint.sh
COPY docker/healthcheck.sh /opt/paff-healthcheck.sh
RUN chmod +x /opt/paff-entrypoint.sh /opt/paff-healthcheck.sh

USER odoo

ENTRYPOINT ["/opt/paff-entrypoint.sh"]
CMD ["odoo"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD /opt/paff-healthcheck.sh
