-- =============================================================================
--  Parcial 2 practico - Comunicaciones (UMNG)
--  Esquema "observabilidad": convierte los access logs de Nginx y de Joomla
--  en vistas SQL consultables por Grafana y por el cuaderno de Jupyter.
--
--  Mecanismo: los volumenes de logs estan montados en SOLO LECTURA dentro del
--  contenedor database (/mnt/logs/edge y /mnt/logs/joomla).  Dos funciones
--  SECURITY DEFINER leen la cola del archivo con pg_read_file(), separan las
--  lineas y convierten cada una a JSONB descartando las malformadas.
--  De este modo NO se requiere un agente externo (Promtail/Loki/Fluentd) y el
--  stack se mantiene en exactamente cinco contenedores.
-- =============================================================================

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS observabilidad;
COMMENT ON SCHEMA observabilidad IS
  'Vistas derivadas de los access logs del edge (Nginx) y del CMS (Joomla).';

-- -----------------------------------------------------------------------------
-- Catalogo de fuentes (documentacion viva de las rutas montadas)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS observabilidad.fuentes_log (
    id          text PRIMARY KEY,
    ruta        text NOT NULL,
    origen      text NOT NULL,
    descripcion text NOT NULL
);

INSERT INTO observabilidad.fuentes_log (id, ruta, origen, descripcion) VALUES
    ('edge',   '/mnt/logs/edge/access.json.log',          'nginx',
     'Access log JSON del proxy inverso: toda peticion que entra por el puerto 80'),
    ('joomla', '/mnt/logs/joomla/joomla_access.json.log', 'joomla',
     'Access log JSON de Apache dentro del contenedor Joomla (Capa 7 del CMS)')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
--  1) Lectura de la cola de un archivo de log
--     - pg_stat_file() obtiene el tamano actual; se leen como maximo los
--       ultimos p_max_bytes para que el costo sea acotado aunque el log crezca.
--     - missing_ok = true: si el archivo aun no existe (proxy sin trafico), la
--       funcion devuelve el conjunto vacio en lugar de fallar.
-- =============================================================================
CREATE OR REPLACE FUNCTION observabilidad.leer_lineas(
        p_ruta      text,
        p_max_bytes bigint DEFAULT 8388608)      -- 8 MiB
RETURNS SETOF text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $fn$
DECLARE
    v_tam    bigint;
    v_desde  bigint;
    v_texto  text;
    v_lineas text[];
    i        integer;
BEGIN
    SELECT size INTO v_tam FROM pg_stat_file(p_ruta, true);
    IF v_tam IS NULL OR v_tam = 0 THEN
        RETURN;                      -- archivo inexistente o vacio
    END IF;

    v_desde := GREATEST(v_tam - p_max_bytes, 0);
    v_texto := pg_read_file(p_ruta, v_desde, p_max_bytes, true);
    IF v_texto IS NULL THEN
        RETURN;
    END IF;

    v_lineas := string_to_array(v_texto, E'\n');
    FOR i IN 1 .. COALESCE(cardinality(v_lineas), 0) LOOP
        -- Si se leyo desde un offset, la primera linea puede venir cortada.
        CONTINUE WHEN i = 1 AND v_desde > 0;
        IF length(v_lineas[i]) > 3 THEN
            RETURN NEXT v_lineas[i];
        END IF;
    END LOOP;
END;
$fn$;

COMMENT ON FUNCTION observabilidad.leer_lineas(text, bigint) IS
  'Devuelve las ultimas lineas de un archivo de log montado en el contenedor.';

-- =============================================================================
--  2) Conversion linea -> JSONB tolerante a fallos
--     Una linea a medio escribir (el proceso de Nginx/Apache puede estar
--     escribiendo mientras se lee) no debe invalidar toda la consulta.
-- =============================================================================
CREATE OR REPLACE FUNCTION observabilidad.leer_json(p_ruta text)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $fn$
DECLARE
    v_linea text;
    v_json  jsonb;
BEGIN
    FOR v_linea IN SELECT * FROM observabilidad.leer_lineas(p_ruta) LOOP
        BEGIN
            v_json := v_linea::jsonb;
            RETURN NEXT v_json;
        EXCEPTION WHEN others THEN
            NULL;   -- linea truncada o con escapes invalidos: se descarta
        END;
    END LOOP;
END;
$fn$;

COMMENT ON FUNCTION observabilidad.leer_json(text) IS
  'Lee un log JSON-lines y devuelve un JSONB por linea valida.';

