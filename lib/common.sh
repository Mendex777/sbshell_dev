#!/bin/bash

set -o pipefail

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED:-}Отсутствует обязательная команда: ${cmd}${NC:-}" >&2
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
