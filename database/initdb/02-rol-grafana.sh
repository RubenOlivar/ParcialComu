#!/bin/bash
# =============================================================================
#  Parcial 2 practico - Comunicaciones (UMNG)
#  Crea el rol de SOLO LECTURA que utiliza Grafana como datasource.
#
#  Principio de minimo privilegio: Grafana nunca se conecta con el superusuario
#  del CMS; usa un rol sin permisos de escritura que solo puede consultar las
#  vistas del esquema "observabilidad", las tablas de Joomla y las estadisticas
#  del motor (rol predefinido pg_monitor).
#
#  Se ejecuta una unica vez, durante la inicializacion del cluster.
# =============================================================================
set -euo pipefail

ROL="${GRAFANA_DB_USER:-grafana_ro}"
CLAVE="${GRAFANA_DB_PASSWORD:-Comm2026_GrafanaRO}"

echo "[initdb] Creando rol de solo lectura '${ROL}' para Grafana..."

psql -v ON_ERROR_STOP=1 \
     --username "${POSTGRES_USER}" \
     --dbname   "${POSTGRES_DB}" \
     -v rol="${ROL}" -v clave="${CLAVE}" -v duenio="${POSTGRES_USER}" -v bd="${POSTGRES_DB}" <<-'EOSQL'

    -- Creacion idempotente del rol (se genera el DDL y se ejecuta con \gexec)
    SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'rol', :'clave')
    WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'rol')
    \gexec

    -- Conexion a la base del CMS
    GRANT CONNECT ON DATABASE :"bd" TO :"rol";

    -- Vistas de logs (esquema observabilidad) y funciones SECURITY DEFINER
    GRANT USAGE  ON SCHEMA observabilidad TO :"rol";
    GRANT SELECT ON ALL TABLES IN SCHEMA observabilidad TO :"rol";
    GRANT EXECUTE ON FUNCTION observabilidad.leer_lineas(text, bigint) TO :"rol";
    GRANT EXECUTE ON FUNCTION observabilidad.leer_json(text)           TO :"rol";

    -- Tablas del CMS: las existentes y las que Joomla cree durante su
    -- instalacion (ALTER DEFAULT PRIVILEGES se aplica a objetos futuros).
    GRANT USAGE  ON SCHEMA public TO :"rol";
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"rol";
    ALTER DEFAULT PRIVILEGES FOR ROLE :"duenio" IN SCHEMA public
        GRANT SELECT ON TABLES TO :"rol";

    -- Estadisticas del motor (pg_stat_database, pg_stat_user_tables, ...)
    GRANT pg_monitor TO :"rol";

    -- Cinturon de seguridad: ninguna consulta de un panel puede bloquear al CMS
    ALTER ROLE :"rol" SET statement_timeout = '30s';
    ALTER ROLE :"rol" SET idle_in_transaction_session_timeout = '60s';
EOSQL

echo "[initdb] Rol '${ROL}' listo."
