#!/bin/bash

# ==================================================
# Description:    检查wlan0的状态是否为"Connected"， 必要时启动相关服务
#                 因为配网Ap存在，After=network.target不再使用，转而改用其他的启动条件
# Author:         liuguoping
# ==================================================

INTERFACE="wlan0"  # 默认网络接口，可通过参数传入
CHECK_INTERVAL=3   # 检查间隔

LOG_FILE="/var/log/hubv3-boot-monitor.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

check_network() {
    local msg
    msg=$(iw dev "$INTERFACE" link 2>&1)
    
    if echo "$msg" | grep -q "Not connected"; then
        log "INFO: $INTERFACE not connected. Retrying in $CHECK_INTERVAL seconds..."
        return 1
    elif echo "$msg" | grep -q "No such device"; then
        log "WARNING: $INTERFACE device not found. Retrying in $CHECK_INTERVAL seconds..."
        return 2
    else
        log "INFO: $INTERFACE connected."
        return 0
    fi
}

start_services() {
    echo "B-" > /run/led_state
    log "INFO: hubv3-button.service service started."
}

# 主逻辑
main() {
    while true; do
        check_network
        local status=$?
        if [ "$status" -eq 0 ]; then
            log "INFO: Starting services..."
            start_services
            log "INFO: Stopping hubv3-boot-monitor.service as $INTERFACE is connected."
            systemctl stop hubv3-boot-monitor.service
            exit 0
        elif [ "$status" -eq 2 ]; then
            log "ERROR: Network interface $INTERFACE not found. Retrying..."
        fi
        sleep "$CHECK_INTERVAL"
    done
}

# 接收命令行参数
if [ -n "$1" ]; then
    INTERFACE="$1"
fi

main
