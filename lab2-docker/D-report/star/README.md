# Со звёздочкой: устойчивый стек

Надстройка над compose-стеком из части C. Файлы лежат в `lab2-docker/D-report/star/`:

    star/
    ├── docker-compose.yml        устойчивый стек: healthcheck, restart, service_healthy, лимиты
    ├── docker-compose.tight.yml  намеренно тесные лимиты (накладывается поверх основного)
    ├── loadgen.py                генератор нагрузки (потоки + статистика ответов)
    └── screenshots/              скриншоты демонстраций (S-01 ... S-06)

Стек использует отдельное имя проекта (`having-fun-star`), контейнеры `lab2s-*` и порт **8081**, поэтому его можно держать рядом со стеком из C (порт 8080). Если запускаешь по одному, разницы нет.

## Что настроено

| Механизм | db | backend | frontend |
| --- | --- | --- | --- |
| `healthcheck` | `pg_isready`, каждые 5 с, `start_period` 10 с | `GET /health` из python, каждые 5 с | `wget --spider http://127.0.0.1/`, каждые 5 с |
| `restart` | `unless-stopped` | `unless-stopped` | `unless-stopped` |
| `depends_on` | нет | `db: service_healthy` | `backend: service_healthy` |
| Лимиты (итоговые, подобраны нагрузкой) | 1.0 CPU, 512 МБ | 0.5 CPU, 128 МБ | 0.5 CPU, 64 МБ |

- `depends_on` с `service_healthy` задаёт порядок старта: БД, затем бэкенд, затем фронт. Бэкенд при старте создаёт таблицу, поэтому до готовности БД он стартовать не должен.
- Переподключение бэкенда к БД не требует отдельной логики: `get_conn()` в `backend/main.py` открывает новое соединение на каждый запрос, пула нет. Пока БД лежит, запросы к ней дают ошибку 500, как только БД поднялась, они снова проходят. Сам бэкенд при этом не падает и не перезапускается.
- `/health` бэкенда проверяет только то, что процесс жив, к БД он не обращается. Поэтому бэкенд остаётся `healthy`, пока БД лежит, и `restart` его не трогает.
- Лимиты заданы через `deploy.resources.limits` (Compose v2 применяет их и без swarm).

## Запуск

    cd lab2-docker/D-report/star
    docker compose up -d --build
    docker compose ps          # все три сервиса healthy
    curl http://localhost:8081/api/moods

(В PowerShell используй `curl.exe` вместо `curl`.)

## Демонстрация 1. Самовосстановление

Открой два терминала.

**Терминал 1.** Опрос раз в секунду, печатает HTTP-код API и главной страницы:

    # bash / zsh / git bash
    while true; do
      echo "$(date +%T) api=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/api/moods) site=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/)"
      sleep 1
    done

    # PowerShell
    while ($true) {
      $api = curl.exe -s -o NUL -w "%{http_code}" http://localhost:8081/api/moods
      $site = curl.exe -s -o NUL -w "%{http_code}" http://localhost:8081/
      "$(Get-Date -f HH:mm:ss) api=$api site=$site"
      Start-Sleep 1
    }

**Терминал 2.** Записать данные, аварийно остановить БД и смотреть, как стек её поднимает:

    curl -X POST -H "Content-Type: application/json" -d '{"value":"great"}' http://localhost:8081/api/moods
    docker exec -u postgres lab2s-db pg_ctl stop -m immediate
    docker compose ps                       # db снова healthy
    docker inspect -f '{{.RestartCount}}' lab2s-db
    curl http://localhost:8081/api/moods    # запись на месте

(В PowerShell для POST используй `Invoke-RestMethod`, как в части C.)

