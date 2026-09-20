# =============================================================================
#  Parcial 2 practico - Comunicaciones (UMNG)
#  Entorno de ciencia de datos derivado de la imagen sugerida en el enunciado.
#
#  Se extiende jupyter/base-notebook con las librerias que necesita el cuaderno
#  precargado (analisis_datos.ipynb): cliente PostgreSQL, pandas y matplotlib.
#  Construir la imagen en el despliegue garantiza que las celdas se ejecuten
#  sin que el evaluador instale nada a mano.
# =============================================================================
FROM jupyter/base-notebook:latest

LABEL org.opencontainers.image.title="Jupyter - Analitica de trafico y BD" \
      org.opencontainers.image.description="JupyterLab con psycopg2/pandas/matplotlib para el Parcial 2 de Comunicaciones (UMNG)" \
      org.opencontainers.image.vendor="Universidad Militar Nueva Granada"

USER root

# Configuracion del servidor: subpath /jupyter, sin token y apertura directa
# del cuaderno. Se hornea en la imagen para que no dependa de permisos del host.
COPY config/jupyter_server_config.py /home/jovyan/.jupyter/jupyter_server_config.py
RUN chown -R "${NB_UID}:${NB_GID}" /home/jovyan/.jupyter

USER ${NB_UID}

# Versiones fijadas para que el despliegue sea reproducible en cualquier maquina
RUN pip install --no-cache-dir --quiet \
        "psycopg2-binary==2.9.10" \
        "SQLAlchemy==2.0.36" \
        "pandas==2.2.3" \
        "matplotlib==3.9.2" \
        "requests==2.32.3" \
        "tabulate==0.9.0" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

WORKDIR /home/jovyan
EXPOSE 8888
