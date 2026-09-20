# Parcial 2 práctico — Despliegue multi-contenedor y análisis del modelo OSI

**Comunicaciones · Ingeniería Mecatrónica · Universidad Militar Nueva Granada**
Docente: Ing. Andrés Julián Moreno, M.Sc.

Infraestructura web completa orquestada con Docker Compose: un **proxy inverso
Nginx** como único punto de entrada, el CMS **Joomla** persistiendo sobre
**PostgreSQL 16**, un entorno **Jupyter** con un cuaderno precargado y
**Grafana** con datasource y dashboard aprovisionados automáticamente.

> El documento técnico con el análisis del modelo OSI está en **[INFORME.md](INFORME.md)**.

---

## 1. Requisitos

| Requisito | Versión mínima | Comprobación |
|---|---|---|
| Docker Engine | 24.x | `docker --version` |
| Docker Compose | v2.x (plugin) | `docker compose version` |
| Puerto libre en el host | **80/tcp** | `curl http://localhost` no debe responder antes de desplegar |
| Espacio en disco | ~3 GB | imágenes + volúmenes |

El despliegue necesita salida a Internet la primera vez (descarga de imágenes y
construcción de la imagen de Jupyter).

---

## 2. Despliegue en un solo paso

```bash
git clone <URL_DEL_REPOSITORIO>
cd <CARPETA_DEL_REPOSITORIO>
cp .env.example .env
docker compose up -d
```

Eso es todo. No hay pasos manuales posteriores: no se configura Grafana por la
interfaz, no se sube el cuaderno de Jupyter y no se ejecuta el asistente de
instalación de Joomla.

La primera ejecución tarda entre **3 y 6 minutos** (descarga de imágenes,
construcción de la imagen de Jupyter e instalación desatendida de Joomla). El
estado se sigue con:

```bash
docker compose ps
docker compose logs -f joomla      # progreso de la instalación del CMS
```

El despliegue está listo cuando los cinco contenedores aparecen en estado
`Up` y los que declaran sonda de salud muestran `(healthy)`:

```
NAME            IMAGE                                          STATUS
comm_database   postgres:16-alpine                             Up (healthy)
comm_joomla     joomla:latest                                  Up (healthy)
comm_jupyter    parcial2-comunicaciones/jupyter-analitica:1.0   Up (healthy)
comm_grafana    grafana/grafana:latest                         Up (healthy)
comm_nginx      nginx:alpine                                   Up (healthy)
```

---

## 3. Puntos de acceso

Todo se sirve por el **puerto 80** del host; ningún otro contenedor publica
puertos.

| URL | Servicio | Credenciales |
|---|---|---|
| <http://localhost/> | Portal Joomla | — |
| <http://localhost/administrator/> | Backend de Joomla | `administrador` / `Comm2026_Joomla_Admin` |
| <http://localhost/jupyter/> | JupyterLab — abre `analisis_datos.ipynb` directamente | sin token |
| <http://localhost/grafana/> | Grafana — redirige al dashboard aprovisionado | lectura anónima · admin: `admin` / `Comm2026_Grafana` |

Las credenciales se definen en `.env.example`; cámbielas allí si desea otras
antes de desplegar.

> Si el puerto 80 está ocupado, basta con poner `HTTP_PORT=8080` en `.env`: el
> stack completo queda en <http://localhost:8080/> (portal, `/jupyter/` y
> `/grafana/` incluidos). El edge emite redirecciones relativas, de modo que el
> puerto publicado se conserva en toda la navegación.

---

## 4. Verificación rápida

```bash
# 1) Los cinco contenedores arriba
docker compose ps

# 2) El edge enruta a los tres backends
curl -I http://localhost/                 # Joomla   -> 200
curl -s http://localhost/grafana/api/health   # Grafana  -> {"database":"ok",...}
curl -s http://localhost/jupyter/api          # Jupyter  -> {"version":"..."}

# 3) Generar tráfico para poblar los paneles
./scripts/generar_trafico.sh 15            # Linux / macOS / Git Bash
powershell -File scripts\generar_trafico.ps1 -Vueltas 15   # Windows

# 4) Ver los datos ya convertidos en SQL
docker compose exec database psql -U joomla -d joomladb \
  -c "SELECT servicio, count(*) FROM observabilidad.nginx_access GROUP BY 1;"
```

El procedimiento completo de demostración (paso a paso, con lo que debe
observarse en cada pantalla) está en la **sección 3 de [INFORME.md](INFORME.md)**.

---

## 5. Estructura del repositorio