**Почему не `docker kill` и не `docker stop`.** Docker считает их ручной остановкой, и политика `restart` для такого контейнера не срабатывает (мы проверили: после `docker kill lab2s-db` контейнер остался в статусе `Exited (137)`, `RestartCount=0`, а API всё время отвечал 500, пока базу не запустили руками через `docker start`). Аварию надо имитировать так, чтобы процесс упал сам. Для этого `pg_ctl stop -m immediate` завершает postgres без аккуратного выключения, контейнер выходит, и Docker применяет `restart: unless-stopped`.

Ожидаемая картина в терминале 1: пока БД лежит, `site=200` (статику отдаёт nginx), а `api` отдаёт ошибку (500); когда БД снова поднялась, `api=200`. Сколько секунд длился провал, видно по меткам времени.

### Результат

Скриншоты: `S-01-ps-healthy.png` (стек поднят, все healthy), `S-02-kill-db.png` (терминал 1: мониторинг, виден один ответ 500 и возврат 200), `S-02-recovery.png` (терминал 2: неудачная попытка через `docker kill` с `Exited (137)`, затем аварийная остановка, `docker compose ps`, `RestartCount`, запись на месте).

| Метрика | Значение |
| --- | --- |
| Как уронили БД | `docker exec -u postgres lab2s-db pg_ctl stop -m immediate` |
| Состояние БД после падения | Docker перезапустил контейнер сам, `RestartCount=1`, статус `healthy` |
| Длительность ошибок `api` | около 2 секунд (один ответ 500 в 21:06:24, в 21:06:26 снова 200) |
| Сайт (`/`) во время простоя | всё время 200 (статику отдаёт nginx) |
| Запись после восстановления | на месте (`{"id":1,"value":"great",...}`) |
| Бэкенд | не перезапускался, переподключился к БД сам |

Дополнительно можно показать порядок старта: `docker compose down` (без `-v`), затем `docker compose up -d` и `docker compose ps` несколько раз подряд. Бэкенд ждёт БД, фронт ждёт бэкенд.

## Демонстрация 2. Лимиты под нагрузкой

Метод: сначала ставим намеренно тесные лимиты и ловим проблемы, затем поднимаем значения, пока сервис не станет стабильным.

### Шаг 1. Тесные лимиты

    docker compose -f docker-compose.yml -f docker-compose.tight.yml up -d --force-recreate

В `docker-compose.tight.yml` заданы: backend 0.10 CPU / 48 МБ, db 0.25 CPU / 64 МБ. Это догадка о том, что будет тесно, точные цифры подбираются экспериментом. `memswap_limit` равен `memory`, иначе при включённом swap OOM не сработает.

Терминал 1, статистика ресурсов:

    docker stats lab2s-backend lab2s-db lab2s-frontend

Терминал 2, нагрузка (50 потоков, 30 секунд, запросы идут через nginx на бэкенд и в БД):

    docker compose --profile load run --rm load

Аргументы можно менять прямо в команде: `docker compose --profile load run --rm load python /loadgen.py http://frontend/api/moods 100 60`.

Что смотреть:

| Признак | Как проверить |
| --- | --- |
| Троттлинг CPU | в `docker stats` колонка CPU % упирается в лимит (около 10% у backend при 0.10); счётчики: `docker exec lab2s-backend cat /sys/fs/cgroup/cpu.stat` (строки `nr_throttled`, `throttled_usec`) |
| OOM | `docker inspect -f '{{.State.OOMKilled}} {{.RestartCount}}' lab2s-backend lab2s-db`; в `docker stats` колонка MEM USAGE / LIMIT близка к 100% |
| Влияние на клиента | вывод `loadgen.py`: число ошибок, rps, p95/p99 |

### Шаг 2. Подбор значений

Лимиты меняли прямо у работающего контейнера, не пересоздавая стек:

    docker update --memory 128m --memory-swap 128m lab2s-backend   # память (swap равен памяти)
    docker update --cpus 0.5 lab2s-backend                         # процессор
    docker update --memory 512m --memory-swap 512m --cpus 1 lab2s-db

