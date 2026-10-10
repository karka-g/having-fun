#!/usr/bin/env bash
# Запуск nginx для проверки части В в Docker (официальный образ, без apt).
# Использование: ./run.sh        (запуск на http://localhost:8080)
#                ./run.sh stop   (остановка)
set -e
cd "$(dirname "$0")"

NAME=nginx-lab-v
if [ "$1" = "stop" ]; then docker rm -f "$NAME" >/dev/null 2>&1 && echo "stopped"; exit 0; fi

# Собираем conf.d: заглушка upstream (вместо части Б) + наши конфиги
rm -rf .run && mkdir -p .run/conf.d
cat > .run/conf.d/00-upstream.conf <<'EOF'
# ЗАГЛУШКА для одиночного теста. В репо это файл Б.
upstream backend { server host.docker.internal:3001; }
EOF
cp 20-sites.conf 30-errors.conf .run/conf.d/

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p 8080:80 \
  --add-host=host.docker.internal:host-gateway \
  -v "$PWD/.run/conf.d:/etc/nginx/conf.d:ro" \
  -v "$PWD/static:/var/www/lab1/static:ro" \
  -v "$PWD/docs:/var/www/lab1/docs:ro" \
  -v "$PWD/site2:/var/www/lab1/site2:ro" \
  -v "$PWD/errors:/var/www/lab1/errors:ro" \
  nginx:stable

sleep 1
docker exec "$NAME" nginx -t
echo "OK: http://localhost:8080 (Host: site1.local / site2.local)"
