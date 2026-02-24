#!/bin/bash
set -u

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

fail_count=0
warn_count=0

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    warn_count=$((warn_count + 1))
    echo -e "${YELLOW}[WARN]${NC} $1"
}

fail() {
    fail_count=$((fail_count + 1))
    echo -e "${RED}[FAIL]${NC} $1"
}

check_cmd() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Команда доступна: $cmd"
    else
        fail "Команда отсутствует: $cmd"
    fi
}

echo "=== sbshell doctor ==="

for c in sing-box nft curl systemctl; do
    check_cmd "$c"
done

if [ -f /etc/sing-box/config.json ]; then
    if sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
        ok "config.json валиден"
    else
        fail "config.json не проходит sing-box check"
    fi
else
    fail "Отсутствует /etc/sing-box/config.json"
fi

if systemctl is-active --quiet sing-box; then
    ok "Служба sing-box активна"
else
    fail "Служба sing-box не активна"
fi

if systemctl is-enabled --quiet sing-box; then
    ok "Автозапуск sing-box включен"
else
    warn "Автозапуск sing-box отключен"
fi

if nft list tables 2>/dev/null | grep -q "inet sing-box"; then
    ok "Таблица nftables inet sing-box присутствует"
else
    fail "Таблица nftables inet sing-box отсутствует"
fi

if [ -f /var/lib/sbshell/install.stage ]; then
    stage=$(cat /var/lib/sbshell/install.stage)
    ok "Текущий stage: $stage"
else
    warn "Файл stage не найден: /var/lib/sbshell/install.stage"
fi

echo "=== summary ==="
echo "fails: $fail_count"
echo "warns: $warn_count"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi

exit 0
