#!/bin/bash
set -Eeuo pipefail

# Каталог для загрузки скрипта
SCRIPT_DIR="/etc/sing-box/scripts"


BACKEND_URL=http://localhost:5000
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TEMPLATE_URL=https://raw.githubusercontent.com/Mendex777/sbshell_3/refs/heads/main/config_template/my/config_tproxy_25_07_2025_v1.json

# Базовый URL для скачивания скриптов
BASE_URL="https://raw.githubusercontent.com/Mendex777/sbshell_3/refs/heads/main/debian"
NFTP_BACKUP_DIR="/etc/sing-box/nft/backup"

# Определение цветов
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Без цвета
STATE_DIR="/var/lib/sbshell"
STAGE_FILE="$STATE_DIR/install.stage"
COMMON_LIB="/home/tdcadmin/sbshell/lib/common.sh"
CONFIG_FILE="/etc/sing-box/config.json"
CONFIG_BACKUP_FILE="/etc/sing-box/config.json.backup"

on_error() {
    local line="$1"
    local stage="unknown"
    if [ -f "$STAGE_FILE" ]; then
        stage=$(cat "$STAGE_FILE")
    fi
    echo -e "${RED}Ошибка на строке ${line} (stage: ${stage}). Установка прервана.${NC}"
    rollback_install "$stage"
}
trap 'on_error $LINENO' ERR

mkdir -p "$STATE_DIR"
if [ -f "$COMMON_LIB" ]; then
    # shellcheck disable=SC1090
    source "$COMMON_LIB"
else
    echo -e "${RED}Не найден общий модуль: $COMMON_LIB${NC}"
    exit 1
fi

rollback_install() {
    local stage="${1:-unknown}"
    echo -e "${YELLOW}Запуск rollback для stage: ${stage}${NC}"

    if [ -f "$CONFIG_BACKUP_FILE" ]; then
        cp -f "$CONFIG_BACKUP_FILE" "$CONFIG_FILE" || true
        echo -e "${YELLOW}Восстановлен backup config.json${NC}"
    fi

    local latest_nft_backup=""
    latest_nft_backup=$(ls -1t "$NFTP_BACKUP_DIR"/ruleset-*.nft 2>/dev/null | head -n1 || true)
    if [ -n "$latest_nft_backup" ]; then
        nft -f "$latest_nft_backup" || true
        echo -e "${YELLOW}Восстановлены правила nft из backup${NC}"
    fi

    systemctl daemon-reload || true
}

echo -e "${YELLOW}Preflight-проверка окружения...${NC}"
write_stage "$STAGE_FILE" "preflight_start"
for cmd in awk grep sed cut curl wget sysctl nft systemctl tee; do
    require_cmd "$cmd"
done
write_stage "$STAGE_FILE" "preflight_ok"

# Проверка операционной системы
if ! grep -qi 'ubuntu' /etc/os-release; then
    echo -e "${RED}Ошибка: Этот скрипт предназначен только для Ubuntu.${NC}"
    echo -e "${YELLOW}Текущая система не поддерживается.${NC}"
    exit 1
fi


# Проверка версии Ubuntu (24.04 или выше)
UBUNTU_VERSION=$(grep 'VERSION_ID' /etc/os-release | cut -d'"' -f2)
if [[ "$UBUNTU_VERSION" < "24.04" ]]; then
    echo -e "${RED}Ошибка: Требуется Ubuntu 24.04 или выше.${NC}"
    echo -e "${YELLOW}Текущая версия: $UBUNTU_VERSION${NC}"
    echo -e "${YELLOW}Пожалуйста, обновите систему до Ubuntu 24.04 или выше.${NC}"
    exit 1
fi


# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: Скрипт должен запускаться от имени root.${NC}"
    echo -e "${YELLOW}Пожалуйста, запустите скрипт с помощью sudo или от имени root.${NC}"
    exit 1
fi

echo -e "${GREEN}Проверки пройдены успешно. Ubuntu обнаружена, права root подтверждены.${NC}"

