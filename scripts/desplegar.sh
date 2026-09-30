#!/usr/bin/env bash
#
# DESPLEGAR CUADRE EN ATHENAS.
#
# Sube el código, reconstruye el contenedor y comprueba que contesta. El `.env`
# vive solo en el servidor y no se toca desde aquí: las llaves no viajan en el
# repositorio ni en este script.
#
#   scripts/desplegar.sh
#
set -euo pipefail

SERVIDOR=${SERVIDOR:-athenas}
DESTINO=${DESTINO:-/opt/stacks/cuadre}
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "▸ Comprobando antes de subir…"
( cd "$RAIZ/servidor" && for f in src/*.js src/rutas/*.js; do node --check "$f"; done )
echo "  sintaxis del servidor, bien"

echo "▸ Subiendo a $SERVIDOR:$DESTINO"
ssh "$SERVIDOR" "mkdir -p $DESTINO/datos"
rsync -az --delete \
  --exclude 'node_modules' \
  --exclude 'datos' \
  --exclude '.env' \
  --exclude '.git' \
  --exclude 'ios' \
  --exclude 'build' \
  "$RAIZ/servidor" "$RAIZ/sitio" "$RAIZ/compose.yml" "$SERVIDOR:$DESTINO/"

echo "▸ La versión, del propio git, para que /api/salud diga qué corre"
VERSION=$(cd "$RAIZ" && git describe --tags --always --dirty 2>/dev/null || echo dev)
ssh "$SERVIDOR" "cd $DESTINO && touch .env && \
  grep -q '^CUADRE_VERSION=' .env && sed -i 's|^CUADRE_VERSION=.*|CUADRE_VERSION=$VERSION|' .env \
  || echo 'CUADRE_VERSION=$VERSION' >> .env"

echo "▸ Reconstruyendo"
ssh "$SERVIDOR" "cd $DESTINO && docker compose up -d --build"

echo "▸ Esperando a que conteste"
for i in $(seq 1 30); do
  if ssh "$SERVIDOR" "docker exec cuadre-app node -e \"fetch('http://127.0.0.1:3000/api/salud').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\"" 2>/dev/null; then
    echo "  vivo"
    ssh "$SERVIDOR" "docker exec cuadre-app node -e \"fetch('http://127.0.0.1:3000/api/salud').then(r=>r.text()).then(console.log)\""
    exit 0
  fi
  sleep 2
done

echo "✗ No contestó. Los últimos registros:"
ssh "$SERVIDOR" "docker logs --tail 40 cuadre-app"
exit 1
