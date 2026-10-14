#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

NAME=nginx-lab1

if [ "$1" = "stop" ]; then
  docker rm -f "$NAME" >/dev/null 2>&1 && echo "stopped" || echo "уже остановлен"
  exit 0
fi

if [ ! -f certs/server.crt ] || [ ! -f certs/server.key ]; then
  echo "Генерирую сертификаты..."
  (cd certs && bash generate.sh)
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true

docker run -d --name "$NAME" \
  -p 8080:80 \
  -p 8443:443 \
  --add-host=host.docker.internal:host-gateway \
  -v "$PWD/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$PWD/conf.d:/etc/nginx/conf.d:ro" \
  -v "$PWD/certs:/etc/nginx/certs:ro" \
  -v "$PWD/htpasswd:/etc/nginx/htpasswd:ro" \
  -v "$PWD/www/static:/var/www/lab1/static:ro" \
  -v "$PWD/www/docs:/var/www/lab1/docs:ro" \
  -v "$PWD/www/site2:/var/www/lab1/site2:ro" \
  -v "$PWD/www/errors:/var/www/lab1/errors:ro" \
  -v "$PWD/www/admin:/var/www/lab1/admin:ro" \
  nginx:stable

sleep 1
docker exec "$NAME" nginx -t
echo "OK. http://site1.local:8080 (редирект) → https://site1.local:8443"