После каждого изменения повторяли замер или нагрузку. Так как `docker compose up` ругается на `unhealthy` бэкенд и не запускает фронт, когда бэкенд не здоров, после подъёма лимитов стек надо было ещё раз запустить: `docker compose -f docker-compose.yml -f docker-compose.tight.yml up -d`.

Как проверяли, что бэкенд здоров на каждом шаге CPU: замеряли, за сколько секунд выполняется та же проверка, что делает healthcheck (`time docker exec lab2s-backend python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:5000/health', timeout=20).read())"`). Тайм-аут healthcheck 3 секунды.

### Результат

Скриншоты: `S-03-limits-config.png` (итоговые лимиты через `docker inspect`), `S-04-stats-tight.png` (повтор опыта на 0.10 CPU: ошибки healthcheck `exceeded timeout (3s)`, проверка 6.97 с, `nr_throttled` 5607 из 26058 периодов; счётчики копятся с запуска контейнера, поэтому больше, чем в таблице), `S-04b-cpu-steps.png` (после подъёма до 0.5 CPU: проверка 0.41 с, стек поднялся целиком), `S-05-oom.png` (`restarts=35` и события `oom` у бэкенда на 48 МБ), `S-06-stats-load.png` (`docker stats` под нагрузкой на итоговых лимитах), `S-06-load-result.png` (вывод генератора нагрузки на итоговых лимитах: ошибок 0).

| Шаг | Лимиты | Что произошло | Вердикт |
| --- | --- | --- | --- |
| 1 | backend 0.10 CPU / 48 МБ, db 0.25 CPU / 64 МБ | Бэкенд убивается по OOM каждые ~22 с (35 перезапусков за ~10 минут, события `oom`), на простое он использовал 43 МиБ из 48. Фронт не запускается: он ждёт здорового бэкенда | не стартует |
| 2 | backend 0.10 CPU / 128 МБ | OOM ушёл, бэкенд живёт, но healthcheck пишет `Health check exceeded timeout (3s)`, проверка `/health` вручную занимает **7.56 с**. В `cpu.stat`: `nr_throttled` 2771 из 4871 периодов (57%), `throttled_usec` около 268 с | троттлинг CPU, `unhealthy` |
| 3 | backend 0.25 CPU / 128 МБ | проверка `/health` занимает **3.27 с**, всё ещё больше тайм-аута | мало |
| 4 | backend 0.5 CPU / 128 МБ | проверка занимает **0.41 с**, бэкенд `healthy`, стек поднялся целиком | хватает для старта |
| 5 | нагрузка 50 потоков, 30 с; backend 0.5 CPU / 128 МБ, db 0.25 CPU / 64 МБ | `ok=205 errors=5739` (из них `HTTP 500`: 5732, таймаутов 7), `rps=5.2`, p95 4825 мс. У базы `RestartCount=8` (событий `oom` Docker не показал, точная причина не установлена), бэкенд упирался в 50% CPU | слишком тесно для базы |
| 6 (финал) | нагрузка 50 потоков, 30 с; backend 0.5 CPU / 128 МБ, db 1 CPU / 512 МБ, frontend 0.5 CPU / 64 МБ | `ok=1405 errors=0`, `rps=45.7`, p50 1003 мс, p95 1704 мс, p99 2648 мс. В `docker stats`: backend 50% CPU (упёрся в лимит), 74 МиБ из 128; db 34% CPU, 32 МиБ из 512; frontend 1.7% CPU | **стабильно** |

Итоговые значения: **backend 0.5 CPU / 128 МБ, db 1.0 CPU / 512 МБ, frontend 0.5 CPU / 64 МБ**. Они записаны в основной `docker-compose.yml`. Задержка около секунды объясняется тем, что бэкенд работает на пределе своего лимита CPU. Если нужно быстрее, повышать надо его лимит процессора.

## Уборка

    docker compose down          # контейнеры и сети, том остаётся
    docker compose down -v       # то же вместе с томом db_data
