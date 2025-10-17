# Docker для проекта

## 🐳 Универсальный образ

Проект использует **один универсальный образ** для всех задач:

- **`Dockerfile.universal`** - Универсальный образ с Ruby + Node.js + все пакеты
- **`registry.gitlab.com/vvvnik/ods-project/ruby-node-antora:1`** - готовый образ в реестре

## 🚀 Локальная разработка

```bash
# PDF генерация
docker-compose -f docker/docker-compose.yml run --rm pdf

# Сборка сайта
docker-compose -f docker/docker-compose.yml run --rm site

# С конкретным компонентом
docker-compose -f docker/docker-compose.yml run --rm pdf ruby tools/start.rb airport-service
```

## 🔧 Сборка образов

```bash
# Универсальный образ
docker build -f docker/Dockerfile.universal -t registry.gitlab.com/vvvnik/ods-project/ruby-node-antora:1 .
docker push registry.gitlab.com/vvvnik/ods-project/ruby-node-antora:1

# Kroki сервис
./docker/build-kroki.sh
```

## 📦 Содержимое образа

- **Ruby 3.2** + gems (asciidoctor, asciidoctor-pdf, asciidoctor-diagram, asciidoctor-kroki)
- **Node.js 20** + пакеты (@antora/cli, @antora/site-generator)
- **Системные зависимости** (build-essential, git, curl, fonts)

## 📁 Структура

```
docker/
├── Dockerfile.universal     # Универсальный образ
├── docker-compose.yml       # Локальная разработка
├── build-images.sh         # Сборка образов
├── build-kroki.sh          # Сборка Kroki
└── README.md               # Эта документация
```