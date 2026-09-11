#!/bin/bash

# Do not use set -e to avoid aborting the whole script when a single command fails
# set -e

SCRIPT="HubV3"

# OTBR 老形态的 SysV 脚本(feb106c 之前;otbr-nat44 更早一代才有)
FIREWALL_SERVICE="/etc/init.d/otbr-firewall"
NAT44_SERVICE="/etc/init.d/otbr-nat44"
# OTBR 新形态的防火墙脚本(setup/teardown 由 otbr-agent.service 的 drop-in 成对调用)
OTBR_FIREWALL_SCRIPT="/usr/lib/thirdreality/otbr-firewall.sh"
SYSCTL_ACCEPT_RA_FILE="/etc/sysctl.d/60-otbr-accept-ra.conf"
SYSCTL_IP_FORWARD_FILE="/etc/sysctl.d/60-otbr-ip-forward.conf"
RESTORE_APT_SERVICES="${RESTORE_APT_SERVICES:-0}"
DPKG_LOCK_MAX_WAIT="${DPKG_LOCK_MAX_WAIT:-30}"

DPKG_LOCK_FILES=(
    "/var/lib/dpkg/lock-frontend"
    "/var/lib/dpkg/lock"
    "/var/cache/apt/archives/lock"
    "/var/lib/apt/lists/lock"
)
DPKG_READY=0

function _ts() { date '+%Y-%m-%d %H:%M:%S'; }
function print_info()  { echo -e "\e[1;34m[$( _ts )] [${SCRIPT}] INFO:\e[0m $1"; }
function print_error() { echo -e "\e[1;31m[$( _ts )] [${SCRIPT}] ERROR:\e[0m $1"; }
function print_request() { echo -n -e "\e[1;34m[$( _ts )] [${SCRIPT}] INFO:\e[0m $1"; }

# Helper: check whether a systemd service unit exists on this system.
# Returns 0 if the unit is known, non-zero otherwise.
service_exists() {
    local unit="$1"
    systemctl list-unit-files "$unit" >/dev/null 2>&1 || systemctl status "$unit" >/dev/null 2>&1
}

repositories_to_remove=(
    "ghcr.io/home-assistant/odroid-n2-homeassistant"
    "ghcr.io/home-assistant/aarch64-hassio-supervisor"
    "homeassistant/aarch64-addon-matter-server"
    "homeassistant/aarch64-addon-otbr"
    "ghcr.io/home-assistant/aarch64-hassio-dns"
    "ghcr.io/home-assistant/aarch64-hassio-cli"
    "ghcr.io/home-assistant/aarch64-hassio-multicast"
    "ghcr.io/home-assistant/aarch64-hassio-audio"
    "ghcr.io/home-assistant/aarch64-hassio-observer"
)

error_handler() {
    local lineno=$1
    print_error "Error occurred at line $lineno (continuing anyway)"
}

trap 'error_handler $LINENO' ERR

APT_AUTO_SERVICES=(
    "apt-daily.service"
    "apt-daily-upgrade.service"
    "unattended-upgrades.service"
)

APT_AUTO_TIMERS=(
    "apt-daily.timer"
    "apt-daily-upgrade.timer"
)

get_trhub_model() {
  if [ -f /etc/armbian-release ]; then
    local board=$(grep "^BOARD=" /etc/armbian-release | cut -d'=' -f2)
    if [ -n "$board" ]; then
      echo "$board"
    else
      echo "trhubv3"
    fi
  else
    echo "trhubv3"
  fi
}

function disable_apt_auto_services() {
    print_info "Disabling apt automatic update services (start)"
    for unit in "${APT_AUTO_SERVICES[@]}" "${APT_AUTO_TIMERS[@]}"; do
        systemctl stop "$unit" >/dev/null 2>&1 || true
        systemctl disable "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null 2>&1 || true
    done
    print_info "Disabling apt automatic update services (done)"
}

