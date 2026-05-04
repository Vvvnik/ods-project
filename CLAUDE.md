# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Проект

**ODS (Open Documentation Standard)** — открытый стандарт и инструменты для автоматизации технической документации в ИТ-проектах. Документация хранится в формате AsciiDoc, собирается в HTML-сайт через Antora и в PDF через asciidoctor-pdf.

## Два независимых процесса сборки

### 1. Сборка документации (генерация .adoc, PDF, диаграмм)

```bash
ruby tools/start.rb                    # все компоненты
ruby tools/start.rb airport-service   # один компонент
npm run build                          # то же через npm
```

Управляется через `tools/config.yml`. Выполняет по порядку: BPMN → Draw.io → API → БД → PDF → списки файлов → lint.

### 2. Сборка HTML-сайта (Antora)

```bash
npm run site                           # локально с Kroki на localhost:8000
npx antora antora-playbook.yml         # то же вручную
npm run build-all                      # сборка документации + сайт последовательно
```

Сайт собирается в `public/`. Требует работающего Kroki-сервера для рендеринга диаграмм.

### Docker

```bash
docker-compose -f docker/docker-compose.yml run --rm start   # только документация
docker-compose -f docker/docker-compose.yml run --rm site    # только сайт
```

Для Docker в `antora-playbook.yml` нужно установить `kroki-server-url: http://host.docker.internal:8000`.

### Python-инструменты (генерация описаний через LLM)

```bash
cd python
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python src/services/generate_description.py [--dry-run]
```

Требует Python 3.10+ и работающего Ollama. Настройки в `python/config.yaml`.

### Jira → Markdown

```bash
ruby tools/scripts/jira_issue_to_md.rb         # все задачи из tools/jira/jira_main_issues.txt
ruby tools/scripts/jira_issue_to_md.rb ODS-42  # одна задача
```

Требует переменную окружения `JIRA_API_TOKEN`. Результат в `tools/jira/<KEY>/`.

## Архитектура

### Компоненты Antora (`components/`)

Каждый компонент — независимая единица документации со структурой:

```
components/<name>/
  antora.yml              # метаданные компонента (name, title, version, nav)
  modules/ROOT/
    pages/                # .adoc страницы (источник контента)
    partials/             # include-фрагменты (docs-api/, docs-db/, lists/)
    images/               # изображения (bpmn/, drawio/, images-db/)
    examples/             # исходники для конвертации (bpmn/, drawio/, sources.yml, database.yml)
    attachments/          # готовые PDF
    nav.adoc              # навигация
```

Компоненты: `airport-service`, `data-processing-engine`, `information-system`, `toys-service`, `project-guide`, `project-guide-en`.

Набор компонентов и порядок их загрузки задаётся в `antora-playbook.yml`.

### Инструменты (`tools/`)

`tools/start.rb` — оркестратор сборки. Читает `tools/config.yml`, обходит каждый компонент и вызывает скрипты из `tools/scripts/`:

| Скрипт | Назначение |
|--------|-----------|
| `bpmn_to_img.js` | `.bpmn` → SVG (через Puppeteer) |
| `drawio_to_img.js` | `.drawio` → SVG |
| `openapi-swagger-adoc.rb` | OpenAPI/Swagger → `.adoc` |
| `db_to_adoc.rb` | схема PostgreSQL → `.adoc` + PNG (ERD) |
| `generate_lists.rb` | генерация списков файлов `.adoc`/PDF |
| `convert_ascii_to_pdf.rb` | `.adoc` → PDF (с титульными страницами) |
| `jira_issue_to_md.rb` | Jira issue → `.md` |

Библиотеки в `tools/lib/` используются скриптами напрямую через `require_relative`.

### Python (`python/`)

Генерирует описания/release notes из Jira-задач через LLM (Ollama). Точка входа — `python/src/services/generate_description.py`. Настройки в `python/config.yaml`; виртуальное окружение — `python/venv` (не `.venv`).

