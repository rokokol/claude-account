<div align="center">

# claude-account

**Инструмент для менеджмента аккаунтов Claude Code с общей памятью и скиллами** (｡･ω･｡)

![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?style=flat&logo=anthropic&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/claude-account/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/claude-account/actions/workflows/build.yml)

[English](README.md)

</div>

Сколько угодно аккаунтов на одном пользователе — рабочий, личный, заказчика — и переключение между ними одной командой. Чего при этом **не** появляется, так это второй копии всего остального: скиллы, плагины, команды, агенты, настройки и — самое важное — чаты, память, планы и история команд остаются **одним набором, которым пользуются все аккаунты**

В этом вся идея. Залогиниться другим аккаунтом меняет, с чьего счёта уходят токены, а не то, кто ты на этой машине

```sh
claude-account use work    # и следующий `claude` уже рабочий аккаунт
```

Приехало из моего райса, **[rokokol/huix](https://github.com/rokokol/huix)**

## Как устроено переключение

`~/.claude` — **симлинк** на активный профиль. Весь механизм в этом:

```
~/.claude -> ~/.local/share/claude-profiles/work
~/.local/share/
├── claude-profiles/
│   ├── work/                  .credentials.json, .claude.json, симлинки в общее
│   ├── personal/              .credentials.json, .claude.json, симлинки в общее
│   └── …
└── claude-shared/             settings.json, CLAUDE.md, skills/, plugins/, commands/,
                               agents/, projects/, history.jsonl, plans/, tasks/, …
```

Поэтому **стоковому бинарнику `claude` не нужна обёртка**: он как и всегда смотрит в `~/.claude`, а переключение — один `ln -sfn`. Ничто не оборачивает запуск, ничто не переписывает конфиг, и обновление Claude Code не может сломать переключение

Пути резолвятся лениво, так что переключение догоняет и уже открытые сессии: их следующий рефреш токена уйдёт в новый активный профиль. `use` про это говорит и переключает всё равно

## Что по умолчанию своё у аккаунта, а что общее

| остаётся в профиле | общее |
| --- | --- |
| `.credentials.json` — OAuth-токен | `settings.json`, `CLAUDE.md` |
| `.claude.json` — `oauthAccount`, привязка токена к аккаунту | `skills/`, `plugins/`, `commands/`, `agents/` |
| | `projects/` — чаты и память, `history.jsonl` |
| | `plans/`, `tasks/`, `todos/`, `file-history/` |

Claude Code пишет **сквозь** симлинки, так что `/config`, `/memory` и `/resume` работают с общими файлами, ничего не зная про эту схему

В `.claude.json` лежат ещё MCP уровня пользователя и флаги доверия папкам — они едут туда же и потому у каждого аккаунта свои, а не общие. Общий MCP заводить через `.mcp.json` внутри проекта

`claude-shared` — это одна директория обычных файлов, поэтому если натравить на неё синхронизацию, на другой машине окажутся те же скиллы, чаты и память. Симлинки внутрь неё **относительные**, так что там они остаются валидными, а не указывают в чужой `/home`

## Команды

```sh
claude-account list             # профили с почтой, активный со звёздочкой
claude-account use <name>       # сделать активным
claude-account add <name>       # создать, дальше `claude` → /login
claude-account current          # имя активного профиля
claude-account path             # его директория
claude-account ensure           # перелинковать активный профиль (это зовёт модуль)
claude-account init [name]      # втянуть существующий ~/.claude в профиль
```

`init` — разовая миграция: переносит настоящий `~/.claude` в профиль, вынимает общие части в `claude-shared` и наводит на него симлинк. Он отказывается работать изнутри сессии Claude и пока открыта хоть одна — уносить `~/.claude` из-под живой сессии значит её сломать; `--force`, если уверен

Написанный руками глобальный `CLAUDE.md` **никогда** не уезжает в общее автоматически: он паркуется рядом с профилем как `CLAUDE.md.bak-init-<дата>` под ручной мёрж, потому что этот файл курируют, а не накапливают

## Установка

### Home Manager

```nix
{
  inputs.claude-account.url = "github:rokokol/claude-account";

  # в home-конфигурации
  imports = [ inputs.claude-account.homeManagerModules.default ];

  programs.claude-account.enable = true;
}
```

Это ставит переключатель, пинит `CLAUDE_CONFIG_DIR` и чинит симлинки активного профиля на каждой активации. Сам Claude Code ставь как ставил — модуль намеренно этого не делает, чтобы не спорить с твоим пином

| опция | | по умолчанию |
| --- | --- | --- |
| `sharedEntries` | что общее у всех профилей | таблица выше |
| `sharedDir` / `profilesDir` | где лежит общее и профили | под `$XDG_DATA_HOME` |
| `claudeDir` | входной симлинк | `$HOME/.claude` |
| `pinConfigDir` | экспортировать `CLAUDE_CONFIG_DIR` | `true` |
| `repairOnActivation` | звать `ensure` на каждой активации | `true` |

### Зачем прибивать `CLAUDE_CONFIG_DIR`

`.claude.json` — это файл, в котором записано, **какому аккаунту принадлежит токен** (`oauthAccount`). Сам по себе Claude Code держит его в `~/.claude.json` — в домашней директории, *снаружи* конфиг-директории. Путь этот один и тот же для всех профилей, то есть привязка к аккаунту оказалась бы там, куда переключение не дотягивается: симлинк меняешь, токен меняется, а личность нет

Сделать `~/.claude.json` симлинком в профиль не помогает. Файл переписывается через `rename(2)` на этот путь, а `rename` подменяет саму запись в директории — симлинк превратится в обычный файл при первом же сохранении

Если навести `CLAUDE_CONFIG_DIR` на входной симлинк, файл переезжает **внутрь** конфиг-директории. А `~/.claude` — это и есть симлинк на активный профиль, поэтому `.claude.json` ложится в профиль, по своему на каждый аккаунт, и `rename` происходит там, где он никому не мешает. Это и делает `pinConfigDir`, и поэтому выключить его — не сменить путь, а сломать изоляцию аккаунтов

`repairOnActivation` попроще: он зовёт `claude-account ensure` после `linkGeneration` — не после `writeBoundary`, потому что именно на `linkGeneration` home-manager сносит файлы прошлого поколения и отменил бы починку

### Любой другой дистрибутив

```sh
git clone https://github.com/rokokol/claude-account
cd claude-account
sudo ./install.sh          # PREFIX=~/.local ./install.sh для пользовательской установки
```

Нужны `bash` 4+ (ассоциативные массивы), `jq`, `pgrep` и coreutils. Дальше — экспортировать `CLAUDE_CONFIG_DIR="$HOME/.claude"` из своего шелл-профиля, по причине выше

## Тесты

```sh
tests/run.sh              # 26 проверок, ничего за пределами временного HOME
```

Каждому кейсу достаётся свежий `HOME` **и** свежий `XDG_DATA_HOME`, и три переменные с путями тоже наведены внутрь него. Одного `HOME` мало: сессия, экспортирующая `XDG_DATA_HOME` — а home-manager это делает, — увела бы тесты в настоящие профили. `pgrep` подставной, так что "открыта ли сессия" решает набор тестов, а не машина, на которой он запущен

`nix flake check` гоняет этот набор плюс: упакованная обёртка делает настоящее переключение с голым `PATH`, каждая настройка доезжает до скрипта, модуль Home Manager вычисляется против заглушек опций — включая то, что починка назначена после `linkGeneration` и что всё добавленное можно выключить обратно

## Структура

```
claude-account.sh    переключатель
nix/                 package.nix, module.nix, module-test.nix
tests/               run.sh и заглушка pgrep
install.sh           для систем без Nix
```

## Лицензия

MIT