function restore_apt_auto_services() {
    print_info "Restoring apt automatic update services"
    for unit in "${APT_AUTO_SERVICES[@]}" "${APT_AUTO_TIMERS[@]}"; do
        systemctl unmask "$unit" >/dev/null 2>&1 || true
        systemctl enable "$unit" >/dev/null 2>&1 || true
        # 不启动服务，因为马上就要 reboot 了
        # systemctl start "$unit" >/dev/null 2>&1 || true
    done
}

function log_dpkg_lock_holders() {
    local file holders
    for file in "${DPKG_LOCK_FILES[@]}"; do
        if [ -f "$file" ]; then
            holders=$(fuser "$file" 2>/dev/null || true)
            if [ -n "$holders" ]; then
                print_info "Lock file $file held by PIDs: $holders"
                for pid in $holders; do
                    if [ -d "/proc/$pid" ]; then
                        local proc_info
                        proc_info=$(ps -p "$pid" -o pid=,ppid=,cmd= 2>/dev/null || true)
                        if [ -n "$proc_info" ]; then
                            print_info "    $proc_info"
                        fi
                    fi
                done
            else
                print_info "Lock file $file exists but fuser reported no holders; possible stale lock"
            fi
        fi
    done

    local running
    running=$(pgrep -a -f '(apt[-. ]|apt$|dpkg|unattended-upgrade)' 2>/dev/null || true)
    if [ -n "$running" ]; then
        print_info "Running package-management processes:\n$running"
    fi
}

function terminate_package_processes() {
    local killed_any=0
    local pids cmdline exe_path

    pids=$(pgrep -f 'apt|dpkg|unattended-upgrade' 2>/dev/null || true)
    for pid in $pids; do
        if [ -z "$pid" ] || ! kill -0 "$pid" >/dev/null 2>&1; then
            continue
        fi

        exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)

        if [[ "$exe_path" =~ /(apt|dpkg|unattended-upgrade)/ ]] ||
           [[ "$cmdline" == *"/usr/share/unattended-upgrades/"* ]] ||
           [[ "$cmdline" == *"/usr/lib/apt/"* ]] ||
           [[ "$cmdline" == *"systemd-apt-"* ]]; then
            print_info "Killing PID $pid ($cmdline)"
            kill -9 "$pid" >/dev/null 2>&1 || true
            killed_any=1
        fi
    done

    if [ "$killed_any" -eq 0 ]; then
        print_info "No package-management processes required termination"
    fi
}

function wait_for_dpkg_lock() {
    if [ "$DPKG_READY" -eq 1 ]; then
        return 0
    fi

    print_info "Ensuring dpkg is idle (start)"
    log_dpkg_lock_holders
    terminate_package_processes

    local locks_found=0
    for file in "${DPKG_LOCK_FILES[@]}"; do
        if [ -f "$file" ]; then
            print_info "Removing stale lock $file"
            rm -f "$file" >/dev/null 2>&1 || true
            locks_found=1
        fi
    done

    if [ "$locks_found" -eq 1 ]; then
        print_info "Repairing dpkg state (dpkg --configure -a only; skip apt-get -f install when no network)"
        dpkg --configure -a >/dev/null 2>&1 || true
    fi

    print_info "Ensuring dpkg is idle (done)"
    DPKG_READY=1
}

# ---------------------------------------------------------------------------
# OTBR 的清理按两代形态各写一份，两份都会被调用:现网既有已经升级到"总闸模型"的机器,
# 也有仍是老形态(otbr-agent/otbr-web 各自 enable、init.d 防火墙、外部 mDNSResponder)
# 的机器,单靠任一份都会漏。分界线是 2026-07 的 feb106c
# "feat(otbr-agent): Pair firewall setup/teardown and add hubv3 master switch"。
#
# 边界原则:**当前包拥有的文件一律交给 apt-get purge 删**(unit、/usr/sbin/otbr-*、
# /usr/share/otbr-web、/etc/default/otbr-*、/etc/sysctl.d/60-otbr-*、
# /etc/modules-load.d/otbr.conf、/usr/lib/thirdreality/* 等)。手工删这些会造成
# "dpkg 认为包还装着、文件却已消失"的不一致,之后同版本 deb 又会被 U 盘安装器判为
# "已是最新"跳过,反倒修不回来。这里只手工清理**当前包不再拥有的历史孤儿文件**
# (init.d 脚本、mDNSResponder 那一套)以及**运行期状态与全局配置**
# (ipset/iptables、rt_tables、sysctl、/var/lib/thread)。
#
# avahi 一律不碰:老形态用的是外部 mDNSResponder(mdnsd / libdns_sd / libnss_mdns),
# 与系统 avahi-daemon 无关,后者是共享组件。
# ---------------------------------------------------------------------------

