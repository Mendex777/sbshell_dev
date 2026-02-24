#!/bin/bash

# Определение цветов
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Без цвета

# Каталог для скриптов
SCRIPT_DIR="/etc/sing-box/scripts"
TEMP_DIR="/tmp/sing-box"

# Базовый URL для скачивания скриптов
BASE_URL="https://raw.githubusercontent.com/Mendex777/sbshell_3/refs/heads/main/debian"

# URL скрипта меню для первичной загрузки
MENU_SCRIPT_URL="$BASE_URL/menu.sh"

# Сообщение о проверке версии
echo -e "${CYAN}Проверка версии, пожалуйста, подождите...${NC}"

# Создание каталогов и установка прав
sudo mkdir -p "$SCRIPT_DIR"
sudo mkdir -p "$TEMP_DIR"
sudo chown "$(whoami)":"$(whoami)" "$SCRIPT_DIR"
sudo chown "$(whoami)":"$(whoami)" "$TEMP_DIR"

# Загрузка удалённого скрипта в временный каталог
wget -q -O "$TEMP_DIR/menu.sh" "$MENU_SCRIPT_URL"

# Проверка успешности загрузки
if ! [ -f "$TEMP_DIR/menu.sh" ]; then
    echo -e "${RED}Не удалось скачать удалённый скрипт, проверьте подключение к сети.${NC}"
    exit 1
fi

# Получение версии локального и удалённого скрипта
LOCAL_VERSION=$(grep '^# 版本:' "$SCRIPT_DIR/menu.sh" | awk '{print $3}')
REMOTE_VERSION=$(grep '^# 版本:' "$TEMP_DIR/menu.sh" | awk '{print $3}')

# Проверка, пустая ли версия удалённого скрипта
if [ -z "$REMOTE_VERSION" ]; then
    echo -e "${RED}Не удалось получить версию удалённого скрипта, проверьте подключение к сети.${NC}"
    read -rp "Повторить попытку? (y/n): " retry_choice
    if [[ "$retry_choice" =~ ^[Yy]$ ]]; then
        wget -q -O "$TEMP_DIR/menu.sh" "$MENU_SCRIPT_URL"
        REMOTE_VERSION=$(grep '^# 版本:' "$TEMP_DIR/menu.sh" | awk '{print $3}')
        if [ -z "$REMOTE_VERSION" ]; then
            echo -e "${RED}Не удалось получить версию удалённого скрипта, проверьте подключение к сети и попробуйте позже. Возврат в меню.${NC}"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    else
        echo -e "${RED}Проверьте подключение к сети и попробуйте позже. Возврат в меню.${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

# Вывод обнаруженных версий
echo -e "${CYAN}Обнаруженные версии: локальная $LOCAL_VERSION, удалённая $REMOTE_VERSION${NC}"

# Сравнение версий
if [ "$LOCAL_VERSION" == "$REMOTE_VERSION" ]; then
    echo -e "${GREEN}Скрипт обновлён до последней версии, обновление не требуется.${NC}"
    read -rp "Принудительно обновить? (y/n): " force_update
    if [[ "$force_update" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Выполняется принудительное обновление...${NC}"
    else
        echo -e "${CYAN}Возврат в меню.${NC}"
        rm -rf "$TEMP_DIR"
        exit 0
    fi
else
    echo -e "${RED}Обнаружена новая версия, начинаем обновление.${NC}"
fi

# Список скриптов для загрузки
SCRIPTS=(
    "check_environment.sh"
    "set_network.sh"
    "check_update.sh"
    "install_singbox.sh"
    "manual_input.sh"
    "manual_update.sh"
    "auto_update.sh"
    "configure_tproxy.sh"

    "start_singbox.sh"
    "stop_singbox.sh"
    "clean_nft.sh"
    "set_defaults.sh"
    "commands.sh"
    "switch_mode.sh"
    "manage_autostart.sh"
    "check_config.sh"
    "update_scripts.sh"
    "update_ui.sh"
    "doctor.sh"
    "menu.sh"
)

# Функция загрузки одного скрипта с повторными попытками
download_script() {
    local SCRIPT="$1"
    local RETRIES=3
    local RETRY_DELAY=5

    for ((i=1; i<=RETRIES; i++)); do
        if wget -q -O "$SCRIPT_DIR/$SCRIPT" "$BASE_URL/$SCRIPT"; then
            chmod +x "$SCRIPT_DIR/$SCRIPT"
            return 0
        else
            sleep "$RETRY_DELAY"
        fi
    done

    echo -e "${RED}Не удалось скачать $SCRIPT, проверьте подключение к сети.${NC}"
    return 1
}

# Параллельная загрузка всех скриптов
parallel_download_scripts() {
    local pids=()
    for SCRIPT in "${SCRIPTS[@]}"; do
        download_script "$SCRIPT" &
        pids+=("$!")
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Обычное обновление
regular_update() {
    echo -e "${CYAN}Очистка кэша, пожалуйста, подождите...${NC}"
    rm -f "$SCRIPT_DIR"/*.sh
    echo -e "${CYAN}Выполняется обычное обновление, пожалуйста, подождите...${NC}"
    parallel_download_scripts
    echo -e "${CYAN}Обычное обновление скриптов завершено.${NC}"
}

# Полный сброс и обновление
reset_update() {
    echo -e "${RED}Останавливаем sing-box и сбрасываем все настройки, пожалуйста, подождите...${NC}"
    sudo bash "$SCRIPT_DIR/clean_nft.sh"
    sudo rm -rf /etc/sing-box
    echo -e "${CYAN}Папка sing-box удалена.${NC}"
    echo -e "${CYAN}Загрузка скриптов заново, пожалуйста, подождите...${NC}"
    bash <(curl -s "$MENU_SCRIPT_URL")
}

# Запрос выбора пользователя
echo -e "${CYAN}Выберите способ обновления:${NC}"
echo -e "${GREEN}1. Обычное обновление${NC}"
echo -e "${GREEN}2. Полный сброс и обновление${NC}"
read -rp "Выберите действие: " update_choice

case $update_choice in
    1)
        echo -e "${RED}Обычное обновление обновляет только скрипты, новое меню выполнит обновленные скрипты.${NC}"
        read -rp "Продолжить обычное обновление? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            regular_update
        else
            echo -e "${CYAN}Обычное обновление отменено.${NC}"
        fi
        ;;
    2)
        echo -e "${RED}Будет остановлен sing-box и сброшены все настройки, затем выполнена инициализация.${NC}"
        read -rp "Продолжить сброс и обновление? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            reset_update
        else
            echo -e "${CYAN}Сброс и обновление отменены.${NC}"
        fi
        ;;
    *)
        echo -e "${RED}Недопустимый выбор.${NC}"
        ;;
esac

# Очистка временной папки
rm -rf "$TEMP_DIR"
