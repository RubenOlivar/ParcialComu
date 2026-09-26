#!/bin/bash
# Lanza la siembra de contenido de Joomla en segundo plano: no debe retrasar
# el arranque de JupyterLab, ya que puede tardar varios minutos en que la
# instalacion desatendida de Joomla termine de crear sus tablas.
#
# ATENCION: jupyter-docker-stacks ejecuta los hooks .sh con `source`, es
# decir en el MISMO proceso de start.sh, no en un subshell. Por eso este
# script no debe usar `exit` ni `set -e`/`pipefail`: cortarian el arranque
# completo del servidor Jupyter en vez de solo el hook.
nohup python3 /usr/local/bin/seed_joomla_content.py > /tmp/seed_joomla.log 2>&1 &
disown 2>/dev/null || true
