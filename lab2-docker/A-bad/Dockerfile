# BAD #1: не зафиксирована версия python.
# При следующей сборке может подтянуться другая версия (3.13, 4.x)
# и приложение внезапно сломается.
# Хорошо: FROM python:3.12-slim-bookworm
FROM python:latest

WORKDIR /app

# BAD #2: COPY . . стоит ДО установки зависимостей.
# Любая правка в ЛЮБОМ файле проекта инвалидирует этот слой,
# а значит и следующий за ним pip install. кеш слоёв не работает вообще.
# Хорошо: сначала COPY backend/requirements.txt, потом pip install,
# и только потом COPY . .
COPY . .

# BAD #3: pip install без --no-cache-dir.
# Кеш pip (десятки МБ wheels) остаётся внутри слоя и раздувает образ.
# Хорошо: RUN pip install --no-cache-dir -r backend/requirements.txt
RUN pip install -r backend/requirements.txt

# Нет .dockerignore — поэтому COPY . . втянул в образ .git/, lab1/,
# lab1-nginx/, demo-lab1/, screenshot.png и все картинки.
# Это тоже bad practice, но реализуется ОТСУТСТВИЕМ файла, а не строкой.

# BAD #4: нет инструкции USER. контейнер запускается от root.
# Если в приложении найдут RCE, атакующий получит root в контейнере.
# Хорошо: RUN useradd -m appuser  +  USER appuser

EXPOSE 5000

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "5000"]