```
PARCIAL COMUNICACIONES/
├── docker-compose.yml              # Orquestación de los 5 servicios, 2 redes y 5 volúmenes
├── .env.example                    # Credenciales y parámetros por defecto (listos para usar)
├── README.md                       # Este archivo
├── INFORME.md                      # Documento técnico: topología + modelo OSI + demostración
│
├── nginx/
│   └── conf.d/
│       └── default.conf            # Enrutamiento por prefijo, WebSockets y log JSON
│
├── joomla/
│   └── apache/
│       └── zz-observabilidad.conf  # LogFormat JSON de Apache + mod_remoteip
│
├── database/
│   └── initdb/
│       ├── 01-observabilidad.sql   # Funciones y vistas que parsean los access logs
│       └── 02-rol-grafana.sh       # Rol de solo lectura usado por Grafana
│
├── jupyter/
│   ├── Dockerfile                  # base-notebook + psycopg2/pandas/matplotlib
│   ├── config/
│   │   └── jupyter_server_config.py# base_url /jupyter, sin token, abre el cuaderno
│   └── notebooks/
│       └── analisis_datos.ipynb    # Cuaderno precargado (bind-mount)
│
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       │   └── datasource.yml      # Datasource PostgreSQL (rol de solo lectura)
│       └── dashboards/
│           ├── dashboard.yml       # Proveedor de dashboards
│           └── json/
│               └── observabilidad_joomla.json   # 12 paneles
│
└── scripts/
    ├── generar_trafico.sh          # Generador de tráfico (bash)
    └── generar_trafico.ps1         # Generador de tráfico (PowerShell)
```

---

## 6. Arquitectura en una página

```
                    ┌──────────────────────────┐
                    │  Navegador del usuario   │
                    └────────────┬─────────────┘
                          HTTP · 80/tcp
                                 │
   ════════════════════ frontend_net (172.28.10.0/24) ════════════════════
                                 │
                    ┌────────────▼─────────────┐
                    │  nginx  (edge router)    │  ← único puerto publicado
                    └───┬──────────┬───────────┘
              /         │          │ /jupyter/        \ /grafana/
        ┌─────▼────┐ ┌──▼────────┐ ┌────────▼──┐
        │  joomla  │ │  jupyter  │ │  grafana  │
        └────┬─────┘ └─────┬─────┘ └─────┬─────┘
             │             │             │
   ════════════════════ backend_net (172.28.20.0/24, internal) ═══════════
             │             │             │
             └─────────────┴──────┬──────┘
                        TCP 5432  │
                          ┌───────▼────────┐
                          │    database    │  PostgreSQL 16
                          └────────────────┘   (sin ruta al exterior)
```

Los access logs de `nginx` y de `joomla` viajan por volúmenes compartidos hasta
el contenedor `database`, que los expone como vistas SQL; Grafana y Jupyter
consultan esas vistas. El mecanismo completo se explica en
[INFORME.md § 1.3](INFORME.md).

---

## 7. Operación

```bash
docker compose ps                      # estado y salud
docker compose logs -f <servicio>      # logs de un servicio
docker compose restart <servicio>      # reiniciar uno
docker compose down                    # detener (conserva los volúmenes)
docker compose down -v                 # detener y BORRAR datos (parte de cero)
docker compose up -d --build           # reconstruir tras cambiar el Dockerfile
```

---

## 8. Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `bind: address already in use` al levantar | Otro servicio ocupa el puerto 80 | Editar `HTTP_PORT` en `.env` (p. ej. `HTTP_PORT=8080`) y volver a `docker compose up -d` |
| `Pool overlaps with other one on this address space` | Otra red de Docker ya usa 172.28.x | Comentar los bloques `ipam:` de `docker-compose.yml` (Docker asignará subredes libres automáticamente) |
| `comm_joomla` tarda en pasar a `healthy` | Instalación desatendida del CMS en curso | Esperar 1–3 min; seguir con `docker compose logs -f joomla` |
| Grafana muestra "No data" | Aún no hay tráfico en el rango de tiempo | Ejecutar `scripts/generar_trafico.sh` o navegar el portal y usar el rango *Last 15 minutes* |
| Jupyter abre pero el kernel no conecta | Cabeceras de WebSocket bloqueadas por un proxy externo | Revisar `proxy_set_header Upgrade` en `nginx/conf.d/default.conf` |
| Se quiere partir de cero | Volúmenes con datos de una ejecución previa | `docker compose down -v && docker compose up -d --build` |

---

## 9. Integrantes

| Nombre |
|---|
| Rubén Olivar |
| Nicolás Bernal |
| Juan Castilla |