# Запрос URL подписки у пользователя
echo -e "${YELLOW}Введите URL подписки (subscription URL):${NC}"
read -rp "URL подписки: " SUBSCRIPTION_URL

if [ -z "$SUBSCRIPTION_URL" ]; then
    echo -e "${RED}Ошибка: URL подписки не может быть пустым.${NC}"
    exit 1
fi
if ! validate_url "$SUBSCRIPTION_URL"; then
    echo -e "${RED}Ошибка: URL подписки должен начинаться с http:// или https://${NC}"
    exit 1
fi

echo -e "${GREEN}URL подписки установлен: $SUBSCRIPTION_URL${NC}"

# Проверка включения IP-перенаправления для IPv4 и IPv6
ipv4_forward=$(sysctl net.ipv4.ip_forward | awk '{print $3}')
ipv6_forward=$(sysctl net.ipv6.conf.all.forwarding | awk '{print $3}')

if [ "$ipv4_forward" -eq 1 ] && [ "$ipv6_forward" -eq 1 ]; then
    echo "IP-перенаправление уже включено"
else
    echo "Включение IP-перенаправления..."
    sudo sed -i '/net.ipv4.ip_forward/s/^#//;/net.ipv6.conf.all.forwarding/s/^#//' /etc/sysctl.conf
    sudo sysctl -p
    echo "IP-перенаправление успешно включено"
fi

# Проверка и установка sing-box
echo -e "${YELLOW}Проверка установки sing-box...${NC}"
if command -v sing-box &> /dev/null; then
    sing_box_version=$(sing-box version | grep 'sing-box version' | awk '{print $3}')
    echo -e "${GREEN}sing-box уже установлен, версия: $sing_box_version${NC}"
else
    echo -e "${YELLOW}sing-box не найден, начинаем установку...${NC}"
    
    # Добавление официального GPG ключа и репозитория
    echo -e "${YELLOW}Добавление официального репозитория...${NC}"
    sudo mkdir -p /etc/apt/keyrings
    sudo curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
    sudo chmod a+r /etc/apt/keyrings/sagernet.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | sudo tee /etc/apt/sources.list.d/sagernet.list > /dev/null
    
    # Обновление списка пакетов
    echo -e "${YELLOW}Обновление списка пакетов...${NC}"
    sudo apt-get update -qq > /dev/null 2>&1
    
    # Установка стабильной версии sing-box
    echo -e "${YELLOW}Установка стабильной версии sing-box...${NC}"
    sudo apt-get install sing-box -yq > /dev/null 2>&1
    
    # Проверка успешности установки
    if command -v sing-box &> /dev/null; then
        sing_box_version=$(sing-box version | grep 'sing-box version' | awk '{print $3}')
        echo -e "${GREEN}sing-box успешно установлен, версия: $sing_box_version${NC}"
    else
        echo -e "${RED}Ошибка: Установка sing-box не удалась${NC}"
        echo -e "${YELLOW}Проверьте подключение к интернету и повторите попытку${NC}"
        exit 1
    fi
fi

# Настройка режима TProxy
echo -e "${YELLOW}Настройка режима sing-box...${NC}"

# Функция остановки sing-box
stop_singbox() {
    sudo systemctl stop sing-box 2>/dev/null
    if ! systemctl is-active --quiet sing-box 2>/dev/null; then
        echo -e "${GREEN}sing-box остановлен${NC}"
    fi
}

# Остановка службы если она запущена
stop_singbox

# Создание каталога конфигурации если не существует
sudo mkdir -p /etc/sing-box

# Установка режима TProxy
echo "MODE=TProxy" | sudo tee /etc/sing-box/mode.conf > /dev/null
echo -e "${GREEN}Режим sing-box установлен: TProxy${NC}"

# Установка Docker
echo -e "${YELLOW}Проверка и установка Docker...${NC}"
if command -v docker &> /dev/null; then
    docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    echo -e "${GREEN}Docker уже установлен, версия: $docker_version${NC}"