# 新形态(feb106c 之后):hubv3-otbr-agent 是总闸,Wants=otbr-agent(后者又 Wants=otbr-web),
# otbr-agent 是 PartOf=hubv3、otbr-web 是 BindsTo=otbr-agent,因此只有总闸被 enable。
# 防火墙由 otbr-agent.service 的 ExecStartPre/ExecStopPost 调 otbr-firewall.sh 成对建拆。
function _remove_otbr_agent_current()
{
    if ! service_exists "hubv3-otbr-agent.service" && [ ! -x "${OTBR_FIREWALL_SCRIPT}" ]; then
        print_info "otbr (current layout) not present; skipping _remove_otbr_agent_current"
        return 0
    fi

    print_info "_remove_otbr_agent_current (start)"

    # 先停总闸:整条链随之停止,且 otbr-agent 的 ExecStopPost 会把防火墙规则拆掉。
    # 之后再逐个兜底,防止 unit 依赖关系已被改动。
    /usr/bin/systemctl stop hubv3-otbr-agent > /dev/null 2>&1 || true
    /usr/bin/systemctl stop otbr-web > /dev/null 2>&1 || true
    /usr/bin/systemctl stop otbr-agent > /dev/null 2>&1 || true

    /usr/bin/systemctl disable hubv3-otbr-agent > /dev/null 2>&1 || true
    /usr/bin/systemctl disable otbr-web > /dev/null 2>&1 || true
    /usr/bin/systemctl disable otbr-agent > /dev/null 2>&1 || true

    killall otbr-web otbr-agent > /dev/null 2>&1 || true

    # 兜底拆防火墙(ipset、OTBR_FORWARD_INGRESS/EGRESS 链、NAT64 的 mangle/nat/forward),
    # 应对 ExecStopPost 没跑到的情况;脚本本身是幂等的。
    if [ -x "${OTBR_FIREWALL_SCRIPT}" ]; then
        "${OTBR_FIREWALL_SCRIPT}" teardown > /dev/null 2>&1 || true
    fi

    # systemd drop-in:purge 正常也会带走,这里兜底 purge 失败的情况
    rm -f /etc/systemd/system/otbr-agent.service.d/firewall.conf > /dev/null 2>&1 || true
    rm -f /etc/systemd/system/otbr-web.service.d/ordering.conf > /dev/null 2>&1 || true
    rmdir /etc/systemd/system/otbr-agent.service.d > /dev/null 2>&1 || true
    rmdir /etc/systemd/system/otbr-web.service.d > /dev/null 2>&1 || true

    print_info "_remove_otbr_agent_current (done)"
}

