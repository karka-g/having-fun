# Часть B: Хороший Dockerfile

## 🎯 Что было сделано
В этой части мы переписали Dockerfile для нашего FastAPI-приложения (из Лабы 0), исправив все ошибки из части А. Теперь образ собирается с помощью multi-stage build, работает от безопасного пользователя и использует кеширование слоев.

## 📄 Код `Dockerfile`

```dockerfile
FROM python:3.12-slim-bookworm AS builder

WORKDIR /app

COPY backend/requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.12-slim-bookworm

WORKDIR /app

COPY --from=builder /install /usr/local

COPY backend/ /app/backend/
COPY frontend/ /app/frontend/

RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "5000"]
```

## 🚫 Файл .dockerignore

Чтобы контекст сборки не раздувался лишними файлами, был добавлен `.dockerignore`:

```dockerignore
text
.git
.gitignore
node_modules
__pycache__
*.md
venv/
.env
.env.example
lab1-nginx/
lab1/
lab2-docker/
screenshot.png
``` 

## 🔄 Исправления (Bad → Good)

| Плохая практика (Часть А) | Как исправлено в Части Б |
| :--- | :--- |
| `FROM python:latest` | Зафиксирована версия `python:3.12-slim-bookworm` |
| `COPY . .` перед `pip install` | Сначала копируется `requirements.txt`, затем пакеты, и только потом код |
| `pip install` без `--no-cache-dir` | Добавлен флаг `--no-cache-dir` |
| Нет `.dockerignore` | Добавлен `.dockerignore` (контекст сборки сократился с 46 МБ до 1.1 МБ) |
| Запуск от `root` | Создан юзер `appuser`, контейнер работает от него |
| Один этап сборки | Использован multi-stage build (builder + runtime) |
| Нет проверки здоровья | Добавлен `HEALTHCHECK` на `/health` |

## 📊 Результаты замеров

| Параметр | Часть А (Плохой) | Часть Б (Хороший) | Результат |
| :--- | :--- | :--- | :--- |
| **Размер образа (Content size)** | 491 MB | **62.4 MB** | Уменьшился в **~8 раз** |
| **Пересборка после правки одной строки кода** | 27.6 сек | **2.33 сек** | Ускорилась в **~12 раз** (сработал кеш) |
| **Пересборка без изменений кода** | — | **1.88 сек** | Все слои взяты из кеша |
| **Пользователь (`whoami`)** | root | **appuser** | Повышена безопасность |
| **Статус контейнера** | — | **`Up (healthy)`** | Работает HEALTHCHECK |

## 📸 Скриншоты проверок

Все доказательства лежат в папке `screenshots/`:

- Сборка образа (успешно, 13 шагов): `B-01-build.png`
- Размер образа (62.4 MB): `B-02-size.png`
- Проверка пользователя (whoami → appuser): `B-03-whoami.png`
- Проверка статуса (Up (healthy)): `B-04-health.png`
- Замер кеша: пересборка без изменений кода (1.88 сек): `B-05-timing.png`
- Замер кеша: пересборка после правки одной строки кода (2.33 сек): `../D-report/screenshots/D-03-timing-comparison.png`

## 💡 Вывод

Благодаря правильному порядку слоев (сначала `requirements.txt`, потом код) и использованию `--no-cache-dir`, нам удалось ускорить пересборку после правки одной строки кода до 2.33 секунды (27.6 секунды у плохого образа). Multi-stage build и slim версия базового образа позволили уменьшить размер с 491 МБ до 62.4 МБ. Приложение теперь запускается от безопасного пользователя appuser и имеет встроенную проверку здоровья.

