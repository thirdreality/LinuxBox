#!/bin/bash
# LinuxBox Supervisor (C version) install script

set -e  # Exit immediately on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_NAME="supervisor"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/var/lib/hubv3-supervisor"
STATIC_DIR="/usr/share/hubv3-supervisor/static"
LOG_DIR="/var/log"
DBUS_SYSTEM_DIR="/usr/share/dbus-1/system-services"
DBUS_CONF_DIR="/etc/dbus-1/system.d"
SYSTEMD_DIR="/etc/systemd/system"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "  LinuxBox Supervisor (C) Installer"
echo "========================================="
echo ""

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run this script as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# 1. Check build artifact
echo -e "${YELLOW}[1/9]${NC} Checking build artifact..."
if [ ! -f "${SCRIPT_DIR}/${BINARY_NAME}" ]; then
    echo -e "${RED}Error: Binary not found: ${BINARY_NAME}${NC}"
    echo "Run first: make or ./build.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} Binary found"

# 2. Stop existing service
echo -e "${YELLOW}[2/9]${NC} Stopping existing supervisor service..."
if systemctl is-active --quiet supervisor.service; then
    echo "  Stopping supervisor..."
    systemctl stop supervisor.service || true
fi

# Fallback: kill any supervisor process not managed by systemd
# (e.g. started manually or via build.sh). These would keep /dev/ttyACMx and
# the D-Bus name held, causing the new instance to fail.
if pgrep -x "${BINARY_NAME}" > /dev/null; then
    echo "  Found running ${BINARY_NAME} process(es), terminating..."
    pkill -TERM -x "${BINARY_NAME}" || true
    # Wait up to 3s for graceful exit
    for _ in $(seq 1 30); do
        pgrep -x "${BINARY_NAME}" > /dev/null || break
        sleep 0.1
    done
    # Force kill if still alive
    if pgrep -x "${BINARY_NAME}" > /dev/null; then
        echo "  Process still running, force killing..."
        pkill -9 -x "${BINARY_NAME}" || true
        sleep 0.5
    fi
fi

# Remove stale PID file if present
if [ -f "/var/run/supervisor.pid" ]; then
    rm -f "/var/run/supervisor.pid"
fi
echo -e "${GREEN}✓${NC} Service stopped"

# 3. Backup old installation
echo -e "${YELLOW}[3/9]${NC} Backing up old installation (if any)..."
BACKUP_DIR="/tmp/supervisor-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"

if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
    cp "${INSTALL_DIR}/${BINARY_NAME}" "${BACKUP_DIR}/" || true
    echo "  Backed up old binary to: ${BACKUP_DIR}/"
fi

if [ -f "${SYSTEMD_DIR}/supervisor.service" ]; then
    cp "${SYSTEMD_DIR}/supervisor.service" "${BACKUP_DIR}/" || true
    echo "  Backed up old service file to: ${BACKUP_DIR}/"
fi
echo -e "${GREEN}✓${NC} Backup done"

# 4. Install binary
echo -e "${YELLOW}[4/9]${NC} Installing binary..."
install -m 755 "${SCRIPT_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
echo -e "${GREEN}✓${NC} Binary installed to: ${INSTALL_DIR}/${BINARY_NAME}"

# 5. Create required directories and copy config (overwrite)
echo -e "${YELLOW}[5/9]${NC} Creating directories and copying config..."
mkdir -p "${CONFIG_DIR}"
mkdir -p "${STATIC_DIR}"
mkdir -p "${LOG_DIR}"

CONFIG_SRC="${SCRIPT_DIR}/config"
if [ ! -d "${CONFIG_SRC}" ]; then
    echo -e "${RED}Error: Config source not found: ${CONFIG_SRC}${NC}"
    exit 1
fi

# Copy configuration.yaml — DO NOT clobber an existing deployed config.
# The running config may hold user settings (e.g. timezone set from HA), so on
# upgrade we preserve it and only drop a reference copy as configuration.yaml.default.
if [ -f "${CONFIG_SRC}/configuration.yaml" ]; then
    if [ -f "${CONFIG_DIR}/configuration.yaml" ]; then
        cp -f "${CONFIG_SRC}/configuration.yaml" "${CONFIG_DIR}/configuration.yaml.default"
        echo "  Preserved existing configuration.yaml (ref: configuration.yaml.default)"
    else
        cp -f "${CONFIG_SRC}/configuration.yaml" "${CONFIG_DIR}/"
        echo "  Copied: configuration.yaml -> ${CONFIG_DIR}/"
    fi
fi

