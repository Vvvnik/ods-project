# Docker для проекта

## 🐳 Образы

Проект использует **три образа**:

- **`ruby-node-antora`** - Универсальный образ с Ruby + Node.js + все пакеты
  - Реестр: `registry.gitlab.com/vvvnik/ods-project/ruby-node-antora:2` (используется в CI и docker-compose)
  - Dockerfile: `docker/Dockerfile.universal`
- **`kroki`** - Сервис для рендеринга диаграмм (PlantUML, Mermaid, Graphviz)
  - Реестр: `registry.gitlab.com/vvvnik/ods-project/kroki:0.28.0`
  - Базовый образ: `yuzutech/kroki:0.28.0`
- **`ollama`** - Сервис для LLM переводов (опционально, для локальной разработки)
  - Реестр: `registry.gitlab.com/vvvnik/ods-project/ollama:1`
  - Базовый образ: `ollama/ollama:latest`
  - Модель: `gemma:latest` (предзагружена в образе с моделью)

## 🚀 Локальная разработка

### Архитектура для локальной разработки

Для локальной разработки в `docker-compose.yml` достаточно **двух сервисов**:

1. **`pdf`** - генерация PDF документов
2. **`site`** - сборка сайта с Antora

Все внешние сервисы (Kroki, Ollama, PostgreSQL) работают **на хосте** и доступны контейнерам через `host.docker.internal`:

* **Kroki** - запускается на хосте, доступен через `host.docker.internal:8000` (настроено в `antora-playbook.yml`)
* **Ollama** - запускается на хосте, доступен через `host.docker.internal:11434` (настроено в `docker-compose.yml` через `OLLAMA_HOST`)
* **PostgreSQL** (pg-demo) - работает на хосте, доступен через `host.docker.internal` (настроено через `DB_HOST`)

Такая архитектура позволяет:

- Использовать минимальное количество контейнеров (только `pdf` и `site`)
- Переиспользовать сервисы, запущенные на хосте
- Легко переключаться между локальной разработкой и CI/CD

### Запуск

```bash
# PDF генерация
docker-compose -f docker/docker-compose.yml run --rm pdf

# Сборка сайта
docker-compose -f docker/docker-compose.yml run --rm site

# С конкретным компонентом
docker-compose -f docker/docker-compose.yml run --rm pdf ruby tools/start.rb airport-service
```

### Проверка подключения к сервисам

Перед запуском убедитесь, что все необходимые сервисы запущены на хосте:

```bash
# Проверка Kroki
# Проверяем Kroki рендером PlantUML (это то, что реально нужно проекту)
printf '%s\n' '@startuml' 'Alice -> Bob: test' '@enduml' | \
  curl -sS -X POST http://localhost:8000/plantuml/svg \
    -H 'Content-Type: text/plain' \
    --data-binary @- -o /dev/null -w 'HTTP=%{http_code} CT=%{content_type}\n'
# Ожидаемый ответ:
# HTTP=200 CT=image/svg+xml

# Проверка Ollama
# Ollama опциональна — проверяйте только если используете LLM
curl -sS http://localhost:11434/api/version || true
# Ожидаемый ответ (пример):
# {"version":"0.13.4"}
# Если поддерживается, можно посмотреть список моделей:
# curl -sS http://localhost:11434/api/tags

# Проверка PostgreSQL
# psql может быть не установлен на хосте — проверим, что порт доступен
nc -vz localhost 5432
# Ожидаемый ответ (пример):
# Connection to localhost port 5432 [tcp/postgresql] succeeded!
```

### Настройка Kroki для docker-compose

При использовании `docker-compose -f docker/docker-compose.yml run --rm site` необходимо настроить `kroki-server-url` в `antora-playbook.yml`:

```yaml
# Для docker-compose локальной разработки:
kroki-server-url: http://host.docker.internal:8000

# Перед отправкой в CI замените на:
# kroki-server-url: http://kroki:8000 # for CI
```

⚠️ **Важно**: Перед отправкой изменений в CI убедитесь, что в `antora-playbook.yml` установлено `kroki-server-url: http://kroki:8000`.

## 🔧 Сборка образов

### Универсальный образ (ruby-node-antora)

```bash
# Сборка и отправка в реестр (по умолчанию)
./docker/build-images.sh [tag]

# Только сборка, без отправки в реестр
./docker/build-images.sh [tag] --no-push

# Примеры
./docker/build-images.sh 2
./docker/build-images.sh 2 --no-push
```

### Kroki образ

```bash
# Сборка и отправка в реестр (по умолчанию)
./docker/build-kroki.sh [tag]

# Только сборка, без отправки в реестр
./docker/build-kroki.sh [tag] --no-push

# Примеры
./docker/build-kroki.sh 0.28.0
./docker/build-kroki.sh 0.29.0 --no-push
```

### Ollama образ

#### Базовый образ (без модели)

Модель загружается при запуске контейнера:

```bash
# Сборка и отправка в реестр (по умолчанию)
./docker/build-ollama.sh [tag]

# Только сборка, без отправки в реестр
./docker/build-ollama.sh [tag] --no-push

# Примеры
./docker/build-ollama.sh 1
./docker/build-ollama.sh 1 --no-push
```

#### Образ с предзагруженной моделью

Модель загружается во время сборки образа (размер образа 10+ GB):

```bash
# Сборка и отправка в реестр (по умолчанию)
./docker/build-ollama-with-model.sh [tag] [model]

# Только сборка, без отправки в реестр
./docker/build-ollama-with-model.sh [tag] [model] --no-push

# Примеры
./docker/build-ollama-with-model.sh 1 gemma:latest
./docker/build-ollama-with-model.sh 1 gemma:latest --no-push
```

⚠️ **Важно**: Образ с моделью очень большой (10+ GB), загрузка в реестр может занять много времени.

## 📦 Содержимое универсального образа

### Ruby 3.2 + Gems (зафиксированные версии)

- `asciidoctor:2.0.25`
- `asciidoctor-pdf:2.3.21`
- `asciidoctor-diagram:3.0.1`
- `asciidoctor-kroki:0.10.0`
- `rouge:4.6.1`
- `prawn:2.5.0`
- `hexapdf:1.4.1`
- `pg:1.6.2`

### Node.js 20 + NPM пакеты (зафиксированные версии)

- `@antora/cli@3.1.14`
- `@antora/site-generator-default@3.1.14`
- `@antora/site-generator@3.1.14`
- `@antora/lunr-extension@1.0.0-alpha.10`
- `puppeteer@24.26.1`
- `xml2js@0.6.2`

### Системные зависимости

- `build-essential`, `git`, `curl`, `wget`, `unzip`, `ca-certificates`, `gnupg`

**Все версии пакетов зафиксированы для воспроизводимости сборок.**

## 📁 Структура

```text
docker/
├── Dockerfile.universal          # Универсальный образ (Ruby + Node.js)
├── docker-compose.yml            # Локальная разработка
├── build-images.sh              # Сборка универсального образа
├── build-kroki.sh               # Сборка Kroki образа
├── build-ollama.sh              # Сборка Ollama образа (без модели)
├── build-ollama-with-model.sh   # Сборка Ollama образа (с моделью)
└── README.md                    # Эта документация
```
