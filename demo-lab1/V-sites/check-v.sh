#!/usr/bin/env bash
# Проверки части В. Не требует правки /etc/hosts: Host подставляется через --resolve.
# Использование: ./check-v.sh [порт]   (по умолчанию 8080)
PORT="${1:-8080}"
PASS=0; FAIL=0

R1="--resolve site1.local:$PORT:127.0.0.1"
R2="--resolve site2.local:$PORT:127.0.0.1"

ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "1) site1.local / -> 200 и страница site1"
set -x; curl -s -i $R1 http://site1.local:$PORT/ | head -n 12; set +x
[ "$(code $R1 http://site1.local:$PORT/)" = 200 ] && ok "200" || bad "ожидали 200"
curl -s $R1 http://site1.local:$PORT/ | grep -q "site1.local" && ok "контент site1" || bad "нет контента site1"

echo; echo "2) site1.local /docs/ -> 200 (alias)"
set -x; curl -s -i $R1 http://site1.local:$PORT/docs/ | head -n 12; set +x
[ "$(code $R1 http://site1.local:$PORT/docs/)" = 200 ] && ok "200" || bad "ожидали 200"
curl -s $R1 http://site1.local:$PORT/docs/ | grep -q "DOCS-PAGE" && ok "отдалась страница из каталога docs" || bad "нет DOCS-PAGE"

echo; echo "3) site2.local / -> 200 и страница site2"
set -x; curl -s -i $R2 http://site2.local:$PORT/ | head -n 12; set +x
curl -s $R2 http://site2.local:$PORT/ | grep -q "SITE2-PAGE" && ok "контент site2" || bad "нет SITE2-PAGE"

echo; echo "4) виртуальные хосты разведены: site2 не отдаёт контент site1"
[ "$(code $R2 http://site2.local:$PORT/docs/)" = 404 ] && ok "site2/docs/ -> 404" || bad "site2/docs/ должен быть 404"
curl -s $R2 http://site2.local:$PORT/ | grep -q "site1.local" && bad "site2 отдаёт site1!" || ok "в site2 нет контента site1"
curl -s $R1 http://site1.local:$PORT/ | grep -q "SITE2-PAGE" && bad "site1 отдаёт site2!" || ok "в site1 нет контента site2"

echo; echo "5) чужой Host -> default-сервер, ничего лишнего"
set -x; curl -s -i -H 'Host: evil.example' http://127.0.0.1:$PORT/ | head -n 12; set +x
B=$(curl -s -H 'Host: evil.example' http://127.0.0.1:$PORT/)
[ "$(code -H 'Host: evil.example' http://127.0.0.1:$PORT/)" = 404 ] && ok "чужой Host -> 404" || bad "ожидали 404"
echo "$B" | grep -Eq "SITE2-PAGE|site1.local" && bad "утечка контента проектов" || ok "контент проектов не отдан"

echo; echo "6) несуществующая страница -> своя 404"
set -x; curl -s -i $R1 http://site1.local:$PORT/no-such-page | head -n 14; set +x
[ "$(code $R1 http://site1.local:$PORT/no-such-page)" = 404 ] && ok "код 404" || bad "ожидали 404"
curl -s $R1 http://site1.local:$PORT/no-such-page | grep -q "CUSTOM-404" && ok "своя страница 404" || bad "стандартная 404 nginx"

echo; echo "7) /errors/404.html напрямую недоступен (internal)"
[ "$(code $R1 http://site1.local:$PORT/errors/404.html)" = 404 ] && ok "internal работает" || bad "должно быть 404"

echo; echo "Итого: $PASS ок, $FAIL ошибок"
[ "$FAIL" = 0 ]
