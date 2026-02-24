#!/bin/bash
set -Eeuo pipefail

# РљР°С‚Р°Р»РѕРі РґР»СЏ Р·Р°РіСЂСѓР·РєРё СЃРєСЂРёРїС‚Р°
SCRIPT_DIR="/etc/sing-box/scripts"


BACKEND_URL=http://localhost:5000
SUBSCRIPTION_URL="${SUBSCRIPTION_URL:-}"
TEMPLATE_URL=https://raw.githubusercontent.com/Mendex777/sbshell_dev/refs/heads/main/config_template/my/config_tproxy_19_02_2026_v1.json
CLI_SUBSCRIPTION_URL="${1:-}"

# Р‘Р°Р·РѕРІС‹Р№ URL РґР»СЏ СЃРєР°С‡РёРІР°РЅРёСЏ СЃРєСЂРёРїС‚РѕРІ
BASE_URL="https://raw.githubusercontent.com/Mendex777/sbshell_dev/refs/heads/main/debian"
NFTP_BACKUP_DIR="/etc/sing-box/nft/backup"

# РћРїСЂРµРґРµР»РµРЅРёРµ С†РІРµС‚РѕРІ
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Р‘РµР· С†РІРµС‚Р°
STATE_DIR="/var/lib/sbshell"
STAGE_FILE="$STATE_DIR/install.stage"
COMMON_LIB="/home/tdcadmin/sbshell/lib/common.sh"
CONFIG_FILE="/etc/sing-box/config.json"
CONFIG_BACKUP_FILE="/etc/sing-box/config.json.backup"
INSTALL_LOG="/var/log/sbshell-auto-install.log"

on_error() {
    local line="$1"
    local stage="unknown"
    if [ -f "$STAGE_FILE" ]; then
        stage=$(cat "$STAGE_FILE")
    fi
    echo -e "${RED}РћС€РёР±РєР° РЅР° СЃС‚СЂРѕРєРµ ${line} (stage: ${stage}). РЈСЃС‚Р°РЅРѕРІРєР° РїСЂРµСЂРІР°РЅР°.${NC}"
    rollback_install "$stage"
}
trap 'on_error $LINENO' ERR

mkdir -p "$STATE_DIR"
if [ -f "$COMMON_LIB" ]; then
    # shellcheck disable=SC1090
    source "$COMMON_LIB"
