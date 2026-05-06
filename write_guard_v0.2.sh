write_guard() {
  info "Installing AI Guard v0.2..."

  cat > "$GUARD_BIN" << 'GUARDEOF'
#!/bin/bash
# AI-Xray Guard v0.2 - Chameleon Mode
# Monitors network health and rotates identity before detection
# 
# IMPORTANT: This is a threshold-based rule engine, NOT a trained model.
# Rotation triggers systemctl restart xray, which WILL briefly disconnect clients.
# Clients must re-pull subscription to get new shortId after rotation.
#
# Future: Replace with lightweight ML model trained on M-Lab data.

set -euo pipefail

INSTALL_DIR="/etc/ai-xray"
CONFIG="${INSTALL_DIR}/config.json"
DEST_POOL="${INSTALL_DIR}/dest-pool.json"
REALITY_KEY="${INSTALL_DIR}/reality.key"
DB="${INSTALL_DIR}/guard.db"
LOG="/var/log/ai-xray.log"

# Monitoring intervals
CHECK_INTERVAL=60
ROTATION_COOLDOWN=3600  # 1 hour minimum between rotations

# Thresholds (conservative to avoid false positives)
LATENCY_THRESHOLD=800    # ms
LOSS_THRESHOLD=15        # %
RST_THRESHOLD=10         # count per minute
CONSECUTIVE_FAILURES=3   # trigger after N consecutive bad checks

# Traffic shaping: max concurrent connections (ramps up over days)
MAX_CONN_INITIAL=20
MAX_CONN_FULL=200
RAMP_DAYS=7

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG"
}

# ==================== Database ====================

init_db() {
    sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS rotations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT DEFAULT (datetime('now')),
        old_dest TEXT,
        new_dest TEXT,
        old_short_id TEXT,
        new_short_id TEXT,
        trigger_reason TEXT,
        latency_ms INTEGER,
        loss_pct REAL,
        rst_count INTEGER
    );"

    sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS health (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT DEFAULT (datetime('now')),
        dest TEXT,
        latency_ms INTEGER,
        loss_pct REAL,
        rst_count INTEGER,
        conn_count INTEGER,
        status TEXT
    );"

    sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT
    );"

    sqlite3 "$DB" "INSERT OR IGNORE INTO meta (key, value) VALUES ('install_time', datetime('now'));"
    sqlite3 "$DB" "INSERT OR IGNORE INTO meta (key, value) VALUES ('consecutive_failures', '0');"
    sqlite3 "$DB" "INSERT OR IGNORE INTO meta (key, value) VALUES ('last_rotation', '0');"
}

get_meta() {
    local key=$1
    sqlite3 "$DB" "SELECT value FROM meta WHERE key='${key}';" 2>/dev/null || echo ""
}

set_meta() {
    local key=$1
    local value=$2
    sqlite3 "$DB" "INSERT OR REPLACE INTO meta (key, value) VALUES ('${key}', '${value}');"
}

# ==================== Traffic Shaping ====================

get_max_connections() {
    local install_time=$(get_meta "install_time")
    if [ -z "$install_time" ]; then
        echo $MAX_CONN_INITIAL
        return
    fi

    local age_seconds=$(( $(date +%s) - $(date -d "$install_time" +%s 2>/dev/null || echo $(date +%s)) ))
    local age_days=$(( age_seconds / 86400 ))

    if [ $age_days -ge $RAMP_DAYS ]; then
        echo $MAX_CONN_FULL
    else
        local range=$(( MAX_CONN_FULL - MAX_CONN_INITIAL ))
        local current=$(( MAX_CONN_INITIAL + (range * age_days / RAMP_DAYS) ))
        echo $current
    fi
}

enforce_conn_limit() {
    local max_conn=$(get_max_connections)
    local current_conn=$(ss -tn state established '( sport = :443 )' 2>/dev/null | wc -l)

    iptables -D INPUT -p tcp --dport 443 --syn -m connlimit --connlimit-above $max_conn -j DROP 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 443 --syn -m connlimit --connlimit-above $max_conn -j DROP 2>/dev/null || true

    echo "$current_conn/$max_conn"
}

# ==================== Config Helpers ====================

get_current_dest() {
    jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG" 2>/dev/null || echo ""
}

get_current_short_id() {
    jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[] | select(. != "")' "$CONFIG" 2>/dev/null | head -1 || echo ""
}

# ==================== Health Checks ====================

measure_latency() {
    local dest=$1
    local result=$(curl -o /dev/null -s -w "%{time_connect}" --max-time 5 "https://${dest}" 2>/dev/null || echo "9999")
    
    if [ "$result" = "0.000000" ] || [ -z "$result" ]; then
        echo "9999"
    else
        echo "$result" | awk '{printf "%.0f", $1 * 1000}'
    fi
}

measure_loss() {
    local dest=$1
    local result=$(ping -c 5 -W 2 "$dest" 2>/dev/null | grep "packet loss" | awk -F',' '{print $3}' | awk '{print $1}' | tr -d '%' || echo "100")
    echo "${result:-100}"
}

