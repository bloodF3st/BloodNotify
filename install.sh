#!/usr/bin/env bash
# BloodNotify installer
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[..] $1${NC}"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

# ── Config ────────────────────────────────────────────────────────────────────

read -rp "ntfy topic URL [https://ntfy.sh/YOUR_TOPIC]: " NTFY_URL
NTFY_URL="${NTFY_URL:-https://ntfy.sh/YOUR_TOPIC}"

read -rp "SSH alias/host for VDS [bloodvds]: " VDS_HOST
VDS_HOST="${VDS_HOST:-bloodvds}"

# ── VDS: blood-monitor ────────────────────────────────────────────────────────

info "Deploying blood-monitor to VDS ($VDS_HOST)..."

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
