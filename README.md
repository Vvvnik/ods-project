# ODS – Open Documentation Standard

ODS предназначен для:

- разработчиков и архитекторов;
- технических писателей;
- команд, использующих Docs-as-Code и CI/CD.

*(Не связан с форматом OpenDocument Spreadsheet (.ods) или проектами Open Data)*  

[![License Code](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE-CODE.md)
[![License Docs](https://img.shields.io/badge/license-CC--BY--4.0-yellow)](LICENSE-DOCS.md)

ODS — это открытый стандарт и инструменты для автоматизации технической документации в ИТ-проектах.

## Быстрый старт

```bash
# Установка зависимостей
gem install asciidoctor asciidoctor-pdf asciidoctor-kroki
npm install

# Установка и запуск Ollama (для LLM переводов)
curl -fsSL https://ollama.ai/install.sh | sh
ollama serve &
       ollama pull gemma:latest  # Рекомендуемая модель (5 GB)

# Сборка документации (диаграммы, БД, API, PDF)
ruby tools/start.rb

# Сборка сайта документации (Antora)
npx antora --attribute kroki-server-url=http://localhost:8000 antora-playbook.yml
```

## Два независимых процесса

1. **Сборка документации** — генерация AsciiDoc файлов и PDF из различных источников
2. **Сборка сайта** — создание HTML сайта из готовых AsciiDoc файлов

Процессы независимы. Конфигурация Antora не связана с конфигурацией сборки документации.

## Требования к LLM

Для автоматических переводов атрибутов базы данных требуется:

- **Ollama** — локальный сервер для запуска LLM моделей
       - **Рекомендуемая модель**: `gemma:latest` (5 GB) — лучший баланс качества и скорости
       - **Самая быстрая**: `gemma3:4b` (3.3 GB) — оптимальная скорость и качество
       - **Альтернативные модели**: `mistral:7b`, `qwen2.5:latest`, `gpt-oss:20b`
- **Локальное использование** — LLM работает только на машине разработчика

Подробнее см. [Работа с LLM](./components/project-guide/modules/ROOT/pages/Работа_с_LLM.adoc).

## Документация

Подробная документация находится в файле [readme.adoc](./readme.adoc) и разделе: [Руководство по документированию](./components/project-guide/modules/ROOT/pages/index.adoc).

## Лицензии

- Код: [Apache-2.0](./LICENSE-CODE.md)
- Документы: [CC-BY 4.0](./LICENSE-DOCS.md)

## Коммерческое использование

ODS — полностью открытый проект (Apache 2.0 / CC-BY 4.0).  

Дополнительные коммерческие возможности, внедрение и сопровождение описаны в [COMMERCIAL.md](./COMMERCIAL.md).

## Благодарности

Этот проект был создан с использованием ИИ-инструментов для генерации кода и руководства по документированию.