count_rst() {
    local count=$(ss -ti state close-wait,fin-wait-1,fin-wait-2 '( sport = :443 )' 2>/dev/null | wc -l)
    echo "$count"
}

# ==================== Rotation Logic ====================

can_rotate() {
    local last_rotation=$(get_meta "last_rotation")
    local now=$(date +%s)
    local elapsed=$(( now - last_rotation ))
    
    if [ $elapsed -lt $ROTATION_COOLDOWN ]; then
        return 1
    fi
    
    return 0
}

rotate_dest() {
    local reason=$1
    local old_dest=$(get_current_dest)
    local old_sid=$(get_current_short_id)
    
    if ! can_rotate; then
        return 1
    fi

    local pool=$(cat "$DEST_POOL")
    local pool_size=$(echo "$pool" | jq 'length')
    local current_idx=$(echo "$pool" | jq --arg d "$old_dest" 'to_entries[] | select(.value == $d) | .key' 2>/dev/null || echo 0)

    if [ -z "$current_idx" ]; then
        current_idx=0
    fi

    local next_idx=$(( (current_idx + 1) % pool_size ))
    local new_dest=$(echo "$pool" | jq -r ".[$next_idx]")
    local new_sid=$(openssl rand -hex 8)

    local tmp=$(mktemp)
    jq --arg dest "$new_dest" --arg sid "$new_sid" '
        .inbounds[0].streamSettings.realitySettings.dest = ($dest + ":443") |
        .inbounds[0].streamSettings.realitySettings.serverNames = [$dest] |
        .inbounds[0].streamSettings.realitySettings.shortIds = ["", $sid]
    ' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"

    if systemctl is-active xray >/dev/null 2>&1; then
        systemctl restart xray 2>/dev/null || {
            log "[ERROR] Failed to restart Xray"
            return 1
        }
    fi

    sqlite3 "$DB" "INSERT INTO rotations (old_dest, new_dest, old_short_id, new_short_id, trigger_reason, latency_ms, loss_pct, rst_count)
        VALUES ('$old_dest', '$new_dest', '$old_sid', '$new_sid', '$reason', $CURRENT_LATENCY, $CURRENT_LOSS, $CURRENT_RST);"

    set_meta "last_rotation" "$(date +%s)"
    set_meta "consecutive_failures" "0"

    log "[MORPH] $old_dest -> $new_dest (reason: $reason)"
    return 0
}

# ==================== Main Loop ====================

main() {
    init_db
    log "[START] AI Guard v0.2 (threshold-based, restart on rotation)"

    while true; do
        local dest=$(get_current_dest)
        
        if [ -z "$dest" ]; then
            sleep $CHECK_INTERVAL
            continue
        fi

        CURRENT_LATENCY=$(measure_latency "$dest")
        CURRENT_LOSS=$(measure_loss "$dest")
        CURRENT_RST=$(count_rst)
        
        local conn_info=$(enforce_conn_limit)
        local conn_count=$(echo "$conn_info" | cut -d/ -f1)

        local status="ok"
        local reason=""
        local consecutive=$(get_meta "consecutive_failures")

        if [ "$CURRENT_LATENCY" -ge "$LATENCY_THRESHOLD" ]; then
            status="degraded"
            reason="latency_spike(${CURRENT_LATENCY}ms)"
        elif [ "$CURRENT_LOSS" -ge "$LOSS_THRESHOLD" ]; then
            status="degraded"
            reason="packet_loss(${CURRENT_LOSS}%)"
        elif [ "$CURRENT_RST" -ge "$RST_THRESHOLD" ]; then
            status="degraded"
            reason="rst_flood(${CURRENT_RST})"
        fi

        sqlite3 "$DB" "INSERT INTO health (dest, latency_ms, loss_pct, rst_count, conn_count, status)
            VALUES ('$dest', $CURRENT_LATENCY, $CURRENT_LOSS, $CURRENT_RST, $conn_count, '$status');"

        if [ "$status" = "degraded" ]; then
            consecutive=$(( consecutive + 1 ))
            set_meta "consecutive_failures" "$consecutive"
            
            log "[WARN] $reason (consecutive: $consecutive/$CONSECUTIVE_FAILURES)"
            
            if [ $consecutive -ge $CONSECUTIVE_FAILURES ]; then
                if rotate_dest "$reason"; then
                    log "[OK] Rotation complete"
                fi
            fi
        else
            set_meta "consecutive_failures" "0"
            log "[OK] dest=$dest latency=${CURRENT_LATENCY}ms loss=${CURRENT_LOSS}% rst=$CURRENT_RST conn=$conn_info"
        fi

        sleep $CHECK_INTERVAL
    done
}

trap 'log "[STOP] AI Guard stopped"; exit 0' SIGTERM SIGINT

main "$@"
GUARDEOF

  chmod +x "$GUARD_BIN"

  # Create systemd service
  cat > /etc/systemd/system/ai-xray-guard.service << EOF
[Unit]
Description=AI-Xray Guard v0.2 (Chameleon Mode)
After=xray.service

[Service]
Type=simple
ExecStart=${GUARD_BIN}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  ok "AI Guard v0.2 installed"
}
