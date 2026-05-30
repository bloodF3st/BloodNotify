#!/usr/bin/env bash
# BloodNotify installer
# Usage: bash install.sh [--vds-only | --local-only]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[..] $1${NC}"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

MODE="${1:-both}"

# ── Config ────────────────────────────────────────────────────────────────────

read -rp "ntfy topic URL [https://ntfy.sh/YOUR_TOPIC]: " NTFY_URL
NTFY_URL="${NTFY_URL:-https://ntfy.sh/YOUR_TOPIC}"

if [[ "$MODE" != "--local-only" ]]; then
    read -rp "SSH alias/host for VDS [bloodvds]: " VDS_HOST
    VDS_HOST="${VDS_HOST:-bloodvds}"
fi

if [[ "$MODE" != "--vds-only" ]]; then
    read -rp "VDS IP for ping watchdog [YOUR_VDS_IP]: " VDS_IP
    VDS_IP="${VDS_IP:-YOUR_VDS_IP}"
fi

# ── VDS: blood-monitor ────────────────────────────────────────────────────────

if [[ "$MODE" != "--local-only" ]]; then
    info "Deploying blood-monitor to VDS ($VDS_HOST)..."

    # Patch NTFY_URL in script
    MONITOR_SCRIPT=$(sed "s|https://ntfy.sh/YOUR_TOPIC|${NTFY_URL}|g" blood-monitor.sh)

    ssh "$VDS_HOST" "mkdir -p /opt/blood-monitor"
    echo "$MONITOR_SCRIPT" | ssh "$VDS_HOST" "cat > /opt/blood-monitor/blood-monitor.sh && chmod +x /opt/blood-monitor/blood-monitor.sh"
    scp systemd/blood-monitor.service "$VDS_HOST":/etc/systemd/system/blood-monitor.service

    ssh "$VDS_HOST" "systemctl daemon-reload && systemctl enable --now blood-monitor.service"
    ok "blood-monitor deployed and started on VDS"

    # Add NTFY_URL to .env files if they exist
    for ENV_PATH in /opt/bloodharvest/.env /opt/bloodlogs/.env /opt/vkfest/.env; do
        ssh "$VDS_HOST" "
            if [ -f '$ENV_PATH' ]; then
                grep -q '^NTFY_URL=' '$ENV_PATH' || echo 'NTFY_URL=${NTFY_URL}' >> '$ENV_PATH'
                echo 'patched $ENV_PATH'
            fi
        " 2>/dev/null || true
    done
    ok "NTFY_URL added to bot .env files on VDS"
fi

# ── Local: watchdog ───────────────────────────────────────────────────────────

if [[ "$MODE" != "--vds-only" ]]; then
    info "Installing local watchdog..."

    WATCHDOG_SCRIPT=$(sed "s|YOUR_VDS_IP|${VDS_IP}|g; s|https://ntfy.sh/YOUR_TOPIC|${NTFY_URL}|g" watchdog.sh)

    sudo bash -c "echo '$WATCHDOG_SCRIPT' > /usr/local/bin/bloodvds-watchdog.sh && chmod +x /usr/local/bin/bloodvds-watchdog.sh"

    # Patch IP and NTFY_URL in systemd unit
    sed "s|YOUR_VDS_IP|${VDS_IP}|g" systemd/bloodvds-watchdog.service | sudo tee /etc/systemd/system/bloodvds-watchdog.service > /dev/null
    sudo cp systemd/bloodvds-watchdog.timer /etc/systemd/system/bloodvds-watchdog.timer

    sudo systemctl daemon-reload
    sudo systemctl enable --now bloodvds-watchdog.timer
    ok "Local watchdog installed (runs every 5 min)"
fi

# ── Test notification ─────────────────────────────────────────────────────────

info "Sending test notification..."
curl -s \
    -H "Title: ✅ BloodNotify установлен" \
    -H "Priority: low" \
    -H "Tags: white_check_mark" \
    -d "Мониторинг активен. Уведомления настроены." \
    "$NTFY_URL" > /dev/null && ok "Test notification sent to $NTFY_URL"

echo ""
echo -e "${GREEN}BloodNotify установлен.${NC}"
echo "Подпишись на топик в приложении ntfy: $NTFY_URL"
