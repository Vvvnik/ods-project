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

- **Kroki** - запускается на хосте, доступен через `host.docker.internal:8000` (URL передаётся в Antora через `KROKI_SERVER_URL` и `--attribute kroki-server-url=...`)
- **Ollama** - запускается на хосте, доступен через `host.docker.internal:11434` (настроено в `docker-compose.yml` через `OLLAMA_HOST`)
- **PostgreSQL** (pg-demo) - работает на хосте, доступен через `host.docker.internal` (настроено через `DB_HOST`)

Такая архитектура позволяет:

- Использовать минимальное количество контейнеров (только `pdf` и `site`)
- Переиспользовать сервисы, запущенные на хосте
- Легко переключаться между локальной разработкой и CI/CD

### Запуск

```bash
# Генерация (tools/start.rb)
docker-compose -f docker/docker-compose.yml run --rm start

# Сборка сайта
docker-compose -f docker/docker-compose.yml run --rm site

# Предпросмотр сайта (поднимает HTTP сервер на порту 8080)
# Откройте в браузере: http://localhost:8080
docker-compose -f docker/docker-compose.yml up site-preview

# Альтернатива через run (нужно пробросить порты):
docker-compose -f docker/docker-compose.yml run --rm --service-ports site-preview

# Откройте ссылку из вывода сервера (Ctrl+Click).
# Для выхода из режима сервера: Ctrl+C.

# С конкретным компонентом
docker-compose -f docker/docker-compose.yml run --rm start ruby tools/start.rb postgre-service
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
# Ollama опциональна – проверяйте только если используете LLM
curl -sS http://localhost:11434/api/version || true
# Ожидаемый ответ (пример):
# {"version":"0.13.4"}
# Если поддерживается, можно посмотреть список моделей:
# curl -sS http://localhost:11434/api/tags

# Проверка PostgreSQL
# psql может быть не установлен на хосте – проверим, что порт доступен
nc -vz localhost 5432
# Ожидаемый ответ (пример):
# Connection to localhost port 5432 [tcp/postgresql] succeeded!
```

### Настройка Kroki для docker-compose / CI

Единый подход: передаём `kroki-server-url` через CLI-атрибут Antora, а само значение берём из `KROKI_SERVER_URL`.

- Локально (docker-compose): по умолчанию `http://host.docker.internal:8000` (задаётся в `docker/docker-compose.yml`)
- В CI: `http://kroki:8000` (задаётся в `.gitlab-ci.yml`)

Примечание: в docker-compose для сервиса `site` используется `kroki-fetch-diagram!`, поэтому Antora **не обращается к Kroki во время сборки** (сборка пройдёт даже если Kroki не запущен).
При этом диаграммы **не встраиваются** в результат сборки (`public/`) и без доступного Kroki (или без пересборки в режиме “встроить диаграммы”) могут не отображаться.
+
Если хотите “встроить” диаграммы в HTML на этапе сборки (чтобы они отображались из `public/` без Kroki при просмотре), уберите `kroki-fetch-diagram!` и убедитесь, что Kroki доступен по `KROKI_SERVER_URL` во время сборки (неважно: Kroki на хосте или отдельным контейнером).

### Важно про “порт Antora”

Antora **не поднимает веб‑сервер** – она генерирует статические файлы в `public/`.  
Чтобы “запустить с портом”, используйте сервис `site-preview` (или любой другой статический сервер).

### Примечание про 404 шрифтов в site-preview

Если в логах `site-preview` вы видите 404 вида `GET /_/css/~@fontsource/...`, это означает, что браузер/сервер отдавал закешированную версию CSS со старыми путями.
В сервисе `site-preview` кеширование отключено (опция `http-server -c-1`), поэтому обычно достаточно перезапустить `site-preview` и сделать hard refresh страницы (Cmd+Shift+R / Ctrl+F5).

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