# 老形态(feb106c 之前):otbr-agent / otbr-web 各自独立 enable,hubv3-otbr-agent 当时只是
# Type=oneshot 的一次性配置脚本(2025-10 的 a1c2d36 就已存在,语义与现在的总闸不同);
# 防火墙是 ot-br-posix 自带的 /etc/init.d/otbr-firewall,用 update-rc.d 注册。
# 更早一代(a2266f7 之前)还有 /etc/init.d/otbr-nat44、外部 mDNSResponder 一套,以及
# otbr-agent-init.sh 作为 ExecStartPre。这些文件新包都不再包含,属于孤儿,手工清理。
function _remove_otbr_agent_legacy()
{
    local found=0
    local f
    # 探测项必须是"只有老形态才有"的文件。注意不能用 /lib/thirdreality/hubv3-otbr-agent.sh:
    # 本系统是 usrmerge(/lib -> /usr/lib),它与新包安装的
    # /usr/lib/thirdreality/hubv3-otbr-agent.sh 是同一个文件,拿它当老形态标志会在纯新形态
    # 机器上恒为真,连带把新包的文件删掉,造成 dpkg 状态与磁盘不一致。
    for f in "${FIREWALL_SERVICE}" "${NAT44_SERVICE}" /etc/init.d/mdns /etc/nss_mdns.conf \
             /etc/dbus-1/system.d/otbr-agent.conf /usr/lib/thirdreality/otbr-agent-init.sh \
             /usr/lib/libnss_mdns.so.2 \
             /usr/lib/libnss_mdns-0.2.so /usr/lib/libdns_sd.so /usr/lib/libdns_sd.so.1; do
        if [ -e "$f" ]; then
            found=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        print_info "otbr (legacy layout) not present; skipping _remove_otbr_agent_legacy"
        return 0
    fi

    print_info "_remove_otbr_agent_legacy (start)"

    # 老形态下这两个是各自 enable 的,新形态的清理只停总闸时会漏掉它们
    /usr/bin/systemctl stop otbr-web > /dev/null 2>&1 || true
    /usr/bin/systemctl stop otbr-agent > /dev/null 2>&1 || true
    /usr/bin/systemctl disable otbr-web > /dev/null 2>&1 || true
    /usr/bin/systemctl disable otbr-agent > /dev/null 2>&1 || true
    killall otbr-web otbr-agent > /dev/null 2>&1 || true

    # init.d 防火墙 / NAT44:先按 SysV 停,再摘掉 rcX.d 注册,最后删脚本本身
    for f in otbr-firewall otbr-nat44; do
        /usr/bin/systemctl stop "$f" > /dev/null 2>&1 || true
        /usr/bin/systemctl disable "$f" > /dev/null 2>&1 || true
    done
    if [ -x "${FIREWALL_SERVICE}" ]; then
        "${FIREWALL_SERVICE}" stop > /dev/null 2>&1 || true
    fi
    if [ -x "${NAT44_SERVICE}" ]; then
        "${NAT44_SERVICE}" stop > /dev/null 2>&1 || true
    fi
    if command -v update-rc.d > /dev/null 2>&1; then
        update-rc.d otbr-firewall remove > /dev/null 2>&1 || true
        update-rc.d otbr-nat44 remove > /dev/null 2>&1 || true
        update-rc.d mdns remove > /dev/null 2>&1 || true
    fi
    rm -f "${FIREWALL_SERVICE}" "${NAT44_SERVICE}" > /dev/null 2>&1 || true

    # 外部 mDNSResponder 一套(内置 mDNS 之前的形态)。注意与 avahi 无关,不要动 avahi。
    rm -f /etc/init.d/mdns /etc/nss_mdns.conf > /dev/null 2>&1 || true
    rm -f /etc/rc2.d/S52mdns /etc/rc3.d/S52mdns /etc/rc4.d/S52mdns /etc/rc5.d/S52mdns \
          /etc/rc0.d/K16mdns /etc/rc6.d/K16mdns > /dev/null 2>&1 || true
    rm -f /usr/lib/libnss_mdns.so.2 /usr/lib/libnss_mdns-0.2.so \
          /usr/lib/libdns_sd.so /usr/lib/libdns_sd.so.1 > /dev/null 2>&1 || true

    # otbr-agent 的 dbus 策略文件与老的 ExecStartPre 脚本,新包都不再安装
    if [ -e /etc/dbus-1/system.d/otbr-agent.conf ]; then
        rm -f /etc/dbus-1/system.d/otbr-agent.conf > /dev/null 2>&1 || true
        /usr/bin/systemctl reload dbus > /dev/null 2>&1 || true
    fi
    rm -f /usr/lib/thirdreality/otbr-agent-init.sh > /dev/null 2>&1 || true
    # 最早一代的 hubv3-otbr-agent.sh 曾写作 /lib/thirdreality/,但 usrmerge 下它与新包的
    # /usr/lib/thirdreality/hubv3-otbr-agent.sh 是同一个文件,所以这里不能删 ——
    # 那属于当前包拥有的文件,交给 purge。

    print_info "_remove_otbr_agent_legacy (done)"
}

