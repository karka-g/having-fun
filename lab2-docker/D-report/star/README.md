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
| Лимиты (стартовые) | 1.0 CPU, 512 МБ | 1.0 CPU, 256 МБ | 0.5 CPU, 64 МБ |

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

**Терминал 2.** Записать данные, убить БД и смотреть, как стек её поднимает:

    curl -X POST -H "Content-Type: application/json" -d '{"value":"great"}' http://localhost:8081/api/moods
    docker kill lab2s-db
    docker compose ps                       # db перезапускается, потом снова healthy
    docker inspect -f '{{.RestartCount}}' lab2s-db
    curl http://localhost:8081/api/moods    # запись на месте

(В PowerShell для POST используй `Invoke-RestMethod`, как в части C.)

Именно `docker kill`, а не `docker stop`: после ручной остановки (`docker stop`) политика `unless-stopped` контейнер не поднимает, потому что остановка считается намеренной.

Ожидаемая картина в терминале 1: пока БД лежит, `site=200` (статику отдаёт nginx), а `api` отдаёт ошибку (500); через несколько секунд, когда БД снова healthy, `api=200`. Сколько именно секунд длился провал, зафиксируй по меткам времени в выводе.

### Результат

_Заполнить после прогона._ Скриншоты: `S-01-ps-healthy.png` (стек поднят, все healthy), `S-02-kill-db.png` (вывод терминала 1 во время и после `docker kill`, `docker compose ps`, `RestartCount`).

| Метрика | Значение |
| --- | --- |
| Время от `docker kill` до `healthy` у БД | _заполнить_ |
| Длительность ошибок `api` | _заполнить_ |
| Сайт (`/`) во время простоя | _заполнить_ |
| Запись после восстановления на месте | _да / нет_ |

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

Подними лимиты, поправив значения в `docker-compose.tight.yml` (или сразу в основном файле), повтори нагрузку и снова смотри `docker stats`. Цель: ошибок нет, `OOMKilled=false`, `RestartCount` не растёт, CPU % заметно ниже лимита, задержки приемлемые. Основной `docker-compose.yml` содержит стартовые значения (1.0 CPU / 256 МБ для backend, 1.0 CPU / 512 МБ для db, 0.5 CPU / 64 МБ для frontend), финальные значения после подбора внеси в таблицу ниже и поправь основной файл, если они отличаются.

### Результат

_Заполнить после прогона._ Скриншоты: `S-03-limits-config.png` (выставленные лимиты, например `docker inspect` или `docker stats` с колонкой LIMIT), `S-04-stats-tight.png` (docker stats под нагрузкой на тесных лимитах, виден троттлинг), `S-05-oom.png` (`OOMKilled=true` / `RestartCount`), `S-06-stats-final.png` (docker stats под нагрузкой на финальных лимитах).

| Попытка | Лимиты (backend / db) | Что произошло | Вердикт |
| --- | --- | --- | --- |
| 1 (tight) | 0.10 CPU, 48 МБ / 0.25 CPU, 64 МБ | _заполнить: троттлинг? OOM? ошибки, rps_ | _заполнить_ |
| 2 | _заполнить_ | _заполнить_ | _заполнить_ |
| финал | _заполнить_ | _заполнить: rps, p95, ошибок 0, OOM нет_ | стабильно |

## Уборка

    docker compose down          # контейнеры и сети, том остаётся
    docker compose down -v       # то же вместе с томом db_data
