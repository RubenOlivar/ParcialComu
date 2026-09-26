"""Siembra dos artículos destacados en Joomla tras el despliegue desatendido.

Se ejecuta en segundo plano al arrancar el contenedor jupyter (ver
before-notebook.d/10-seed-joomla.sh) porque las tablas de Joomla no existen
todavía cuando arranca PostgreSQL: las crea la propia instalación desatendida
de Joomla, minutos después. El script espera a que aparezcan y luego inserta
el contenido una sola vez (es idempotente: si el alias ya existe, lo salta).
"""

import os
import sys
import time

import psycopg2

HOST = os.environ.get("POSTGRES_HOST", "database")
PORT = os.environ.get("POSTGRES_PORT", "5432")
DB = os.environ.get("POSTGRES_DB", "joomladb")
USER = os.environ.get("POSTGRES_USER", "joomla")
PASSWORD = os.environ.get("POSTGRES_PASSWORD", "")

CONNECT_RETRIES = 30
CONNECT_DELAY_S = 5
TABLE_WAIT_RETRIES = 120
TABLE_WAIT_DELAY_S = 10

ARTICLES = [
    {
        "alias": "portal-institucional-umng-comunicaciones",
        "title": "Portal Institucional UMNG - Comunicaciones",
        "introtext": (
            "<p>Bienvenido al <strong>portal institucional</strong> del "
            "departamento de Comunicaciones, Ingeniería Mecatrónica "
            "— Universidad Militar Nueva Granada.</p>"
            "<p>Este sitio forma parte del <strong>Parcial 2 práctico</strong>: "
            "un despliegue multi-contenedor con orquestación Docker que "
            "integra un proxy inverso (Nginx), este CMS (Joomla), una base de "
            "datos relacional (PostgreSQL), un entorno de análisis de datos "
            "(Jupyter) y un panel de observabilidad (Grafana).</p>"
        ),
        "fulltext": (
            "<ul><li><strong>Nginx</strong> enruta todo el tráfico entrante "
            "por prefijo.</li><li><strong>PostgreSQL</strong> persiste el "
            "contenido del CMS y centraliza los registros de acceso.</li>"
            "<li><strong>Grafana</strong> visualiza el tráfico en tiempo "
            "real.</li><li><strong>Jupyter</strong> permite el análisis "
            "interactivo de los datos.</li></ul>"
            "<p>Navegue el sitio para generar tráfico de prueba visible en "
            "los paneles de observabilidad.</p>"
        ),
        "metadesc": "Portal institucional del despliegue multi-contenedor - Parcial 2 Comunicaciones UMNG",
        "ordering": 1,
    },
    {
        "alias": "el-modelo-osi-en-este-despliegue",
        "title": "El modelo OSI en este despliegue",
        "introtext": (
            "<p>Este proyecto no solo despliega servicios: cada capa del "
            "<strong>modelo OSI</strong> tiene un rol observable y verificable "
            "en la infraestructura.</p>"
        ),
        "fulltext": (
            "<ul>"
            "<li><strong>Capa 7 (Aplicación):</strong> Nginx inyecta "
            "cabeceras HTTP (Host, X-Forwarded-For) y negocia el WebSocket "
            "del kernel de Jupyter.</li>"
            "<li><strong>Capa 4 (Transporte):</strong> tres conexiones TCP "
            "distintas se abren en cada visita: navegador↔nginx, "
            "nginx↔joomla y joomla↔postgres.</li>"
            "<li><strong>Capa 3 (Red):</strong> dos redes bridge aisladas "
            "(frontend_net y backend_net) separan el borde público del "
            "plano de datos; el DNS embebido de Docker (127.0.0.11) resuelve "
            "por nombre de servicio.</li>"
            "<li><strong>Capa 2 (Enlace):</strong> cada contenedor se conecta "
            "a su red mediante un par veth hacia un bridge por software, con "
            "resolución ARP interna entre vecinos.</li>"
            "</ul>"
            "<p>El análisis completo, con capturas reales del despliegue, "
            "está documentado en INFORME.md.</p>"
        ),
        "metadesc": "Modelo OSI aplicado al despliegue - Parcial 2 Comunicaciones UMNG",
        "ordering": 2,
    },
]


def connect():
    for attempt in range(1, CONNECT_RETRIES + 1):
        try:
            return psycopg2.connect(
                host=HOST, port=PORT, dbname=DB, user=USER, password=PASSWORD
            )
        except psycopg2.OperationalError as exc:
            print(f"seed: intento {attempt}/{CONNECT_RETRIES}, BD no lista aun ({exc})", flush=True)
            time.sleep(CONNECT_DELAY_S)
    return None


def wait_for_joomla_schema(conn):
    with conn.cursor() as cur:
        for attempt in range(1, TABLE_WAIT_RETRIES + 1):
            cur.execute("SELECT to_regclass('public.joom_content')")
            if cur.fetchone()[0] is not None:
                return True
            print(f"seed: esperando instalacion de Joomla ({attempt}/{TABLE_WAIT_RETRIES})", flush=True)
            time.sleep(TABLE_WAIT_DELAY_S)
    return False


def seed(conn):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id FROM joom_categories WHERE extension = 'com_content' ORDER BY id ASC LIMIT 1"
        )
        row = cur.fetchone()
        if row is None:
            print("seed: no hay categorias de contenido todavia, abortando", flush=True)
            return
        catid = row[0]

        cur.execute("SELECT id FROM joom_users ORDER BY id ASC LIMIT 1")
        row = cur.fetchone()
        created_by = row[0] if row else 0

        for art in ARTICLES:
            cur.execute("SELECT id FROM joom_content WHERE alias = %s", (art["alias"],))
            if cur.fetchone():
                print(f"seed: '{art['alias']}' ya existe, se omite", flush=True)
                continue

            cur.execute(
                """
                INSERT INTO joom_content (
                    asset_id, title, alias, introtext, fulltext, state, catid,
                    created, created_by, created_by_alias, modified, modified_by,
                    publish_up, images, urls, attribs, version, ordering,
                    metakey, metadesc, access, hits, metadata, featured, language, note
                ) VALUES (
                    0, %s, %s, %s, %s, 1, %s,
                    now(), %s, '', now(), %s,
                    now(), '{}', '{}', '{}', 1, %s,
                    '', %s, 1, 0, '{}', 1, '*', ''
                ) RETURNING id
                """,
                (
                    art["title"], art["alias"], art["introtext"], art["fulltext"], catid,
                    created_by, created_by, art["ordering"], art["metadesc"],
                ),
            )
            new_id = cur.fetchone()[0]
            cur.execute(
                """
                INSERT INTO joom_content_frontpage (content_id, ordering, featured_up)
                VALUES (%s, %s, now())
                ON CONFLICT (content_id) DO NOTHING
                """,
                (new_id, art["ordering"]),
            )
            print(f"seed: articulo creado id={new_id} alias={art['alias']}", flush=True)
    conn.commit()


def main():
    conn = connect()
    if conn is None:
        print("seed: no se pudo conectar a PostgreSQL, abortando", flush=True)
        sys.exit(0)
    conn.autocommit = False
    try:
        if not wait_for_joomla_schema(conn):
            print("seed: Joomla nunca termino de instalarse, abortando", flush=True)
            return
        seed(conn)
        print("seed: listo", flush=True)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