# 对外入口:两代形态都清,然后 purge 包、收尾全局配置。
# 独立于 remove_homeassistant_core 调用 —— 以前它被塞在那个函数里,而那个函数在
# home-assistant.service 不存在时直接 return,导致没装 HA 的机器上 OTBR 永远清不掉。
remove_otbr_agent()
{
    print_info "remove_otbr_agent (start)"

    _remove_otbr_agent_current
    _remove_otbr_agent_legacy

    # 包自己的 prerm 才是权威拆除逻辑(停总闸、拆防火墙、删 drop-in、清 rt_tables/sysctl.d、
    # 删 /var/lib/thread),所以先让 purge 跑。失败只告警,不手工删包文件。
    if dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*thirdreality-otbr-agent"; then
        apt-get purge -y thirdreality-otbr-agent > /dev/null 2>&1 || \
            print_error "purge thirdreality-otbr-agent failed; package files may remain (left in place on purpose to keep dpkg state consistent)"
    fi

    # 全局配置收尾:即使 purge 跑过也要复核,其中 /etc/sysctl.conf 里 postinst 追加的
    # optmem_max 从来没有任何 prerm 清理过。
    if [ -f /etc/iproute2/rt_tables ]; then
        sed -i.bak '/88[[:space:]]\+openthread/d' /etc/iproute2/rt_tables > /dev/null 2>&1 || true
        rm -f /etc/iproute2/rt_tables.bak > /dev/null 2>&1 || true
    fi
    if [ -f /etc/sysctl.conf ]; then
        sed -i '/^net\.core\.optmem_max=65536$/d' /etc/sysctl.conf > /dev/null 2>&1 || true
        sed -i '/^# OpenThread configuration$/d' /etc/sysctl.conf > /dev/null 2>&1 || true
    fi
    rm -f "${SYSCTL_ACCEPT_RA_FILE}" "${SYSCTL_IP_FORWARD_FILE}" > /dev/null 2>&1 || true
    rm -f /etc/modules-load.d/otbr.conf > /dev/null 2>&1 || true
    rm -rf /var/lib/thread > /dev/null 2>&1 || true

    systemctl daemon-reload > /dev/null 2>&1 || true
    sysctl -p /etc/sysctl.conf > /dev/null 2>&1 || true

    print_info "remove_otbr_agent (done)"
}

remove_homeassistant_core()
{
    if ! service_exists "home-assistant.service"; then
        print_info "home-assistant.service not found; skipping remove_homeassistant_core"
        return 0
    fi

    print_info "remove_homeassistant_core (start)"
    /usr/bin/systemctl stop home-assistant > /dev/null 2>&1 || true
    /usr/bin/systemctl stop matter-server > /dev/null 2>&1 || true

    /usr/bin/systemctl disable home-assistant > /dev/null 2>&1 || true
    /usr/bin/systemctl disable matter-server > /dev/null 2>&1|| true

    dpkg --configure -a > /dev/null 2>&1 || true

    apt-get purge -y thirdreality-hacore > /dev/null 2>&1 || true
    apt-get purge -y thirdreality-hacore-config > /dev/null 2>&1 || true
    apt-get purge -y thirdreality-python3.13 > /dev/null 2>&1 || true
    apt-get purge -y thirdreality-python3 > /dev/null 2>&1 || true

    apt-get autoremove -y >/dev/null 2>&1 || true
    systemctl daemon-reload || true

    # OTBR 的清理已移到独立的 remove_otbr_agent(主流程直接调用):它与 HA 无关,
    # 留在这里会被本函数开头"没有 home-assistant.service 就 return"挡掉。
    print_info "remove_homeassistant_core (done)"
}

