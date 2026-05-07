#!/bin/bash
# AI-Xray Multi-System Test Script
# Tests installation on all major Linux distributions

API_KEY="private_gUeIsfdsyAT5VZg4Bn0zuN69"
VEID="747329"
SERVER_IP="172.96.195.127"
INSTALL_URL="https://raw.githubusercontent.com/ScientificInternet/AI-Xray/28e5327/install.sh"

# Test systems
declare -A SYSTEMS=(
    ["debian-12"]="debian-12-x86_64"
    ["debian-11"]="debian-11-x86_64"
    ["ubuntu-22.04"]="ubuntu-22.04-x86_64"
    ["ubuntu-20.04"]="ubuntu-20.04-x86_64"
    ["centos-7"]="centos-7-x86_64"
    ["rocky-9"]="rocky-9-x86_64"
    ["almalinux-9"]="almalinux-9-x86_64"
)

RESULTS_DIR="test_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RESULTS_DIR/test.log"
}

reinstall_os() {
    local os_template=$1
    log "Stopping VPS..."
    curl -s "https://api.64clouds.com/v1/stop" -d "veid=$VEID" -d "api_key=$API_KEY" >/dev/null
    sleep 10
    
    log "Reinstalling OS: $os_template"
    local response=$(curl -s "https://api.64clouds.com/v1/reinstallOS" \
        -d "veid=$VEID" \
        -d "api_key=$API_KEY" \
        -d "os=$os_template")
    
    local password=$(echo "$response" | jq -r '.rootPassword')
    if [[ -z "$password" || "$password" == "null" ]]; then
        log "ERROR: Failed to get root password"
        echo "$response" | jq .
        return 1
    fi
    
    echo "$password"
}

wait_for_os() {
    local password=$1
    local max_wait=300
    local waited=0
    
    log "Waiting for OS to be ready..."
    
    # Wait for installation to complete
    while [[ $waited -lt $max_wait ]]; do
        local status=$(curl -s "https://api.64clouds.com/v1/getServiceInfo?veid=$VEID&api_key=$API_KEY" | jq -r '.os')
        if [[ "$status" != "null" ]]; then
            break
        fi
        sleep 10
        ((waited+=10))
    done
    
    # Start VPS
    log "Starting VPS..."
    curl -s "https://api.64clouds.com/v1/start" -d "veid=$VEID" -d "api_key=$API_KEY" >/dev/null
    sleep 40
    
    # Wait for SSH
    log "Waiting for SSH..."
    ssh-keygen -f '/root/.ssh/known_hosts' -R "$SERVER_IP" 2>/dev/null
    waited=0
    while [[ $waited -lt $max_wait ]]; do
        if sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$SERVER_IP "echo ok" 2>/dev/null | grep -q "ok"; then
            log "SSH ready"
            return 0
        fi
        sleep 10
        ((waited+=10))
    done
    
    log "ERROR: SSH timeout"
    return 1
}

test_installation() {
    local os_name=$1
    local password=$2
    local log_file="$RESULTS_DIR/${os_name}.log"
    
    log "Testing installation on $os_name..."
    
    # Get OS info
    local os_info=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no root@$SERVER_IP "cat /etc/os-release 2>/dev/null | head -3" 2>/dev/null)
    echo "$os_info" > "$log_file"
    echo "---" >> "$log_file"
    
    # Run installation
    log "Running AI-Xray installer..."
    local start_time=$(date +%s)
    
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no root@$SERVER_IP \
        "curl -fsSL $INSTALL_URL -o /tmp/install.sh && bash /tmp/install.sh" \
        >> "$log_file" 2>&1
    
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Check results
    if [[ $exit_code -eq 0 ]]; then
        # Verify Xray is running
        local xray_status=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no root@$SERVER_IP \
            "systemctl is-active xray" 2>/dev/null)
        
        if [[ "$xray_status" == "active" ]]; then
            log "✅ SUCCESS: $os_name (${duration}s)"
            echo "SUCCESS" > "$RESULTS_DIR/${os_name}.result"
            return 0
        else
            log "❌ FAILED: $os_name - Xray not running"
            echo "FAILED: Xray not running" > "$RESULTS_DIR/${os_name}.result"
            return 1
        fi
    else
        log "❌ FAILED: $os_name - Installation script failed (exit $exit_code)"
        echo "FAILED: Exit code $exit_code" > "$RESULTS_DIR/${os_name}.result"
        return 1
    fi
}

# Main test loop
log "========================================="
log "AI-Xray Multi-System Test"
log "========================================="
log "Testing ${#SYSTEMS[@]} systems"
log ""

for os_name in "${!SYSTEMS[@]}"; do
    os_template="${SYSTEMS[$os_name]}"
    
    log "========================================="
    log "Testing: $os_name"
    log "========================================="
    
    # Reinstall OS
    password=$(reinstall_os "$os_template")
    if [[ $? -ne 0 ]]; then
        log "❌ FAILED: $os_name - OS reinstall failed"
        echo "FAILED: OS reinstall" > "$RESULTS_DIR/${os_name}.result"
        continue
    fi
    
    log "Root password: $password"
    
    # Wait for OS
    if ! wait_for_os "$password"; then
        log "❌ FAILED: $os_name - OS not ready"
        echo "FAILED: OS not ready" > "$RESULTS_DIR/${os_name}.result"
        continue
    fi
    
    # Test installation
    test_installation "$os_name" "$password"
    
    log ""
done

# Summary
log "========================================="
log "Test Summary"
log "========================================="

success=0
failed=0

for os_name in "${!SYSTEMS[@]}"; do
    result_file="$RESULTS_DIR/${os_name}.result"
    if [[ -f "$result_file" ]]; then
        result=$(cat "$result_file")
        if [[ "$result" == "SUCCESS" ]]; then
            log "✅ $os_name: SUCCESS"
            ((success++))
        else
            log "❌ $os_name: $result"
            ((failed++))
        fi
    else
        log "⚠️  $os_name: NOT TESTED"
    fi
done

log ""
log "Total: $((success + failed))"
log "Success: $success"
log "Failed: $failed"
log ""
log "Results saved to: $RESULTS_DIR"
