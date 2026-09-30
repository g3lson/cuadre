# Una sola etapa: el servidor es Node puro y el sitio son archivos estáticos que
# ya vienen escritos. No hay paso de compilación que valga la pena separar.
FROM node:22-slim

# better-sqlite3 trae binarios precompilados para esta imagen; si algún día no,
# python3 y build-essential son lo que hace falta para compilarlo.
WORKDIR /app

COPY servidor/package.json servidor/package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund

COPY servidor/src ./src
COPY sitio ./sitio

ENV NODE_ENV=production
ENV CUADRE_BD=/datos/cuadre.db
ENV CUADRE_SITIO_DIR=/app/sitio
EXPOSE 3000

# El proxy comprueba esto antes de mandar tráfico.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
  CMD node -e "fetch('http://127.0.0.1:3000/api/salud').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/index.js"]