remove_zigbee2mqtt()
{
    if ! service_exists "zigbee2mqtt.service"; then
        print_info "zigbee2mqtt.service not found; skipping remove_zigbee2mqtt"
        return 0
    fi

    print_info "remove_zigbee2mqtt (start)"
    /usr/bin/systemctl stop zigbee2mqtt.service > /dev/null 2>&1|| true
    /usr/bin/systemctl disable zigbee2mqtt.service > /dev/null 2>&1 || true

    # Do NOT stop/disable mosquitto: it is a pre-installed base component and is
    # enabled by default. The device reboots at the end of factory reset, so
    # leaving it enabled lets it start automatically on the next boot.

    dpkg --configure -a > /dev/null 2>&1 || true

    apt-get purge -y thirdreality-zigbee-mqtt > /dev/null 2>&1 || true

    # NOTE: nodejs and mosquitto are now pre-installed base components of the
    # factory image (nodejs is also required by the openthread web UI, and
    # mosquitto is the shipped MQTT broker), so factory reset must NOT remove
    # them. Only the zigbee2mqtt application and its data are removed here.

    apt-get autoremove -y >/dev/null 2>&1 || true
    systemctl daemon-reload || true

    rm -rf /opt/zigbee2mqtt > /dev/null 2>&1 || true
    print_info "remove_zigbee2mqtt (done)"
}

remove_matter2mqtt()
{
    # Also check the directories: a service unit may be gone while the fabric
    # credentials in /var/lib survive an earlier manual uninstall.
    if ! service_exists "matter2mqtt.service" && [ ! -d /var/lib/matter2mqtt ] && [ ! -d /opt/matter2mqtt ]; then
        print_info "matter2mqtt not present; skipping remove_matter2mqtt"
        return 0
    fi

    print_info "remove_matter2mqtt (start)"
    /usr/bin/systemctl stop matter-ble-proxy.service > /dev/null 2>&1 || true
    /usr/bin/systemctl stop matter2mqtt.service > /dev/null 2>&1 || true

    /usr/bin/systemctl disable matter-ble-proxy.service > /dev/null 2>&1 || true
    /usr/bin/systemctl disable matter2mqtt.service > /dev/null 2>&1 || true

    # mosquitto stays: pre-installed base component (see remove_zigbee2mqtt)

    apt-get purge -y thirdreality-matter2mqtt > /dev/null 2>&1 || true

    # /opt may hold npm-runtime leftovers not owned by the package; /var/lib
    # holds the Matter fabric credentials and commissioned-node storage and
    # must not survive a factory reset.
    rm -rf /opt/matter2mqtt > /dev/null 2>&1 || true
    rm -rf /var/lib/matter2mqtt > /dev/null 2>&1 || true

    systemctl daemon-reload || true
    print_info "remove_matter2mqtt (done)"
}

remove_openhab()
{
    if ! service_exists "openhab.service"; then
        print_info "openhab.service not found; skipping remove_openhab"
        return 0
    fi

    print_info "remove_openhab (start)"
    /usr/bin/systemctl stop openhab.service > /dev/null 2>&1 || true
    /usr/bin/systemctl disable openhab.service > /dev/null 2>&1 || true

    apt-get purge -y openhab* > /dev/null 2>&1 || true
    apt-get purge -y openjdk-17-jre* > /dev/null 2>&1 || true

    rm -rf /usr/share/keyrings/openhab.gpg > /dev/null 2>&1 || true
    rm -rf /etc/apt/sources.list.d/openhab.list > /dev/null 2>&1 || true
    rm -rf /var/log/openhab > /dev/null 2>&1 || true

    apt-get autoremove -y >/dev/null 2>&1 || true
    systemctl daemon-reload || true
    print_info "remove_openhab (done)"
}

remove_music_assistant()
{
    if ! service_exists "music-assistant.service"; then
        print_info "music-assistant.service not found; skipping remove_music_assistant"
        return 0
    fi

    print_info "remove_music_assistant (start)"
    /usr/bin/systemctl stop music-assistant.service > /dev/null 2>&1 || true
    /usr/bin/systemctl disable music-assistant.service > /dev/null 2>&1 || true

    apt-get purge -y thirdreality-music-assistant > /dev/null 2>&1 || true
    print_info "remove_music_assistant (done)"
}

