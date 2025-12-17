# Docker для проекта

## 🐳 Образы

Проект использует **два образа**:

- **`ruby-node-antora`** - Универсальный образ с Ruby + Node.js + все пакеты
  - Реестр: `registry.gitlab.com/vvvnik/ods-project/ruby-node-antora:2` (используется в CI и docker-compose)
  - Dockerfile: `docker/Dockerfile.universal`
- **`kroki`** - Сервис для рендеринга диаграмм (PlantUML, Mermaid, Graphviz)
  - Реестр: `registry.gitlab.com/vvvnik/ods-project/kroki:0.28.0`
  - Базовый образ: `yuzutech/kroki:0.28.0`

## 🚀 Локальная разработка

```bash
# PDF генерация
docker-compose -f docker/docker-compose.yml run --rm pdf

# Сборка сайта
docker-compose -f docker/docker-compose.yml run --rm site

# С конкретным компонентом
docker-compose -f docker/docker-compose.yml run --rm pdf ruby tools/start.rb airport-service
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
├── Dockerfile.universal     # Универсальный образ (Ruby + Node.js)
├── docker-compose.yml       # Локальная разработка
├── build-images.sh         # Сборка универсального образа
├── build-kroki.sh          # Сборка Kroki образа
└── README.md               # Эта документация
```