else
    echo -e "${YELLOW}Docker не найден, начинаем установку...${NC}"
    
    # Add Docker's official GPG key
    echo -e "${YELLOW}Добавление официального GPG ключа Docker...${NC}"
    sudo apt-get update -y
    sudo apt-get install ca-certificates curl -y
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add the repository to Apt sources
    echo -e "${YELLOW}Добавление репозитория Docker...${NC}"
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    
    # Установка Docker
    echo -e "${YELLOW}Установка Docker и компонентов...${NC}"
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    
    # Проверка успешности установки
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        echo -e "${GREEN}Docker успешно установлен, версия: $docker_version${NC}"
    else
        echo -e "${RED}Ошибка: Установка Docker не удалась${NC}"
        exit 1
    fi
fi

# Настройка Docker - отключение iptables
echo -e "${YELLOW}Настройка Docker (отключение iptables)...${NC}"
sudo mkdir -p /etc/docker
echo '{ "iptables": false, "ip6tables": false }' | sudo tee /etc/docker/daemon.json > /dev/null
echo -e "${GREEN}Docker настроен для работы без iptables${NC}"

# Перезапуск Docker для применения настроек
echo -e "${YELLOW}Перезапуск Docker...${NC}"
sudo systemctl restart docker
sudo systemctl enable docker

# Очистка правил nft
echo -e "${YELLOW}Очистка правил nftables...${NC}"
backup_nft_rules "$NFTP_BACKUP_DIR"
sudo nft flush ruleset
echo -e "${GREEN}Правила nftables очищены${NC}"
write_stage "$STAGE_FILE" "docker_ready"

# Запуск контейнера sing-box-subscribe
echo -e "${YELLOW}Запуск контейнера sing-box-subscribe...${NC}"
# Остановка и удаление существующего контейнера если есть
sudo docker stop sing-box-subscribe 2>/dev/null || true
sudo docker rm sing-box-subscribe 2>/dev/null || true

# Запуск нового контейнера
if sudo docker run -d --name sing-box-subscribe --network host jwy8645/sing-box-subscribe:amd64; then
    echo -e "${GREEN}Контейнер sing-box-subscribe успешно запущен${NC}"
else
    echo -e "${RED}Ошибка запуска контейнера sing-box-subscribe${NC}"
    exit 1
fi

#Установка инструментов для API (для редактирования файлов)
bash <(curl -fsSL "https://raw.githubusercontent.com/Mendex777/zashboard/refs/heads/test/api%20web%20editor/install-api.sh")


# Создание каталога для скриптов и установка прав
echo -e "${YELLOW}Создание каталога для скриптов...${NC}"
mkdir -p "$SCRIPT_DIR"
chown "$(logname):$(logname)" "$SCRIPT_DIR" 2>/dev/null || chown "$SUDO_USER:$SUDO_USER" "$SCRIPT_DIR" 2>/dev/null
echo -e "${GREEN}Каталог $SCRIPT_DIR создан успешно.${NC}"


# Список скриптов для загрузки
SCRIPTS=(
    "check_environment.sh"     # Проверка системной среды
    "set_network.sh"           # Настройка сети
    "check_update.sh"          # Проверка обновлений
    "install_singbox.sh"       # Установка Sing-box
    "manual_input.sh"          # Ввод конфигурации вручную
    "manual_update.sh"         # Ручное обновление конфигурации
    "auto_update.sh"           # Автоматическое обновление конфигурации
    "configure_tproxy.sh"      # Настройка режима TProxy
    "start_singbox.sh"         # Запуск Sing-box вручную
    "stop_singbox.sh"          # Остановка Sing-box вручную
    "clean_nft.sh"             # Очистка правил nftables
    "set_defaults.sh"          # Установка настроек по умолчанию
    "commands.sh"              # Часто используемые команды
    "switch_mode.sh"           # Переключение режима прокси
    "manage_autostart.sh"      # Настройка автозапуска
    "check_config.sh"          # Проверка конфигурационных файлов
    "update_scripts.sh"        # Обновление скриптов
    "update_ui.sh"             # Установка/обновление/проверка панели управления
    "doctor.sh"                # Диагностика и проверка состояния
    "menu.sh"                  # Главное меню
)

