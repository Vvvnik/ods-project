# Секреты, переменные и интеграции Jira ↔ GitLab

Секреты **не коммитятся** в Git. В `tools/config.yml` строка `"${JIRA_API_TOKEN}"` – только **имя** переменной для людей; Ruby при чтении YAML **не подставляет** окружение. Скрипт `tools/scripts/jira_issue_to_md.rb` сначала смотрит **`ENV['JIRA_API_TOKEN']`**, и только если пусто – берёт значение из YAML (поэтому без окружения в логах бывает «ложный» 404 от Jira).

Ниже – **что за токен куда кладётся** (это разные места, их путают чаще всего):

| Где используется | Что за секрет | Типичное место настройки |
|------------------|---------------|---------------------------|
| Локальный скрипт (macOS / Linux / Windows), опционально CI job | Atlassian **API token** + email | `.env`, [API tokens](https://id.atlassian.com/manage-profile/security/api-tokens) |
| Пайплайны GitLab | Тот же или отдельный токен (как решите) | [CI/CD Variables](https://docs.gitlab.com/ee/ci/variables/) в проекте |
| Форма **Jira** в GitLab (коммиты, ссылки на задачи) | Обычно **тот же** Atlassian API token + URL сайта Jira + email | [Integrations → Jira](https://docs.gitlab.com/ee/integration/jira/) в проекте GitLab |
| Приложение **GitLab for Jira Cloud** | OAuth / подключение организации GitLab к сайту Jira | Сторона Jira: приложения, конфигурация коннектора |

Один и тот же API-токен Atlassian **технически** можно указать и в `.env`, и в интеграции GitLab, и в CI – но при отзыве токена всё отвалится сразу. Для продакшена CI иногда заводят **отдельный** токен и отдельную учётную запись с минимальными правами.

---

## 1. Выпустить API-токен Atlassian (база для Jira Cloud)

1. Войдите в аккаунт Atlassian.
2. Откройте страницу управления API-токенами:  
   **[https://id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens)**
3. **Create API token**, задайте заметное имя (например `gitlab-jira-integration`), скопируйте значение **один раз** и сохраните в менеджер паролей / `.env` / переменную GitLab.

Для запросов к Jira Cloud API (скрипт, интеграция GitLab) используется пара **email учётной записи Atlassian** + этот **API token** (не пароль от сайта).

---

## 2. Локально: `.env` и скрипт выгрузки задач из Jira

1. В **корне репозитория** (рядом с `.git`) создайте файл `.env` (он в `.gitignore`). Содержимое **одинаково на всех ОС**:

   ```bash
   JIRA_API_TOKEN=вставьте_токен_из_шага_1
   JIRA_EMAIL=your-atlassian-email@example.com
   ```

2. Подставить переменные в **текущий** терминал:

   **macOS / Linux – bash или zsh** (в т.ч. Git Bash на Windows):

   ```bash
   set -a
   source .env
   set +a
   ```

   **Windows – PowerShell** (в каталоге с `.env`):

   ```powershell
   Get-Content .env | ForEach-Object {
     if ($_ -match '^\s*([^#][^=]*?)\s*=\s*(.*)$') {
       $n = $matches[1].Trim(); $v = $matches[2].Trim().Trim('"')
       Set-Item -Path "env:$n" -Value $v
     }
   }
   ```

   **Windows – CMD:** встроенной загрузки `.env` нет; используйте PowerShell из шага выше или **Git Bash** с блоком для macOS/Linux.

3. Проверка, что токен не пустой:

   **macOS / Linux – bash/zsh / Git Bash:** `echo "${#JIRA_API_TOKEN}"` – число должно быть > 0.

   **Windows – PowerShell:** длина строки должна быть > 0, например  
   `if ([string]::IsNullOrEmpty($env:JIRA_API_TOKEN)) { 0 } else { $env:JIRA_API_TOKEN.Length }`

4. Настройка в `tools/config.yml` (блок `defaults.jira`):

   - `url` – базовый адрес сайта Jira Cloud.
   - `email` – учётная почта Atlassian (дублируется переменной `JIRA_EMAIL` из `.env`, если задана).
   - `api_token` – обычно оставляют как `"${JIRA_API_TOKEN}"` для подсказки; фактическое значение скрипт берёт из `ENV['JIRA_API_TOKEN']`, иначе из этого поля.
   - `main_issues_file` – путь **от корня репозитория** к текстовому файлу со списком **основных** задач для выгрузки (по умолчанию `tools/jira/jira_main_issues.txt`). В файле: одна строка – один ключ (`ODS-123`); пустые строки и строки, начинающиеся с `#`, игнорируются; повторы ключей отбрасываются.
   - `dst` – базовая папка для результата (например `tools/jira`).

5. Запуск скрипта из корня репозитория (**все ОС**, если `ruby` в `PATH`):

   ```bash
   ruby tools/scripts/jira_issue_to_md.rb
   ```

   Скрипт читает все ключи из `main_issues_file` и для **каждой** основной задачи создаёт каталог `<dst>/<KEY>/`. Внутри него:

   - `<KEY>.md` – сама основная задача;
   - для каждой **подзадачи** в Jira (поле subtasks) – отдельный файл `<SUBKEY>.md` в той же папке.

   Выгрузить **одну** задачу, не меняя список в файле:

   ```bash
   ruby tools/scripts/jira_issue_to_md.rb ODS-42
   ```

   Будет создан каталог `<dst>/ODS-42/` с `ODS-42.md` и файлами подзадач при их наличии.

**Постоянно без ручного `source`:** установите [direnv](https://direnv.net/), добавьте hook в профиль оболочки (см. приложение в конце файла: отдельно для macOS, Linux и Windows), в корне репозитория файл `.envrc` с одной строкой `dotenv`, затем `direnv allow`.

**Почему без токена в окружении – «404» в Jira.** Если `JIRA_API_TOKEN` пустой, из `config.yml` может подставиться буквальная строка `"${JIRA_API_TOKEN}"` – для Jira это неверная авторизация; ответ часто выглядит как отсутствие доступа к задаче.

---

## 3. GitLab: интеграция проекта с Jira (коммиты и разработка)

Здесь GitLab ходит в Jira от имени указанных учётных данных. Если токен отозвали или не обновили после смены – **коммиты перестают отображаться** в задачах, даже при правильном ключе `ODS-123` в сообщении.

**Прямая ссылка на форму (подставьте свой namespace и имя проекта):**

- Пример для этого репозитория:  
  **[https://gitlab.com/vvvnik/ods-project/-/settings/integrations/jira/edit](https://gitlab.com/vvvnik/ods-project/-/settings/integrations/jira/edit)**

**Что указать в форме (типичный случай Jira Cloud):**

- URL сайта Jira – базовый адрес вида `https://<ваш-сайт>.atlassian.net` (для примера: `https://vvv85594.atlassian.net`).
- Email – тот же, что для Atlassian.
- Пароль/API token – **API-токен** с шага 1 (не пароль).

Сохраните интеграцию. При смене токена на [id.atlassian.com/.../api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens) **обязательно обновите** его и здесь.

---

## 4. GitLab: CI/CD Variables (только пайплайны)

Переменные из этого раздела попадают в **jobs** `.gitlab-ci.yml`, а **не** в форму Jira из §3.

**Прямая ссылка (пример этого проекта):**

- **[https://gitlab.com/vvvnik/ods-project/-/settings/ci_cd#js-cicd-variables-settings](https://gitlab.com/vvvnik/ods-project/-/settings/ci_cd#js-cicd-variables-settings)**  
  Общий шаблон: `https://gitlab.com/<group>/<project>/-/settings/ci_cd` → раздел **Variables**.

Добавьте, например, `JIRA_API_TOKEN` (и при необходимости `JIRA_EMAIL`), включите **Mask** / **Protect** по [правилам GitLab](https://docs.gitlab.com/ee/ci/variables/#mask-a-cicd-variable). В YAML секреты не дублируйте.

---

## 5. Jira: приложение «GitLab for Jira Cloud»

Отдельный канал: приложение Atlassian связывает **организацию/аккаунт GitLab** с сайтом Jira (панель разработки, переходы в репозиторий и т.д.). Настройки живут **в Jira и в интерфейсе приложения**, а не в `.env`.

**Управление приложениями в Atlassian** перенесено в администрирование: приложения смотрят и настраивают через **администрирование сайта** и раздел вроде **«Подключённые приложения»**; в продукте Jira также можно попасть через **Приложения → Управление приложениями** (точные подписи зависят от языка интерфейса).

Дальше:

1. Найдите в списке установленных приложений **GitLab for Jira Cloud**.
2. Откройте **сведения** (Details) или меню **⋯** → **Настроить** / **Configure** – проверьте привязку к GitLab.com (или self-managed), группам/репозиториям и статус подключения.
3. У части конфигураций открывается встроенная страница коннектора, URL зависит от вашего сайта. Пример формата (ваш инстанс):  
   **[https://vvv85594.atlassian.net/plugins/servlet/ac/gitlab-jira-connect-gitlab.com/gitlab-configuration](https://vvv85594.atlassian.net/plugins/servlet/ac/gitlab-jira-connect-gitlab.com/gitlab-configuration)**  
   Если ссылка отличается – используйте ту, что открывается из **Настроить** у приложения в Jira.

Если OAuth-сессия или доступ GitLab истекли – переподключите интеграцию в мастере приложения.

---

## 6. Порядок «с нуля» (чеклист)

1. Создать API-токен: [id.atlassian.com → API tokens](https://id.atlassian.com/manage-profile/security/api-tokens).
2. Положить токен и email в локальный `.env` (и при желании настроить direnv).
3. В GitLab проекта: **Settings → Integrations → Jira** – URL сайта Jira, email, API token; сохранить.  
   Прямой пример URL страницы: […/settings/integrations/jira/edit](https://gitlab.com/vvvnik/ods-project/-/settings/integrations/jira/edit).
4. В Jira под **администрированием**: проверить **GitLab for Jira Cloud** (⋯ → Настроить, связь с GitLab).
5. Для job’ов: [CI/CD → Variables](https://gitlab.com/vvvnik/ods-project/-/settings/ci_cd#js-cicd-variables-settings) – если скрипты в CI должны звать Jira API.
6. В коммитах указывать ключ задачи проекта (**`ODS-123`** и т.д.), пушить в тот репозиторий GitLab, который привязан к Jira.

---

## Сводная таблица «куда что»

| Место | Назначение |
|--------|------------|
| [Atlassian API tokens](https://id.atlassian.com/manage-profile/security/api-tokens) | Выпуск и отзыв токена для Jira Cloud API |
| `.env` в корне репо (не в Git) | Локальные `JIRA_*` для скриптов |
| GitLab **Settings → Integrations → Jira** | Доступ GitLab к Jira для коммитов/ссылок; обновлять токен при смене |
| GitLab **Settings → CI/CD → Variables** | Секреты только для пайплайнов |
| Jira **GitLab for Jira Cloud** (админ, приложения) | Организационная связка GitLab ↔ Jira Cloud |
| `tools/config.yml` | Несекретные поля (`url`, `email` при желании) и плейсхолдер имени переменной для токена |

Если токен попал в Git – **отзовите** его на стороне Atlassian, создайте новый и обновите **все** места из таблицы, где он использовался.

---

## Приложение: direnv по шагам

Ниже: **шаг 1–2** зависят от ОС (как поставить direnv и куда прописать hook). **Шаг 3** – везде суть одна (файл `.envrc` с `dotenv`, команда `direnv allow`); ниже даны примеры для **macOS/Linux (bash)** и отдельно для **Windows PowerShell**. **Шаг 4** – проверка с пометкой ОС.

### Шаг 1. Установить direnv

**macOS** (Homebrew):

```bash
brew install direnv
```

**Linux** – пакетный менеджер дистрибутива, например:

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y direnv

# Fedora
sudo dnf install -y direnv

# Arch
sudo pacman -S direnv
```

**Windows** – [Scoop](https://scoop.sh/) или [Chocolatey](https://chocolatey.org/), либо бинарник с [релизов direnv](https://github.com/direnv/direnv/releases):

```powershell
scoop install direnv
# или: choco install direnv
```

### Шаг 2. Включить hook (один раз на машину)

**macOS / Linux – zsh** (типичный zsh на macOS; на Linux – если вы в zsh):

```bash
grep -q 'direnv hook zsh' ~/.zshrc || echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
source ~/.zshrc
```

**Linux – bash** (и WSL с bash по умолчанию):

```bash
grep -q 'direnv hook bash' ~/.bashrc || echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
source ~/.bashrc
```

**Windows – PowerShell** (в профиль; путь к профилю: `$PROFILE`):

```powershell
if (-not (Test-Path $PROFILE)) { New-Item -Path $PROFILE -ItemType File -Force }
$line = 'Invoke-Expression "$(direnv hook pwsh)"'
if (-not (Select-String -Path $PROFILE -Pattern 'direnv hook pwsh' -Quiet)) { Add-Content -Path $PROFILE -Value $line }
. $PROFILE
```

**Windows – Git Bash:** используйте блок **Linux – bash** для `~/.bashrc` внутри Git Bash (или общий `~` в WSL).

### Шаг 3. В корне репозитория (macOS / Linux / Windows)

Подставьте свой путь к клону вместо примеров.

**macOS / Linux:**

```bash
cd ~/ods-project
printf '%s\n' 'dotenv' > .envrc
direnv allow
```

**Windows – PowerShell:**

```powershell
cd $HOME\ods-project   # или полный путь, например C:\Users\You\ods-project
Set-Content -Path .envrc -Value "dotenv" -Encoding utf8
direnv allow
```

### Шаг 4. Проверка

Выйдите из каталога репозитория и зайдите снова; переменные из `.env` должны подхватиться.

**macOS / Linux – zsh/bash:** `echo "${#JIRA_API_TOKEN}"`

**Windows – PowerShell:**  
`if ([string]::IsNullOrEmpty($env:JIRA_API_TOKEN)) { 0 } else { $env:JIRA_API_TOKEN.Length }`

Если встроенный `dotenv` в `.envrc` недоступен в вашей версии direnv, замените строку в `.envrc` на `source_env .env` и снова выполните `direnv allow`.

### Без direnv (только локальная машина)

Нежелательно для секретов, но возможно: прописать `export JIRA_API_TOKEN=...` (и при необходимости `export JIRA_EMAIL=...`) в профиле оболочки – **macOS/Linux:** `~/.zshrc` или `~/.bashrc`; **Windows PowerShell:** `$PROFILE`. Файлы с секретами не коммитить и не копировать.

---

## Форки и MR

Для пайплайнов из **fork** переменные CI могут быть скрыты политикой GitLab – это нормальная защита от утечки секретов чужим кодом.
