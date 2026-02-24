#!/bin/bash

#################################################
# Описание: Официальный полностью автоматический скрипт sing-box для Debian/Ubuntu/Armbian
# Версия: 2.1.0
#################################################

# Определение цветов для вывода в терминал
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Без цвета (сброс цвета)

# Каталог для скриптов и файл-флаг инициализации
SCRIPT_DIR="/etc/sing-box/scripts"
INITIALIZED_FILE="$SCRIPT_DIR/.initialized"

# Создаём каталог для скриптов, если его нет, и устанавливаем владельца
sudo mkdir -p "$SCRIPT_DIR"
sudo chown "$(whoami)":"$(whoami)" "$SCRIPT_DIR"

# Базовый URL для скачивания скриптов
BASE_URL="https://raw.githubusercontent.com/Mendex777/sbshell_3/refs/heads/main/debian"

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
    "status_check.sh"          # Проверка состояния системы

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
    "doctor.sh"                # Диагностика и проверки
    "menu.sh"                  # Главное меню
)

# Функция для загрузки одного скрипта с попытками и логированием
download_script() {
    local SCRIPT="$1"
    local RETRIES=5  # Количество попыток
    local RETRY_DELAY=5

    for ((i=1; i<=RETRIES; i++)); do
        if wget -q -O "$SCRIPT_DIR/$SCRIPT" "$BASE_URL/$SCRIPT"; then
            chmod +x "$SCRIPT_DIR/$SCRIPT"
            return 0
        else
            echo -e "${YELLOW}Загрузка $SCRIPT не удалась, попытка $i из $RETRIES...${NC}"
            sleep "$RETRY_DELAY"
        fi
    done

    echo -e "${RED}Не удалось загрузить $SCRIPT, проверьте подключение к сети.${NC}"
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

# Проверка наличия скриптов и загрузка отсутствующих
check_and_download_scripts() {
    local missing_scripts=()
    for SCRIPT in "${SCRIPTS[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$SCRIPT" ]; then
            missing_scripts+=("$SCRIPT")
        fi
    done

    if [ ${#missing_scripts[@]} -ne 0 ]; then
        echo -e "${CYAN}Загрузка скриптов, пожалуйста подождите...${NC}"
        for SCRIPT in "${missing_scripts[@]}"; do
            download_script "$SCRIPT" || {
                echo -e "${RED}Загрузка $SCRIPT не удалась, повторить? (y/n): ${NC}"
                read -r retry_choice
                if [[ "$retry_choice" =~ ^[Yy]$ ]]; then
                    download_script "$SCRIPT"
                else
                    echo -e "${RED}Пропускаем загрузку $SCRIPT.${NC}"
                fi
            }
        done
    fi
}

# Функция инициализации
initialize() {
    # Удаляем старые скрипты, кроме menu.sh
    if ls "$SCRIPT_DIR"/*.sh 1> /dev/null 2>&1; then
        find "$SCRIPT_DIR" -type f -name "*.sh" ! -name "menu.sh" -exec rm -f {} \;
        rm -f "$INITIALIZED_FILE"
    fi

    # Загружаем скрипты заново
    parallel_download_scripts
    # Выполняем первичные настройки
    auto_setup
    touch "$INITIALIZED_FILE"
}

# Автоматическая настройка
auto_setup() {
    # Остановка sing-box, если запущен
    systemctl is-active --quiet sing-box && sudo systemctl stop sing-box
    bash "$SCRIPT_DIR/check_environment.sh"
    # Установка sing-box, если не установлен, иначе проверка обновлений
    command -v sing-box &> /dev/null || bash "$SCRIPT_DIR/install_singbox.sh" || bash "$SCRIPT_DIR/check_update.sh"
    bash "$SCRIPT_DIR/switch_mode.sh"
    
    # Установка API панели управления
    echo -e "${CYAN}Установка API панели управления...${NC}"
    if curl -fsSL "https://raw.githubusercontent.com/Mendex777/zashboard/refs/heads/test/api%20web%20editor/install-api.sh" -o "/tmp/install-api.sh"; then
        chmod +x "/tmp/install-api.sh"
        bash "/tmp/install-api.sh"
        rm -f "/tmp/install-api.sh"
        echo -e "${GREEN}API панель управления установлена успешно!${NC}"
    else
        echo -e "${RED}Не удалось загрузить скрипт установки API панели${NC}"
    fi
    
    bash "$SCRIPT_DIR/manual_input.sh"
    bash "$SCRIPT_DIR/start_singbox.sh"
}

# Проверяем, нужно ли инициализировать систему
if [ ! -f "$INITIALIZED_FILE" ]; then
    echo -e "${CYAN}Нажмите Enter для запуска инициализации, или введите skip для пропуска${NC}"
    read -r init_choice
    if [[ "$init_choice" =~ ^[Ss]kip$ ]]; then
        echo -e "${CYAN}Пропускаем инициализацию, переходим в меню...${NC}"
    else
        initialize
    fi
fi

# Функция создания алиасов
create_aliases() {
    echo -e "${CYAN}Создание алиасов...${NC}"
    
    # Создание алиасов для быстрого доступа к функциям
    alias sbmenu="bash $SCRIPT_DIR/menu.sh"
    alias sbstart="sudo bash $SCRIPT_DIR/start_singbox.sh"
    alias sbstop="sudo bash $SCRIPT_DIR/stop_singbox.sh"
    alias sbupdate="bash $SCRIPT_DIR/manual_update.sh"
    alias sbauto="bash $SCRIPT_DIR/auto_update.sh"
    alias sbconfig="bash $SCRIPT_DIR/manual_input.sh"
    alias sbcheck="bash $SCRIPT_DIR/check_config.sh"
    alias sbcommands="bash $SCRIPT_DIR/commands.sh"
    alias sbdefaults="bash $SCRIPT_DIR/set_defaults.sh"
    alias sbnetwork="sudo bash $SCRIPT_DIR/set_network.sh"
    alias sbautostart="sudo bash $SCRIPT_DIR/manage_autostart.sh"
    alias sbclean="sudo bash $SCRIPT_DIR/clean_nft.sh"
    alias sbinstall="sudo bash $SCRIPT_DIR/install_singbox.sh"
    alias sbui="bash $SCRIPT_DIR/update_ui.sh"
    alias sbstatus="sudo bash $SCRIPT_DIR/status_check.sh"
    alias sbdoctor="sudo bash $SCRIPT_DIR/doctor.sh"
    alias sbapi='curl -fsSL "https://raw.githubusercontent.com/Mendex777/zashboard/refs/heads/test/api%20web%20editor/install-api.sh" -o "/tmp/install-api.sh" && chmod +x "/tmp/install-api.sh" && bash "/tmp/install-api.sh" && rm -f "/tmp/install-api.sh"'
    
    echo -e "${GREEN}Алиасы созданы успешно!${NC}"
    echo -e "${YELLOW}Доступные команды:${NC}"
    echo -e "  sbmenu     - Главное меню"
    echo -e "  sbstart    - Запуск sing-box"
    echo -e "  sbstop     - Остановка sing-box"
    echo -e "  sbupdate   - Ручное обновление конфигурации"
    echo -e "  sbauto     - Автоматическое обновление"
    echo -e "  sbconfig   - Ввод конфигурации"
    echo -e "  sbcheck    - Проверка конфигурации"
    echo -e "  sbcommands - Часто используемые команды"
    echo -e "  sbdefaults - Настройки по умолчанию"
    echo -e "  sbnetwork  - Настройка сети"
    echo -e "  sbautostart- Настройка автозапуска"
    echo -e "  sbclean    - Очистка правил nftables"
    echo -e "  sbinstall  - Установка/обновление sing-box"
    echo -e "  sbui       - Обновление панели управления"
    echo -e "  sbstatus   - Проверка состояния системы"
    echo -e "  sbdoctor   - Диагностика окружения"
    echo -e "  sbapi      - Установка API панели управления"
}

# Добавляем алиас sb в .bashrc, если ещё нет
if ! grep -q "alias sb=" ~/.bashrc; then
    echo "alias sb='bash $SCRIPT_DIR/menu.sh menu'" >> ~/.bashrc
fi

# Создаем исполняемый файл для быстрого запуска меню sb
if [ ! -f /usr/local/bin/sb ]; then
    echo -e '#!/bin/bash\nbash /etc/sing-box/scripts/menu.sh menu' | sudo tee /usr/local/bin/sb >/dev/null
    sudo chmod +x /usr/local/bin/sb
fi

# Функция отображения меню
show_menu() {
    echo -e "${CYAN}=========== Меню управления Sbshell ===========${NC}"
    echo -e "${GREEN}1. Настройка режима TProxy${NC}"
    echo -e "${GREEN}2. Ручное обновление конфигурации${NC}"
    echo -e "${GREEN}3. Автоматическое обновление конфигурации${NC}"
    echo -e "${GREEN}4. Ручной запуск sing-box${NC}"
    echo -e "${GREEN}5. Ручная остановка sing-box${NC}"
    echo -e "${GREEN}6. Установка/обновление sing-box${NC}"
    echo -e "${GREEN}7. Настройка параметров по умолчанию${NC}"
    echo -e "${GREEN}8. Настройка автозапуска${NC}"
    echo -e "${GREEN}9. Настройка сети (только для Debian)${NC}"
    echo -e "${GREEN}10. Часто используемые команды${NC}"
    echo -e "${GREEN}11. Обновление скриптов${NC}"
    echo -e "${GREEN}12. Обновление панели управления${NC}"
    echo -e "${GREEN}13. Проверка состояния системы${NC}"
    echo -e "${GREEN}14. Установка API панели управления${NC}"
    echo -e "${GREEN}15. Диагностика (doctor)${NC}"
    echo -e "${GREEN}0. Выход${NC}"
    echo -e "${CYAN}=============================================${NC}"
}

# Обработка выбора пользователя
handle_choice() {
    read -rp "Выберите действие: " choice
    case $choice in
        1)
            bash "$SCRIPT_DIR/switch_mode.sh"
            bash "$SCRIPT_DIR/manual_input.sh"
            bash "$SCRIPT_DIR/start_singbox.sh"
            ;;
        2)
            bash "$SCRIPT_DIR/manual_update.sh"
            ;;
        3)
            bash "$SCRIPT_DIR/auto_update.sh"
            ;;
        4)
            bash "$SCRIPT_DIR/start_singbox.sh"
            ;;
        5)
            bash "$SCRIPT_DIR/stop_singbox.sh"
            ;;
        6)
            if command -v sing-box &> /dev/null; then
                bash "$SCRIPT_DIR/check_update.sh"
            else
                bash "$SCRIPT_DIR/install_singbox.sh"
            fi
            ;;
        7)
            bash "$SCRIPT_DIR/set_defaults.sh"
            ;;
        8)
            bash "$SCRIPT_DIR/manage_autostart.sh"
            ;;
        9)
            bash "$SCRIPT_DIR/set_network.sh"
            ;;
        10)
            bash "$SCRIPT_DIR/commands.sh"
            ;;
        11)
            bash "$SCRIPT_DIR/update_scripts.sh"
            ;;
        12)
            bash "$SCRIPT_DIR/update_ui.sh"
            ;;
        13)
            sudo bash "$SCRIPT_DIR/status_check.sh"
            ;;
        14)
            echo -e "${CYAN}Установка API панели управления...${NC}"
            if curl -fsSL "https://raw.githubusercontent.com/Mendex777/zashboard/refs/heads/test/api%20web%20editor/install-api.sh" -o "/tmp/install-api.sh"; then
                chmod +x "/tmp/install-api.sh"
                bash "/tmp/install-api.sh"
                rm -f "/tmp/install-api.sh"
                echo -e "${GREEN}API панель управления установлена успешно!${NC}"
            else
                echo -e "${RED}Не удалось загрузить скрипт установки API панели${NC}"
            fi
            ;;
        15)
            sudo bash "$SCRIPT_DIR/doctor.sh"
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            ;;
    esac
}

# Главный цикл программы
while true; do
    show_menu
    handle_choice
done
