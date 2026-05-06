# PAFF Odoo runtime image
# Versiune pinned + digest SHA pentru imutabilitate garantată.
#
# DO NOT edit manual aici fără verificare digest. Folosește:
#   ./scripts/update-odoo.sh --target <version>
#
# Update procedure: docs/runbooks/upgrade.md
# Pinning policy:   docs/adr/0002-upstream-pinning-policy.md

# Versiune pinned: tag format Odoo official e `19.0-YYYYMMDD` (liniuță, nu punct).
# Update procedure: scripts/update-odoo.sh (NU manual edit aici fără verificare).
#
# Verificare digest:
#   docker pull odoo:${ODOO_VERSION}
#   docker inspect odoo:${ODOO_VERSION} | jq -r '.[0].RepoDigests[]'
ARG ODOO_VERSION=19.0-20260504
ARG ODOO_DIGEST=sha256:5db447482177ca598b97539bc186b61f5f271371ab3a90f3940ecf33b63af7b0

FROM odoo:${ODOO_VERSION}@${ODOO_DIGEST}

USER root

# Locale ro_RO.UTF-8 pentru Romania-specific formatting (date, currency, CIF)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         locales tzdata gettext-base \
    && sed -i -e 's/# ro_RO.UTF-8 UTF-8/ro_RO.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen ro_RO.UTF-8 \
    && update-locale LANG=ro_RO.UTF-8 \
    && ln -fs /usr/share/zoneinfo/Europe/Bucharest /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=ro_RO.UTF-8 \
    LANGUAGE=ro_RO:ro \
    LC_ALL=ro_RO.UTF-8 \
    TZ=Europe/Bucharest

# Dependencies Python suplimentare PAFF
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
