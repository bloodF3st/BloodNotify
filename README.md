# BloodNotify

Система push-уведомлений для стека **BloodHarvest / BloodFestival / bloodLogs / VKBloodHarvest** через [ntfy.sh](https://ntfy.sh).

Уведомления приходят на **iOS / Android** в реальном времени — без email, без сторонних сервисов, без подписок.

---

## Что отслеживается

| Событие | Источник | Приоритет |
|---------|---------|-----------|
| Таймер неактивности сработал | BloodHarvest / bloodLogs | default |
| Festival токен упал (3 проверки) | BloodHarvest renew watchdog | urgent |
| Festival бот пересоздан | BloodHarvest renew watchdog | default |
| Festival ренью провалился | BloodHarvest renew watchdog | default |
| ERROR / CRIT / panic в логах бота | blood-monitor (VDS daemon) | urgent |
| VK API токен/авторизация невалидна | blood-monitor (VDS daemon) | urgent |
| CPU > 80% | blood-monitor (VDS daemon) | high |
| RAM > 85% | blood-monitor (VDS daemon) | high |
| Диск > 85% | blood-monitor (VDS daemon) | high |
| Сервис упал и не рестартует | blood-monitor (VDS daemon) | urgent |
| VDS недоступен (ping) | watchdog (локальная машина) | urgent |

**Что не алертит** (ожидаемые API ошибки):
FloodWait, RetryAfter, нет доступа к чату, CHANNEL_PRIVATE, CHAT_WRITE_FORBIDDEN,
медиа-ограничения, Forbidden, chat not found, деактивированные пользователи,
message is not modified, VK API error 917 и другие не-критичные RPC-ошибки.

---

## Архитектура

```
VDS (blood-monitor.service)
├── journald → grep ERROR/CRIT/panic → ntfy push
├── CPU / RAM / Disk polling → ntfy push
└── Сервисы: blood-harvest, bloodlogs-bot, blood-festival-bot, vkfest

Локальная машина (bloodvds-watchdog.timer)
└── ping VDS каждые 5 мин → если нет ответа → ntfy push

Боты (встроенная интеграция, NTFY_URL в .env)
├── BloodHarvest — таймеры неактивности + renew watchdog events
└── bloodLogs — таймеры неактивности (/btimer, /balltimer)
```

---

## Быстрая установка

### 1. Установить ntfy на iOS / Android

- [App Store](https://apps.apple.com/app/ntfy/id1625396347)
- [Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
- [F-Droid](https://f-droid.org/packages/io.heckel.ntfy/)

### 2. Выбрать топик

Придумай уникальную строку, например `blood-alerts-abc123`.
Полный адрес будет: `https://ntfy.sh/blood-alerts-abc123`

Подпишись на топик в приложении: нажми **+**, введи адрес.

> ⚠️ Топики на ntfy.sh публичны — любой кто знает адрес может читать. Используй случайный суффикс.

### 3. Клонировать и запустить install.sh

```bash
git clone https://github.com/bloodF3st/BloodNotify
cd BloodNotify
chmod +x install.sh
bash install.sh
```

Скрипт запросит:
- URL топика ntfy
- SSH алиас/хост VDS
- IP VDS для ping watchdog

После установки придёт тестовый push `✅ BloodNotify установлен`.

---

## Ручная установка

### VDS: blood-monitor daemon

```bash
# Скопировать на VDS
scp blood-monitor.sh user@vds:/opt/blood-monitor/blood-monitor.sh
scp systemd/blood-monitor.service user@vds:/etc/systemd/system/

# На VDS:
chmod +x /opt/blood-monitor/blood-monitor.sh
# Поменять NTFY_URL в скрипте
nano /opt/blood-monitor/blood-monitor.sh

systemctl daemon-reload
systemctl enable --now blood-monitor.service
systemctl status blood-monitor.service
```

### VDS: добавить NTFY_URL в .env ботов

Для встроенных уведомлений от самих ботов (таймеры, renew):

```bash
echo 'NTFY_URL=https://ntfy.sh/твой-топик' >> /opt/bloodharvest/.env
echo 'NTFY_URL=https://ntfy.sh/твой-топик' >> /opt/bloodlogs/.env
```

Перезапустить соответствующие сервисы.

### Локальная машина: ping watchdog

```bash
sudo cp watchdog.sh /usr/local/bin/bloodvds-watchdog.sh
sudo chmod +x /usr/local/bin/bloodvds-watchdog.sh
# Отредактировать VDS_HOST и NTFY_URL в скрипте
sudo nano /usr/local/bin/bloodvds-watchdog.sh

sudo cp systemd/bloodvds-watchdog.service /etc/systemd/system/
sudo cp systemd/bloodvds-watchdog.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now bloodvds-watchdog.timer
```

---

## Конфигурация blood-monitor

Редактируется в `/opt/blood-monitor/blood-monitor.sh`:

| Параметр | По умолчанию | Описание |
|----------|-------------|---------|
| `NTFY_URL` | — | URL топика ntfy (обязательно) |
| `CPU_THRESHOLD` | `80` | % нагрузки ЦП для алерта |
| `MEM_THRESHOLD` | `85` | % использования RAM для алерта |
| `DISK_THRESHOLD` | `85` | % использования диска для алерта |
| `ERROR_COOLDOWN` | `300` | Сек между алертами с одного сервиса |
| `RESOURCE_COOLDOWN` | `600` | Сек между алертами CPU/RAM/Disk |
| `SERVICES` | см. скрипт | Список systemd-сервисов для мониторинга |

---

## Совместимость

| Компонент | Репозиторий |
|-----------|-------------|
| BloodHarvest (userbot) | [bloodHarvest-](https://github.com/bloodF3st/bloodHarvest-) |
| BloodFestival (bot) | [bloodFestival-](https://github.com/bloodF3st/bloodFestival-) |
| bloodLogs (logger bot) | [bloodlogs-bot](https://github.com/bloodF3st/bloodlogs-bot) |
| VKBloodHarvest (VK userbot) | [VKBloodHarvest](https://github.com/bloodF3st/VKBloodHarvest) |

Встроенная ntfy-интеграция (NTFY_URL в .env) есть у **BloodHarvest** и **bloodLogs**.
**VKBloodHarvest** и **BloodFestival** покрываются через blood-monitor на уровне логов.

---

## Структура репозитория

```
BloodNotify/
├── blood-monitor.sh          # Демон мониторинга (запускается на VDS)
├── watchdog.sh               # Ping watchdog (запускается на локальной машине)
├── install.sh                # Автоматический установщик
├── systemd/
│   ├── blood-monitor.service # systemd unit для VDS
│   ├── bloodvds-watchdog.service
│   └── bloodvds-watchdog.timer
└── README.md
```
