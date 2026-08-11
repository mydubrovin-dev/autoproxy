# autoproxy

Скрипт для разворачивания на свежем CentOS/Rocky/RHEL VPS готового
прокси-сервера в один шаг. Скачали и запустили один скрипт — всё
остальное настраивается само, кроме одного интерактивного шага для
настройки MTProto/SNI (см. ниже).

## Что разворачивает

1. **Squid** — forward-прокси с авторизацией по логину/паролю. В интернет
   пропускаются только авторизованные клиенты.
2. **[MTProto FIX by MEKO](https://github.com/Mekotofeuka/MTPROTO_FIX_By_MEKO)**
   в Docker-контейнере (`--network host --cap-add NET_ADMIN` — нужно,
   потому что фикс правит iptables на хосте).
3. **fail2ban** — следит за sshd и банит тех, кто ломится по SSH.

## Использование

На свежей машине CentOS/Rocky/RHEL, от root:

```bash
curl -fsSL https://raw.githubusercontent.com/mydubrovin-dev/autoproxy/main/install.sh | sudo bash
```

Необязательные переопределения (переменные окружения, задать перед пайпом):

| Переменная              | По умолчанию | Описание                     |
|--------------------------|--------------|--------------------------------|
| `AUTOPROXY_SQUID_USER`     | `proxyuser`  | Логин для Squid              |
| `AUTOPROXY_SQUID_PASS`     | случайный    | Пароль для Squid              |
| `AUTOPROXY_SQUID_PORT`     | `3128`       | Порт, на котором слушает Squid |

Учётные данные Squid всегда сохраняются в
`/root/autoproxy/squid-credentials.txt` (доступ только root, права 600),
независимо от того, были они сгенерированы автоматически или заданы вручную.

## Настройка MTProto / SNI (один ручной шаг)

Установщик MEKO — интерактивное меню без флагов для автоматического
режима, поэтому `install.sh` только готовит контейнер — саму настройку
прокси нужно один раз выполнить вручную:

```bash
docker exec -it autoproxy-mtproto bash /tmp/meko-install.sh
```

В меню: установить прокси (Telemt / MTG / MTProto.zig) → применить
**MTProto FIX** ([1]) → проверить SNI ([7]) и указать этот домен:

```
www.ite-ng.ru
```

Снова открыть меню в любой момент можно так:

```bash
docker exec -it autoproxy-mtproto mekopr
```

## Структура проекта

```
install.sh              точка входа (именно этот файл вы скачиваете curl'ом)
lib/
  common.sh              логирование, проверка root/ОС, общие функции
  squid.sh                установка и настройка Squid с авторизацией
  fail2ban.sh              установка fail2ban и jail для sshd
  docker.sh                 установка Docker Engine
  mtproto.sh                 сборка и запуск контейнера MTProto-fix
docker/mtproto/
  Dockerfile                 образ для контейнера MTProto-fix
  entrypoint.sh                скачивает установщик MEKO, печатает инструкцию
```

## Примечания

- Рассчитан на CentOS/Rocky/RHEL (`dnf`/`yum`). На Debian/Ubuntu не тестировался.
- Перед тем как пускать `install.sh` через `curl | bash` на важной машине,
  просмотрите его содержимое — обычная рекомендация для любого
  `curl | bash`-установщика, этот не исключение.
- Повторный запуск `install.sh` безопасен для Squid/fail2ban/Docker;
  контейнер MTProto каждый раз пересоздаётся с нуля (вся настройка MEKO
  внутри контейнера теряется — донастройте через `mekopr` заново).
