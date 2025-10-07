# ODS – Open Documentation Standard

[![License Code](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE-CODE)
[![License Docs](https://img.shields.io/badge/license-CC--BY--4.0-yellow)](LICENSE-DOCS)

ODS — это открытый стандарт и инструменты для автоматизации технической документации в ИТ-проектах.

## Быстрый старт

```bash
# Сборка документации (диаграммы, БД, API, PDF)
gem install asciidoctor asciidoctor-pdf asciidoctor-kroki
npm install
ruby tools/start.rb

# Сборка сайта документации (Antora)
npx antora --fetch antora-playbook.yml
```

## Два независимых процесса

1. **Сборка документации** — генерация AsciiDoc файлов и PDF из различных источников
2. **Сборка сайта** — создание HTML сайта из готовых AsciiDoc файлов

Процессы независимы. Конфигурация Antora не связана с конфигурацией сборки документации.

## Документация

Полная документация находится в файле [readme.adoc](./readme.adoc).

## Лицензии

- Код: [Apache-2.0](./LICENSE-CODE.md)
- Документы: [CC-BY 4.0](./LICENSE-DOCS.md)
