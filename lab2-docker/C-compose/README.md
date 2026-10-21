# Часть C. Docker Compose: том и сетевая изоляция

## Что делали

Подняли весь стек Лабы 0 одной командой `docker compose up -d`: PostgreSQL, бэкенд (хороший образ из части B) и nginx в роли фронтенда. Данные БД лежат в именованном томе, а сети настроены так, что фронт не имеет доступа к базе.

## Структура

    C-compose/
    ├── docker-compose.yml   три сервиса, две сети, один том
    ├── nginx.conf           конфиг фронта: статика + прокси /api на бэкенд
    ├── .env.example         необязательные переменные (есть значения по умолчанию)
    └── screenshots/

## Сервисы и сети

| Сервис   | Образ                              | Сети                        | Порты хоста |
| -------- | ---------------------------------- | --------------------------- | ----------- |
| db       | postgres:16-alpine                 | backend-net                 | нет         |
| backend  | собирается из `B-good/Dockerfile`  | backend-net + frontend-net  | нет         |
| frontend | nginx:1.27-alpine                  | frontend-net                | 8080 -> 80  |

- Бэкенд единственный сервис в обеих сетях, поэтому только он может говорить с БД.
- Порт БД наружу не публикуется.
- Сервисы находят друг друга по имени (`db`, `backend`) через DNS compose.
- Контекст сборки бэкенда - корень репозитория (`../..`), потому что `B-good/Dockerfile` копирует `backend/` и `frontend/` от корня.
- Бэкенд стартует только после `service_healthy` у БД, иначе падает при создании таблицы.

## Запуск

    cd lab2-docker/C-compose
    docker compose up -d --build
    docker compose ps

Открыть http://localhost:8080.

## Проверки

### 1. Стек поднимается одной командой

`docker compose up -d` создаёт 3 контейнера, `docker compose ps` показывает их все в статусе running (db и backend ещё и healthy).

### 2. Данные переживают пересоздание контейнера

    Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/moods -ContentType "application/json" -Body '{"value":"great"}'
    curl.exe -s http://localhost:8080/api/moods        # запись есть
    docker volume ls --filter name=db_data             # том существует
    docker rm -f lab2-db                               # удаляем контейнер БД
    docker compose up -d                               # создаём заново
    curl.exe -s http://localhost:8080/api/moods        # запись на месте

Том `having-fun_db_data` контейнеру не принадлежит, поэтому остаётся после `docker rm`. (`docker compose down -v` том бы удалил, поэтому для проверки он не подходит.)

### 3. Сетевая изоляция

    docker exec lab2-frontend ping -c 1 db         # ошибка: bad address 'db'
    docker exec lab2-frontend nc -zv -w 2 db 5432  # ошибка соединения
    docker exec lab2-backend python -c "import socket; socket.create_connection(('db',5432),2); print('OK')"   # успех

Фронт и БД не делят ни одной сети, поэтому фронт даже не может разрешить имя `db`. Бэкенд, который стоит в обеих сетях, до БД доходит.

## Скриншоты

- `C-01-up.png` - `docker compose up -d`
- `C-02-ps.png` - `docker compose ps`, все сервисы running
- `C-03-persist.png` - запись до и после пересоздания контейнера БД
- `C-04-isolation.png` - фронт не видит БД, бэкенд видит