else
    # Fallback РґР»СЏ Р·Р°РїСѓСЃРєР° С‡РµСЂРµР· one-liner (curl | bash), РєРѕРіРґР° lib/common.sh РЅРµРґРѕСЃС‚СѓРїРµРЅ.
    require_cmd() {
        local cmd="$1"
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}РћС‚СЃСѓС‚СЃС‚РІСѓРµС‚ РѕР±СЏР·Р°С‚РµР»СЊРЅР°СЏ РєРѕРјР°РЅРґР°: ${cmd}${NC}"
            exit 1
        fi
    }

    validate_url() {
        local url="$1"
        [[ "$url" =~ ^https?:// ]]
    }

    backup_nft_rules() {
        local backup_dir="$1"
        mkdir -p "$backup_dir"
        if nft list ruleset >/dev/null 2>&1; then
            nft list ruleset > "$backup_dir/ruleset-$(date +%F_%H-%M-%S).nft" || true
        fi
    }

    write_stage() {
        local stage_file="$1"
        local stage="$2"
        echo "$stage" > "$stage_file"
    }

    ensure_singbox_dropin() {
        local dropin_dir="/etc/systemd/system/sing-box.service.d"
        local dropin_file="$dropin_dir/10-nftables-singbox.conf"
        mkdir -p "$dropin_dir"
        cat > "$dropin_file" <<EOF
[Unit]
After=nftables-singbox.service
Requires=nftables-singbox.service
EOF
    }

    remove_legacy_singbox_unit_edits() {
        local unit_file="/usr/lib/systemd/system/sing-box.service"
        if [ -f "$unit_file" ]; then
            sed -i '/After=nftables-singbox.service/d' "$unit_file"
            sed -i '/Requires=nftables-singbox.service/d' "$unit_file"
        fi
    }
fi

rollback_install() {
    local stage="${1:-unknown}"
    echo -e "${YELLOW}Р—Р°РїСѓСЃРє rollback РґР»СЏ stage: ${stage}${NC}"

    if [ -f "$CONFIG_BACKUP_FILE" ]; then
        cp -f "$CONFIG_BACKUP_FILE" "$CONFIG_FILE" || true
        echo -e "${YELLOW}Р’РѕСЃСЃС‚Р°РЅРѕРІР»РµРЅ backup config.json${NC}"
    fi

    local latest_nft_backup=""
    latest_nft_backup=$(ls -1t "$NFTP_BACKUP_DIR"/ruleset-*.nft 2>/dev/null | head -n1 || true)
    if [ -n "$latest_nft_backup" ]; then
        nft -f "$latest_nft_backup" || true
        echo -e "${YELLOW}Р’РѕСЃСЃС‚Р°РЅРѕРІР»РµРЅС‹ РїСЂР°РІРёР»Р° nft РёР· backup${NC}"
    fi

    systemctl daemon-reload || true
}

init_log() {
    mkdir -p "$(dirname "$INSTALL_LOG")"
    : > "$INSTALL_LOG"
}

step_line() {
    local text="$1"
    printf "%-100s" "$text .............................................................................."
}

step_run() {
    local title="$1"
    shift
    step_line "$title"
    if "$@" >>"$INSTALL_LOG" 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[FAIL]${NC}"
        return 1
    fi
}

step_run_bash() {
    local title="$1"
    local cmd="$2"
    step_line "$title"
    if bash -lc "$cmd" >>"$INSTALL_LOG" 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[FAIL]${NC}"
        return 1
    fi
}

init_log
echo -e "${YELLOW}Р›РѕРі СѓСЃС‚Р°РЅРѕРІРєРё: $INSTALL_LOG${NC}"
echo -e "${YELLOW}РџСЂРѕРІРµСЂРєР° РѕРєСЂСѓР¶РµРЅРёСЏ...${NC}"
write_stage "$STAGE_FILE" "preflight_start"
for cmd in awk grep sed cut curl wget sysctl nft systemctl tee; do
    require_cmd "$cmd"
done
write_stage "$STAGE_FILE" "preflight_ok"

# РџСЂРѕРІРµСЂРєР° РѕРїРµСЂР°С†РёРѕРЅРЅРѕР№ СЃРёСЃС‚РµРјС‹
if ! grep -qi 'ubuntu' /etc/os-release; then
    echo -e "${RED}РћС€РёР±РєР°: Р­С‚РѕС‚ СЃРєСЂРёРїС‚ РїСЂРµРґРЅР°Р·РЅР°С‡РµРЅ С‚РѕР»СЊРєРѕ РґР»СЏ Ubuntu.${NC}"
    echo -e "${YELLOW}РўРµРєСѓС‰Р°СЏ СЃРёСЃС‚РµРјР° РЅРµ РїРѕРґРґРµСЂР¶РёРІР°РµС‚СЃСЏ.${NC}"
    exit 1
fi


# РџСЂРѕРІРµСЂРєР° РІРµСЂСЃРёРё Ubuntu (24.04 РёР»Рё РІС‹С€Рµ)
UBUNTU_VERSION=$(grep 'VERSION_ID' /etc/os-release | cut -d'"' -f2)
if [[ "$UBUNTU_VERSION" < "24.04" ]]; then
    echo -e "${RED}РћС€РёР±РєР°: РўСЂРµР±СѓРµС‚СЃСЏ Ubuntu 24.04 РёР»Рё РІС‹С€Рµ.${NC}"
    echo -e "${YELLOW}РўРµРєСѓС‰Р°СЏ РІРµСЂСЃРёСЏ: $UBUNTU_VERSION${NC}"
    echo -e "${YELLOW}РџРѕР¶Р°Р»СѓР№СЃС‚Р°, РѕР±РЅРѕРІРёС‚Рµ СЃРёСЃС‚РµРјСѓ РґРѕ Ubuntu 24.04 РёР»Рё РІС‹С€Рµ.${NC}"
    exit 1
fi


# РџСЂРѕРІРµСЂРєР° РїСЂР°РІ root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}РћС€РёР±РєР°: РЎРєСЂРёРїС‚ РґРѕР»Р¶РµРЅ Р·Р°РїСѓСЃРєР°С‚СЊСЃСЏ РѕС‚ РёРјРµРЅРё root.${NC}"
    echo -e "${YELLOW}РџРѕР¶Р°Р»СѓР№СЃС‚Р°, Р·Р°РїСѓСЃС‚РёС‚Рµ СЃРєСЂРёРїС‚ СЃ РїРѕРјРѕС‰СЊСЋ sudo РёР»Рё РѕС‚ РёРјРµРЅРё root.${NC}"
    exit 1
fi

echo -e "${GREEN}РџСЂРѕРІРµСЂРєРё РїСЂРѕР№РґРµРЅС‹ СѓСЃРїРµС€РЅРѕ. Ubuntu РѕР±РЅР°СЂСѓР¶РµРЅР°, РїСЂР°РІР° root РїРѕРґС‚РІРµСЂР¶РґРµРЅС‹.${NC}"

# РЎРєСЂС‹С‚Р°СЏ С„РёС‡Р°:
# 1) РµСЃР»Рё URL РїРµСЂРµРґР°РЅ РїРµСЂРІС‹Рј Р°СЂРіСѓРјРµРЅС‚РѕРј, РёСЃРїРѕР»СЊР·СѓРµРј РµРіРѕ РєР°Рє subscription
# 2) РµСЃР»Рё РЅРµ РїРµСЂРµРґР°РЅ, РїСЂРѕРґРѕР»Р¶Р°РµРј СѓСЃС‚Р°РЅРѕРІРєСѓ СЃ TEMPLATE_URL Р±РµР· РїРѕРґРїРёСЃРєРё
if [ -n "$CLI_SUBSCRIPTION_URL" ]; then
    SUBSCRIPTION_URL="$CLI_SUBSCRIPTION_URL"
fi

if [ -n "$SUBSCRIPTION_URL" ]; then
    if ! validate_url "$SUBSCRIPTION_URL"; then
        echo -e "${RED}РћС€РёР±РєР°: URL РїРѕРґРїРёСЃРєРё РґРѕР»Р¶РµРЅ РЅР°С‡РёРЅР°С‚СЊСЃСЏ СЃ http:// РёР»Рё https://${NC}"
        exit 1
    fi
    echo -e "${GREEN}РСЃРїРѕР»СЊР·СѓРµС‚СЃСЏ SUBSCRIPTION_URL: $SUBSCRIPTION_URL${NC}"
else
    echo -e "${YELLOW}SUBSCRIPTION_URL РЅРµ Р·Р°РґР°РЅ. РСЃРїРѕР»СЊР·СѓРµС‚СЃСЏ РґРµС„РѕР»С‚РЅС‹Р№ TEMPLATE_URL (СЃРєСЂС‹С‚С‹Р№ СЂРµР¶РёРј).${NC}"
fi

# РџСЂРѕРІРµСЂРєР° РІРєР»СЋС‡РµРЅРёСЏ IP-РїРµСЂРµРЅР°РїСЂР°РІР»РµРЅРёСЏ РґР»СЏ IPv4 Рё IPv6
ipv4_forward=$(sysctl net.ipv4.ip_forward | awk '{print $3}')
ipv6_forward=$(sysctl net.ipv6.conf.all.forwarding | awk '{print $3}')

if [ "$ipv4_forward" -eq 1 ] && [ "$ipv6_forward" -eq 1 ]; then
    step_line "РџСЂРѕРІРµСЂРєР° IP forwarding"
    echo -e "${GREEN}[OK]${NC}"
else
    step_run_bash "Р’РєР»СЋС‡РµРЅРёРµ IP forwarding" "sed -i '/net.ipv4.ip_forward/s/^#//;/net.ipv6.conf.all.forwarding/s/^#//' /etc/sysctl.conf && sysctl -p"
fi

# РџСЂРѕРІРµСЂРєР° Рё СѓСЃС‚Р°РЅРѕРІРєР° sing-box
if command -v sing-box &> /dev/null; then
    sing_box_version=$(sing-box version | grep 'sing-box version' | awk '{print $3}')
    step_line "РџСЂРѕРІРµСЂРєР° sing-box (РІРµСЂСЃРёСЏ $sing_box_version)"
    echo -e "${GREEN}[OK]${NC}"
else
    step_run_bash "РќР°СЃС‚СЂРѕР№РєР° СЂРµРїРѕР·РёС‚РѕСЂРёСЏ sing-box" "mkdir -p /etc/apt/keyrings && curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc && chmod a+r /etc/apt/keyrings/sagernet.asc && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *\n' \"\$(dpkg --print-architecture)\" > /etc/apt/sources.list.d/sagernet.list"
    step_run "РћР±РЅРѕРІР»РµРЅРёРµ СЃРїРёСЃРєР° РїР°РєРµС‚РѕРІ (apt)" apt-get update -qq
    step_run "РЈСЃС‚Р°РЅРѕРІРєР° РїР°РєРµС‚Р° sing-box" apt-get install -yq sing-box
    
    # РџСЂРѕРІРµСЂРєР° СѓСЃРїРµС€РЅРѕСЃС‚Рё СѓСЃС‚Р°РЅРѕРІРєРё
    if command -v sing-box &> /dev/null; then
        sing_box_version=$(sing-box version | grep 'sing-box version' | awk '{print $3}')
        step_line "РЈСЃС‚Р°РЅРѕРІРєР° sing-box (РІРµСЂСЃРёСЏ $sing_box_version)"
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}РћС€РёР±РєР°: РЈСЃС‚Р°РЅРѕРІРєР° sing-box РЅРµ СѓРґР°Р»Р°СЃСЊ${NC}"
        echo -e "${YELLOW}РџСЂРѕРІРµСЂСЊС‚Рµ РїРѕРґРєР»СЋС‡РµРЅРёРµ Рє РёРЅС‚РµСЂРЅРµС‚Сѓ Рё РїРѕРІС‚РѕСЂРёС‚Рµ РїРѕРїС‹С‚РєСѓ${NC}"
        exit 1
    fi
fi

# РќР°СЃС‚СЂРѕР№РєР° СЂРµР¶РёРјР° TProxy
echo -e "${YELLOW}РќР°СЃС‚СЂРѕР№РєР° СЂРµР¶РёРјР° sing-box...${NC}"

# Р¤СѓРЅРєС†РёСЏ РѕСЃС‚Р°РЅРѕРІРєРё sing-box
stop_singbox() {
    sudo systemctl stop sing-box 2>/dev/null
    if ! systemctl is-active --quiet sing-box 2>/dev/null; then
        echo -e "${GREEN}sing-box РѕСЃС‚Р°РЅРѕРІР»РµРЅ${NC}"
    fi
}

# РћСЃС‚Р°РЅРѕРІРєР° СЃР»СѓР¶Р±С‹ РµСЃР»Рё РѕРЅР° Р·Р°РїСѓС‰РµРЅР°
stop_singbox

# РЎРѕР·РґР°РЅРёРµ РєР°С‚Р°Р»РѕРіР° РєРѕРЅС„РёРіСѓСЂР°С†РёРё РµСЃР»Рё РЅРµ СЃСѓС‰РµСЃС‚РІСѓРµС‚
step_run "РЎРѕР·РґР°РЅРёРµ РєР°С‚Р°Р»РѕРіР° /etc/sing-box" mkdir -p /etc/sing-box

# РЈСЃС‚Р°РЅРѕРІРєР° СЂРµР¶РёРјР° TProxy
step_run_bash "РЈСЃС‚Р°РЅРѕРІРєР° СЂРµР¶РёРјР° TProxy" "echo 'MODE=TProxy' > /etc/sing-box/mode.conf"

# РЈСЃС‚Р°РЅРѕРІРєР° Docker
echo -e "${YELLOW}РџСЂРѕРІРµСЂРєР° Рё СѓСЃС‚Р°РЅРѕРІРєР° Docker...${NC}"
if command -v docker &> /dev/null; then
    docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    step_line "РџСЂРѕРІРµСЂРєР° Docker (РІРµСЂСЃРёСЏ $docker_version)"
    echo -e "${GREEN}[OK]${NC}"
else
    step_run "РћР±РЅРѕРІР»РµРЅРёРµ СЃРїРёСЃРєР° РїР°РєРµС‚РѕРІ (apt)" apt-get update -y
    step_run "РЈСЃС‚Р°РЅРѕРІРєР° Р·Р°РІРёСЃРёРјРѕСЃС‚РµР№ Docker" apt-get install -y ca-certificates curl
    step_run_bash "РќР°СЃС‚СЂРѕР№РєР° СЂРµРїРѕР·РёС‚РѕСЂРёСЏ Docker" "install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && chmod a+r /etc/apt/keyrings/docker.asc && echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \${UBUNTU_CODENAME:-\$VERSION_CODENAME}) stable\" > /etc/apt/sources.list.d/docker.list"
    step_run "РћР±РЅРѕРІР»РµРЅРёРµ СЃРїРёСЃРєР° РїР°РєРµС‚РѕРІ Docker repo" apt-get update -y
    step_run "РЈСЃС‚Р°РЅРѕРІРєР° Docker" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # РџСЂРѕРІРµСЂРєР° СѓСЃРїРµС€РЅРѕСЃС‚Рё СѓСЃС‚Р°РЅРѕРІРєРё
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        echo -e "${GREEN}Docker СѓСЃРїРµС€РЅРѕ СѓСЃС‚Р°РЅРѕРІР»РµРЅ, РІРµСЂСЃРёСЏ: $docker_version${NC}"
    else
        echo -e "${RED}РћС€РёР±РєР°: РЈСЃС‚Р°РЅРѕРІРєР° Docker РЅРµ СѓРґР°Р»Р°СЃСЊ${NC}"
        exit 1
    fi
fi

# РќР°СЃС‚СЂРѕР№РєР° Docker - РѕС‚РєР»СЋС‡РµРЅРёРµ iptables
step_run_bash "РќР°СЃС‚СЂРѕР№РєР° Docker (iptables off)" "mkdir -p /etc/docker && echo '{ \"iptables\": false, \"ip6tables\": false }' > /etc/docker/daemon.json"

# РџРµСЂРµР·Р°РїСѓСЃРє Docker РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ РЅР°СЃС‚СЂРѕРµРє
step_run "РџРµСЂРµР·Р°РїСѓСЃРє Docker" systemctl restart docker
step_run "Р’РєР»СЋС‡РµРЅРёРµ Docker РІ Р°РІС‚РѕР·Р°РїСѓСЃРє" systemctl enable docker

# РћС‡РёСЃС‚РєР° РїСЂР°РІРёР» nft
backup_nft_rules "$NFTP_BACKUP_DIR" >>"$INSTALL_LOG" 2>&1
step_run "РћС‡РёСЃС‚РєР° РїСЂР°РІРёР» nftables" nft flush ruleset
write_stage "$STAGE_FILE" "docker_ready"

# Р—Р°РїСѓСЃРє РєРѕРЅС‚РµР№РЅРµСЂР° sing-box-subscribe
# РћСЃС‚Р°РЅРѕРІРєР° Рё СѓРґР°Р»РµРЅРёРµ СЃСѓС‰РµСЃС‚РІСѓСЋС‰РµРіРѕ РєРѕРЅС‚РµР№РЅРµСЂР° РµСЃР»Рё РµСЃС‚СЊ
step_run_bash "РћСЃС‚Р°РЅРѕРІРєР° СЃС‚Р°СЂРѕРіРѕ РєРѕРЅС‚РµР№РЅРµСЂР° subscribe" "docker stop sing-box-subscribe >/dev/null 2>&1 || true; docker rm sing-box-subscribe >/dev/null 2>&1 || true"

# Р—Р°РїСѓСЃРє РЅРѕРІРѕРіРѕ РєРѕРЅС‚РµР№РЅРµСЂР°
step_run_bash "Р—Р°РїСѓСЃРє РєРѕРЅС‚РµР№РЅРµСЂР° sing-box-subscribe" "docker run -d --name sing-box-subscribe --network host jwy8645/sing-box-subscribe:amd64 >/dev/null"

#РЈСЃС‚Р°РЅРѕРІРєР° РёРЅСЃС‚СЂСѓРјРµРЅС‚РѕРІ РґР»СЏ API (РґР»СЏ СЂРµРґР°РєС‚РёСЂРѕРІР°РЅРёСЏ С„Р°Р№Р»РѕРІ)
step_run_bash "РЈСЃС‚Р°РЅРѕРІРєР° API-РёРЅСЃС‚СЂСѓРјРµРЅС‚РѕРІ" "bash <(curl -fsSL \"https://raw.githubusercontent.com/Mendex777/zashboard/refs/heads/test/api%20web%20editor/install-api.sh\")"


# РЎРѕР·РґР°РЅРёРµ РєР°С‚Р°Р»РѕРіР° РґР»СЏ СЃРєСЂРёРїС‚РѕРІ Рё СѓСЃС‚Р°РЅРѕРІРєР° РїСЂР°РІ
step_run "РЎРѕР·РґР°РЅРёРµ РєР°С‚Р°Р»РѕРіР° СЃРєСЂРёРїС‚РѕРІ" mkdir -p "$SCRIPT_DIR"
step_run_bash "РЈСЃС‚Р°РЅРѕРІРєР° РІР»Р°РґРµР»СЊС†Р° РєР°С‚Р°Р»РѕРіР° СЃРєСЂРёРїС‚РѕРІ" "chown \"\$(logname):\$(logname)\" \"$SCRIPT_DIR\" 2>/dev/null || chown \"\${SUDO_USER:-root}:\${SUDO_USER:-root}\" \"$SCRIPT_DIR\" 2>/dev/null || true"


# РЎРїРёСЃРѕРє СЃРєСЂРёРїС‚РѕРІ РґР»СЏ Р·Р°РіСЂСѓР·РєРё
SCRIPTS=(
    "check_environment.sh"     # РџСЂРѕРІРµСЂРєР° СЃРёСЃС‚РµРјРЅРѕР№ СЃСЂРµРґС‹
    "set_network.sh"           # РќР°СЃС‚СЂРѕР№РєР° СЃРµС‚Рё
    "check_update.sh"          # РџСЂРѕРІРµСЂРєР° РѕР±РЅРѕРІР»РµРЅРёР№
    "install_singbox.sh"       # РЈСЃС‚Р°РЅРѕРІРєР° Sing-box
    "manual_input.sh"          # Р’РІРѕРґ РєРѕРЅС„РёРіСѓСЂР°С†РёРё РІСЂСѓС‡РЅСѓСЋ
    "manual_update.sh"         # Р СѓС‡РЅРѕРµ РѕР±РЅРѕРІР»РµРЅРёРµ РєРѕРЅС„РёРіСѓСЂР°С†РёРё
    "auto_update.sh"           # РђРІС‚РѕРјР°С‚РёС‡РµСЃРєРѕРµ РѕР±РЅРѕРІР»РµРЅРёРµ РєРѕРЅС„РёРіСѓСЂР°С†РёРё
    "configure_tproxy.sh"      # РќР°СЃС‚СЂРѕР№РєР° СЂРµР¶РёРјР° TProxy
    "start_singbox.sh"         # Р—Р°РїСѓСЃРє Sing-box РІСЂСѓС‡РЅСѓСЋ
    "stop_singbox.sh"          # РћСЃС‚Р°РЅРѕРІРєР° Sing-box РІСЂСѓС‡РЅСѓСЋ
    "clean_nft.sh"             # РћС‡РёСЃС‚РєР° РїСЂР°РІРёР» nftables
    "set_defaults.sh"          # РЈСЃС‚Р°РЅРѕРІРєР° РЅР°СЃС‚СЂРѕРµРє РїРѕ СѓРјРѕР»С‡Р°РЅРёСЋ
    "commands.sh"              # Р§Р°СЃС‚Рѕ РёСЃРїРѕР»СЊР·СѓРµРјС‹Рµ РєРѕРјР°РЅРґС‹
    "switch_mode.sh"           # РџРµСЂРµРєР»СЋС‡РµРЅРёРµ СЂРµР¶РёРјР° РїСЂРѕРєСЃРё
    "manage_autostart.sh"      # РќР°СЃС‚СЂРѕР№РєР° Р°РІС‚РѕР·Р°РїСѓСЃРєР°
    "check_config.sh"          # РџСЂРѕРІРµСЂРєР° РєРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅС‹С… С„Р°Р№Р»РѕРІ
    "update_scripts.sh"        # РћР±РЅРѕРІР»РµРЅРёРµ СЃРєСЂРёРїС‚РѕРІ
    "update_ui.sh"             # РЈСЃС‚Р°РЅРѕРІРєР°/РѕР±РЅРѕРІР»РµРЅРёРµ/РїСЂРѕРІРµСЂРєР° РїР°РЅРµР»Рё СѓРїСЂР°РІР»РµРЅРёСЏ
    "doctor.sh"                # Р”РёР°РіРЅРѕСЃС‚РёРєР° Рё РїСЂРѕРІРµСЂРєР° СЃРѕСЃС‚РѕСЏРЅРёСЏ
    "menu.sh"                  # Р“Р»Р°РІРЅРѕРµ РјРµРЅСЋ
)
OPTIONAL_SCRIPTS=("doctor.sh")

# Р¤СѓРЅРєС†РёСЏ РґР»СЏ Р·Р°РіСЂСѓР·РєРё СЃРєСЂРёРїС‚РѕРІ
download_scripts() {
    echo -e "${YELLOW}Р—Р°РіСЂСѓР·РєР° СЃРєСЂРёРїС‚РѕРІ...${NC}"
    local failed_scripts=()
    
    for SCRIPT in "${SCRIPTS[@]}"; do
        step_line "Р—Р°РіСЂСѓР·РєР° $SCRIPT"
        if wget -q -O "$SCRIPT_DIR/$SCRIPT" "$BASE_URL/$SCRIPT"; then
            chmod +x "$SCRIPT_DIR/$SCRIPT"
            echo -e "${GREEN}[OK]${NC}"
        else
            is_optional=0
            for optional in "${OPTIONAL_SCRIPTS[@]}"; do
                if [ "$optional" = "$SCRIPT" ]; then
                    is_optional=1
                    break
                fi
            done
            if [ "$is_optional" -eq 1 ]; then
                echo -e "${YELLOW}[SKIP]${NC}"
            else
                echo -e "${RED}[FAIL]${NC}"
                failed_scripts+=("$SCRIPT")
            fi
        fi
    done
    
    # РџСЂРѕРІРµСЂРєР° СЂРµР·СѓР»СЊС‚Р°С‚РѕРІ Р·Р°РіСЂСѓР·РєРё
    if [ ${#failed_scripts[@]} -eq 0 ]; then
        echo -e "${GREEN}Р’СЃРµ СЃРєСЂРёРїС‚С‹ Р·Р°РіСЂСѓР¶РµРЅС‹ СѓСЃРїРµС€РЅРѕ!${NC}"
        return 0
    else
        echo -e "${RED}РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РіСЂСѓР·РёС‚СЊ СЃР»РµРґСѓСЋС‰РёРµ СЃРєСЂРёРїС‚С‹:${NC}"
        for script in "${failed_scripts[@]}"; do
            echo -e "${RED}- $script${NC}"
        done
        return 1
    fi
}

# Р—Р°РїСѓСЃРє Р·Р°РіСЂСѓР·РєРё СЃРєСЂРёРїС‚РѕРІ
download_scripts || exit 1
###################################################################################################
#РџСЂРёРјРµРЅСЏРµРј РїСЂР°РІРёР»Р° С„Р°РµСЂРІРѕР»Р°
step_run "РџСЂРёРјРµРЅРµРЅРёРµ РїСЂР°РІРёР» TProxy" bash "$SCRIPT_DIR/configure_tproxy.sh"

###################################################################################################
# Р’РєР»СЋС‡Р°РµРј Р°РІС‚РѕР·Р°РіСЂСѓР·РєСѓ sing-box
echo -e "${YELLOW}РќР°СЃС‚СЂРѕР№РєР° Р°РІС‚РѕР·Р°РїСѓСЃРєР° sing-box...${NC}"

# Р¤СѓРЅРєС†РёСЏ РїСЂРёРјРµРЅРµРЅРёСЏ РїСЂР°РІРёР» С„Р°Р№РµСЂРІРѕР»Р°
apply_firewall() {
    MODE=$(grep -oP '(?<=^MODE=).*' /etc/sing-box/mode.conf)
    if [ "$MODE" = "TProxy" ]; then
        echo "РџСЂРёРјРµРЅРµРЅРёРµ РїСЂР°РІРёР» С„Р°Р№РµСЂРІРѕР»Р° РґР»СЏ СЂРµР¶РёРјР° TProxy..."
        bash /etc/sing-box/scripts/configure_tproxy.sh
    elif [ "$MODE" = "TUN" ]; then
        if [ ! -x /etc/sing-box/scripts/configure_tun.sh ]; then
            echo "РЎРєСЂРёРїС‚ configure_tun.sh РѕС‚СЃСѓС‚СЃС‚РІСѓРµС‚, РїСЂРёРјРµРЅРµРЅРёРµ РїСЂР°РІРёР» TUN РЅРµРІРѕР·РјРѕР¶РЅРѕ."
            exit 1
        fi
        echo "РџСЂРёРјРµРЅРµРЅРёРµ РїСЂР°РІРёР» С„Р°Р№РµСЂРІРѕР»Р° РґР»СЏ СЂРµР¶РёРјР° TUN..."
        bash /etc/sing-box/scripts/configure_tun.sh
    else
        echo "РќРµРґРѕРїСѓСЃС‚РёРјС‹Р№ СЂРµР¶РёРј, РїСЂРѕРїСѓСЃРєР°РµРј РїСЂРёРјРµРЅРµРЅРёРµ РїСЂР°РІРёР» С„Р°Р№РµСЂРІРѕР»Р°."
        exit 1
    fi
}

# РџСЂРѕРІРµСЂРєР°, РІРєР»СЋС‡С‘РЅ Р»Рё СѓР¶Рµ Р°РІС‚РѕР·Р°РїСѓСЃРє
if systemctl is-enabled sing-box.service >/dev/null 2>&1 && systemctl is-enabled nftables-singbox.service >/dev/null 2>&1; then
    echo -e "${GREEN}РђРІС‚РѕР·Р°РїСѓСЃРє СѓР¶Рµ РІРєР»СЋС‡С‘РЅ, РЅРёРєР°РєРёС… РґРµР№СЃС‚РІРёР№ РЅРµ С‚СЂРµР±СѓРµС‚СЃСЏ.${NC}"
else
    step_line "Р’РєР»СЋС‡РµРЅРёРµ Р°РІС‚РѕР·Р°РїСѓСЃРєР° sing-box"
    
    # РЈРґР°Р»СЏРµРј СЃС‚Р°СЂС‹Р№ С„Р°Р№Р» СЃРµСЂРІРёСЃР°, С‡С‚РѕР±С‹ РёР·Р±РµР¶Р°С‚СЊ РґСѓР±Р»РёСЂРѕРІР°РЅРёСЏ
    sudo rm -f /etc/systemd/system/nftables-singbox.service
    
    # РЎРѕР·РґР°С‘Рј СЃРµСЂРІРёСЃ nftables-singbox.service
    sudo bash -c 'cat > /etc/systemd/system/nftables-singbox.service <<EOF
[Unit]
Description=РџСЂРёРјРµРЅРµРЅРёРµ РїСЂР°РІРёР» nftables РґР»СЏ Sing-Box
After=network.target

[Service]
ExecStart=/etc/sing-box/scripts/manage_autostart.sh apply_firewall
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'
    
    # РСЃРїРѕР»СЊР·СѓРµРј drop-in РІРјРµСЃС‚Рѕ РїСЂР°РІРєРё vendor unit
    ensure_singbox_dropin
    remove_legacy_singbox_unit_edits
    
    # РџРµСЂРµР·Р°РіСЂСѓР¶Р°РµРј РєРѕРЅС„РёРіСѓСЂР°С†РёСЋ systemd Рё РІРєР»СЋС‡Р°РµРј СЃРµСЂРІРёСЃС‹
    if systemctl daemon-reload >>"$INSTALL_LOG" 2>&1 && systemctl enable nftables-singbox.service sing-box.service >>"$INSTALL_LOG" 2>&1 && systemctl start nftables-singbox.service sing-box.service >>"$INSTALL_LOG" 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
        write_stage "$STAGE_FILE" "autostart_ready"
    else
        echo -e "${RED}[FAIL]${NC}"
        exit 1
    fi
fi

###################################################################################################

# РћР±РЅРѕРІР»СЏРµРј С„Р°Р№Р» СЃ РєРѕРЅС„РёРіСѓСЂР°С†РёРµР№ РїРѕ СѓРјРѕР»С‡Р°РЅРёСЋ
echo -e "${YELLOW}РЎРѕР·РґР°РЅРёРµ С„Р°Р№Р»РѕРІ РєРѕРЅС„РёРіСѓСЂР°С†РёРё...${NC}"

DEFAULTS_FILE="/etc/sing-box/defaults.conf"

cat > "$DEFAULTS_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TPROXY_TEMPLATE_URL=$TEMPLATE_URL
TUN_TEMPLATE_URL=
EOF

step_line "РЎРѕР·РґР°РЅРёРµ defaults.conf"
echo -e "${GREEN}[OK]${NC}"

# Р¤Р°Р№Р» РґР»СЏ СЂСѓС‡РЅРѕРіРѕ РІРІРѕРґР° РєРѕРЅС„РёРіСѓСЂР°С†РёРё
MANUAL_FILE="/etc/sing-box/manual.conf"

cat > "$MANUAL_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TEMPLATE_URL=$TEMPLATE_URL
EOF

step_line "РЎРѕР·РґР°РЅРёРµ manual.conf"
echo -e "${GREEN}[OK]${NC}"
###################################################################################################


#Р‘Р»РѕРє С„РѕСЂРјРёСЂРѕРІР°РЅРёСЏ С„Р°Р№Р»Р° РёРЅРёС†РёР°Р»РёР·Р°С†РёРё (С‚Р°Рє РєР°Рє Сѓ РЅР°СЃ С„СѓР» Р°РІС‚РѕРјР°С‚)
#СЃРѕР·РґР°С‘Рј С„Р°Р№Р» РёРЅРёС†РёР°Р»РёР·Р°С†РёРё
INITIALIZED_FILE="$SCRIPT_DIR/.initialized"
touch "$INITIALIZED_FILE"

# Р”РѕР±Р°РІР»СЏРµРј Р°Р»РёР°СЃ sb РІ .bashrc, РµСЃР»Рё РµС‰С‘ РЅРµС‚
if ! grep -q "alias sb=" ~/.bashrc; then
    echo "alias sb='bash $SCRIPT_DIR/menu.sh menu'" >> ~/.bashrc
fi

# РЎРѕР·РґР°РµРј РёСЃРїРѕР»РЅСЏРµРјС‹Р№ С„Р°Р№Р» РґР»СЏ Р±С‹СЃС‚СЂРѕРіРѕ Р·Р°РїСѓСЃРєР° РјРµРЅСЋ sb
if [ ! -f /usr/local/bin/sb ]; then
    echo -e '#!/bin/bash\nbash /etc/sing-box/scripts/menu.sh menu' | sudo tee /usr/local/bin/sb >/dev/null
    sudo chmod +x /usr/local/bin/sb
fi

###################################################################################################
#Р‘Р»РѕРє СЃ РєР°СЃС‚РѕРј Р»РёСЃС‚
mkdir -p /etc/sing-box/rules
cat > /etc/sing-box/rules/custom_list.json <<EOF
{
  "version": 1,
  "rules": [
    {
      "domain_suffix": [
        "mozilla.org",
        "veeam.com",
        "kino.pub",
        "anilibria.tv",
        "rutor.org",
        "zona.media",
        "skvalex.dev",
        "googleplay.com",
        "play-fe.googleapis.com",
        "play-games.googleusercontent.com",
        "play-lh.googleusercontent.com",
        "play.google.com",
        "play.googleapis.com",
        "xn--ngstr-lra8j.com",
        "intel.com",
        "hashicorp.com",
        "bitwarden.com",
        "repack.me",
        "nzxt.com",
        "cub.red",
        "byteintlapi.com",
        "byteoversea.com",
        "bytednsdoc.com",
        "bytelemon.com",
        "exp-tas.com",
        "trae.ai",
        "trae.com.cn",
        "mchost.guru",
        "huggingface.co",
        "copilot.microsoft.com",
        "2ip.ru"
      ]
    },
    {
      "domain": "tmdb-image-prod.b-cdn.net",
      "domain_suffix": [
        "themoviedb.org",
        "tmdb.org"
      ]
    },

    {
      "ip_cidr": [
        "5.35.91.158",
        "87.236.16.19/32"
      ]
    }
  ]
}

EOF


###################################################################################################

#Р‘Р»РѕРє С„РѕСЂРјРёСЂРѕРІР°РЅРёСЏ РєРѕРЅС„РёРіСѓСЂР°С†РёРё sing-box РёР· РїРѕРґРїРёСЃРєРєРё Рё РєРѕРЅС„РёРіР°

#РћС‚С‡РёС‰Р°РµРј РїСЂР°РІРёР»Р° nft (С‡С‚Рѕ Р±С‹ РЅРµ РјРµС€Р°С‚СЊ РґРѕРєРµСЂСѓ)
backup_nft_rules "$NFTP_BACKUP_DIR" >>"$INSTALL_LOG" 2>&1
nft flush ruleset

# Р¤РѕСЂРјРёСЂРѕРІР°РЅРёРµ URL РєРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅРѕРіРѕ С„Р°Р№Р»Р°
if [ -n "$SUBSCRIPTION_URL" ]; then
    FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}&file=${TEMPLATE_URL}"
    echo "РЎС„РѕСЂРјРёСЂРѕРІР°РЅ РїРѕР»РЅС‹Р№ URL РїРѕРґРїРёСЃРєРё: $FULL_URL"
else
    FULL_URL="${TEMPLATE_URL}"
    echo "SUBSCRIPTION_URL РЅРµ Р·Р°РґР°РЅ, РёСЃРїРѕР»СЊР·СѓРµРј С€Р°Р±Р»РѕРЅ РЅР°РїСЂСЏРјСѓСЋ: $FULL_URL"
fi

# Р РµР·РµСЂРІРЅРѕРµ РєРѕРїРёСЂРѕРІР°РЅРёРµ С‚РµРєСѓС‰РµРіРѕ РєРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅРѕРіРѕ С„Р°Р№Р»Р°
[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_BACKUP_FILE"

if curl -fsSL --connect-timeout 10 --max-time 30 "$FULL_URL" -o "$CONFIG_FILE" >>"$INSTALL_LOG" 2>&1; then
    step_line "Р—Р°РіСЂСѓР·РєР° config.json"
    echo -e "${GREEN}[OK]${NC}"
    step_line "РџСЂРѕРІРµСЂРєР° config.json"
    if sing-box check -c "$CONFIG_FILE" >>"$INSTALL_LOG" 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[FAIL]${NC}"
        echo -e "${RED}РџСЂРѕРІРµСЂРєР° РєРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅРѕРіРѕ С„Р°Р№Р»Р° РЅРµ РїСЂРѕР№РґРµРЅР°, РІРѕСЃСЃС‚Р°РЅР°РІР»РёРІР°РµРј СЂРµР·РµСЂРІРЅСѓСЋ РєРѕРїРёСЋ...${NC}"
        [ -f "$CONFIG_BACKUP_FILE" ] && cp "$CONFIG_BACKUP_FILE" "$CONFIG_FILE"
    fi
else
    echo -e "${RED}РќРµ СѓРґР°Р»РѕСЃСЊ СЃРєР°С‡Р°С‚СЊ РєРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅС‹Р№ С„Р°Р№Р», РІРѕСЃСЃС‚Р°РЅР°РІР»РёРІР°РµРј СЂРµР·РµСЂРІРЅСѓСЋ РєРѕРїРёСЋ...${NC}"
    [ -f "$CONFIG_BACKUP_FILE" ] && cp "$CONFIG_BACKUP_FILE" "$CONFIG_FILE"
fi
write_stage "$STAGE_FILE" "config_ready"

# РџСЂРёРјРµРЅСЏРµРј РїСЂР°РІРёР»Р° firewall (РІРѕР·РІСЂР°С‰Р°РµРј РїСЂР°РІРёР»Р°)
step_run "РџСЂРёРјРµРЅРµРЅРёРµ nftables.conf" nft -f /etc/sing-box/nft/nftables.conf

# РР·РјРµРЅРµРЅРёРµ РїСЂР°РІ РЅР° РєР°С‚Р°Р»РѕРі /etc/sing-box
step_run "РЈСЃС‚Р°РЅРѕРІРєР° РІР»Р°РґРµР»СЊС†Р° /etc/sing-box" chown -R sing-box:sing-box /etc/sing-box

# РџРµСЂРµР·Р°РїСѓСЃРє sing-box Рё РїСЂРѕРІРµСЂРєР° СЃС‚Р°С‚СѓСЃР°
step_run "РџРµСЂРµР·Р°РїСѓСЃРє СЃР»СѓР¶Р±С‹ sing-box" systemctl restart sing-box

if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}sing-box СѓСЃРїРµС€РЅРѕ Р·Р°РїСѓС‰РµРЅ${NC}"
    write_stage "$STAGE_FILE" "singbox_active"
else
    echo -e "${RED}РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РїСѓСЃС‚РёС‚СЊ sing-box${NC}"
fi


###################################################################################################


if systemctl is-active --quiet sing-box; then
    write_stage "$STAGE_FILE" "completed"
    echo -e "${GREEN}РђРІС‚РѕРјР°С‚РёС‡РµСЃРєР°СЏ СѓСЃС‚Р°РЅРѕРІРєР° Р·Р°РІРµСЂС€РµРЅР° СѓСЃРїРµС€РЅРѕ!${NC}"
    echo -e "${GREEN}Р”Р»СЏ Р·Р°РїСѓСЃРєР° РјРµРЅСЋ РІРІРµРґРёС‚Рµ: bash $SCRIPT_DIR/menu.sh${NC}"
else
    echo -e "${RED}РђРІС‚РѕРјР°С‚РёС‡РµСЃРєР°СЏ СѓСЃС‚Р°РЅРѕРІРєР° Р·Р°РІРµСЂС€РµРЅР° СЃ РѕС€РёР±РєР°РјРё.${NC}"
    echo -e "${YELLOW}РџСЂРѕРІРµСЂСЊС‚Рµ РїРѕРґРєР»СЋС‡РµРЅРёРµ Рє РёРЅС‚РµСЂРЅРµС‚Сѓ Рё РїРѕРІС‚РѕСЂРёС‚Рµ РїРѕРїС‹С‚РєСѓ.${NC}"
    exit 1
fi