remove_linuxbox_bridge()
{
    if ! service_exists "linuxbox-hubv3-bridge.service"; then
        print_info "linuxbox-hubv3-bridge.service not found; skipping remove_linuxbox_bridge"
        return 0
    fi

    print_info "remove_linuxbox_bridge (start)"
    /usr/bin/systemctl stop linuxbox-hubv3-bridge.service > /dev/null 2>&1 || true
    /usr/bin/systemctl disable linuxbox-hubv3-bridge.service > /dev/null 2>&1 || true

    apt-get purge -y thirdreality-bridge > /dev/null 2>&1 || true
    print_info "remove_linuxbox_bridge (done)"
}

restore_serial_tty()
{
    print_info "Restoring serial tty service (start)"
    systemctl unmask serial-getty@ttyAML0.service >/dev/null 2>&1 || true
    systemctl enable serial-getty@ttyAML0.service >/dev/null 2>&1 || true
    systemctl start serial-getty@ttyAML0.service >/dev/null 2>&1 || true
    print_info "Restoring serial tty service (done)"
}

update_zigbee2mqtt_config()
{
    local config_file="/opt/zigbee2mqtt/data/configuration.yaml"
    
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    
    print_info "Checking Zigbee2MQTT configuration file"
    
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    local backup_file="/opt/zigbee2mqtt/data/configuration_${timestamp}.yaml"
    
    print_info "Creating backup: $backup_file"
    cp "$config_file" "$backup_file" || {
        print_error "Failed to create backup file"
        return 1
    }
    
    print_info "Updating Zigbee2MQTT frontend settings"
    
    /usr/bin/python3 << 'PYTHON_EOF'
import sys

config_file = "/opt/zigbee2mqtt/data/configuration.yaml"

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    modified = False
    result_lines = []
    in_frontend_section = False
    
    for line in lines:
        stripped = line.lstrip()
        
        if line.strip() == 'frontend:':
            in_frontend_section = True
            result_lines.append(line)
            continue
        
        if in_frontend_section and stripped and not line.startswith(' ') and not line.startswith('\t'):
            in_frontend_section = False
        
        if in_frontend_section and stripped.startswith('enabled:'):
            current_value = stripped.split(':', 1)[1].strip().lower()
            if current_value == 'false':
                result_lines.append("  enabled: true\n")
                modified = True
            else:
                result_lines.append(line)
        else:
            result_lines.append(line)
    
    if modified:
        with open(config_file, 'w', encoding='utf-8') as f:
            f.writelines(result_lines)
        print("Frontend enabled set to true", file=sys.stderr)
    else:
        print("Frontend already enabled, no changes needed", file=sys.stderr)
    
    sys.exit(0)

except Exception as e:
    print(f"Error updating configuration: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

    if [ $? -ne 0 ]; then
        print_error "Failed to update configuration"
        if [ -f "$backup_file" ]; then
            print_info "Restoring from backup due to update failure"
            cp "$backup_file" "$config_file" || true
        fi
        return 1
    fi
    
    print_info "Zigbee2MQTT configuration updated successfully"
}

# ========== 主流程开始 ==========

print_info "=== Factory reset script started ==="
echo "System is starting to perform factory reset actions." | wall

# 设置 LED 为 factory reset 状态
if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led clear || true
    /usr/local/bin/supervisor led factory_reset || true
fi

trhub_model=$(get_trhub_model)
print_info "TRHub model: $trhub_model"

# Stop and disable automatic apt services to avoid lock contention
disable_apt_auto_services

wait_for_dpkg_lock

remove_homeassistant_core

# remove otbr-agent (Thread border router). 独立于 HA 调用:两代形态各一份清理,
# 都会跑;没装 HA 的机器也要能清干净。
remove_otbr_agent

# remove matter2mqtt (conflicting stack with the native matter-server; either
# may be installed — the removal is a no-op when absent)
remove_matter2mqtt

# remove zigbee2mqtt
if [ "$trhub_model" == "trhubv3" ] || [ "$trhub_model" == "trhubv3a" ]; then
    remove_zigbee2mqtt
    remove_linuxbox_bridge
else
    /usr/bin/systemctl stop linuxbox-hubv3-bridge.service > /dev/null 2>&1 || true
    /usr/bin/systemctl stop zigbee2mqtt.service > /dev/null 2>&1 || true
    update_zigbee2mqtt_config
fi

/usr/bin/sync

# remove openhab
remove_openhab

remove_music_assistant

print_info "Purging remaining thirdreality packages (start)"
if [ "$trhub_model" == "trhubv3" ] || [ "$trhub_model" == "trhubv3a" ]; then
    debs=$(dpkg --list | awk '/^ii/ && $2 ~ /^thirdreality-/{print $2}')
    if [ -n "$debs" ]; then
        print_info "Found thirdreality packages: $debs"
        echo "$debs" | xargs -r apt-get remove -y || true
    else
        print_info "No thirdreality packages found"
    fi
fi
print_info "Purging remaining thirdreality packages (done)"

print_info "Removing hassio/homeassistant/thread and thirdreality paths (start)"
rm -rf /usr/share/hassio > /dev/null 2>&1 || true
rm -rf /var/lib/homeassistant > /dev/null 2>&1 || true
rm -rf /var/lib/thread  > /dev/null 2>&1 || true
# /lib/thirdreality/conf/ 不再清空:里面的 configuration_blz.yaml.default /
# configuration_zigate.yaml.default / mosquitto.conf.default 是
# **thirdreality-zigbee-mqtt 包拥有的文件**(dpkg -S /lib/thirdreality/conf/... 可查),
# 而 post-fix-zigbee2mqtt.sh 正是靠它们生成 mosquitto.conf 与 z2m 的 configuration.yaml。
# 手工删等于删别人包的文件:purge 成功时这么做是多余的,purge 失败时则留下
# "dpkg 认为文件在、磁盘上却没了"的不一致,连重装同版本都救不回来。交给
# remove_zigbee2mqtt 的 purge 处理。
# backup/ 与 archives/ 是本脚本(supervisor)自己的数据目录,只清内容、不删目录本身。
rm -rf /lib/thirdreality/backup/*  > /dev/null 2>&1 || true
rm -rf /lib/thirdreality/archives/* > /dev/null 2>&1 || true
rm -rf /usr/lib/firmware/bl706/bflb_iot > /dev/null 2>&1 || true
print_info "Removing hassio/homeassistant/thread and thirdreality paths (done)"

/usr/bin/sync
sleep 0.5

print_info "Removing NetworkManager connections (start)"
if [ -e "/usr/bin/nmcli" ]; then
    nmcli -t -f UUID con show | xargs -I {} nmcli con delete uuid {} 2>/dev/null || true
fi
print_info "Removing NetworkManager connections (done)"

# reset wifi connection information
if [ -e "/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf" ]; then
    rm -rf /etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf || true
fi

/usr/bin/systemctl daemon-reload || true

mkdir -p /var/lib/homeassistant/homeassistant || true
mkdir -p /var/lib/homeassistant/matter_server || true

# Restore serial tty service
restore_serial_tty

# Restore apt-related services (do not actively start units)
restore_apt_auto_services

# Set LED to white (indicates reboot is about to happen)
if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led white || true
fi

print_info "=== Factory reset script finished, rebooting ==="
echo "Factory reset completed. Rebooting now..."  | wall

/usr/bin/sync
sleep 1
/usr/bin/sync

# Force reboot even if previous commands failed
print_info "Executing reboot command..."
/usr/sbin/reboot -f || /sbin/reboot -f || reboot -f

# If all commands above fail, try using systemctl as a fallback
sleep 1
systemctl reboot -f || true

# Last-resort fallback using SysRq trigger
sleep 1
echo b > /proc/sysrq-trigger 2>/dev/null || true