# Функция для загрузки скриптов
download_scripts() {
    echo -e "${YELLOW}Начинаем загрузку скриптов...${NC}"
    local failed_scripts=()
    
    for SCRIPT in "${SCRIPTS[@]}"; do
        echo -e "${YELLOW}Загружаем $SCRIPT...${NC}"
        if wget -q -O "$SCRIPT_DIR/$SCRIPT" "$BASE_URL/$SCRIPT"; then
            chmod +x "$SCRIPT_DIR/$SCRIPT"
            echo -e "${GREEN}✓ $SCRIPT загружен успешно${NC}"
        else
            echo -e "${RED}✗ Ошибка загрузки $SCRIPT${NC}"
            failed_scripts+=("$SCRIPT")
        fi
    done
    
    # Проверка результатов загрузки
    if [ ${#failed_scripts[@]} -eq 0 ]; then
        echo -e "${GREEN}Все скрипты загружены успешно!${NC}"
        return 0
    else
        echo -e "${RED}Не удалось загрузить следующие скрипты:${NC}"
        for script in "${failed_scripts[@]}"; do
            echo -e "${RED}- $script${NC}"
        done
        return 1
    fi
}

# Запуск загрузки скриптов
download_scripts || exit 1
###################################################################################################
#Применяем правила фаервола
bash "$SCRIPT_DIR/configure_tproxy.sh"

###################################################################################################
# Включаем автозагрузку sing-box
echo -e "${YELLOW}Настройка автозапуска sing-box...${NC}"

# Функция применения правил файервола
apply_firewall() {
    MODE=$(grep -oP '(?<=^MODE=).*' /etc/sing-box/mode.conf)
    if [ "$MODE" = "TProxy" ]; then
        echo "Применение правил файервола для режима TProxy..."
        bash /etc/sing-box/scripts/configure_tproxy.sh
    elif [ "$MODE" = "TUN" ]; then
        if [ ! -x /etc/sing-box/scripts/configure_tun.sh ]; then
            echo "Скрипт configure_tun.sh отсутствует, применение правил TUN невозможно."
            exit 1
        fi
        echo "Применение правил файервола для режима TUN..."
        bash /etc/sing-box/scripts/configure_tun.sh
    else
        echo "Недопустимый режим, пропускаем применение правил файервола."
        exit 1
    fi
}

# Проверка, включён ли уже автозапуск
if systemctl is-enabled sing-box.service >/dev/null 2>&1 && systemctl is-enabled nftables-singbox.service >/dev/null 2>&1; then
    echo -e "${GREEN}Автозапуск уже включён, никаких действий не требуется.${NC}"
else
    echo -e "${YELLOW}Включаем автозапуск...${NC}"
    
    # Удаляем старый файл сервиса, чтобы избежать дублирования
    sudo rm -f /etc/systemd/system/nftables-singbox.service
    
    # Создаём сервис nftables-singbox.service
    sudo bash -c 'cat > /etc/systemd/system/nftables-singbox.service <<EOF
[Unit]
Description=Применение правил nftables для Sing-Box
After=network.target

[Service]
ExecStart=/etc/sing-box/scripts/manage_autostart.sh apply_firewall
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'
    
    # Используем drop-in вместо правки vendor unit
    ensure_singbox_dropin
    remove_legacy_singbox_unit_edits
    
    # Перезагружаем конфигурацию systemd и включаем сервисы
    sudo systemctl daemon-reload
    sudo systemctl enable nftables-singbox.service sing-box.service
    sudo systemctl start nftables-singbox.service sing-box.service
    cmd_status=$?
    
    if [ "$cmd_status" -eq 0 ]; then
        echo -e "${GREEN}Автозапуск успешно включён.${NC}"
        write_stage "$STAGE_FILE" "autostart_ready"
    else
        echo -e "${RED}Ошибка при включении автозапуска.${NC}"
        exit 1
    fi
fi

###################################################################################################

# Обновляем файл с конфигурацией по умолчанию
echo -e "${YELLOW}Создание файлов конфигурации...${NC}"

DEFAULTS_FILE="/etc/sing-box/defaults.conf"

cat > "$DEFAULTS_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TPROXY_TEMPLATE_URL=$TEMPLATE_URL
TUN_TEMPLATE_URL=
EOF

echo -e "${GREEN}Файл defaults.conf создан успешно.${NC}"

# Файл для ручного ввода конфигурации
MANUAL_FILE="/etc/sing-box/manual.conf"

cat > "$MANUAL_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TEMPLATE_URL=$TEMPLATE_URL
EOF

echo -e "${GREEN}Файл manual.conf создан успешно.${NC}"
###################################################################################################


#Блок формирования файла инициализации (так как у нас фул автомат)
#создаём файл инициализации
INITIALIZED_FILE="$SCRIPT_DIR/.initialized"
touch "$INITIALIZED_FILE"

# Добавляем алиас sb в .bashrc, если ещё нет
if ! grep -q "alias sb=" ~/.bashrc; then
    echo "alias sb='bash $SCRIPT_DIR/menu.sh menu'" >> ~/.bashrc
fi

# Создаем исполняемый файл для быстрого запуска меню sb
if [ ! -f /usr/local/bin/sb ]; then
    echo -e '#!/bin/bash\nbash /etc/sing-box/scripts/menu.sh menu' | sudo tee /usr/local/bin/sb >/dev/null
    sudo chmod +x /usr/local/bin/sb
fi

###################################################################################################
#Блок с кастом лист
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

#Блок формирования конфигурации sing-box из подпискки и конфига

#Отчищаем правила nft (что бы не мешать докеру)
backup_nft_rules "$NFTP_BACKUP_DIR"
nft flush ruleset

# Формирование полного URL конфигурационного файла
FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}&file=${TEMPLATE_URL}"
echo "Сформирован полный URL подписки: $FULL_URL"

# Резервное копирование текущего конфигурационного файла
[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_BACKUP_FILE"

if curl -L --connect-timeout 10 --max-time 30 "$FULL_URL" -o "$CONFIG_FILE"; then
    echo -e "${GREEN}Обновление конфигурационного файла прошло успешно!${NC}"
    if ! sing-box check -c "$CONFIG_FILE"; then
        echo -e "${RED}Проверка конфигурационного файла не пройдена, восстанавливаем резервную копию...${NC}"
        [ -f "$CONFIG_BACKUP_FILE" ] && cp "$CONFIG_BACKUP_FILE" "$CONFIG_FILE"
    fi
else
    echo -e "${RED}Не удалось скачать конфигурационный файл, восстанавливаем резервную копию...${NC}"
    [ -f "$CONFIG_BACKUP_FILE" ] && cp "$CONFIG_BACKUP_FILE" "$CONFIG_FILE"
fi
write_stage "$STAGE_FILE" "config_ready"

# Применяем правила firewall (возвращаем правила)
nft -f /etc/sing-box/nft/nftables.conf

# Изменение прав на каталог /etc/sing-box
sudo chown -R sing-box:sing-box /etc/sing-box

# Перезапуск sing-box и проверка статуса
sudo systemctl restart sing-box

if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}sing-box успешно запущен${NC}"
    write_stage "$STAGE_FILE" "singbox_active"
else
    echo -e "${RED}Не удалось запустить sing-box${NC}"
fi


###################################################################################################


if systemctl is-active --quiet sing-box; then
    write_stage "$STAGE_FILE" "completed"
    echo -e "${GREEN}Автоматическая установка завершена успешно!${NC}"
    echo -e "${GREEN}Для запуска меню введите: bash $SCRIPT_DIR/menu.sh${NC}"
else
    echo -e "${RED}Автоматическая установка завершена с ошибками.${NC}"
    echo -e "${YELLOW}Проверьте подключение к интернету и повторите попытку.${NC}"
    exit 1
fi