### UI (`ui-files/`)

- `ui-bundle.zip` — базовый UI-бандл Antora (не изменять без нужды)
- `ui-bundle-style/` — кастомные CSS/JS/шаблоны поверх базового бандла; подключается как `supplemental_files` в `antora-playbook.yml`

### Ресурсы (`resources/`)

- `resources/themes/` — YAML-темы для asciidoctor-pdf (`report-theme.yml`, `default-theme.yml`, `act-theme.yml` и др.)
- `resources/fonts/` — шрифты Roboto и Times New Roman для PDF

## Конфигурация

### `tools/config.yml`

Центральный конфиг сборки. Секция `defaults` задаёт параметры по умолчанию для всех компонентов (BPMN, Draw.io, API, БД, PDF, lint — все отключены по умолчанию). Компоненты в секции `components` наследуют `defaults` через YAML-якорь `<<: *defaults` и могут переопределять отдельные секции.

В CI (`ENV['CI']`) автоматически отключаются BPMN, Draw.io, API, БД — только PDF и Antora.

### Переменные окружения

| Переменная | Использование |
|-----------|--------------|
| `KROKI_SERVER_URL` | URL Kroki-сервера (по умолчанию `http://localhost:8000`) |
| `JIRA_API_TOKEN` | Atlassian API token для Jira-интеграции |
| `JIRA_EMAIL` | Email аккаунта Atlassian |
| `OLLAMA_HOST` | URL Ollama-сервера (по умолчанию `http://localhost:11434`) |

Секреты хранятся в `.env` (в `.gitignore`). Для автозагрузки — используйте direnv с `.envrc` (`dotenv`).

## CI/CD (`.gitlab-ci.yml`)

Три сценария:
- **MR** → только проверка merge-конфликтов
- **push в main** → полная сборка (`ruby tools/start.rb` + `antora generate`) → деплой GitLab Pages
- **теги** → генерация release notes + создание GitLab Release

Образы: `registry.gitlab.com/vvvnik/ods-project/ruby-node-antora:2` (Ruby + Node.js + Antora), Kroki как сервис.

## Стек технологий

- **AsciiDoc / Antora** — формат документации и генератор сайта
- **Ruby 3.2+** — инструменты сборки: PDF (asciidoctor-pdf), конвертация диаграмм, парсинг БД
- **Node.js 20+ / npm** — Antora, Puppeteer (BPMN), Draw.io CLI, xml2js
- **Python 3.10+** — генерация описаний через LLM (Ollama)
- **Kroki** — серверный рендеринг диаграмм (PlantUML, GraphViz и др.)
- **PostgreSQL** — источник для автогенерации документации БД
- **Docker / docker-compose** — воспроизводимая сборка и CI

## Шаблоны и сниппеты

`templates/` — готовые шаблоны для новых компонентов:
- `templates/diagrams/` — примеры `.drawio` и `.puml`
- `templates/glossary/glossary.adoc` — шаблон глоссария
- `templates/snippets/` — VS Code сниппеты для AsciiDoc
- `templates/templates_doc/` — Antora-компонент с документацией по шаблонам

## Команда и контекст
- Ольга — архитектор, работает с ГОСТ-шаблонами
- Владимир — технический директор, весь стек
- Лена — документация и контент

## Правила общения
- Всегда отвечай только на русском
- Ветки создавать по формату ODS-XX-название
- Целевые клиенты: ИТ-подрядчики госзаказа и интеграторы 5-50 чел. с контрактами от 30 млн ₽, которым нужна документация по ГОСТ 34, мигрирующие с Confluence или работающие с КИИ.

## Частые команды
- Обнови CLAUDE.md: "Перечитай репозиторий и обнови CLAUDE.md"
- Создать ветку из задачи: "Создай ветку для ODS-XX"
- Проверить структуру: "Проверь структуру компонента X"