# Copy conf/ (e.g. zigbee2mqtt)
if [ -d "${CONFIG_SRC}/conf" ]; then
    cp -rf "${CONFIG_SRC}/conf" "${CONFIG_DIR}/"
    echo "  Copied: conf/ -> ${CONFIG_DIR}/"
fi

# Copy static/ (web UI) to /usr/share/hubv3-supervisor/static
if [ -d "${CONFIG_SRC}/static" ]; then
    cp -rf "${CONFIG_SRC}/static/." "${STATIC_DIR}/"
    echo "  Copied: static/ -> ${STATIC_DIR}/"
fi

echo -e "${GREEN}✓${NC} Config directory synced (${CONFIG_DIR})"
echo -e "${GREEN}✓${NC} Static files installed (${STATIC_DIR})"

# 6. Install udev rules
echo -e "${YELLOW}[6/9]${NC} Installing udev rules..."
UDEV_RULES_DIR="/etc/udev/rules.d"
mkdir -p "${UDEV_RULES_DIR}"

if [ -f "${SCRIPT_DIR}/config/udev/33-ama-usb.rules" ]; then
    install -m 644 "${SCRIPT_DIR}/config/udev/33-ama-usb.rules" "${UDEV_RULES_DIR}/"
    echo "  Installed: ${UDEV_RULES_DIR}/33-ama-usb.rules"
    udevadm control --reload-rules || true
    udevadm trigger || true
else
    echo -e "${YELLOW}  Warning: udev rules file not found, skipping${NC}"
fi
echo -e "${GREEN}✓${NC} udev rules installed"

# 7. Install D-Bus policy
echo -e "${YELLOW}[7/9]${NC} Installing D-Bus policy..."

if [ -f "${SCRIPT_DIR}/config/dbus/com.thirdreality.linuxbox.Supervisor.conf" ]; then
    install -m 644 "${SCRIPT_DIR}/config/dbus/com.thirdreality.linuxbox.Supervisor.conf" "${DBUS_CONF_DIR}/"
    echo "  Installed: ${DBUS_CONF_DIR}/com.thirdreality.linuxbox.Supervisor.conf"
else
    echo -e "${RED}  Error: D-Bus policy file not found${NC}"
    exit 1
fi

systemctl reload dbus.service || true
echo -e "${GREEN}✓${NC} D-Bus policy installed"

# 8. Install systemd service
echo -e "${YELLOW}[8/9]${NC} Installing systemd service..."
if [ -f "${SCRIPT_DIR}/supervisor.service" ]; then
    install -m 644 "${SCRIPT_DIR}/supervisor.service" "${SYSTEMD_DIR}/supervisor.service"
    echo "  Installed: ${SYSTEMD_DIR}/supervisor.service"

    systemctl daemon-reload
    echo -e "${GREEN}✓${NC} systemd service installed"
else
    echo -e "${RED}Error: supervisor.service not found${NC}"
    exit 1
fi

# 9. Enable and optionally start service
echo -e "${YELLOW}[9/9]${NC} Enable and start service..."
echo "Start supervisor service now? (Y/n) [default: Y, 3s]"
read -t 3 -p "Your choice: " -n 1 -r || true
echo
# Default Y: empty (timeout) or Y/y -> start; only n/N -> skip
if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
    systemctl enable supervisor.service
    systemctl start supervisor.service

    sleep 2

    if systemctl is-active --quiet supervisor.service; then
        echo -e "${GREEN}✓${NC} Supervisor service is running"

        echo ""
        echo "Service status:"
        systemctl status supervisor.service --no-pager -l | head -20
    else
        echo -e "${RED}✗${NC} Supervisor service failed to start"
        echo ""
        echo "Recent logs:"
        journalctl -u supervisor.service -n 50 --no-pager
        exit 1
    fi
else
    echo "Skipped starting service"
    echo "Start manually later: sudo systemctl start supervisor.service"
fi

echo ""
echo "========================================="
echo -e "${GREEN}Installation complete.${NC}"
echo "========================================="
echo ""
echo "Common commands:"
echo "  Start:   sudo systemctl start supervisor.service"
echo "  Stop:    sudo systemctl stop supervisor.service"
echo "  Restart: sudo systemctl restart supervisor.service"
echo "  Status:  sudo systemctl status supervisor.service"
echo "  Logs:    sudo journalctl -u supervisor.service -f"
echo "  File log: tail -f /var/log/supervisor.log"
echo ""
echo "CLI tools:"
echo "  LED:     supervisor led red"
echo "  Zigbee:  supervisor zigbee info"
echo "  Thread:  supervisor thread info"
echo "  PTest:   supervisor ptest start"
echo ""
echo "Backup location: ${BACKUP_DIR}"
echo ""