-- =============================================================================
--  3) Vista del access log del edge (Nginx)
-- =============================================================================
CREATE OR REPLACE VIEW observabilidad.nginx_access AS
SELECT
    (d->>'ts')::timestamptz                              AS "time",
    d->>'remote_addr'                                    AS ip_cliente,
    NULLIF(d->>'xff', '')                                AS x_forwarded_for,
    d->>'host'                                           AS host,
    d->>'metodo'                                         AS metodo,
    d->>'uri'                                            AS uri,
    NULLIF(d->>'args', '')                               AS query_string,
    d->>'protocolo'                                      AS protocolo,
    (d->>'status')::int                                  AS status,
    left(d->>'status', 1) || 'xx'                        AS clase_status,
    (d->>'bytes')::bigint                                AS bytes,
    (d->>'request_time')::numeric                        AS duracion_s,
    NULLIF(d->>'upstream_addr', '')                      AS upstream_addr,
    NULLIF(d->>'upstream_status', '')                    AS upstream_status,
    d->>'servicio'                                       AS servicio,
    NULLIF(d->>'upgrade', '')                            AS upgrade,
    NULLIF(d->>'referer', '')                            AS referer,
    NULLIF(d->>'user_agent', '')                         AS user_agent
FROM observabilidad.leer_json('/mnt/logs/edge/access.json.log') AS d;

COMMENT ON VIEW observabilidad.nginx_access IS
  'Una fila por peticion HTTP atendida por el proxy inverso.';

-- =============================================================================
--  4) Vista del access log de Joomla (Apache dentro del contenedor CMS)
-- =============================================================================
CREATE OR REPLACE VIEW observabilidad.joomla_access AS
SELECT
    (d->>'ts')::timestamptz                              AS "time",
    d->>'remote_addr'                                    AS ip_cliente,
    d->>'proxy_addr'                                     AS ip_proxy,
    NULLIF(d->>'xff', '-')                               AS x_forwarded_for,
    d->>'host'                                           AS host,
    d->>'metodo'                                         AS metodo,
    d->>'uri'                                            AS uri,
    NULLIF(d->>'query', '')                              AS query_string,
    d->>'protocolo'                                      AS protocolo,
    (d->>'status')::int                                  AS status,
    left(d->>'status', 1) || 'xx'                        AS clase_status,
    (d->>'bytes')::bigint                                AS bytes,
    (d->>'duracion_us')::numeric / 1000000.0             AS duracion_s,
    NULLIF(d->>'referer', '-')                           AS referer,
    NULLIF(d->>'user_agent', '-')                        AS user_agent
FROM observabilidad.leer_json('/mnt/logs/joomla/joomla_access.json.log') AS d;

COMMENT ON VIEW observabilidad.joomla_access IS
  'Una fila por peticion servida por Apache/Joomla (Capa 7 del CMS).';

-- =============================================================================
--  5) Vista unificada edge + CMS
-- =============================================================================
CREATE OR REPLACE VIEW observabilidad.trafico AS
SELECT 'nginx'::text AS origen, "time", ip_cliente, metodo, uri, status,
       clase_status, servicio, duracion_s, bytes
FROM observabilidad.nginx_access
UNION ALL
SELECT 'joomla'::text, "time", ip_cliente, metodo, uri, status,
       clase_status, 'joomla'::text, duracion_s, bytes
FROM observabilidad.joomla_access;

COMMENT ON VIEW observabilidad.trafico IS
  'Union de ambos access logs con columnas homogeneas.';

-- =============================================================================
--  6) Metricas del propio motor relacional (actividad del CMS sobre la BD)
-- =============================================================================
CREATE OR REPLACE VIEW observabilidad.actividad_bd AS
SELECT
    now()                             AS "time",
    datname                           AS base_datos,
    numbackends                       AS conexiones_activas,
    xact_commit                       AS transacciones_commit,
    xact_rollback                     AS transacciones_rollback,
    blks_read                         AS bloques_disco,
    blks_hit                          AS bloques_cache,
    round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
    tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted,
    pg_database_size(datname)         AS bytes_totales
FROM pg_stat_database
WHERE datname = current_database();

CREATE OR REPLACE VIEW observabilidad.tablas_joomla AS
SELECT
    now()                             AS "time",
    schemaname                        AS esquema,
    relname                           AS tabla,
    n_live_tup                        AS filas_estimadas,
    pg_total_relation_size(relid)     AS bytes_totales,
    seq_scan                          AS escaneos_secuenciales,
    COALESCE(idx_scan, 0)             AS escaneos_indice,
    n_tup_ins                         AS inserciones,
    n_tup_upd                         AS actualizaciones,
    n_tup_del                         AS eliminaciones
FROM pg_stat_user_tables;

COMMENT ON VIEW observabilidad.tablas_joomla IS
  'Actividad por tabla del esquema de Joomla (se puebla tras la instalacion).';
