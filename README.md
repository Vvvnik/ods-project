# ODS – Open Documentation Standard

ODS предназначен для:

- разработчиков и архитекторов;
- технических писателей;
- команд, использующих Docs-as-Code и CI/CD.

*(Не связан с форматом OpenDocument Spreadsheet (.ods) или проектами Open Data)*  

[![License Code](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE-CODE.md)
[![License Docs](https://img.shields.io/badge/license-CC--BY--4.0-yellow)](LICENSE-DOCS.md)

ODS – это открытый стандарт и инструменты для автоматизации технической документации в ИТ-проектах.

Репозиторий реализации: **ODS-project** (`ods-project`) – [gitlab.com/vvvnik/ods-project](https://gitlab.com/vvvnik/ods-project).

## Как читать документацию репозитория

- **`README.md`** – краткий обзор и самый быстрый запуск.
- **`readme.adoc`** – подробная инструкция по установке/сборке (Docker, генерация PDF/HTML, зависимости, ссылки).

## Самый быстрый запуск (локально)

```bash
npm install
ruby tools/start.rb
npx antora antora-playbook.yml
```

Подробно (включая Docker/LLM/Kroki и все зависимости): см. [readme.adoc](./readme.adoc).

## Два независимых процесса

1. **Сборка документации** – генерация AsciiDoc файлов и PDF из различных источников
2. **Сборка сайта** – создание HTML сайта из готовых AsciiDoc файлов

Процессы независимы. Конфигурация Antora не связана с конфигурацией сборки документации.

## Документация

Подробная документация находится в файле [readme.adoc](./readme.adoc).

Полное руководство:

- RU: [Руководство по документированию](./components/project-guide/modules/ROOT/pages/index.adoc)
- EN: [Documentation Guide](./components/project-guide-en/modules/ROOT/pages/index.adoc)

## Лицензии

- Код: [Apache-2.0](./LICENSE-CODE.md)
- Документы: [CC-BY 4.0](./LICENSE-DOCS.md)

## Коммерческое использование

ODS – полностью открытый проект (Apache 2.0 / CC-BY 4.0).  

Дополнительные коммерческие возможности, внедрение и сопровождение описаны в [COMMERCIAL.md](./COMMERCIAL.md).

## Благодарности

Этот проект был создан с использованием ИИ-инструментов для генерации кода и руководства по документированию.
