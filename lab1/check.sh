#!/usr/bin/env bash
set -u
HTTP_PORT=8080
HTTPS_PORT=8443
PASS=0; FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
hr()  { echo; echo "==============================================================="; }

R_HTTP="--resolve site1.local:$HTTP_PORT:127.0.0.1"
S1="--resolve site1.local:$HTTPS_PORT:127.0.0.1"
S2="--resolve site2.local:$HTTPS_PORT:127.0.0.1"

hr
echo "1) HTTP → HTTPS: редирект 301"
code=$(curl -s -o /dev/null -w '%{http_code}' $R_HTTP http://site1.local:$HTTP_PORT/)
loc=$(curl -s -I $R_HTTP http://site1.local:$HTTP_PORT/ | awk -F': ' 'tolower($1)=="location"{print $2}' | tr -d '\r')
echo "   код=$code  Location=$loc"
[ "$code" = 301 ] && ok "301" || bad "ожидали 301"

hr
echo "2) Балансировка /api/"
for i in 1 2 3 4 5 6; do
  id=$(curl -k -s -D - -o /dev/null $S1 https://site1.local:$HTTPS_PORT/api/moods \
       | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r')
  echo "   запрос $i → X-Backend: ${id:-нет}"
done

hr
echo "3) Отказоустойчивость (полу-ручная)"
echo "   Погаси ОДИН бэкенд, потом Enter."
read -r _
for i in 1 2 3 4; do
  id=$(curl -k -s -D - -o /dev/null $S1 https://site1.local:$HTTPS_PORT/api/moods \
       | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r')
  code=$(curl -k -s -o /dev/null -w '%{http_code}' $S1 https://site1.local:$HTTPS_PORT/api/moods)
  echo "   запрос $i → X-Backend: ${id:-нет}  (HTTP $code)"
done

hr
echo "4) /admin/ — Basic Auth"
code=$(curl -k -s -o /dev/null -w '%{http_code}' $S1 https://site1.local:$HTTPS_PORT/admin/)
echo "   без пароля → $code"; [ "$code" = 401 ] && ok "401" || bad "ожидали 401"
code=$(curl -k -s -o /dev/null -w '%{http_code}' -u admin:admin123 $S1 https://site1.local:$HTTPS_PORT/admin/)
echo "   с паролем  → $code"; [ "$code" = 200 ] && ok "200" || bad "ожидали 200"

hr
echo "5) Флуд 30 параллельных запросов → должен быть 429"
out=$(seq 1 30 | xargs -P 30 -I {} curl -k -s -o /dev/null -w '%{http_code}\n' \
      $S1 https://site1.local:$HTTPS_PORT/api/moods | sort | uniq -c)
echo "$out"
echo "$out" | grep -q '429' && ok "429 есть" || bad "429 нет"

hr
echo "6) Чужой Host → ничего лишнего"
code=$(curl -k -s -o /dev/null -w '%{http_code}' --resolve evil.example:$HTTPS_PORT:127.0.0.1 https://evil.example:$HTTPS_PORT/)
body=$(curl -k -s --resolve evil.example:$HTTPS_PORT:127.0.0.1 https://evil.example:$HTTPS_PORT/)
echo "   код=$code"; [ "$code" = 404 ] && ok "404" || bad "ожидали 404"
echo "$body" | grep -qE "SITE2-PAGE|site1\.local" && bad "УТЕЧКА" || ok "без утечки"

hr
echo "7) Несуществующая страница → своя 404"
code=$(curl -k -s -o /dev/null -w '%{http_code}' $S1 https://site1.local:$HTTPS_PORT/no-such-page)
body=$(curl -k -s $S1 https://site1.local:$HTTPS_PORT/no-such-page)
echo "   код=$code"; [ "$code" = 404 ] && ok "404" || bad "ожидали 404"
echo "$body" | grep -q "CUSTOM-404" && ok "кастомная 404" || bad "не наша"

hr
echo "ИТОГО: $PASS ✅, $FAIL ❌"
[ "$FAIL" = 0 ]
