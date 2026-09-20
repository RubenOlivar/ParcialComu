# =============================================================================
#  Configuracion del servidor Jupyter - Parcial 2 Comunicaciones (UMNG)
#  Copiada a /home/jovyan/.jupyter/jupyter_server_config.py durante el build.
#
#  Objetivo: que JupyterLab quede accesible en http://localhost/jupyter/ a
#  traves del proxy inverso, sin token y abriendo el cuaderno precargado.
# =============================================================================
c = get_config()  # noqa: F821

# --- Escucha ---------------------------------------------------------------
c.ServerApp.ip = "0.0.0.0"          # todas las interfaces del contenedor
c.ServerApp.port = 8888             # Capa 4: puerto TCP del servicio
c.ServerApp.open_browser = False

# --- Publicacion detras del proxy inverso ----------------------------------
# Nginx entrega la URI completa (/jupyter/...), por lo que el servidor debe
# montarse en ese mismo prefijo; de lo contrario los assets y los WebSockets
# del kernel apuntarian a rutas inexistentes.
c.ServerApp.base_url = "/jupyter"

# Al entrar a http://localhost/jupyter/ se abre directamente el cuaderno.
# JupyterLab se registra como extension por defecto y sobreescribe
# ServerApp.default_url, por lo que la ruta se fija tambien en LabApp.
c.ServerApp.default_url = "/lab/tree/work/analisis_datos.ipynb"
c.LabApp.default_url = "/lab/tree/work/analisis_datos.ipynb"

# Honrar X-Forwarded-For / X-Forwarded-Proto inyectadas por Nginx.
c.ServerApp.trust_xheaders = True
c.ServerApp.allow_remote_access = True

# El handshake WebSocket del kernel llega con el Origin del navegador; se
# acepta cualquier origen porque el unico camino de entrada es el edge.
# (Relajacion consciente, valida para un entorno de laboratorio.)
c.ServerApp.allow_origin = "*"

# --- Autenticacion ---------------------------------------------------------
# Sin token ni contrasena: el enunciado exige acceso inmediato y el servicio
# no esta publicado directamente al host (solo es alcanzable via Nginx).
c.ServerApp.token = ""
c.ServerApp.password = ""
c.IdentityProvider.token = ""
c.PasswordIdentityProvider.hashed_password = ""
c.PasswordIdentityProvider.password_required = False

# --- Area de trabajo -------------------------------------------------------
# /home/jovyan contiene work/ (bind-mount del repositorio con el cuaderno)
# y logs/ (volumenes de Nginx y Joomla montados en solo lectura).
c.ServerApp.root_dir = "/home/jovyan"

# Sesiones largas durante la demostracion.
c.ServerApp.shutdown_no_activity_timeout = 0
c.MappingKernelManager.cull_idle_timeout = 0
