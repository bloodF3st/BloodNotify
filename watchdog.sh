#!/usr/bin/env bash
# Runs on LOCAL machine every 5 minutes.
# Pings VDS — if unreachable, sends ntfy push.
# Configure VDS_HOST and NTFY_URL below or via environment.

VDS_HOST="${VDS_HOST:-YOUR_VDS_IP}"
NTFY_URL="${NTFY_URL:-https://ntfy.sh/YOUR_TOPIC}"

if ! ping -c 3 -W 5 "$VDS_HOST" > /dev/null 2>&1; then
    curl -s \
        -H "Title: 🔌 BloodVDS OFFLINE" \
        -H "Priority: urgent" \
        -H "Tags: skull,no_entry" \
        -d "BloodVDS (${VDS_HOST}) не отвечает — возможно упал интернет или сервер" \
        "$NTFY_URL"
fi
