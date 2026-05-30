#!/usr/bin/env bash
set -euo pipefail

NTFY_URL="https://ntfy.sh/BloodVDS"
CPU_THRESHOLD=80
MEM_THRESHOLD=85
DISK_THRESHOLD=85
ERROR_COOLDOWN=300
RESOURCE_COOLDOWN=600
SERVICES=("blood-harvest" "bloodlogs-bot" "blood-festival-bot" "vkfest")

declare -A last_error_time
declare -A last_service_down
last_cpu_alert=0
last_mem_alert=0
last_disk_alert=0

send_ntfy() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"
    local tags="${4:-warning}"
    curl -s \
        -H "Title: ${title}" \
        -H "Priority: ${priority}" \
        -H "Tags: ${tags}" \
        -d "${message}" \
        "${NTFY_URL}" > /dev/null 2>&1 || true
}

check_resources() {
    local now
    now=$(date +%s)

    local load1 nproc cpu_pct
    load1=$(awk '{print $1}' /proc/loadavg)
    nproc=$(nproc)
    cpu_pct=$(echo "$load1 $nproc" | awk '{printf "%d", ($1/$2)*100}')

    if (( cpu_pct >= CPU_THRESHOLD )) && (( now - last_cpu_alert >= RESOURCE_COOLDOWN )); then
        last_cpu_alert=$now
        send_ntfy "⚡ BloodVDS CPU" "Нагрузка ЦП: ${cpu_pct}% (loadavg: ${load1})" "high" "rotating_light"
    fi

    local mem_total mem_available mem_used_pct used_mb total_mb
    mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    mem_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    mem_used_pct=$(( (mem_total - mem_available) * 100 / mem_total ))

    if (( mem_used_pct >= MEM_THRESHOLD )) && (( now - last_mem_alert >= RESOURCE_COOLDOWN )); then
        last_mem_alert=$now
        used_mb=$(( (mem_total - mem_available) / 1024 ))
        total_mb=$(( mem_total / 1024 ))
        send_ntfy "💾 BloodVDS RAM" "Память: ${mem_used_pct}% (${used_mb}/${total_mb} MB)" "high" "floppy_disk"
    fi

    local disk_pct disk_avail
    disk_pct=$(df / --output=pcent | tail -1 | tr -d ' %')
    disk_avail=$(df / --output=avail -h | tail -1 | tr -d ' ')

    if (( disk_pct >= DISK_THRESHOLD )) && (( now - last_disk_alert >= RESOURCE_COOLDOWN )); then
        last_disk_alert=$now
        send_ntfy "🗄 BloodVDS Диск" "Диск: ${disk_pct}% (свободно: ${disk_avail})" "high" "file_cabinet"
    fi
}

check_service_alive() {
    local service="$1"
    local now
    now=$(date +%s)
    local last="${last_service_down[$service]:-0}"

    if (( now - last < RESOURCE_COOLDOWN )); then
        return
    fi

    if ! systemctl is-active --quiet "${service}.service" 2>/dev/null; then
        last_service_down[$service]=$now
        send_ntfy "💀 ${service} упал" "Сервис не активен — systemd остановил его" "urgent" "skull"
    fi
}

check_logs() {
    local service="$1"
    local now
    now=$(date +%s)
    local last="${last_error_time[$service]:-0}"

    if (( now - last < ERROR_COOLDOWN )); then
        return
    fi

    local errors
    if [ "$service" = "vkfest" ]; then
        errors=$(journalctl -u "${service}.service" --since "-30s" --no-pager -q 2>/dev/null \
            | grep -iE 'token.*invalid|invalid.*token|access.token|authorization.failed|auth.*error|token.*expired|invalid.*api.key' \
            | tail -3) || true
    else
        errors=$(journalctl -u "${service}.service" --since "-30s" --no-pager -q 2>/dev/null \
            | grep -iE '\berror\b|\bcrit\b|\bpanic\b|\bfatal\b' \
            | grep -vE \
                'FloodWait|RetryAfter|flood[._]wait|flood wait|\
VK API error 917|You don.t have access|\
Cannot parse an update|\
MEDIA_EMPTY|MEDIA_INVALID|PHOTO_SAVE_FILE_INVALID|CHAT_SEND_VIDEOS_FORBIDDEN|CHAT_SEND_PHOTOS_FORBIDDEN|CHAT_SEND_STICKERS_FORBIDDEN|\
upload.*media|media.*upload|File too large|фото не отправлено|\
Forbidden|chat not found|USER_BANNED_IN_CHANNEL|CHANNEL_PRIVATE|CHANNEL_INVALID|\
CHAT_WRITE_FORBIDDEN|CHAT_ADMIN_REQUIRED|CHAT_RESTRICTED|RIGHT_FORBIDDEN|\
MESSAGE_TOO_LONG|MSG_ID_INVALID|PEER_ID_INVALID|USERNAME_NOT_OCCUPIED|\
INPUT_USER_DEACTIVATED|USER_DEACTIVATED|bot was blocked|deactivated|\
message is not modified|message to.*edit.*not found|reply.*not found|\
игнор.*задача продолжается|задача продолжается|\
send_html|log relay|\
no such column' \
            | tail -3) || true
    fi

    if [ -n "$errors" ]; then
        last_error_time[$service]=$now
        local short_err
        short_err=$(echo "$errors" | head -1 | cut -c1-220)
        send_ntfy "🔴 ${service}" "${short_err}" "urgent" "skull"
    fi
}

check_inactive_timers() {
    local hits
    hits=$(journalctl -u blood-harvest.service --since "-35s" --no-pager -q 2>/dev/null \
        | grep 'INACTIVE_TIMER_FIRED') || true

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local chat_id=""
        if [[ "$line" =~ chat=(-?[0-9]+) ]]; then
            chat_id="${BASH_REMATCH[1]}"
        fi
        local timer_id=""
        if [[ "$line" =~ \.timer\ id=([0-9]+) ]]; then
            timer_id="${BASH_REMATCH[1]}"
        fi
        local body="Таймер неактивности #${timer_id} сработал"
        [ -n "$chat_id" ] && body="${body} (chat ${chat_id})"
        send_ntfy "⏰ Таймер неактивности" "${body}" "default" "bell"
    done <<< "$hits"
}

ITER=0

while true; do
    for svc in "${SERVICES[@]}"; do
        check_logs "$svc"
        check_service_alive "$svc"
    done

    check_inactive_timers

    ITER=$(( ITER + 1 ))
    if (( ITER % 2 == 0 )); then
        check_resources
    fi

    sleep 30
done
