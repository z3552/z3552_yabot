#!/bin/bash
# Менеджер установки/удаления ботов для управления ВМ Яндекс.Облака
# Автор: z3552[Reenpak]  |  yabot_installer v9.0
# Платформы: Telegram / VK / оба (выбор при установке)

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

YABOT_VER=$(grep -oP 'yabot_installer v\K[0-9.]+' "$0" 2>/dev/null || echo '?')

BOT_DIR="/opt/vm_manager"
TG_DIR="$BOT_DIR/tg"
VK_DIR="$BOT_DIR/vk"
TG_SERVICE="vm-bot-tg"
VK_SERVICE="vm-bot-vk"
SHARED_CONFIG="$BOT_DIR/config.json"
SCHEDULE_FILE="$BOT_DIR/schedule.json"
DB_FILE="$BOT_DIR/bot_data.db"
UNINSTALL_SCRIPT="$BOT_DIR/uninstall.sh"

INSTALL_TG=false
INSTALL_VK=false

# ─────────────────────────────────────────────────────────────
# УТИЛИТЫ
# ─────────────────────────────────────────────────────────────

print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}Менеджер ботов Telegram + VK для ВМ Яндекс.Облака${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_root() {
    [ "$EUID" -ne 0 ] && echo -e "${RED}❌ Запустите от root: sudo bash $0${NC}" && exit 1
}

svc_status_line() {
    local svc="$1" label="$2"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  $label: ${GREEN}● Активен${NC}"
    elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        echo -e "  $label: ${YELLOW}○ Остановлен${NC}"
    else
        echo -e "  $label: ${RED}✗ Не установлен${NC}"
    fi
}

is_installed() {
    local platform="$1"
    [ -f "$SHARED_CONFIG" ] && \
        jq -e --arg p "$platform" '.installed | index($p) != null' "$SHARED_CONFIG" >/dev/null 2>&1
}

# ─────────────────────────────────────────────────────────────
# ГЛАВНОЕ МЕНЮ
# ─────────────────────────────────────────────────────────────


install_tg_bridge() {
    print_header
    echo -e "${CYAN}📱 УСТАНОВКА TG МОСТА (Telethon)${NC}"; echo ""
    BRIDGE_DIR_PATH="/opt/vm_manager/tg_bridge"
    mkdir -p "$BRIDGE_DIR_PATH"
    echo -e "${YELLOW}📦 Устанавливаем Telethon + Pillow...${NC}"
    python3 -m venv "$BRIDGE_DIR_PATH/venv"
    "$BRIDGE_DIR_PATH/venv/bin/pip" install --quiet telethon Pillow requests
    echo -e "${YELLOW}📝 Создаём bridge.py...${NC}"
    python3 - << 'WRITEPY'
import re
with open("/root/yabot_installer.sh") as f: src = f.read()
code = src.split("# BRIDGE_PY_START\n")[1].split("\n# BRIDGE_PY_END")[0]
with open("/opt/vm_manager/tg_bridge/bridge.py","w") as f: f.write(code)
print("✅ bridge.py записан")
WRITEPY
    echo ""
    echo -e "${YELLOW}🔐 Авторизация в Telegram (введи номер телефона и код)...${NC}"; echo ""
    "$BRIDGE_DIR_PATH/venv/bin/python3" - << 'AUTHPY'
import asyncio, json
from pathlib import Path
from telethon import TelegramClient
with open("/opt/vm_manager/config.json") as f: d = json.load(f)
b = d.get("tg_bridge",{})
async def auth():
    c = TelegramClient("/opt/vm_manager/tg_bridge/session",int(b["api_id"]),b["api_hash"])
    await c.start()
    me = await c.get_me()
    print(f"✅ Авторизован: {me.first_name} (@{me.username})")
    await c.disconnect()
asyncio.run(auth())
AUTHPY
    [ $? -ne 0 ] && echo -e "${RED}❌ Авторизация не удалась${NC}" && read -p "Enter..." && return 1
    cat > /etc/systemd/system/vm-bridge-tg.service << SVCEOF
[Unit]
Description=TG Bridge (Telethon)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BRIDGE_DIR_PATH
ExecStart=$BRIDGE_DIR_PATH/venv/bin/python3 $BRIDGE_DIR_PATH/bridge.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable vm-bridge-tg.service
    systemctl start vm-bridge-tg.service
    sleep 2
    if systemctl is-active --quiet vm-bridge-tg.service; then
        echo -e "${GREEN}✅ TG Мост запущен!${NC}"
    else
        echo -e "${RED}❌ Не запустился. Лог: journalctl -u vm-bridge-tg -n 20${NC}"
    fi
    echo ""; read -p "Enter..."
}

main_menu() {
    # Автоочистка stale cron если боты не установлены
    if [ ! -f "$SHARED_CONFIG" ]; then
        crontab -l 2>/dev/null | grep -q "# VM_BOT" && \
            crontab -l 2>/dev/null | grep -v "# VM_BOT" | crontab - 2>/dev/null || true
    fi
    print_header
    echo -e "  Версия: ${GREEN}v${YABOT_VER}${NC}"; echo ""
    echo -e "${YELLOW}Статус ботов:${NC}"
    svc_status_line "$TG_SERVICE" "  🔵 Telegram"
    svc_status_line "$VK_SERVICE" "  🟦 ВКонтакте"
    echo ""
    echo -e "${YELLOW}Выберите действие:${NC}"; echo ""
    echo -e "  ${GREEN}1)${NC} Установить ботов"
    echo -e "  ${GREEN}2)${NC} Удалить ботов"
    echo -e "  ${GREEN}3)${NC} Проверить статус"
    echo -e "  ${GREEN}4)${NC} Просмотреть логи"
    echo -e "  ${GREEN}5)${NC} Перезапустить ботов"
    echo -e "  ${GREEN}6)${NC} Настроить автовключение ВМ"
    echo -e "  ${GREEN}7)${NC} Обновить конфигурацию"
    echo -e "  ${GREEN}8)${NC} 🔄 Обновить скрипты ботов"
    echo -e "  ${GREEN}9)${NC} ⬆️  Обновить установщик с GitHub"
    echo -e "  ${GREEN}10)${NC} 🔃 Принудительное обновление с GitHub"
    echo -e "  ${RED}0)${NC} Выход"; echo ""
    read -p "Введите номер действия: " choice
    case $choice in
        1) install_bot ;; 2) uninstall_bot ;; 3) check_status ;;
        4) view_logs ;;   5) restart_bot ;;  6) setup_auto_power ;;
        7) update_config ;; 8) update_bot_scripts ;; 9) update_from_github ;;
        10) get_user_inputs_bridge && create_shared_config && install_tg_bridge ;; 10) update_from_github force ;; 0) exit 0 ;;
        *) echo -e "${RED}Неверный выбор!${NC}"; sleep 2; main_menu ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# ВЫБОР РЕЖИМА УСТАНОВКИ
# ─────────────────────────────────────────────────────────────

select_install_mode() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ВЫБОР ПЛАТФОРМЫ                                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"; echo ""
    echo -e "  ${GREEN}1)${NC} 🔵 Только Telegram бот"
    echo -e "  ${GREEN}2)${NC} 🟦 Только VK бот"
    echo -e "  ${GREEN}3)${NC} 🔵🟦 Оба бота"; echo ""
    read -p "Выберите платформу: " mode_choice
    case $mode_choice in
        1) INSTALL_TG=true;  INSTALL_VK=false; echo -e "${GREEN}✅ Будет установлен Telegram бот${NC}" ;;
        2) INSTALL_TG=false; INSTALL_VK=true;  echo -e "${GREEN}✅ Будет установлен VK бот${NC}" ;;
        3) INSTALL_TG=true;  INSTALL_VK=true;  echo -e "${GREEN}✅ Будут установлены оба бота${NC}" ;;
        *) echo -e "${RED}Неверный выбор!${NC}"; sleep 2; select_install_mode; return ;;
    esac
    echo ""
}

# ─────────────────────────────────────────────────────────────
# УСТАНОВКА
# ─────────────────────────────────────────────────────────────

install_bot() {
    print_header
    echo -e "${GREEN}🚀 Начинаем установку...${NC}"; echo ""
    if [ -d "$BOT_DIR" ] || \
       systemctl is-active --quiet $TG_SERVICE 2>/dev/null || \
       systemctl is-active --quiet $VK_SERVICE 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Обнаружена существующая установка!${NC}"
        read -p "Удалить старую и продолжить? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            echo -e "${RED}Установка отменена${NC}"; sleep 2; main_menu; return
        fi
        uninstall_bot_silent
    fi
    select_install_mode
    # Чистим stale cron от предыдущих установок
    crontab -l 2>/dev/null | grep -v "# VM_BOT" | crontab - 2>/dev/null || true
    echo -e "${YELLOW}📦 Установка зависимостей...${NC}"
    apt update -qq
    apt install -y python3 python3-pip python3-venv jq curl wget ffmpeg cpulimit >/dev/null 2>&1
    echo -e "${GREEN}✅ Зависимости установлены${NC}"; echo ""
    install_yc_cli
    setup_yandex_cloud
    get_user_inputs_vm
    $INSTALL_TG && get_user_inputs_tg
    $INSTALL_VK && get_user_inputs_vk
    get_admin_pin
    create_dirs
    create_shared_config
    create_db_module
    create_uninstall_script
    $INSTALL_TG && create_tg_bot_structure
    $INSTALL_VK && create_vk_bot_structure
    create_services
    setup_sudoers
    init_database
    print_header
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          ✅ УСТАНОВКА ЗАВЕРШЕНА!                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"; echo ""
    $INSTALL_TG && echo -e "${CYAN}📱 Telegram: найдите бота и отправьте /start${NC}"
    $INSTALL_VK && echo -e "${CYAN}💬 ВКонтакте: напишите в сообщения сообщества${NC}"; echo ""
    $INSTALL_TG && echo -e "${YELLOW}Логи TG:${NC} ${BLUE}journalctl -u $TG_SERVICE -f${NC}"
    $INSTALL_VK && echo -e "${YELLOW}Логи VK:${NC} ${BLUE}journalctl -u $VK_SERVICE -f${NC}"; echo ""
    # Создаём короткую команду yabot
    ln -sf /root/yabot_installer.sh /usr/local/bin/yabot 2>/dev/null || true
    chmod +x /usr/local/bin/yabot 2>/dev/null || true
    echo -e "${CYAN}⚡ Команда 'yabot' теперь доступна глобально${NC}"; echo ""
    read -p "Нажмите Enter для возврата в меню..."
    main_menu
}

# ─────────────────────────────────────────────────────────────
# YC CLI
# ─────────────────────────────────────────────────────────────

install_yc_cli() {
    echo -e "${YELLOW}☁️  Проверка YC CLI...${NC}"
    if command -v yc &>/dev/null; then
        echo -e "${GREEN}✅ YC CLI уже установлен${NC}"
        [ ! -L "/usr/local/bin/yc" ] && ln -sf "$(which yc)" /usr/local/bin/yc
    else
        echo -e "${YELLOW}Установка YC CLI...${NC}"
        curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash >/dev/null 2>&1
        if [ -f "/root/yandex-cloud/bin/yc" ]; then
            ln -sf /root/yandex-cloud/bin/yc /usr/local/bin/yc
            export PATH="/usr/local/bin:$PATH"
            echo -e "${GREEN}✅ YC CLI установлен${NC}"
        else
            echo -e "${RED}❌ Ошибка установки YC CLI${NC}"; exit 1
        fi
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────
# НАСТРОЙКА YANDEX CLOUD
# ─────────────────────────────────────────────────────────────

setup_yandex_cloud() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          НАСТРОЙКА YANDEX CLOUD                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"; echo ""
    if yc config list &>/dev/null; then
        echo -e "${GREEN}✅ Существующая конфигурация:${NC}"; yc config list; echo ""
        read -p "Использовать существующую? (y/n): " u
        [ "$u" == "y" ] && echo "" && return
    fi
    echo -e "${CYAN}https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb${NC}"; echo ""
    read -p "Введите OAuth токен: " OAUTH_TOKEN
    [ -z "$OAUTH_TOKEN" ] && echo -e "${RED}❌ Токен не может быть пустым${NC}" && exit 1
    yc config set token "$OAUTH_TOKEN"
    CLOUDS=$(yc resource-manager cloud list --format json)
    [ -z "$CLOUDS" ] || [ "$CLOUDS" == "[]" ] && echo -e "${RED}❌ Облака не найдены${NC}" && exit 1
    echo -e "${GREEN}Доступные облака:${NC}"
    echo "$CLOUDS" | jq -r '.[] | "\(.id) - \(.name)"' | nl -w2 -s") "
    echo ""; read -p "Введите ID облака: " CLOUD_ID; yc config set cloud-id "$CLOUD_ID"
    FOLDERS=$(yc resource-manager folder list --format json)
    echo -e "${GREEN}Доступные каталоги:${NC}"
    echo "$FOLDERS" | jq -r '.[] | "\(.id) - \(.name)"' | nl -w2 -s") "
    echo ""; read -p "Введите ID каталога: " FOLDER_ID; yc config set folder-id "$FOLDER_ID"
    echo -e "${GREEN}✅ Yandex Cloud настроен${NC}"; echo ""
}

# ─────────────────────────────────────────────────────────────
# СБОР ДАННЫХ
# ─────────────────────────────────────────────────────────────

get_user_inputs_vm() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ВЫБОР ВИРТУАЛЬНОЙ МАШИНЫ                            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"; echo ""
    VMS=$(yc compute instance list --format json 2>/dev/null)
    if [ -z "$VMS" ] || [ "$VMS" == "[]" ]; then
        echo -e "${RED}❌ ВМ не найдены${NC}"; read -p "Введите ID ВМ вручную: " VM_ID
    else
        echo -e "${GREEN}Доступные виртуальные машины:${NC}"
        echo "$VMS" | jq -r '.[] | "\(.id) - \(.name) [\(.status)]"' | nl -w2 -s") "
        echo ""; echo -e "${YELLOW}0) Ввести ID вручную${NC}"; echo ""
        read -p "Выберите номер или 0: " vm_choice
        [ "$vm_choice" == "0" ] && read -p "Введите ID ВМ: " VM_ID \
            || VM_ID=$(echo "$VMS" | jq -r ".[$((vm_choice-1))].id")
    fi
    [ -z "$VM_ID" ] && echo -e "${RED}❌ VM ID не может быть пустым${NC}" && exit 1
    if yc compute instance get "$VM_ID" &>/dev/null; then
        VM_INFO=$(yc compute instance get "$VM_ID" --format json)
        echo -e "${GREEN}✅ ВМ: $(echo $VM_INFO|jq -r '.name') [$(echo $VM_INFO|jq -r '.status')]${NC}"
    else
        echo -e "${RED}❌ Нет доступа к ВМ: $VM_ID${NC}"; exit 1
    fi
    FOLDER_ID=$(yc config get folder-id); echo ""
}

get_user_inputs_tg() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          🔵 НАСТРОЙКА TELEGRAM БОТА                          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"; echo ""
    echo -e "${YELLOW}Создайте бота через @BotFather → /newbot${NC}"
    read -p "Токен Telegram бота: " TG_BOT_TOKEN
    [ -z "$TG_BOT_TOKEN" ] && echo -e "${RED}❌ Токен не может быть пустым${NC}" && exit 1
    echo ""; echo -e "${YELLOW}Ваш Telegram ID (узнать через @userinfobot):${NC}"
    read -p "Ваш Telegram ID: " TG_USER_ID
    [ -z "$TG_USER_ID" ] && echo -e "${RED}❌ User ID не может быть пустым${NC}" && exit 1
    echo ""; read -p "Дополнительные TG ID (через запятую или Enter): " TG_EXTRA
    [ -n "$TG_EXTRA" ] && TG_USER_ID="$TG_USER_ID,$(echo $TG_EXTRA|tr -d ' ')"
    echo -e "${GREEN}✅ Данные Telegram собраны${NC}"; echo ""
}

get_user_inputs_vk() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          🟦 НАСТРОЙКА ВКОНТАКТЕ БОТА                         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"; echo ""
    echo -e "${YELLOW}Сообщество → Управление → Работа с API → ключ (права: сообщения)${NC}"
    echo -e "${YELLOW}Включите «Сообщения сообщества» и Long Poll API ≥ 5.131${NC}"; echo ""
    read -p "Токен сообщества VK: " VK_TOKEN
    [ -z "$VK_TOKEN" ] && echo -e "${RED}❌ Токен не может быть пустым${NC}" && exit 1
    echo ""; read -p "ID сообщества VK (число, со знаком минус или без): " VK_GROUP_ID
    [ -z "$VK_GROUP_ID" ] && echo -e "${RED}❌ ID не может быть пустым${NC}" && exit 1
    VK_GROUP_ID="${VK_GROUP_ID#-}"
    [[ ! "$VK_GROUP_ID" =~ ^[0-9]+$ ]] && echo -e "${RED}❌ ID должен быть числом${NC}" && exit 1
    echo ""; read -p "VK User ID(s) через запятую: " VK_USER_IDS
    [ -z "$VK_USER_IDS" ] && echo -e "${RED}❌ Нужен хотя бы один ID${NC}" && exit 1
    VK_USER_IDS=$(echo "$VK_USER_IDS" | tr -d ' ')
    echo ""
    echo -e "${YELLOW}Яндекс.Диск OAuth токен (для отправки видео >200 MB).${NC}"
    echo -e "${YELLOW}Получить: https://oauth.yandex.ru → создать приложение → права cloud_api:disk.write,read${NC}"
    read -p "Yandex OAuth Token (Enter — пропустить): " YADISK_TOKEN
    echo ""
    if [ -n "$YADISK_TOKEN" ]; then
        echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}📤 SSH загрузка на Яндекс.Диск через ВМ Яндекс.Облака${NC}"
        echo -e "${YELLOW}IP ВМ определится автоматически. Нужны SSH юзер и ключ.${NC}"; echo ""
        echo -e "${YELLOW}SSH ключи найденные в ~/.ssh/:${NC}"
        ls ~/.ssh/ 2>/dev/null | grep -v '\.pub$' | grep -v known_hosts | grep -v authorized_keys \
            | sed 's/^/  - ~\/.ssh\//' || echo "  (не найдено)"
        echo ""
        read -p "SSH пользователь для ВМ [ubuntu]: " YC_VM_SSH_USER
        YC_VM_SSH_USER="${YC_VM_SSH_USER:-ubuntu}"
        read -p "Путь к SSH ключу (Enter — без SSH, загрузка с NL VPS): " YC_VM_SSH_KEY
        if [ -n "$YC_VM_SSH_KEY" ]; then
            [ ! -f "$YC_VM_SSH_KEY" ] && echo -e "${RED}⚠️  Файл ключа не найден: $YC_VM_SSH_KEY${NC}"
            echo -e "${GREEN}✅ SSH загрузка: ${YC_VM_SSH_USER}@<vm_ip_из_yc> ключ ${YC_VM_SSH_KEY}${NC}"
        else
            echo -e "${YELLOW}⚠️  Без SSH ключа — загрузка пойдёт напрямую с NL VPS${NC}"
        fi
    else
        YC_VM_SSH_USER="ubuntu"; YC_VM_SSH_KEY=""
    fi
    echo -e "${GREEN}✅ Данные VK собраны${NC}"; echo ""
}

get_user_inputs_bridge() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          📱 TG МОСТ (Telethon)                               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"; echo ""
    echo -e "${YELLOW}Получи api_id и api_hash: https://my.telegram.org → Apps${NC}"; echo ""
    read -p "api_id (число): " BRIDGE_API_ID
    [ -z "$BRIDGE_API_ID" ] && echo -e "${RED}❌ Обязательно${NC}" && return 1
    read -p "api_hash: " BRIDGE_API_HASH
    [ -z "$BRIDGE_API_HASH" ] && echo -e "${RED}❌ Обязательно${NC}" && return 1
    echo -e "${GREEN}✅ Данные моста получены${NC}"; echo ""
}

get_admin_pin() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ADMIN PIN-КОД (удаление бота через чат)            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"; echo ""
    while true; do
        read -s -p "PIN-код (минимум 4 цифры): " ADMIN_PIN; echo ""
        [[ ! "$ADMIN_PIN" =~ ^[0-9]{4,}$ ]] && echo -e "${RED}❌ Только цифры, минимум 4${NC}" && continue
        read -s -p "Повторите PIN: " ADMIN_PIN2; echo ""
        [ "$ADMIN_PIN" != "$ADMIN_PIN2" ] && echo -e "${RED}❌ PIN-коды не совпадают${NC}" && continue
        break
    done
    echo -e "${GREEN}✅ PIN-код установлен${NC}"; echo ""
}

# ─────────────────────────────────────────────────────────────
# СОЗДАНИЕ СТРУКТУРЫ
# ─────────────────────────────────────────────────────────────

create_dirs() {
    mkdir -p "$BOT_DIR"
    $INSTALL_TG && mkdir -p "$TG_DIR"
    $INSTALL_VK && mkdir -p "$VK_DIR"
    echo -e "${GREEN}✅ Директории созданы${NC}"; echo ""
}

create_shared_config() {
    echo -e "${YELLOW}📝 Создание конфигурации...${NC}"
    if $INSTALL_TG && $INSTALL_VK; then INSTALLED_JSON='["tg","vk"]'
    elif $INSTALL_TG; then              INSTALLED_JSON='["tg"]'
    else                                INSTALLED_JSON='["vk"]'
    fi

    if $INSTALL_TG; then
        TG_USERS_JSON=$(echo "$TG_USER_ID"|tr ','  '\n'|sed 's/^[[:space:]]*//'|jq -R 'tonumber'|jq -s '.')
        TG_BLOCK='"tg":{"bot_token":"'"$TG_BOT_TOKEN"'","allowed_users":'"$TG_USERS_JSON"'}'
    else
        TG_BLOCK='"tg":null'
    fi

    if $INSTALL_VK; then
        VK_USERS_JSON=$(echo "$VK_USER_IDS"|tr ','  '\n'|sed 's/^[[:space:]]*//'|jq -R 'tonumber'|jq -s '.')
        VK_BLOCK='"vk":{"group_token":"'"$VK_TOKEN"'","group_id":'"$VK_GROUP_ID"',"allowed_users":'"$VK_USERS_JSON"',"user_token":"'"$VK_USER_TOKEN"'","yadisk_token":"'"$YADISK_TOKEN"'","yadisk_ssh_user":"'"$YC_VM_SSH_USER"'","yadisk_ssh_key":"'"$YC_VM_SSH_KEY"'"}'
    else
        VK_BLOCK='"vk":null'
    fi

    BRIDGE_BLOCK="\"tg_bridge\":{\"api_id\":\"${BRIDGE_API_ID:-}\",\"api_hash\":\"${BRIDGE_API_HASH:-}\"}"
    printf '{"installed":%s,"vm_id":"%s","folder_id":"%s","admin_pin":"%s",%s,%s,%s}\n' \
        "$INSTALLED_JSON" "$VM_ID" "$FOLDER_ID" "$ADMIN_PIN" "$TG_BLOCK" "$VK_BLOCK" "$BRIDGE_BLOCK" \
        > "$SHARED_CONFIG"
    chmod 600 "$SHARED_CONFIG"
    echo -e "${GREEN}✅ Конфигурация создана (платформы: $INSTALLED_JSON)${NC}"; echo ""
}


# ─────────────────────────────────────────────────────────────
# МОДУЛЬ БАЗЫ ДАННЫХ
# ─────────────────────────────────────────────────────────────

create_db_module() {
    cat > "$BOT_DIR/db_module.py" << 'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SQLite модуль для системы управления ВМ.
Таблицы: command_log, auto_events, settings
"""
import sqlite3, sys
from pathlib import Path

DB_FILE = Path("/opt/vm_manager/bot_data.db")
DEFAULT_RETENTION_DAYS = 7

def _conn():
    conn = sqlite3.connect(str(DB_FILE))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn

def init_db():
    with _conn() as conn:
        conn.executescript(f"""
            CREATE TABLE IF NOT EXISTS command_log (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
                platform  TEXT    NOT NULL CHECK(platform IN ('tg','vk')),
                user_id   INTEGER NOT NULL,
                command   TEXT    NOT NULL,
                result    TEXT,
                success   INTEGER NOT NULL DEFAULT 1 CHECK(success IN (0,1))
            );
            CREATE TABLE IF NOT EXISTS auto_events (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp  TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
                event_type TEXT    NOT NULL,
                details    TEXT,
                success    INTEGER NOT NULL DEFAULT 1 CHECK(success IN (0,1))
            );
            CREATE TABLE IF NOT EXISTS settings (
                key        TEXT PRIMARY KEY,
                value      TEXT NOT NULL,
                updated_at TEXT DEFAULT (datetime('now','localtime'))
            );
            INSERT OR IGNORE INTO settings (key,value) VALUES ('retention_days','{DEFAULT_RETENTION_DAYS}');
        """)

def get_setting(key, default=None):
    with _conn() as conn:
        row = conn.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        return row["value"] if row else default

def set_setting(key, value):
    with _conn() as conn:
        conn.execute("""
            INSERT INTO settings (key,value,updated_at) VALUES(?,?,datetime('now','localtime'))
            ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at
        """, (key, str(value)))

def log_command(platform, user_id, command, result, success=True):
    with _conn() as conn:
        conn.execute(
            "INSERT INTO command_log (platform,user_id,command,result,success) VALUES(?,?,?,?,?)",
            (platform, user_id, command, result, 1 if success else 0)
        )
    _auto_cleanup()

def log_auto_event(event_type, details, success=True):
    with _conn() as conn:
        conn.execute(
            "INSERT INTO auto_events (event_type,details,success) VALUES(?,?,?)",
            (event_type, details, 1 if success else 0)
        )

def _auto_cleanup():
    """Авто-очистка при каждом log_command."""
    try:
        days = int(get_setting("retention_days", DEFAULT_RETENTION_DAYS))
        with _conn() as conn:
            deleted = conn.execute(
                "DELETE FROM command_log WHERE timestamp < datetime('now','localtime',?)",
                (f"-{days} days",)
            ).rowcount
        if deleted > 0:
            log_auto_event("auto_cleanup", f"Автоочистка: удалено {deleted} записей (retention={days}д)")
    except Exception:
        pass

def cleanup(log=True):
    """Плановая очистка — вызывается из cron."""
    days = int(get_setting("retention_days", DEFAULT_RETENTION_DAYS))
    with _conn() as conn:
        deleted = conn.execute(
            "DELETE FROM command_log WHERE timestamp < datetime('now','localtime',?)",
            (f"-{days} days",)
        ).rowcount
    if log:
        log_auto_event("cron_cleanup", f"Плановая очистка (cron): удалено {deleted} записей (retention={days}д)")
    return deleted

def set_retention(days):
    """Новый срок хранения + немедленная обрезка."""
    old = get_setting("retention_days", DEFAULT_RETENTION_DAYS)
    set_setting("retention_days", days)
    with _conn() as conn:
        deleted = conn.execute(
            "DELETE FROM command_log WHERE timestamp < datetime('now','localtime',?)",
            (f"-{days} days",)
        ).rowcount
    log_auto_event("retention_change", f"Срок хранения: {old}д → {days}д. Удалено {deleted} записей.")
    return deleted

def clear_all_history():
    with _conn() as conn:
        deleted = conn.execute("DELETE FROM command_log").rowcount
    log_auto_event("manual_clear", f"Ручная очистка: удалено {deleted} записей.")
    return deleted

def get_history(limit=15):
    with _conn() as conn:
        return conn.execute(
            "SELECT timestamp,platform,user_id,command,result,success "
            "FROM command_log ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()

def get_auto_events(limit=10):
    with _conn() as conn:
        return conn.execute(
            "SELECT timestamp,event_type,details,success "
            "FROM auto_events ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()

def get_stats():
    with _conn() as conn:
        total = conn.execute("SELECT COUNT(*) FROM command_log").fetchone()[0]
        auto  = conn.execute("SELECT COUNT(*) FROM auto_events").fetchone()[0]
        tg    = conn.execute("SELECT COUNT(*) FROM command_log WHERE platform='tg'").fetchone()[0]
        vk    = conn.execute("SELECT COUNT(*) FROM command_log WHERE platform='vk'").fetchone()[0]
        old   = conn.execute("SELECT MIN(timestamp) FROM command_log").fetchone()[0]
        new   = conn.execute("SELECT MAX(timestamp) FROM command_log").fetchone()[0]
    return {"total":total,"auto":auto,"tg":tg,"vk":vk,
            "oldest":old or "—","newest":new or "—",
            "retention":int(get_setting("retention_days",DEFAULT_RETENTION_DAYS))}

if __name__ == "__main__":
    init_db()
    if "--cleanup" in sys.argv:
        print(f"[cron] Удалено: {cleanup(log=True)} записей")
    elif "--stats" in sys.argv:
        s = get_stats()
        print(f"Команд: {s['total']} (TG:{s['tg']} VK:{s['vk']}) | Авто: {s['auto']} | Retention: {s['retention']}д")
        print(f"Диапазон: {s['oldest']} — {s['newest']}")
PYEOF
    chmod 644 "$BOT_DIR/db_module.py"
    echo -e "${GREEN}✅ Модуль БД создан${NC}"; echo ""
}

# ─────────────────────────────────────────────────────────────
# СКРИПТ УДАЛЕНИЯ
# ─────────────────────────────────────────────────────────────

create_uninstall_script() {
    cat > "$UNINSTALL_SCRIPT" << UEOF
#!/bin/bash
for svc in $TG_SERVICE $VK_SERVICE; do
    systemctl stop    \$svc 2>/dev/null || true
    systemctl disable \$svc 2>/dev/null || true
    rm -f /etc/systemd/system/\$svc.service
done
systemctl daemon-reload
crontab -l 2>/dev/null | grep -v "# VM_BOT" | crontab - 2>/dev/null || true
rm -f /etc/sudoers.d/vm-bot
rm -rf $BOT_DIR
echo "Удаление завершено."
UEOF
    chmod 750 "$UNINSTALL_SCRIPT"
    echo -e "${GREEN}✅ Скрипт удаления создан${NC}"; echo ""
}

# ─────────────────────────────────────────────────────────────
# УСТАНОВКА БОТОВ
# ─────────────────────────────────────────────────────────────

create_tg_bot_structure() {
    echo -e "${YELLOW}🔵 Создание Telegram бота...${NC}"
    cd "$TG_DIR"; python3 -m venv venv; source venv/bin/activate
    pip install --quiet --upgrade pip
    pip install --quiet python-telegram-bot==20.7 pytz Pillow qrcode yt-dlp
    deactivate
    create_tg_bot_script
    chmod +x "$TG_DIR/vm_bot.py"
    echo -e "${GREEN}✅ Telegram бот создан${NC}"; echo ""
}

create_vk_bot_structure() {
    echo -e "${YELLOW}🟦 Создание VK бота...${NC}"
    cd "$VK_DIR"; python3 -m venv venv; source venv/bin/activate
    pip install --quiet --upgrade pip
    pip install --quiet vk_api Pillow qrcode yt-dlp
    deactivate
    create_vk_bot_script
    chmod +x "$VK_DIR/vk_bot.py"
    echo -e "${GREEN}✅ VK бот создан${NC}"; echo ""
}

init_database() {
    ACTUAL_USER=${SUDO_USER:-root}
    python3 "$BOT_DIR/db_module.py" --stats 2>/dev/null \
        && echo -e "${GREEN}✅ База данных инициализирована${NC}" \
        || echo -e "${YELLOW}⚠️  БД создастся при первом запуске${NC}"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$DB_FILE" 2>/dev/null || true
    echo ""
}


# ─────────────────────────────────────────────────────────────
# PYTHON: TELEGRAM БОТ
# ─────────────────────────────────────────────────────────────

create_tg_bot_script() {
    cat > "$TG_DIR/vm_bot.py" << 'TGEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Telegram бот управления ВМ Яндекс.Облака. v5.0"""

import asyncio, json, logging, os, subprocess, sys, io, re, tempfile, glob, threading
from pathlib import Path
from functools import partial
import pytz
from telegram import Update, ReplyKeyboardMarkup, KeyboardButton, ReplyKeyboardRemove
from telegram.ext import (Application, CommandHandler, MessageHandler,
                           ContextTypes, filters, ConversationHandler)

BASE_DIR = Path("/opt/vm_manager"); TG_DIR = BASE_DIR / "tg"
CONFIG_FILE = BASE_DIR / "config.json"; LOG_FILE = TG_DIR / "bot.log"
ADMIN_FILE = BASE_DIR / "admins.json"; YT_SUBS_FILE = BASE_DIR / "yt_subs.json"
BASE_DIR.mkdir(parents=True, exist_ok=True); TG_DIR.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(BASE_DIR))
import db_module as db
db.init_db()

SETTINGS_FILE = BASE_DIR / "settings.json"

def get_sensitive():
    try:
        if SETTINGS_FILE.exists(): return json.load(open(SETTINGS_FILE)).get("sensitive_mode", False)
    except: pass
    return False

def set_sensitive(val):
    s = {}
    try:
        if SETTINGS_FILE.exists(): s = json.load(open(SETTINGS_FILE))
    except: pass
    s["sensitive_mode"] = val
    with open(SETTINGS_FILE, "w") as f: json.dump(s, f)

# ── ConversationHandler состояния ────────────────────────────
(SET_START_TIME, SET_STOP_TIME, SET_RETENTION, AWAIT_DELETE_PIN,
 CONSOLE_INPUT, WG_ADDUSER_NAME, WG_GETUSER_NAME, WG_DELUSER_NAME, WG_DELUSER_PIN,
 VKPANEL_STOP_PIN, XUI_STOP_PIN, XUI_PORT_PIN, XUI_PORT_INPUT, XUI_RESET_PIN,
 TG_YT_DUB, TG_YT_QUAL, TG_YT_SEARCH, TG_YT_SEARCH_PICK,
 TG_YT_CHAN, TG_YT_CHAN_PICK, TG_YT_SUB, TG_YT_UNSUB_PICK,
 TG_ADMIN_ADD, TG_ADMIN_ADD_PIN, TG_ADMIN_REMOVE, TG_ADMIN_REMOVE_PIN,
 TG_ADMIN_FEATURES, TG_ADMIN_BROADCAST, TG_ADMIN_MENU_STATE,
 TG_SCHED_START, TG_SCHED_STOP,
 TG_CHAN_BROWSE, TG_CHAN_PICK,
 TG_CHAN_SUB_INPUT) = range(35)

logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s", level=logging.INFO,
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler()])
logger = logging.getLogger(__name__)

class Config:
    def __init__(self):
        self.bot_token=""; self.allowed_users=[]; self.vm_id=""
        self.folder_id=""; self.admin_pin=""; self.vk_installed=False
        self.yadisk_token=""; self.yadisk_ssh_user="ubuntu"; self.yadisk_ssh_key=""
        self.load()
    def load(self):
        try:
            with open(CONFIG_FILE) as f: d = json.load(f)
            self.vm_id=d.get("vm_id",""); self.folder_id=d.get("folder_id","")
            self.admin_pin=d.get("admin_pin","")
            tg=d.get("tg") or {}
            self.bot_token=tg.get("bot_token",""); self.allowed_users=tg.get("allowed_users",[])
            self.vk_installed="vk" in (d.get("installed") or [])
            vk=d.get("vk") or {}
            self.yadisk_token=vk.get("yadisk_token","")
            self.yadisk_ssh_user=vk.get("yadisk_ssh_user","ubuntu")
            self.yadisk_ssh_key=vk.get("yadisk_ssh_key","")
        except Exception as e: logger.error(f"Config error: {e}")

config = Config()

SCHEDULE_FILE = BASE_DIR / "schedule.json"
class Schedule:
    def __init__(self):
        self.auto_start_enabled=False; self.auto_stop_enabled=False
        self.start_time="09:00"; self.stop_time="22:00"; self.load()
    def load(self):
        if SCHEDULE_FILE.exists():
            try:
                with open(SCHEDULE_FILE) as f: d=json.load(f)
                self.auto_start_enabled=d.get("auto_start_enabled",False)
                self.auto_stop_enabled=d.get("auto_stop_enabled",False)
                self.start_time=d.get("start_time","09:00"); self.stop_time=d.get("stop_time","22:00")
            except Exception as e: logger.error(f"Schedule error: {e}")
        else: self.save()
    def save(self):
        with open(SCHEDULE_FILE,"w") as f:
            json.dump({"auto_start_enabled":self.auto_start_enabled,
                       "auto_stop_enabled":self.auto_stop_enabled,
                       "start_time":self.start_time,"stop_time":self.stop_time},f,indent=2)
schedule_config = Schedule()

# ── Система ролей ─────────────────────────────────────────────
def load_admin():
    if ADMIN_FILE.exists():
        try: return json.load(open(ADMIN_FILE))
        except: pass
    return {"extra_users":[],"user_labels":{},"disabled_features":{},
            "global_disabled":["vm_control","terminal","tunnel","xui","vkpanel"]}

def save_admin(data):
    with open(ADMIN_FILE,"w") as f: json.dump(data,f,indent=2,ensure_ascii=False)

def is_admin(uid):
    return uid in [int(u) for u in config.allowed_users]

def get_all_users():
    base=[int(u) for u in config.allowed_users]
    extra=[int(u) for u in load_admin().get("extra_users",[])]
    return list(dict.fromkeys(base+extra))

def user_can(uid, feature):
    if is_admin(uid): return True
    data=load_admin()
    if feature in data.get("global_disabled",[]): return False
    return feature not in data.get("disabled_features",{}).get(str(uid),[])

class YandexCloudVM:
    _ENV={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin:/root/yandex-cloud/bin"}
    @staticmethod
    def _run(cmd,t=60):
        try:
            r=subprocess.run(cmd,capture_output=True,text=True,timeout=t,env=YandexCloudVM._ENV)
            return (True,r.stdout.strip()) if r.returncode==0 else (False,r.stderr.strip())
        except subprocess.TimeoutExpired: return False,f"Таймаут {t}с"
        except Exception as e: return False,str(e)
    @staticmethod
    def get_status():
        ok,out=YandexCloudVM._run(["yc","compute","instance","get",config.vm_id,"--format","json"])
        if ok:
            try: d=json.loads(out); return True,d.get("status","UNKNOWN"),d
            except: pass
        return False,out,None
    @staticmethod
    def start():
        ok,s,_=YandexCloudVM.get_status()
        if not ok: return False,f"Нет статуса: {s}"
        if s=="RUNNING": return True,"ВМ уже запущена"
        if s=="STARTING": return True,"ВМ уже запускается"
        if s not in ["STOPPED","STOPPING"]: return False,f"Запуск невозможен: {s}"
        ok,out=YandexCloudVM._run(["yc","compute","instance","start",config.vm_id])
        return (True,"✅ ВМ запущена") if ok else (False,f"Ошибка: {out}")
    @staticmethod
    def stop():
        ok,s,_=YandexCloudVM.get_status()
        if not ok: return False,f"Нет статуса: {s}"
        if s=="STOPPED": return True,"ВМ уже остановлена"
        if s=="STOPPING": return True,"ВМ уже останавливается"
        if s not in ["RUNNING","STARTING"]: return False,f"Остановка невозможна: {s}"
        ok,out=YandexCloudVM._run(["yc","compute","instance","stop",config.vm_id])
        return (True,"✅ ВМ остановлена") if ok else (False,f"Ошибка: {out}")
    @staticmethod
    def restart():
        ok,s,_=YandexCloudVM.get_status()
        if not ok: return False,f"Нет статуса: {s}"
        if s!="RUNNING": return False,f"Нужен RUNNING, сейчас: {s}"
        ok,out=YandexCloudVM._run(["yc","compute","instance","restart",config.vm_id])
        return (True,"✅ ВМ перезапускается") if ok else (False,f"Ошибка: {out}")
    @staticmethod
    def get_info():
        ok,s,d=YandexCloudVM.get_status()
        if not ok or not d: return False,"Нет данных"
        res=d.get("resources",{}); cores=res.get("cores","N/A")
        try: mem=int(res.get("memory",0))/(1024**3)
        except: mem=0
        ips=[]
        for iface in d.get("network_interfaces",[]):
            pv4=iface.get("primary_v4_address",{})
            if pv4.get("address"): ips.append(f"Внутренний: {pv4['address']}")
            nat=pv4.get("one_to_one_nat",{})
            if nat.get("address"): ips.append(f"Внешний: {nat['address']}")
        return True,(f"📊 <b>Информация о ВМ</b>\n\n🏷 {d.get('name','N/A')}\n"
                     f"📍 {d.get('zone_id','N/A')}\n⚡ {s}\n📅 {d.get('created_at','')[:10]}\n\n"
                     f"💻 Ядра: {cores} | Память: {mem:.1f} GB\n\n🌐\n"
                     +("\n".join(f"• {ip}" for ip in ips) or "• IP не найдены"))

VK_SVC="vm-bot-vk"; TG_SVC="vm-bot-tg"
def svc_active(svc):
    r=subprocess.run(["systemctl","is-active",svc],capture_output=True,text=True)
    return r.stdout.strip()=="active"
def ctrl_svc(svc,action):
    if action=="stop" and svc==TG_SVC: return False,"⛔ Нельзя выключить TG бота через TG!"
    try:
        r=subprocess.run(["sudo","systemctl",action,svc],capture_output=True,text=True,timeout=15)
        return (True,f"✅ {svc} {'запущен' if action=='start' else 'остановлен'}") \
            if r.returncode==0 else (False,f"❌ {r.stderr.strip()}")
    except Exception as e: return False,f"❌ {e}"

def run_cmd(cmd_str, timeout=30):
    try:
        r=subprocess.run(cmd_str,shell=True,capture_output=True,text=True,timeout=timeout,
                        env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
        out=(r.stdout+r.stderr).strip()
        return r.returncode==0, out[:4000]
    except subprocess.TimeoutExpired: return False,f"⏱ Таймаут {timeout}с"
    except Exception as e: return False,str(e)

def run_vkpanel(n, timeout=20): return run_cmd(f'echo "{n}" | vk-panel', timeout)
def run_xui(n, timeout=20): return run_cmd(f'echo "{n}" | x-ui', timeout)

def make_qr_bytes(text):
    import qrcode
    buf=io.BytesIO(); qrcode.make(text).save(buf,format="PNG"); buf.seek(0)
    return buf.getvalue()

# ── Проверка доступа ─────────────────────────────────────────
def check_access(func):
    async def wrapper(update:Update,context:ContextTypes.DEFAULT_TYPE):
        uid = update.effective_user.id
        if uid not in get_all_users():
            await update.message.reply_text("⛔️ Нет доступа"); return ConversationHandler.END
        return await func(update,context)
    wrapper.__name__ = func.__name__
    return wrapper

def admin_only(func):
    async def wrapper(update:Update,context:ContextTypes.DEFAULT_TYPE):
        uid = update.effective_user.id
        if uid not in get_all_users():
            await update.message.reply_text("⛔️ Нет доступа"); return ConversationHandler.END
        if not is_admin(uid):
            await update.message.reply_text("⛔️ Только для администратора")
            return ConversationHandler.END
        return await func(update,context)
    wrapper.__name__ = func.__name__
    return wrapper

# ── Клавиатуры ───────────────────────────────────────────────
def kbd_main():
    rows=[
        [KeyboardButton("📊 Статус"),       KeyboardButton("ℹ️ Информация")],
        [KeyboardButton("▶️ Запустить"),    KeyboardButton("⏹ Остановить")],
        [KeyboardButton("🔄 Перезапустить")],
        [KeyboardButton("⏰ Расписание"),   KeyboardButton("📋 История"),     KeyboardButton("⚙️ Настройки")],
    ]
    if config.vk_installed: rows[2].append(KeyboardButton("🟦 VK бот"))
    if not get_sensitive(): rows.append([KeyboardButton("🔧 Инструменты")])
    return ReplyKeyboardMarkup(rows,resize_keyboard=True)

def kbd_tools():
    return ReplyKeyboardMarkup([
        [KeyboardButton("💻 Терминал"),     KeyboardButton("🔑 Туннель")],
        [KeyboardButton("📡 Медиасервер"),  KeyboardButton("⚙️ Ядро")],
        [KeyboardButton("🎬 YouTube")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_youtube():
    return ReplyKeyboardMarkup([
        [KeyboardButton("🔍 Поиск видео"),        KeyboardButton("▶️ Последние видео канала")],
        [KeyboardButton("📺 Мои подписки"),        KeyboardButton("➕ Подписаться на канал")],
        [KeyboardButton("➖ Отписаться от канала")],
        [KeyboardButton("📡 TG Каналы")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_schedule():
    s="🟢" if schedule_config.auto_start_enabled else "🔴"
    p="🟢" if schedule_config.auto_stop_enabled  else "🔴"
    return ReplyKeyboardMarkup([
        [KeyboardButton(f"{s} Автозапуск"),  KeyboardButton(f"{p} Автоостановка")],
        [KeyboardButton("🕐 Время запуска"), KeyboardButton("🕐 Время остановки")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_vk():
    a=svc_active(VK_SVC)
    return ReplyKeyboardMarkup([
        [KeyboardButton("🟢 VK активен" if a else "🔴 VK неактивен")],
        [KeyboardButton("▶️ Включить VK бота"),KeyboardButton("⏹ Выключить VK бота")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_history():
    days=db.get_setting("retention_days",db.DEFAULT_RETENTION_DAYS)
    return ReplyKeyboardMarkup([
        [KeyboardButton("📜 Последние команды"),  KeyboardButton("🤖 Авто-события")],
        [KeyboardButton(f"⏱ Срок: {days}д"),     KeyboardButton("📊 Статистика БД")],
        [KeyboardButton("🗑️ Очистить историю")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_settings(uid=None):
    lbl="🔒 Скрыть инструменты" if not get_sensitive() else "🔓 Показать инструменты"
    rows=[[KeyboardButton(lbl)]]
    if uid and is_admin(uid): rows.append([KeyboardButton("👮 Администрирование")])
    rows+=[
        [KeyboardButton("🗑️ Удалить бота с сервера")],
        [KeyboardButton("« Назад")],
    ]
    return ReplyKeyboardMarkup(rows,resize_keyboard=True)

def kbd_admin():
    return ReplyKeyboardMarkup([
        [KeyboardButton("➕ Добавить пользователя"), KeyboardButton("➖ Удалить пользователя")],
        [KeyboardButton("📋 Список пользователей")],
        [KeyboardButton("🔧 Функции пользователей")],
        [KeyboardButton("📢 Рассылка")],
        [KeyboardButton("⬆️ Обновить с GitHub")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_console(): return ReplyKeyboardMarkup([[KeyboardButton("« Назад")]],resize_keyboard=True)
def kbd_back():    return ReplyKeyboardMarkup([[KeyboardButton("« Назад")]],resize_keyboard=True)

def kbd_wg():
    return ReplyKeyboardMarkup([
        [KeyboardButton("👥 Пиры")],
        [KeyboardButton("➕ Новый пир"), KeyboardButton("📥 Экспорт"), KeyboardButton("🗑 Удалить пир")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_vkpanel():
    return ReplyKeyboardMarkup([
        [KeyboardButton("▶️ МС-старт"), KeyboardButton("⏹ МС-стоп"), KeyboardButton("🔄 МС-рестарт")],
        [KeyboardButton("📊 МС-статус"), KeyboardButton("📋 МС-логи"), KeyboardButton("📱 МС-QR")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_xui():
    return ReplyKeyboardMarkup([
        [KeyboardButton("📊 Ядро-статус"), KeyboardButton("🔄 Ядро-рестарт")],
        [KeyboardButton("📋 Ядро-логи"),   KeyboardButton("🔧 Ядро-настройки")],
        [KeyboardButton("⏹ Ядро-стоп"), KeyboardButton("🔌 Ядро-порт"), KeyboardButton("🔃 Ядро-сброс")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

# ── YouTube утилиты ──────────────────────────────────────────
def _yt_get_meta_sync(url):
    title="YouTube"; dubbed=[]
    try:
        import yt_dlp as yt
        with yt.YoutubeDL({"quiet":True,"no_warnings":True,"noplaylist":True}) as ydl:
            info=ydl.extract_info(url,download=False)
        title=info.get("title","YouTube")[:60]
        for f in (info.get("formats") or []):
            note=(f.get("format_note") or "").lower(); lang=f.get("language") or ""
            if f.get("acodec")!="none" and f.get("vcodec")=="none":
                if "dubbed" in note or "дубляж" in note or (lang and lang not in ("en","und","")):
                    dubbed.append({"lang":lang,"label":f"{lang.upper()} дубляж" if lang else note,"fid":f["format_id"]})
    except Exception as e: logger.warning(f"yt_meta: {e}")
    return title, dubbed

def _yt_search_sync(query, n=5):
    try:
        import yt_dlp as yt
        with yt.YoutubeDL({"quiet":True,"no_warnings":True,"extract_flat":True,"noplaylist":True}) as ydl:
            info=ydl.extract_info(f"ytsearch{n}:{query}",download=False)
        return [{"id":e.get("id",""),"title":e.get("title","")[:60],
                 "url":f"https://youtu.be/{e.get('id','')}","channel":e.get("channel","")[:30]}
                for e in (info.get("entries") or []) if e]
    except Exception as e: logger.warning(f"yt_search: {e}"); return []


def _normalize_yt_channel_tg(text):
    """Преобразует разные форматы ввода в YouTube URL."""
    text = text.strip()
    # VK-формат: "@id416991442 (@SatiAkura)" → берём username в скобках
    m = re.search(r'\(@([A-Za-z0-9_]+)\)', text)
    if m:
        text = f"@{m.group(1)}"
    # Просто @username → полный URL
    if re.match(r'^@[A-Za-z0-9_]+$', text):
        return f"https://www.youtube.com/{text}"
    # Уже URL — оставляем
    return text

def _yt_channel_info_sync(url):
    try:
        import yt_dlp as yt
        # Добавляем /videos чтобы получить реальные видео, а не вкладки канала
        u = url.rstrip('/')
        if not any(x in u for x in ['/videos','/playlist','/shorts','/live','list=']):
            u = u + '/videos'
        opts={"quiet":True,"no_warnings":True,"extract_flat":"in_playlist",
              "playlist_items":"1-10","noplaylist":False}
        with yt.YoutubeDL(opts) as ydl:
            info=ydl.extract_info(u,download=False)
        cid=info.get("channel_id") or info.get("id","")
        cname=info.get("channel") or info.get("uploader") or info.get("title","")
        videos=[{"id":e.get("id",""),"title":e.get("title","")[:60],
                 "url":f"https://youtu.be/{e.get('id','')}"}
                for e in (info.get("entries") or [])[:10]
                if e and e.get("id") and not e.get("id","").startswith("UC")]
        return cid, cname, videos
    except Exception as e: logger.warning(f"yt_channel: {e}"); return None, None, []

def _yt_sponsorblock_check(video_id):
    import requests as req
    try:
        r=req.get("https://sponsor.ajay.app/api/skipSegments",
            params={"videoID":video_id,"categories":["sponsor","selfpromo","interaction","intro","outro"]},
            timeout=10)
        return r.json() if r.status_code==200 else []
    except: return []

def _yt_sponsorblock_cut(vpath, segments, out_path):
    if not segments: return vpath
    try:
        conditions="+".join([f"between(t,{s['segment'][0]},{s['segment'][1]})" for s in segments])
        r=subprocess.run(["ffmpeg","-y","-i",vpath,
            "-vf",f"select='not({conditions})',setpts=N/FRAME_RATE/TB",
            "-af",f"aselect='not({conditions})',asetpts=N/SR/TB",
            "-c:v","libx264","-c:a","aac","-threads","1",out_path],
            capture_output=True,timeout=300)
        if r.returncode==0: return out_path
    except Exception as e: logger.warning(f"sb cut: {e}")
    return vpath

def _yt_download_sync(url, fmt, safe_title, tmp_dir):
    """Скачивает видео, возвращает (path, error_str)."""
    ytdlp=str(TG_DIR/"venv/bin/yt-dlp")
    out=f"{tmp_dir}/{safe_title}.%(ext)s"
    r=subprocess.run(
        [ytdlp,"-f",fmt,"--merge-output-format","mp4",
         "--postprocessor-args","ffmpeg:-c:v libx264 -preset ultrafast -crf 23 -c:a aac -threads 1",
         "--no-playlist","--socket-timeout","30","--restrict-filenames",
         "-o",out,"--no-part",url],
        capture_output=True,text=True,timeout=600,
        preexec_fn=lambda: os.nice(19),
        env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
    if r.returncode!=0: return None,(r.stderr or r.stdout)[-400:]
    files=glob.glob(f"{tmp_dir}/*.mp4") or glob.glob(f"{tmp_dir}/*.*")
    return (files[0],None) if files else (None,"Файл не найден")

def _yt_get_vm_ip():
    try:
        r=subprocess.run(["yc","compute","instance","get",config.vm_id,"--format","json"],
            capture_output=True,text=True,timeout=30,
            env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin:/root/yandex-cloud/bin"})
        if r.returncode!=0: return None
        d=json.loads(r.stdout)
        for iface in d.get("network_interfaces",[]):
            nat=iface.get("primary_v4_address",{}).get("one_to_one_nat",{})
            if nat.get("address"): return nat["address"]
    except: pass
    return None

def _yt_yadisk_upload_via_ssh(token, local_path, filename):
    user=config.yadisk_ssh_user; key=config.yadisk_ssh_key
    if not key: return None
    vm_ip=_yt_get_vm_ip()
    if not vm_ip: return None
    remote_dir="/tmp/ytdl_yadisk"; remote_file=f"{remote_dir}/{filename}"
    ya_path=f"/yt_bot_videos/{filename}"
    ssh_opts=["-o","StrictHostKeyChecking=no","-o","ConnectTimeout=15","-o","BatchMode=yes","-i",key]
    ssh_base=["ssh"]+ssh_opts+[f"{user}@{vm_ip}"]
    scp_opts=["-o","StrictHostKeyChecking=no","-i",key]
    try:
        subprocess.run(ssh_base+[f"mkdir -p {remote_dir}"],timeout=15,capture_output=True)
        r=subprocess.run(["scp"]+scp_opts+[local_path,f"{user}@{vm_ip}:{remote_file}"],
            capture_output=True,text=True,timeout=600)
        if r.returncode!=0: return None
        subprocess.run(ssh_base+[f"curl -s -X PUT 'https://cloud-api.yandex.net/v1/disk/resources?path=/yt_bot_videos' -H 'Authorization: OAuth {token}'"],timeout=30,capture_output=True)
        r2=subprocess.run(ssh_base+[f"curl -s 'https://cloud-api.yandex.net/v1/disk/resources/upload?path={ya_path}&overwrite=true' -H 'Authorization: OAuth {token}'"],capture_output=True,text=True,timeout=30)
        upload_url=json.loads(r2.stdout).get("href","")
        if not upload_url: subprocess.run(ssh_base+[f"rm -f {remote_file}"],timeout=10,capture_output=True); return None
        subprocess.run(ssh_base+[f"curl -s -T '{remote_file}' '{upload_url}'"],capture_output=True,timeout=900)
        subprocess.run(ssh_base+[f"curl -s -X PUT 'https://cloud-api.yandex.net/v1/disk/resources/publish?path={ya_path}' -H 'Authorization: OAuth {token}'"],timeout=30,capture_output=True)
        r4=subprocess.run(ssh_base+[f"curl -s 'https://cloud-api.yandex.net/v1/disk/resources?path={ya_path}' -H 'Authorization: OAuth {token}'"],capture_output=True,text=True,timeout=30)
        pub_url=json.loads(r4.stdout).get("public_url","")
        subprocess.run(ssh_base+[f"rm -f {remote_file}"],timeout=10,capture_output=True)
        return pub_url or None
    except Exception as e: logger.error(f"yadisk_ssh: {e}"); return None

def _yt_yadisk_upload_direct(token, local_path, filename):
    import requests as req
    h={"Authorization":f"OAuth {token}"}; ya_path=f"/yt_bot_videos/{filename}"
    req.put("https://cloud-api.yandex.net/v1/disk/resources",headers=h,params={"path":"/yt_bot_videos"})
    r=req.get("https://cloud-api.yandex.net/v1/disk/resources/upload",headers=h,
              params={"path":ya_path,"overwrite":"true"},timeout=30)
    r.raise_for_status()
    with open(local_path,"rb") as f: req.put(r.json()["href"],data=f,timeout=600).raise_for_status()
    req.put("https://cloud-api.yandex.net/v1/disk/resources/publish",headers=h,params={"path":ya_path},timeout=30)
    r2=req.get("https://cloud-api.yandex.net/v1/disk/resources",headers=h,params={"path":ya_path},timeout=30)
    return r2.json().get("public_url","")

def load_yt_subs():
    if YT_SUBS_FILE.exists():
        try: return json.load(open(YT_SUBS_FILE))
        except: pass
    return {"channels":{}}

def save_yt_subs(data):
    with open(YT_SUBS_FILE,"w") as f: json.dump(data,f,indent=2,ensure_ascii=False)

# ── Асинхронная загрузка и отправка YouTube ──────────────────
async def _tg_yt_download_and_send(bot, uid, url, title, fmt):
    safe_title=re.sub(r'[\\/*?:"<>|]','',title)[:60].strip() or "video"
    fname=f"{safe_title}.mp4"
    loop=asyncio.get_event_loop()
    with tempfile.TemporaryDirectory() as tmp:
        try:
            vpath,err=await loop.run_in_executor(None,_yt_download_sync,url,fmt,safe_title,tmp)
            if not vpath:
                await bot.send_message(uid,f"❌ Ошибка скачивания:\n{err}"); return

            # SponsorBlock
            vid_m=re.search(r'(?:v=|youtu\.be/)([A-Za-z0-9_-]{11})',url)
            if vid_m:
                segs=await loop.run_in_executor(None,_yt_sponsorblock_check,vid_m.group(1))
                if segs:
                    times=", ".join([f"{int(s['segment'][0]//60)}:{int(s['segment'][0]%60):02d}–"
                                     f"{int(s['segment'][1]//60)}:{int(s['segment'][1]%60):02d}"
                                     for s in segs[:5]])
                    await bot.send_message(uid,f"⚠️ SponsorBlock: {len(segs)} реклам ({times})\n✂️ Вырезаю...")
                    cut_path=os.path.join(tmp,f"{safe_title}_clean.mp4")
                    vpath=await loop.run_in_executor(None,_yt_sponsorblock_cut,vpath,segs,cut_path)

            sz=os.path.getsize(vpath)/(1024*1024)
            await bot.send_message(uid,f"⬆️ Отправляю ({sz:.1f} MB)...")

            token=config.yadisk_token
            if sz>50 and not token:
                await bot.send_message(uid,f"❌ Файл {sz:.0f} MB — в TG лимит 50 MB.\nДобавь Yandex.Disk токен через yabot → 7.")
                return
            if sz>50 and token:
                pub_url=None
                if config.yadisk_ssh_key:
                    await bot.send_message(uid,"☁️ Загружаю через ВМ (быстрый канал)...")
                    pub_url=await loop.run_in_executor(None,_yt_yadisk_upload_via_ssh,token,vpath,fname)
                    if not pub_url:
                        await bot.send_message(uid,"⚠️ SSH недоступен (ВМ выключена?), загружаю напрямую с NL VPS...")
                if not pub_url:
                    pub_url=await loop.run_in_executor(None,_yt_yadisk_upload_direct,token,vpath,fname)
                if pub_url:
                    await bot.send_message(uid,f"📹 <b>{safe_title}</b> ({sz:.1f} MB)\n🔗 <a href='{pub_url}'>Скачать с Яндекс.Диска</a>",parse_mode="HTML")
                else:
                    await bot.send_message(uid,"❌ Яндекс.Диск недоступен")
                return
            # Отправляем напрямую (≤50 MB)
            await bot.send_document(uid,document=open(vpath,"rb"),filename=fname,
                                    caption=f"📹 {safe_title} ({sz:.1f} MB)")
            db.log_command("tg",uid,f"yt {url[:80]}",f"{sz:.1f}MB",True)
        except Exception as e:
            await bot.send_message(uid,f"❌ {e}")
            logger.error(f"tg yt download: {e}")

# ── Обработчики VM ────────────────────────────────────────────
@check_access
async def start_command(u,c): await u.message.reply_text("👋 Панель управления ВМ v5.0",reply_markup=kbd_main())

@check_access
async def status_handler(u,c):
    uid=u.effective_user.id
    if not user_can(uid,"vm_control"):
        await u.message.reply_text("⛔ Управление ВМ только для администратора"); return
    msg=await u.message.reply_text("⏳")
    ok,s,_=YandexCloudVM.get_status()
    e={"RUNNING":"🟢","STOPPED":"🔴","STARTING":"🟡","STOPPING":"🟡"}.get(s,"⚪") if ok else "❌"
    r=f"{e} Статус ВМ: <b>{s}</b>" if ok else f"❌ {s}"
    await msg.edit_text(r,parse_mode="HTML")
    db.log_command("tg",uid,"статус",r,ok)

@check_access
async def info_handler(u,c):
    uid=u.effective_user.id
    if not user_can(uid,"vm_control"):
        await u.message.reply_text("⛔ Управление ВМ только для администратора"); return
    msg=await u.message.reply_text("⏳")
    ok,info=YandexCloudVM.get_info()
    await msg.edit_text(info if ok else f"❌ {info}",parse_mode="HTML" if ok else None)
    db.log_command("tg",uid,"информация","ОК" if ok else info,ok)

@check_access
async def start_vm(u,c):
    uid=u.effective_user.id
    if not user_can(uid,"vm_control"):
        await u.message.reply_text("⛔ Управление ВМ только для администратора"); return
    msg=await u.message.reply_text("⏳ Запуск ВМ...")
    ok,m=YandexCloudVM.start(); await msg.edit_text(m)
    db.log_command("tg",uid,"запуск ВМ",m,ok)

@check_access
async def stop_vm(u,c):
    uid=u.effective_user.id
    if not user_can(uid,"vm_control"):
        await u.message.reply_text("⛔ Управление ВМ только для администратора"); return
    msg=await u.message.reply_text("⏳ Остановка ВМ...")
    ok,m=YandexCloudVM.stop(); await msg.edit_text(m)
    db.log_command("tg",uid,"остановка ВМ",m,ok)

@check_access
async def restart_vm(u,c):
    uid=u.effective_user.id
    if not user_can(uid,"vm_control"):
        await u.message.reply_text("⛔ Управление ВМ только для администратора"); return
    msg=await u.message.reply_text("⏳ Перезапуск ВМ...")
    ok,m=YandexCloudVM.restart(); await msg.edit_text(m)
    db.log_command("tg",uid,"перезапуск ВМ",m,ok)

@check_access
async def vk_menu(u,c):
    if not config.vk_installed: await u.message.reply_text("❌ VK бот не установлен"); return
    a=svc_active(VK_SVC)
    await u.message.reply_text(f"🟦 <b>VK бот</b>\nСтатус: {'🟢 активен' if a else '🔴 неактивен'}",
                               parse_mode="HTML",reply_markup=kbd_vk())

@check_access
async def vk_start(u,c):
    msg=await u.message.reply_text("⏳")
    ok,m=ctrl_svc(VK_SVC,"start"); await msg.edit_text(m)
    db.log_command("tg",u.effective_user.id,"включить VK",m,ok)
    await u.message.reply_text("Статус:",reply_markup=kbd_vk())

@check_access
async def vk_stop(u,c):
    msg=await u.message.reply_text("⏳")
    ok,m=ctrl_svc(VK_SVC,"stop"); await msg.edit_text(m)
    db.log_command("tg",u.effective_user.id,"выключить VK",m,ok)

@check_access
async def vk_refresh(u,c): await vk_menu(u,c)

@check_access
async def schedule_h(u,c):
    if not user_can(u.effective_user.id,"vm_control"):
        await u.message.reply_text("⛔ Расписание только для администратора"); return
    s="🟢" if schedule_config.auto_start_enabled else "🔴"
    p="🟢" if schedule_config.auto_stop_enabled  else "🔴"
    await u.message.reply_text(
        f"⏰ <b>Расписание ВМ</b>\n\n{s} Автозапуск: {'включён' if schedule_config.auto_start_enabled else 'выключен'} [{schedule_config.start_time}]\n{p} Автоостановка: {'включена' if schedule_config.auto_stop_enabled else 'выключена'} [{schedule_config.stop_time}]",
        parse_mode="HTML",reply_markup=kbd_schedule())

@check_access
async def toggle_start(u,c):
    schedule_config.auto_start_enabled=not schedule_config.auto_start_enabled
    schedule_config.save(); update_cron()
    st="🟢 включён" if schedule_config.auto_start_enabled else "🔴 выключен"
    await u.message.reply_text(f"Автозапуск {st}",reply_markup=kbd_schedule())
    db.log_command("tg",u.effective_user.id,"автозапуск",st,True)

@check_access
async def toggle_stop(u,c):
    schedule_config.auto_stop_enabled=not schedule_config.auto_stop_enabled
    schedule_config.save(); update_cron()
    st="🟢 включена" if schedule_config.auto_stop_enabled else "🔴 выключена"
    await u.message.reply_text(f"Автоостановка {st}",reply_markup=kbd_schedule())
    db.log_command("tg",u.effective_user.id,"автоостановка",st,True)

@check_access
async def set_start_begin(u,c):
    await u.message.reply_text(f"Текущее время запуска: {schedule_config.start_time}\nВведите новое (ЧЧ:ММ):",reply_markup=ReplyKeyboardRemove())
    return SET_START_TIME

@check_access
async def set_start_end(u,c):
    t=u.message.text.strip()
    try:
        h,m=t.split(":"); assert 0<=int(h)<24 and 0<=int(m)<60
        schedule_config.start_time=t; schedule_config.save(); update_cron()
        await u.message.reply_text(f"✅ Время запуска: {t}",reply_markup=kbd_schedule())
    except: await u.message.reply_text("❌ Формат ЧЧ:ММ",reply_markup=kbd_schedule())
    return ConversationHandler.END

@check_access
async def set_stop_begin(u,c):
    await u.message.reply_text(f"Текущее время остановки: {schedule_config.stop_time}\nВведите новое (ЧЧ:ММ):",reply_markup=ReplyKeyboardRemove())
    return SET_STOP_TIME

@check_access
async def set_stop_end(u,c):
    t=u.message.text.strip()
    try:
        h,m=t.split(":"); assert 0<=int(h)<24 and 0<=int(m)<60
        schedule_config.stop_time=t; schedule_config.save(); update_cron()
        await u.message.reply_text(f"✅ Время остановки: {t}",reply_markup=kbd_schedule())
    except: await u.message.reply_text("❌ Формат ЧЧ:ММ",reply_markup=kbd_schedule())
    return ConversationHandler.END

@check_access
async def history_menu(u,c):
    await u.message.reply_text("📋 <b>История и БД</b>",parse_mode="HTML",reply_markup=kbd_history())

@check_access
async def history_show(u,c):
    rows=db.get_history(10)
    if not rows: await u.message.reply_text("📭 История пуста",reply_markup=kbd_history()); return
    lines=["📜 <b>Последние 10 команд:</b>\n"]
    for r in rows:
        lines.append(f"{'✅' if r['success'] else '❌'} {r['timestamp']}\n  [{r['platform'].upper()}] {r['command']}\n  ↳ {r['result'] or '—'}")
    await u.message.reply_text("\n".join(lines),parse_mode="HTML",reply_markup=kbd_history())

@check_access
async def auto_events_show(u,c):
    rows=db.get_auto_events(8)
    if not rows: await u.message.reply_text("📭 Нет событий",reply_markup=kbd_history()); return
    lines=["🤖 <b>Авто-события:</b>\n"]
    for r in rows:
        lines.append(f"{'✅' if r['success'] else '❌'} {r['timestamp']} [{r['event_type']}]\n  {r['details']}")
    await u.message.reply_text("\n".join(lines),parse_mode="HTML",reply_markup=kbd_history())

@check_access
async def db_stats(u,c):
    s=db.get_stats()
    await u.message.reply_text(
        f"📊 <b>Статистика БД</b>\n\nКоманд: {s['total']} (TG:{s['tg']} VK:{s['vk']})\nАвто-событий: {s['auto']}\nСрок: {s['retention']} дн.\nСтарейшая: {s['oldest']}\nНовейшая: {s['newest']}",
        parse_mode="HTML",reply_markup=kbd_history())

@check_access
async def set_retention_begin(u,c):
    days=db.get_setting("retention_days",db.DEFAULT_RETENTION_DAYS)
    await u.message.reply_text(f"⏱ Текущий срок хранения: {days} дней\nВведите новое значение (≥1):",reply_markup=ReplyKeyboardRemove())
    return SET_RETENTION

@check_access
async def set_retention_end(u,c):
    try:
        d=int(u.message.text.strip()); assert d>=1
        deleted=db.set_retention(d)
        await u.message.reply_text(f"✅ Срок: {d} дн. Удалено {deleted} записей.",reply_markup=kbd_history())
    except: await u.message.reply_text("❌ Введите целое число ≥1",reply_markup=kbd_history())
    return ConversationHandler.END

@check_access
async def clear_history(u,c):
    n=db.clear_all_history()
    db.log_auto_event("manual_clear",f"Ручная очистка TG: {n} записей")
    await u.message.reply_text(f"✅ Удалено {n} записей",reply_markup=kbd_history())

@check_access
async def settings_menu(u,c):
    uid=u.effective_user.id
    mode="🔒 Скрыт" if get_sensitive() else "🔓 Виден"
    await u.message.reply_text(f"⚙️ <b>Настройки</b>\n\n🔧 Инструменты: <b>{mode}</b>",
                               parse_mode="HTML",reply_markup=kbd_settings(uid))

@check_access
async def toggle_sensitive(u,c):
    uid=u.effective_user.id
    val=not get_sensitive(); set_sensitive(val)
    mode="скрыты 🔒" if val else "видны 🔓"
    await u.message.reply_text(f"✅ Инструменты {mode}",reply_markup=kbd_settings(uid))
    await u.message.reply_text("↩️ Меню:",reply_markup=kbd_main())

@check_access
async def delete_bot_begin(u,c):
    await u.message.reply_text("⚠️ <b>Удаление бота с сервера</b>\n\nВведите PIN:",
                               parse_mode="HTML",reply_markup=ReplyKeyboardRemove())
    return AWAIT_DELETE_PIN

@check_access
async def delete_bot_pin(u,c):
    if u.message.text.strip()==config.admin_pin:
        db.log_command("tg",u.effective_user.id,"удаление бота","выполнено",True)
        await u.message.reply_text("🗑️ PIN верный. Удаление через 3 секунды...",reply_markup=ReplyKeyboardRemove())
        async def _del():
            await asyncio.sleep(3)
            subprocess.Popen(["sudo","/opt/vm_manager/uninstall.sh"])
        asyncio.create_task(_del())
    else:
        db.log_command("tg",u.effective_user.id,"удаление бота","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN. Отменено.",reply_markup=kbd_settings(u.effective_user.id))
    return ConversationHandler.END

@check_access
async def cancel_h(u,c):
    await u.message.reply_text("↩️ Отменено",reply_markup=kbd_main()); return ConversationHandler.END

@check_access
async def back_main(u,c):
    await u.message.reply_text("Главное меню",reply_markup=kbd_main())

@check_access
async def tools_menu(u,c):
    await u.message.reply_text("🔧 <b>Инструменты</b>",parse_mode="HTML",reply_markup=kbd_tools())

# ── YouTube: меню и обработчики ───────────────────────────────
@check_access
async def yt_menu_show(u,c):
    ssh_info="🌍 Загрузка через ВМ (быстрый канал)" if config.yadisk_ssh_key else "☁️ Прямая загрузка на Яндекс.Диск"
    await u.message.reply_text(
        f"🎬 <b>YouTube</b>\n\n{ssh_info}\n\nОтправь ссылку напрямую — скачаю сразу.\nИли используй кнопки ниже:",
        parse_mode="HTML",reply_markup=kbd_youtube())

@check_access
async def yt_inline(u,c):
    """Автодетект YouTube ссылки — запрашиваем качество."""
    url=u.message.text.strip(); uid=u.effective_user.id
    msg=await u.message.reply_text("🔍 Получаю информацию о видео...",reply_markup=ReplyKeyboardRemove())
    loop=asyncio.get_event_loop()
    title,dubbed=await loop.run_in_executor(None,_yt_get_meta_sync,url)
    c.user_data['yt_url']=url; c.user_data['yt_title']=title; c.user_data['yt_dubbed']=dubbed
    if dubbed:
        dub_list="\n".join([f"{i+1}. {d['label']}" for i,d in enumerate(dubbed)])
        await msg.edit_text(
            f"🎬 {title}\n\nДубляжи:\n{dub_list}\n{len(dubbed)+1}. Оригинал\n\n"
            f"Качество: MAX) Максимум  A) 1080p  B) 720p  C) 480p  D) 360p\n\nПример: 1A (1080p) или {len(dubbed)+1}MAX (макс) или « Назад")
        return TG_YT_DUB
    await msg.edit_text(f"🎬 {title}\n\nВыбери качество:\nMAX) Максимум (лучшее)\nA) 1080p\nB) 720p\nC) 480p\nD) 360p\n(или « Назад)")
    return TG_YT_QUAL

async def _yt_dub_handler(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("↩️",reply_markup=kbd_main()); return ConversationHandler.END
    m=re.match(r'^(\d+)([ABCabc]?)$',text)
    if not m: await u.message.reply_text("❌ Формат: 1A или 2C"); return TG_YT_DUB
    url=c.user_data.get('yt_url',''); title=c.user_data.get('yt_title',''); dubbed=c.user_data.get('yt_dubbed',[])
    choice=int(m.group(1))-1; h={"A":"720","B":"480","C":"360"}.get(m.group(2).upper() or "A","720")
    if choice==len(dubbed): fmt=f"bestvideo[height<={h}]+bestaudio/best"
    elif 0<=choice<len(dubbed): fmt=f"bestvideo[height<={h}]+{dubbed[choice]['fid']}/bestvideo[height<={h}]+bestaudio/best"
    else: await u.message.reply_text(f"❌ Неверный номер"); return TG_YT_DUB
    await u.message.reply_text(f"⏳ Скачиваю «{title[:40]}» ({h}p)...\nБот доступен.",reply_markup=kbd_main())
    asyncio.create_task(_tg_yt_download_and_send(c.bot,u.effective_user.id,url,title,fmt))
    return ConversationHandler.END

async def _yt_qual_handler(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("↩️",reply_markup=kbd_main()); return ConversationHandler.END
    if not re.match(r'^(MAX|[ABCDabcd])$',text.upper()):
        await u.message.reply_text("❌ MAX, A, B, C или D"); return TG_YT_QUAL
    url=c.user_data.get('yt_url',''); title=c.user_data.get('yt_title','')
    t=text.upper()
    if t=="MAX":
        fmt="bestvideo+bestaudio/best"; h_label="макс. качество"
    else:
        h={"A":"1080","B":"720","C":"480","D":"360"}.get(t,"720")
        fmt=f"bestvideo[height<={h}]+bestaudio/bestvideo[height<={h}]+bestaudio/best"; h_label=f"{h}p"
    await u.message.reply_text(f"⏳ Скачиваю «{title[:40]}» ({h_label})...\nБот доступен.",reply_markup=kbd_main())
    asyncio.create_task(_tg_yt_download_and_send(c.bot,u.effective_user.id,url,title,fmt))
    return ConversationHandler.END

@check_access
async def yt_search_begin(u,c):
    await u.message.reply_text("🔍 Введи поисковый запрос:",reply_markup=kbd_back()); return TG_YT_SEARCH

async def yt_search_end(u,c):
    text=u.message.text.strip()
    if text in ("« Назад","🎬 YouTube"):
        await u.message.reply_text("🎬 YouTube",reply_markup=kbd_youtube()); return ConversationHandler.END
    await u.message.reply_text("🔍 Ищу...")
    loop=asyncio.get_event_loop()
    results=await loop.run_in_executor(None,_yt_search_sync,text)
    if not results:
        await u.message.reply_text("❌ Ничего не найдено",reply_markup=kbd_youtube()); return ConversationHandler.END
    lines=[f"🔍 <b>{text[:40]}</b>\n"]
    for i,r in enumerate(results,1): lines.append(f"{i}. {r['title']}\n   ▶️ {r['channel']}\n   {r['url']}")
    await u.message.reply_text("\n\n".join(lines)+"\n\nВведи номер:",parse_mode="HTML",reply_markup=kbd_back())
    c.user_data['yt_search_results']=results; return TG_YT_SEARCH_PICK

async def yt_search_pick(u,c):
    text=u.message.text.strip()
    if text in ("« Назад","🎬 YouTube"):
        await u.message.reply_text("🎬 YouTube",reply_markup=kbd_youtube()); return ConversationHandler.END
    try:
        n=int(text)-1; results=c.user_data.get('yt_search_results',[])
        if not 0<=n<len(results): await u.message.reply_text(f"❌ Номер 1-{len(results)}"); return TG_YT_SEARCH_PICK
        v=results[n]; c.user_data['yt_url']=v['url']; c.user_data['yt_title']=v['title']; c.user_data['yt_dubbed']=[]
        await u.message.reply_text(f"🎬 {v['title']}\n\nКачество:\nA) 720p\nB) 480p\nC) 360p")
        return TG_YT_QUAL
    except: await u.message.reply_text("❌ Введи число"); return TG_YT_SEARCH_PICK

@check_access
async def yt_channel_begin(u,c):
    await u.message.reply_text("📺 Введи ссылку на канал или @username:",reply_markup=kbd_back()); return TG_YT_CHAN

async def yt_channel_end(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("🎬 YouTube",reply_markup=kbd_youtube()); return ConversationHandler.END
    await u.message.reply_text("⏳ Получаю видео...")
    loop=asyncio.get_event_loop()
    _,cname,videos=await loop.run_in_executor(None,_yt_channel_info_sync,text)
    if not videos:
        await u.message.reply_text("❌ Не удалось получить видео",reply_markup=kbd_youtube()); return ConversationHandler.END
    lines=[f"📺 <b>{cname or text}</b>\n"]
    for i,v in enumerate(videos,1): lines.append(f"{i}. {v['title']}\n   {v['url']}")
    await u.message.reply_text("\n\n".join(lines)+"\n\nВведи номер:",parse_mode="HTML",reply_markup=kbd_back())
    c.user_data['yt_chan_videos']=videos; return TG_YT_CHAN_PICK

async def yt_channel_pick(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("🎬 YouTube",reply_markup=kbd_youtube()); return ConversationHandler.END
    try:
        n=int(text)-1; videos=c.user_data.get('yt_chan_videos',[])
        if not 0<=n<len(videos): await u.message.reply_text(f"❌ Номер 1-{len(videos)}"); return TG_YT_CHAN_PICK
        v=videos[n]; c.user_data['yt_url']=v['url']; c.user_data['yt_title']=v['title']; c.user_data['yt_dubbed']=[]
        await u.message.reply_text(f"🎬 {v['title']}\n\nКачество:\nA) 720p\nB) 480p\nC) 360p")
        return TG_YT_QUAL
    except: await u.message.reply_text("❌ Введи число"); return TG_YT_CHAN_PICK

@check_access
async def yt_subscribe_begin(u,c):
    await u.message.reply_text("➕ Введи ссылку на канал или @username:",reply_markup=kbd_back()); return TG_YT_SUB

async def yt_subscribe_end(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("🎬 YouTube",reply_markup=kbd_youtube()); return ConversationHandler.END
    text=_normalize_yt_channel_tg(text)
    await u.message.reply_text("⏳ Получаю информацию о канале...")
    uid=u.effective_user.id
    loop=asyncio.get_event_loop()
    cid,cname,videos=await loop.run_in_executor(None,_yt_channel_info_sync,text)
    if not cid:
        await u.message.reply_text("❌ Канал не найден",reply_markup=kbd_youtube()); return ConversationHandler.END
    data=load_yt_subs()
    if cid not in data["channels"]:
        data["channels"][cid]={"name":cname,"url":text,"subscribers":[],
                                "last_video_id":videos[0]["id"] if videos else "","last_check":""}
    ch=data["channels"][cid]
    if uid not in ch["subscribers"]:
        ch["subscribers"].append(uid); save_yt_subs(data)
        await u.message.reply_text(f"✅ Подписался на <b>{cname}</b>!\n\nПоследнее: {videos[0]['title'] if videos else 'нет'}",parse_mode="HTML",reply_markup=kbd_youtube())
    else:
        await u.message.reply_text(f"ℹ️ Уже подписан на <b>{cname}</b>",parse_mode="HTML",reply_markup=kbd_youtube())
    return ConversationHandler.END

@check_access
async def yt_unsubscribe_begin(u,c):
    uid=u.effective_user.id; data=load_yt_subs()
    my_subs=[(cid,ch) for cid,ch in data["channels"].items() if uid in ch.get("subscribers",[])]
    if not my_subs:
        await u.message.reply_text("📭 Нет подписок",reply_markup=kbd_youtube()); return ConversationHandler.END
    lines=["📺 <b>Твои подписки:</b>\n"]
    for i,(cid,ch) in enumerate(my_subs,1): lines.append(f"{i}. {ch.get('name',cid)}")
    await u.message.reply_text("\n".join(lines)+"\n\nВведи номер:",parse_mode="HTML",reply_markup=kbd_back())
    c.user_data['yt_my_subs']=my_subs; return TG_YT_UNSUB_PICK

async def yt_unsubscribe_pick(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("🎬 YouTube",reply_markup=kbd_youtube()); return ConversationHandler.END
    try:
        n=int(text)-1; my_subs=c.user_data.get('yt_my_subs',[]); uid=u.effective_user.id
        if not 0<=n<len(my_subs): await u.message.reply_text(f"❌ Номер 1-{len(my_subs)}"); return TG_YT_UNSUB_PICK
        cid,ch=my_subs[n]; data=load_yt_subs()
        if cid in data["channels"]:
            ch2=data["channels"][cid]
            if uid in ch2["subscribers"]: ch2["subscribers"].remove(uid)
            if not ch2["subscribers"]: del data["channels"][cid]
            save_yt_subs(data)
        await u.message.reply_text(f"✅ Отписался от <b>{ch.get('name',cid)}</b>",parse_mode="HTML",reply_markup=kbd_youtube())
        return ConversationHandler.END
    except: await u.message.reply_text("❌ Введи число"); return TG_YT_UNSUB_PICK

# ── Администрирование ─────────────────────────────────────────
@admin_only
async def tg_admin_menu(u,c):
    await u.message.reply_text("👮 <b>Администрирование</b>",parse_mode="HTML",reply_markup=kbd_admin())
    return TG_ADMIN_MENU_STATE

async def tg_admin_add_begin(u,c):
    await u.message.reply_text("➕ Введи TG User ID или @username\n(ID точнее — узнать через @userinfobot):",reply_markup=kbd_back())
    return TG_ADMIN_ADD

async def tg_admin_add_mid(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("👮 Администрирование",reply_markup=kbd_admin()); return ConversationHandler.END
    uid_str=text.lstrip('@')
    try:
        new_uid=int(uid_str)
        if new_uid in get_all_users():
            await u.message.reply_text(f"ℹ️ ID {new_uid} уже в списке",reply_markup=kbd_admin()); return ConversationHandler.END
        c.user_data['admin_add_uid']=new_uid; c.user_data['admin_add_label']=text
        await u.message.reply_text(f"Добавить ID {new_uid}?\nВведи PIN для подтверждения:")
        return TG_ADMIN_ADD_PIN
    except:
        await u.message.reply_text("❌ Введи числовой ID (@userinfobot поможет узнать)"); return TG_ADMIN_ADD

async def tg_admin_add_pin(u,c):
    if u.message.text.strip()==config.admin_pin:
        new_uid=c.user_data.get('admin_add_uid'); label=c.user_data.get('admin_add_label',str(new_uid))
        data=load_admin()
        if new_uid not in data["extra_users"]: data["extra_users"].append(new_uid)
        data["user_labels"][str(new_uid)]=label; save_admin(data)
        db.log_command("tg",u.effective_user.id,f"add_user {new_uid}",label,True)
        await u.message.reply_text(f"✅ ID {new_uid} добавлен в вайтлист!\nМожет использовать YouTube.",reply_markup=kbd_admin())
    else:
        await u.message.reply_text("❌ Неверный PIN",reply_markup=kbd_admin())
    return TG_ADMIN_MENU_STATE

async def tg_admin_remove_begin(u,c):
    data=load_admin(); extra=data.get("extra_users",[]); labels=data.get("user_labels",{})
    if not extra:
        await u.message.reply_text("📭 Вайтлист пуст",reply_markup=kbd_admin()); return TG_ADMIN_MENU_STATE
    lines=["➖ <b>Вайтлист:</b>\n"]
    for uid2 in extra: lines.append(f"• {labels.get(str(uid2),str(uid2))} — ID {uid2}")
    await u.message.reply_text("\n".join(lines)+"\n\nВведи ID для удаления:",parse_mode="HTML",reply_markup=kbd_back())
    return TG_ADMIN_REMOVE

async def tg_admin_remove_mid(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("👮 Администрирование",reply_markup=kbd_admin()); return ConversationHandler.END
    try:
        rem_uid=int(text); data=load_admin()
        if rem_uid not in [int(x) for x in data.get("extra_users",[])]:
            await u.message.reply_text("❌ ID не найден в вайтлисте"); return TG_ADMIN_REMOVE
        label=data.get("user_labels",{}).get(str(rem_uid),str(rem_uid))
        c.user_data['admin_rem_uid']=rem_uid; c.user_data['admin_rem_label']=label
        await u.message.reply_text(f"Удалить {label} (ID {rem_uid})? Введи PIN:")
        return TG_ADMIN_REMOVE_PIN
    except: await u.message.reply_text("❌ Числовой ID"); return TG_ADMIN_REMOVE

async def tg_admin_remove_pin(u,c):
    if u.message.text.strip()==config.admin_pin:
        rem_uid=c.user_data.get('admin_rem_uid'); label=c.user_data.get('admin_rem_label')
        data=load_admin()
        data["extra_users"]=[x for x in data["extra_users"] if int(x)!=rem_uid]
        data["user_labels"].pop(str(rem_uid),None); data["disabled_features"].pop(str(rem_uid),None)
        save_admin(data)
        db.log_command("tg",u.effective_user.id,f"remove_user {rem_uid}",label,True)
        await u.message.reply_text(f"✅ {label} (ID {rem_uid}) удалён",reply_markup=kbd_admin())
    else:
        await u.message.reply_text("❌ Неверный PIN",reply_markup=kbd_admin())
    return TG_ADMIN_MENU_STATE

async def tg_admin_features_begin(u,c):
    data=load_admin(); gd=data.get("global_disabled",[])
    await u.message.reply_text(
        f"🔧 <b>Управление функциями</b>\n\n"
        f"Формат: &lt;ID&gt; &lt;функция&gt; вкл/выкл\nили: глобально &lt;функция&gt; вкл/выкл\n\n"
        f"Функции: youtube, vm_control, terminal, tunnel, xui, vkpanel\n\n"
        f"Сейчас глобально отключено: {', '.join(gd) or 'ничего'}\n\n"
        f"Примеры:\n123456 youtube выкл\nглобально vm_control выкл",
        parse_mode="HTML",reply_markup=kbd_back())
    return TG_ADMIN_FEATURES

async def tg_admin_features_end(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("👮 Администрирование",reply_markup=kbd_admin()); return TG_ADMIN_MENU_STATE
    parts=text.lower().split()
    if len(parts)!=3:
        await u.message.reply_text("❌ Формат: <ID/глобально> <функция> вкл/выкл"); return TG_ADMIN_FEATURES
    target,feature,action=parts
    if feature not in ("youtube","vm_control","terminal","tunnel","xui","vkpanel"):
        await u.message.reply_text("❌ Неизвестная функция"); return TG_ADMIN_FEATURES
    data=load_admin()
    if target=="глобально":
        gd=data.setdefault("global_disabled",[])
        if action in ("выкл","off"):
            if feature not in gd: gd.append(feature)
            await u.message.reply_text(f"✅ {feature} глобально отключена",reply_markup=kbd_admin())
        else:
            if feature in gd: gd.remove(feature)
            await u.message.reply_text(f"✅ {feature} глобально включена",reply_markup=kbd_admin())
    else:
        try: t_uid=int(target)
        except: await u.message.reply_text("❌ Неверный ID"); return TG_ADMIN_FEATURES
        ud=data.setdefault("disabled_features",{}).setdefault(str(t_uid),[])
        if action in ("выкл","off"):
            if feature not in ud: ud.append(feature)
        else:
            if feature in ud: ud.remove(feature)
        await u.message.reply_text(f"✅ {feature} {'отключена' if action in ('выкл','off') else 'включена'} для ID {t_uid}",reply_markup=kbd_admin())
    save_admin(data)
    return TG_ADMIN_MENU_STATE

async def tg_admin_broadcast_begin(u,c):
    await u.message.reply_text("📢 Введи текст рассылки:",reply_markup=kbd_back()); return TG_ADMIN_BROADCAST

async def tg_admin_broadcast_end(u,c):
    text=u.message.text.strip()
    if text=="« Назад":
        await u.message.reply_text("👮 Администрирование",reply_markup=kbd_admin()); return TG_ADMIN_MENU_STATE
    users=get_all_users(); uid=u.effective_user.id; sent=0
    for user_id in users:
        if user_id==uid: continue
        try: await c.bot.send_message(user_id,f"📢 Сообщение от администратора:\n\n{text}"); sent+=1
        except: pass
    await u.message.reply_text(f"✅ Рассылка отправлена {sent} пользователям",reply_markup=kbd_admin())
    return TG_ADMIN_MENU_STATE

async def tg_admin_list_h(u,c):
    data=load_admin(); labels=data.get("user_labels",{}); gd=data.get("global_disabled",[])
    lines=["📋 <b>Пользователи:</b>\n","👑 Администраторы (конфиг):"]
    for uid2 in config.allowed_users: lines.append(f"  • ID {uid2} (все права)")
    lines.append("\n🔓 Вайтлист:")
    extra=data.get("extra_users",[])
    if not extra: lines.append("  (пусто)")
    for uid2 in extra:
        dis=data.get("disabled_features",{}).get(str(uid2),[])
        tag=f" [блок: {','.join(dis)}]" if dis else ""
        lines.append(f"  • {labels.get(str(uid2),str(uid2))} — ID {uid2}{tag}")
    lines.append(f"\n🚫 Глобально отключено: {', '.join(gd) or 'ничего'}")
    await u.message.reply_text("\n".join(lines),parse_mode="HTML",reply_markup=kbd_admin())
    return TG_ADMIN_MENU_STATE

# ── 💻 Консоль ───────────────────────────────────────────────
@check_access
async def console_menu(u,c):
    if not user_can(u.effective_user.id,"terminal"):
        await u.message.reply_text("⛔ Терминал только для администратора"); return ConversationHandler.END
    await u.message.reply_text("💻 <b>Консоль</b>\nВведите команду. Таймаут: 30с\n/cancel для выхода",
        parse_mode="HTML",reply_markup=kbd_console()); return CONSOLE_INPUT

@check_access
async def console_exec(u,c):
    cmd=u.message.text.strip()
    if cmd=="« Назад":
        await u.message.reply_text("↩️",reply_markup=kbd_tools()); return ConversationHandler.END
    msg=await u.message.reply_text("⏳")
    ok,out=run_cmd(cmd,timeout=30)
    await msg.edit_text(f"{'✅' if ok else '❌'} <code>$ {cmd[:100]}</code>\n\n<code>{out or '(нет вывода)'}</code>",
                        parse_mode="HTML")
    db.log_command("tg",u.effective_user.id,f"console: {cmd[:100]}",out[:200],ok)
    return CONSOLE_INPUT

# ── WireGuard ─────────────────────────────────────────────────
@check_access
async def wg_menu(u,c):
    if not user_can(u.effective_user.id,"tunnel"):
        await u.message.reply_text("⛔ Туннель только для администратора"); return
    await u.message.reply_text("🔑 <b>Туннель</b>",parse_mode="HTML",reply_markup=kbd_wg())

@check_access
async def wg_listusers(u,c):
    msg=await u.message.reply_text("⏳"); ok,out=run_cmd("wv listusers")
    await msg.edit_text(f"👥 <b>Пиры:</b>\n<code>{out or '—'}</code>",parse_mode="HTML")
    db.log_command("tg",u.effective_user.id,"wg listusers",out[:100],ok)

@check_access
async def wg_adduser_begin(u,c):
    await u.message.reply_text("➕ Имя нового пира (без пробелов):",reply_markup=ReplyKeyboardRemove()); return WG_ADDUSER_NAME

@check_access
async def wg_adduser_end(u,c):
    name=u.message.text.strip()
    if not name or ' ' in name:
        await u.message.reply_text("❌ Имя без пробелов и пустое"); return WG_ADDUSER_NAME
    msg=await u.message.reply_text(f"⏳ Добавляю {name}…")
    ok,out=run_cmd(f"wv adduser {name}")
    await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}")
    db.log_command("tg",u.effective_user.id,f"wg adduser {name}",out[:100],ok)
    await u.message.reply_text("Туннель:",reply_markup=kbd_wg()); return ConversationHandler.END

@check_access
async def wg_getuser_begin(u,c):
    await u.message.reply_text("📥 Имя пира для экспорта:",reply_markup=ReplyKeyboardRemove()); return WG_GETUSER_NAME

@check_access
async def wg_getuser_end(u,c):
    name=u.message.text.strip(); msg=await u.message.reply_text(f"⏳ Получаю {name}…")
    ok,out=run_cmd(f"wv getuser {name}")
    if not ok:
        await msg.edit_text(f"❌ {out}"); db.log_command("tg",u.effective_user.id,f"wg getuser {name}",out[:100],False)
        await u.message.reply_text("Туннель:",reply_markup=kbd_wg()); return ConversationHandler.END
    try:
        import zipfile
        with tempfile.NamedTemporaryFile(delete=False,suffix=f"_{name}.conf") as cf:
            cf.write(out.encode()); cpath=cf.name
        await u.message.reply_document(document=open(cpath,"rb"),filename=f"{name}.conf")
        os.unlink(cpath)
        with tempfile.NamedTemporaryFile(delete=False,suffix=".zip") as zf_tmp: zpath=zf_tmp.name
        with zipfile.ZipFile(zpath,'w',zipfile.ZIP_DEFLATED) as zf: zf.writestr(f"{name}.conf",out)
        await u.message.reply_document(document=open(zpath,"rb"),filename=f"{name}.zip")
        os.unlink(zpath)
        await msg.edit_text(f"✅ Конфиг {name} отправлен (.conf + .zip)")
        db.log_command("tg",u.effective_user.id,f"wg getuser {name}","sent",True)
    except Exception as e:
        await msg.edit_text(f"❌ {e}")
    await u.message.reply_text("Туннель:",reply_markup=kbd_wg()); return ConversationHandler.END

@check_access
async def wg_deluser_begin(u,c):
    await u.message.reply_text("🗑 Имя пира для удаления:",reply_markup=ReplyKeyboardRemove()); return WG_DELUSER_NAME

@check_access
async def wg_deluser_name(u,c):
    c.user_data['wg_del_name']=u.message.text.strip()
    await u.message.reply_text(f"🔐 Удалить {c.user_data['wg_del_name']}? Введите PIN:"); return WG_DELUSER_PIN

@check_access
async def wg_deluser_pin(u,c):
    name=c.user_data.get('wg_del_name','?')
    if u.message.text.strip()==config.admin_pin:
        msg=await u.message.reply_text(f"⏳ Удаляю {name}…")
        ok,out=run_cmd(f"wv deluser {name}")
        await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}")
        db.log_command("tg",u.effective_user.id,f"wg deluser {name}",out[:100],ok)
    else:
        db.log_command("tg",u.effective_user.id,f"wg deluser {name}","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN")
    await u.message.reply_text("Туннель:",reply_markup=kbd_wg()); return ConversationHandler.END

# ── Медиасервер ───────────────────────────────────────────────
@check_access
async def vkpanel_menu(u,c):
    if not user_can(u.effective_user.id,"vkpanel"):
        await u.message.reply_text("⛔ Медиасервер только для администратора"); return
    await u.message.reply_text("📡 <b>Медиасервер</b>",parse_mode="HTML",reply_markup=kbd_vkpanel())

@check_access
async def vkpanel_start(u,c):
    msg=await u.message.reply_text("⏳"); ok,out=run_vkpanel(1)
    await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}"); db.log_command("tg",u.effective_user.id,"vkpanel start",out[:100],ok)

@check_access
async def vkpanel_restart(u,c):
    msg=await u.message.reply_text("⏳"); ok,out=run_vkpanel(3)
    await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}"); db.log_command("tg",u.effective_user.id,"vkpanel restart",out[:100],ok)

@check_access
async def vkpanel_status(u,c):
    msg=await u.message.reply_text("⏳"); ok,out=run_vkpanel(4)
    await msg.edit_text(f"📊 МС:\n{out or '—'}"); db.log_command("tg",u.effective_user.id,"vkpanel status",out[:100],ok)

@check_access
async def vkpanel_logs(u,c):
    msg=await u.message.reply_text("⏳"); ok,out=run_vkpanel(5)
    await msg.edit_text(f"📋 Логи МС:\n<code>{out or '—'}</code>",parse_mode="HTML")
    db.log_command("tg",u.effective_user.id,"vkpanel logs",out[:50],ok)

@check_access
async def vkpanel_qr(u,c):
    import re as _re
    msg=await u.message.reply_text("⏳ QR…"); ok,out=run_vkpanel(13,timeout=25)
    urls=_re.findall(r'https?://\S+',out); url=urls[0].rstrip(')') if urls else None
    if url:
        try:
            png=make_qr_bytes(url)
            await u.message.reply_photo(photo=io.BytesIO(png),caption=f"📱 МС\n{url}")
            await msg.delete()
            db.log_command("tg",u.effective_user.id,"vkpanel qr",f"url={url[:80]}",True)
        except Exception as e: await msg.edit_text(f"❌ {e}")
    else: await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}")

@check_access
async def vkpanel_stop_begin(u,c):
    await u.message.reply_text("🔐 PIN для остановки МС:",reply_markup=ReplyKeyboardRemove()); return VKPANEL_STOP_PIN

@check_access
async def vkpanel_stop_pin(u,c):
    if u.message.text.strip()==config.admin_pin:
        msg=await u.message.reply_text("⏳ Остановка МС…"); ok,out=run_vkpanel(2)
        await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}"); db.log_command("tg",u.effective_user.id,"vkpanel stop",out[:100],ok)
    else:
        db.log_command("tg",u.effective_user.id,"vkpanel stop","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN")
    await u.message.reply_text("Медиасервер:",reply_markup=kbd_vkpanel()); return ConversationHandler.END

# ── X-UI ─────────────────────────────────────────────────────
@check_access
async def xui_menu(u,c):
    if not user_can(u.effective_user.id,"xui"):
        await u.message.reply_text("⛔ Ядро только для администратора"); return
    await u.message.reply_text("⚙️ <b>Ядро</b>",parse_mode="HTML",reply_markup=kbd_xui())

@check_access
async def xui_status(u,c):
    msg=await u.message.reply_text("⏳"); ok,out=run_xui(15)
    await msg.edit_text(f"📊 Ядро:\n<code>{out or '—'}</code>",parse_mode="HTML")
    db.log_command("tg",u.effective_user.id,"xui status",out[:100],ok)

@check_access
async def xui_restart(u,c):
    msg=await u.message.reply_text("⏳ Рестарт…"); ok,out=run_xui(13)
    await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}"); db.log_command("tg",u.effective_user.id,"xui restart",out[:100],ok)

@check_access
async def xui_logs(u,c):
    msg=await u.message.reply_text("⏳"); ok,out=run_xui(16)
    await msg.edit_text(f"📋 Логи ядра:\n<code>{out or '—'}</code>",parse_mode="HTML")
    db.log_command("tg",u.effective_user.id,"xui logs",out[:50],ok)

@check_access
async def xui_settings(u,c):
    msg=await u.message.reply_text("⏳"); ok,out=run_xui(10)
    await msg.edit_text(f"⚙️ Настройки ядра:\n<code>{out or '—'}</code>",parse_mode="HTML")
    db.log_command("tg",u.effective_user.id,"xui settings",out[:100],ok)

@check_access
async def xui_stop_begin(u,c):
    await u.message.reply_text("🔐 PIN для остановки ядра:",reply_markup=ReplyKeyboardRemove()); return XUI_STOP_PIN

@check_access
async def xui_stop_pin(u,c):
    if u.message.text.strip()==config.admin_pin:
        msg=await u.message.reply_text("⏳ Остановка ядра…"); ok,out=run_xui(12)
        await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}"); db.log_command("tg",u.effective_user.id,"xui stop",out[:100],ok)
    else:
        db.log_command("tg",u.effective_user.id,"xui stop","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN")
    await u.message.reply_text("Ядро:",reply_markup=kbd_xui()); return ConversationHandler.END

@check_access
async def xui_port_begin(u,c):
    await u.message.reply_text("🔐 PIN для смены порта:",reply_markup=ReplyKeyboardRemove()); return XUI_PORT_PIN

@check_access
async def xui_port_pin(u,c):
    if u.message.text.strip()==config.admin_pin:
        await u.message.reply_text("🔌 Новый порт (1–65535):"); return XUI_PORT_INPUT
    db.log_command("tg",u.effective_user.id,"xui port","неверный PIN",False)
    await u.message.reply_text("❌ Неверный PIN",reply_markup=kbd_xui()); return ConversationHandler.END

@check_access
async def xui_port_input(u,c):
    try:
        port=int(u.message.text.strip()); assert 1<=port<=65535
    except:
        await u.message.reply_text("❌ Неверный порт (1–65535):"); return XUI_PORT_INPUT
    msg=await u.message.reply_text(f"⏳ Меняю порт на {port}…")
    try:
        r=subprocess.run(f'printf "9\\n{port}\\n" | x-ui',shell=True,capture_output=True,text=True,timeout=20,
                        env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
        out=(r.stdout+r.stderr).strip()[:4000]; ok=r.returncode==0
    except Exception as e: ok=False; out=str(e)
    await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}")
    db.log_command("tg",u.effective_user.id,f"xui port {port}",out[:100],ok)
    await u.message.reply_text("Ядро:",reply_markup=kbd_xui()); return ConversationHandler.END

@check_access
async def xui_reset_begin(u,c):
    await u.message.reply_text("🔐 PIN для сброса ядра:",reply_markup=ReplyKeyboardRemove()); return XUI_RESET_PIN

@check_access
async def xui_reset_pin(u,c):
    if u.message.text.strip()==config.admin_pin:
        msg=await u.message.reply_text("⏳ Сброс ядра…"); ok,out=run_xui(8)
        await msg.edit_text(f"{'✅' if ok else '❌'} {out or '—'}"); db.log_command("tg",u.effective_user.id,"xui reset",out[:100],ok)
    else:
        db.log_command("tg",u.effective_user.id,"xui reset","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN")
    await u.message.reply_text("Ядро:",reply_markup=kbd_xui()); return ConversationHandler.END


# ── TG Каналы (просмотр постов публичных каналов) ────────────
TG_CHANNELS_FILE = BASE_DIR / "tg_channels.json"

def load_tg_channels():
    if TG_CHANNELS_FILE.exists():
        try: return json.load(open(TG_CHANNELS_FILE))
        except: pass
    return {"channels":{}}

def save_tg_channels(data):
    with open(TG_CHANNELS_FILE,"w") as f: json.dump(data,f,indent=2,ensure_ascii=False)

def _fetch_tg_channel_posts(slug, before_id=None, limit=8):
    import requests as req
    try:
        url=f"https://t.me/s/{slug}"
        if before_id: url+=f"?before={before_id}"
        r=req.get(url,headers={"User-Agent":"Mozilla/5.0"},timeout=15)
        if r.status_code!=200: return []
        posts=[]
        # Use double-quote only patterns to avoid heredoc issues
        ids=re.findall(r"data-post=[^/]+/([0-9]+)[^0-9]",r.text)
        raw_texts=re.findall(r"tgme_widget_message_text[^>]*>(.*?)</div>",r.text,re.DOTALL)
        dates=re.findall(r"datetime=.([0-9T:+\-]{10,})",r.text)
        has_video="video_thumb" in r.text or "tgme_widget_message_video" in r.text
        def clean(s):
            s=re.sub(r"<br\s*/?>","\n",s)
            s=re.sub(r"<[^>]+>","",s)
            for ent,ch in [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&#39;","'"),("&quot;",'"')]:
                s=s.replace(ent,ch)
            return s.strip()
        for i,pid in enumerate(ids[:limit]):
            text=clean(raw_texts[i]) if i<len(raw_texts) else ""
            date=dates[i][:10] if i<len(dates) else ""
            preview=text[:80].replace("\n"," ")+("…" if len(text)>80 else "")
            posts.append({"id":pid,"preview":preview or "(медиа)","text":text[:500],
                          "date":date,"url":f"https://t.me/{slug}/{pid}",
                          "has_video":has_video})
        return posts
    except Exception as e:
        logger.warning(f"fetch_tg_posts {slug}: {e}"); return []


def kbd_tg_channels():
    return ReplyKeyboardMarkup([
        [KeyboardButton("📋 Мои TG каналы"),   KeyboardButton("➕ Добавить TG канал")],
        [KeyboardButton("➖ Удалить TG канал")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

@check_access
async def tg_channels_menu(u,c):
    data=load_tg_channels(); ch=data.get("channels",{})
    lines=["📡 <b>TG Каналы</b>\n\nПросмотр постов публичных каналов.\n"]
    if ch:
        for slug,info in ch.items(): lines.append(f"• @{slug}")
    await u.message.reply_text("\n".join(lines),parse_mode="HTML",reply_markup=kbd_tg_channels())

@check_access
async def tg_channels_list(u,c):
    data=load_tg_channels(); channels=data.get("channels",{})
    if not channels:
        await u.message.reply_text("📭 Нет каналов\n\nДобавь через ➕",reply_markup=kbd_tg_channels()); return ConversationHandler.END
    lines=["📋 <b>Выбери канал:</b>\n"]
    items=list(channels.items())
    for i,(slug,ch) in enumerate(items,1): lines.append(f"{i}. {ch.get('name','@'+slug)}")
    await u.message.reply_text("\n".join(lines)+"\n\nВведи номер:",parse_mode="HTML",reply_markup=kbd_back())
    c.user_data["tg_chan_list"]=items
    return TG_CHAN_BROWSE

@check_access
async def tg_channels_add_begin(u,c):
    await u.message.reply_text("➕ Введи @username канала (например @AEROCEtg):",reply_markup=kbd_back())
    return TG_CHAN_SUB_INPUT

async def tg_channels_add_end(u,c):
    text=u.message.text.strip()
    if text in ("« Назад","📡 TG Каналы"):
        await u.message.reply_text("📡 TG Каналы",reply_markup=kbd_tg_channels()); return ConversationHandler.END
    slug=text.lstrip("@").split("/")[-1].split("?")[0].strip()
    await u.message.reply_text(f"⏳ Проверяю @{slug}...")
    loop=asyncio.get_event_loop()
    posts=await loop.run_in_executor(None,_fetch_tg_channel_posts,slug,None,3)
    if not posts:
        await u.message.reply_text(f"❌ @{slug} не найден или закрыт (только публичные каналы)",reply_markup=kbd_tg_channels())
        return ConversationHandler.END
    data=load_tg_channels()
    data["channels"][slug]={"name":f"@{slug}","slug":slug}
    save_tg_channels(data)
    await u.message.reply_text(f"✅ @{slug} добавлен!\n\nПоследний: {posts[0]['preview']}",reply_markup=kbd_tg_channels())
    return ConversationHandler.END

@check_access
async def tg_channels_remove(u,c):
    data=load_tg_channels(); channels=data.get("channels",{})
    if not channels:
        await u.message.reply_text("📭 Нет каналов",reply_markup=kbd_tg_channels()); return ConversationHandler.END
    slugs=list(channels.keys())
    lines=["➖ <b>Удалить:</b>\n"]
    for i,slug in enumerate(slugs,1): lines.append(f"{i}. @{slug}")
    await u.message.reply_text("\n".join(lines)+"\n\nВведи номер:",parse_mode="HTML",reply_markup=kbd_back())
    c.user_data["tg_chan_remove_list"]=slugs
    return TG_CHAN_PICK

async def tg_chan_browse_pick(u,c):
    text=u.message.text.strip()
    if text in ("« Назад","📡 TG Каналы"):
        c.user_data.pop("tg_chan_list",None)
        await u.message.reply_text("📡 TG Каналы",reply_markup=kbd_tg_channels()); return ConversationHandler.END
    chan_list=c.user_data.get("tg_chan_list",[])
    try:
        n=int(text)-1
        if not 0<=n<len(chan_list): await u.message.reply_text(f"❌ Номер 1-{len(chan_list)}"); return TG_CHAN_BROWSE
        slug,ch=chan_list[n]
        msg=await u.message.reply_text(f"⏳ Загружаю посты @{slug}...")
        loop=asyncio.get_event_loop()
        posts=await loop.run_in_executor(None,_fetch_tg_channel_posts,slug,None)
        if not posts:
            await msg.edit_text("❌ Посты не получены"); return TG_CHAN_BROWSE
        lines=[f"📡 <b>@{slug}</b>:\n"]
        for i,p in enumerate(posts,1):
            vid="🎬 " if p.get("has_video") else ""
            lines.append(f"{i}. {vid}{p['date']} — {p['preview']}\n   {p['url']}")
        c.user_data["tg_cur_slug"]=slug; c.user_data[f"tg_posts"]=posts
        c.user_data[f"tg_oldest_id"]=posts[-1]["id"]
        await msg.edit_text("\n\n".join(lines)+"\n\n▶️ Номер поста · 'старше' · « Назад",
                            parse_mode="HTML",disable_web_page_preview=True)
        return TG_CHAN_PICK
    except: await u.message.reply_text("❌ Введи число"); return TG_CHAN_BROWSE

async def tg_chan_post_pick(u,c):
    text=u.message.text.strip()
    slug=c.user_data.get("tg_cur_slug","")
    # Удаление
    remove_list=c.user_data.get("tg_chan_remove_list")
    if remove_list:
        if text in ("« Назад","📡 TG Каналы"):
            c.user_data.pop("tg_chan_remove_list",None)
            await u.message.reply_text("📡 TG Каналы",reply_markup=kbd_tg_channels()); return ConversationHandler.END
        try:
            n=int(text)-1
            if not 0<=n<len(remove_list): await u.message.reply_text(f"❌ Номер 1-{len(remove_list)}"); return TG_CHAN_PICK
            sl=remove_list[n]; data=load_tg_channels(); data["channels"].pop(sl,None); save_tg_channels(data)
            c.user_data.pop("tg_chan_remove_list",None)
            await u.message.reply_text(f"✅ @{sl} удалён",reply_markup=kbd_tg_channels()); return ConversationHandler.END
        except: await u.message.reply_text("❌ Введи число"); return TG_CHAN_PICK
    if text in ("« Назад","📡 TG Каналы"):
        await u.message.reply_text("📡 TG Каналы",reply_markup=kbd_tg_channels()); return ConversationHandler.END
    posts=c.user_data.get("tg_posts",[])
    if text.lower() in ("старше","older"):
        oldest=c.user_data.get("tg_oldest_id")
        msg=await u.message.reply_text("⏳ Загружаю старые посты...")
        loop=asyncio.get_event_loop()
        old_posts=await loop.run_in_executor(None,_fetch_tg_channel_posts,slug,oldest)
        if not old_posts: await msg.edit_text("❌ Больше постов нет"); return TG_CHAN_PICK
        lines=[f"📡 <b>@{slug}</b> (старые):\n"]
        for i,p in enumerate(old_posts,1):
            vid="🎬 " if p.get("has_video") else ""
            lines.append(f"{i}. {vid}{p['date']} — {p['preview']}\n   {p['url']}")
        c.user_data["tg_posts"]=old_posts; c.user_data["tg_oldest_id"]=old_posts[-1]["id"]
        await msg.edit_text("\n\n".join(lines)+"\n\n▶️ Номер · 'старше' · « Назад",
                            parse_mode="HTML",disable_web_page_preview=True)
        return TG_CHAN_PICK
    try:
        n=int(text)-1
        if not 0<=n<len(posts): await u.message.reply_text(f"❌ Номер 1-{len(posts)}"); return TG_CHAN_PICK
        p=posts[n]; body=p.get("text","") or p["preview"]
        vid_note="\n\n🎬 Есть видео — отправь ссылку боту для скачивания:" if p.get("has_video") else ""
        await u.message.reply_text(
            f"📄 @{slug}/{p['id']}  📅 {p['date']}\n\n{body}{vid_note}\n\n🔗 {p['url']}",
            disable_web_page_preview=True,reply_markup=kbd_back())
        return TG_CHAN_PICK
    except: await u.message.reply_text("❌ Введи число"); return TG_CHAN_PICK


# ── GitHub обновление ────────────────────────────────────────
@admin_only
async def tg_admin_github_update(u,c):
    await u.message.reply_text(
        "⏳ Запускаю обновление с GitHub...\n\nБот перезапустится автоматически. Подожди ~30 секунд.",
        reply_markup=kbd_admin())
    async def _do_update():
        try:
            loop=asyncio.get_event_loop()
            r=await loop.run_in_executor(None,lambda: subprocess.run(
                ["bash","/root/yabot_installer.sh","--github-force"],
                capture_output=True,text=True,timeout=120,
                env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"}))
            logger.info(f"github update: rc={r.returncode} {(r.stdout+r.stderr)[-200:]}")
        except Exception as e:
            logger.error(f"github update error: {e}")
    asyncio.create_task(_do_update())
    return TG_ADMIN_MENU_STATE

# ── Cron ─────────────────────────────────────────────────────
def update_cron():
    try:
        r=subprocess.run(["crontab","-l"],capture_output=True,text=True)
        cur=r.stdout if r.returncode==0 else ""
        lines=[l for l in cur.split("\n") if "# VM_BOT" not in l and l.strip()]
        py=str(TG_DIR/"venv/bin/python3"); sc=str(Path(__file__).resolve())
        db_sc=str(BASE_DIR/"db_module.py")
        if schedule_config.auto_start_enabled:
            h,m=schedule_config.start_time.split(":")
            lines.append(f"{m} {h} * * * PATH=/usr/local/bin:/usr/bin:/bin {py} {sc} --start # VM_BOT")
        if schedule_config.auto_stop_enabled:
            h,m=schedule_config.stop_time.split(":")
            lines.append(f"{m} {h} * * * PATH=/usr/local/bin:/usr/bin:/bin {py} {sc} --stop # VM_BOT")
        lines.append(f"0 3 * * * {py} {db_sc} --cleanup # VM_BOT")
        subprocess.run(["crontab","-"],input="\n".join(lines)+"\n",text=True,check=True)
    except Exception as e: logger.error(f"Cron error: {e}")

# ── main() ───────────────────────────────────────────────────
def main():
    if not config.bot_token: print("❌ Нет токена TG"); return
    if not config.vm_id: print("❌ Нет VM ID"); return
    update_cron()
    app=Application.builder().token(config.bot_token).build()
    H=app.add_handler

    # ConversationHandlers
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🕐 Время запуска$"),set_start_begin)],
        states={SET_START_TIME:[MessageHandler(filters.TEXT&~filters.COMMAND,set_start_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🕐 Время остановки$"),set_stop_begin)],
        states={SET_STOP_TIME:[MessageHandler(filters.TEXT&~filters.COMMAND,set_stop_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex(r"^⏱ Срок:"),set_retention_begin)],
        states={SET_RETENTION:[MessageHandler(filters.TEXT&~filters.COMMAND,set_retention_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🗑️ Удалить бота с сервера$"),delete_bot_begin)],
        states={AWAIT_DELETE_PIN:[MessageHandler(filters.TEXT&~filters.COMMAND,delete_bot_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^💻 Терминал$"),console_menu)],
        states={CONSOLE_INPUT:[MessageHandler(filters.TEXT&~filters.COMMAND,console_exec)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^➕ Новый пир$"),wg_adduser_begin)],
        states={WG_ADDUSER_NAME:[MessageHandler(filters.TEXT&~filters.COMMAND,wg_adduser_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^📥 Экспорт$"),wg_getuser_begin)],
        states={WG_GETUSER_NAME:[MessageHandler(filters.TEXT&~filters.COMMAND,wg_getuser_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🗑 Удалить пир$"),wg_deluser_begin)],
        states={WG_DELUSER_NAME:[MessageHandler(filters.TEXT&~filters.COMMAND,wg_deluser_name)],
                WG_DELUSER_PIN: [MessageHandler(filters.TEXT&~filters.COMMAND,wg_deluser_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^⏹ МС-стоп$"),vkpanel_stop_begin)],
        states={VKPANEL_STOP_PIN:[MessageHandler(filters.TEXT&~filters.COMMAND,vkpanel_stop_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^⏹ Ядро-стоп$"),xui_stop_begin)],
        states={XUI_STOP_PIN:[MessageHandler(filters.TEXT&~filters.COMMAND,xui_stop_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🔌 Ядро-порт$"),xui_port_begin)],
        states={XUI_PORT_PIN:  [MessageHandler(filters.TEXT&~filters.COMMAND,xui_port_pin)],
                XUI_PORT_INPUT:[MessageHandler(filters.TEXT&~filters.COMMAND,xui_port_input)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🔃 Ядро-сброс$"),xui_reset_begin)],
        states={XUI_RESET_PIN:[MessageHandler(filters.TEXT&~filters.COMMAND,xui_reset_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    # YouTube inline (автодетект ссылок)
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex(r'https?://((www|m)\.)?youtube\.com/\S+|https?://youtu\.be/\S+'),yt_inline)],
        states={TG_YT_DUB: [MessageHandler(filters.TEXT&~filters.COMMAND,_yt_dub_handler)],
                TG_YT_QUAL:[MessageHandler(filters.TEXT&~filters.COMMAND,_yt_qual_handler)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    # YouTube меню
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🎬 YouTube$"),yt_menu_show)],
        states={
            TG_YT_SEARCH:      [MessageHandler(filters.TEXT&~filters.COMMAND,yt_search_end)],
            TG_YT_SEARCH_PICK: [MessageHandler(filters.TEXT&~filters.COMMAND,yt_search_pick)],
            TG_YT_CHAN:        [MessageHandler(filters.TEXT&~filters.COMMAND,yt_channel_end)],
            TG_YT_CHAN_PICK:   [MessageHandler(filters.TEXT&~filters.COMMAND,yt_channel_pick)],
            TG_YT_DUB:        [MessageHandler(filters.TEXT&~filters.COMMAND,_yt_dub_handler)],
            TG_YT_QUAL:       [MessageHandler(filters.TEXT&~filters.COMMAND,_yt_qual_handler)],
            TG_YT_SUB:        [MessageHandler(filters.TEXT&~filters.COMMAND,yt_subscribe_end)],
            TG_YT_UNSUB_PICK: [MessageHandler(filters.TEXT&~filters.COMMAND,yt_unsubscribe_pick)],
        },
        fallbacks=[CommandHandler("cancel",cancel_h),
                   MessageHandler(filters.Regex("^« Назад$"),cancel_h)]))
    # Администрирование
    H(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^👮 Администрирование$"),tg_admin_menu)],
        states={
            TG_ADMIN_MENU_STATE:[
                MessageHandler(filters.Regex("^➕ Добавить пользователя$"),tg_admin_add_begin),
                MessageHandler(filters.Regex("^➖ Удалить пользователя$"),tg_admin_remove_begin),
                MessageHandler(filters.Regex("^📋 Список пользователей$"),tg_admin_list_h),
                MessageHandler(filters.Regex("^🔧 Функции пользователей$"),tg_admin_features_begin),
                MessageHandler(filters.Regex("^📢 Рассылка$"),tg_admin_broadcast_begin),
                MessageHandler(filters.Regex("^⬆️ Обновить с GitHub$"),tg_admin_github_update),
                MessageHandler(filters.Regex("^« Назад$"),cancel_h),
            ],
            TG_ADMIN_ADD:        [MessageHandler(filters.TEXT&~filters.COMMAND,tg_admin_add_mid)],
            TG_ADMIN_ADD_PIN:    [MessageHandler(filters.TEXT&~filters.COMMAND,tg_admin_add_pin)],
            TG_ADMIN_REMOVE:     [MessageHandler(filters.TEXT&~filters.COMMAND,tg_admin_remove_mid)],
            TG_ADMIN_REMOVE_PIN: [MessageHandler(filters.TEXT&~filters.COMMAND,tg_admin_remove_pin)],
            TG_ADMIN_FEATURES:   [MessageHandler(filters.TEXT&~filters.COMMAND,tg_admin_features_end)],
            TG_ADMIN_BROADCAST:  [MessageHandler(filters.TEXT&~filters.COMMAND,tg_admin_broadcast_end)],
        },
        fallbacks=[CommandHandler("cancel",cancel_h)],
        per_message=False))

    # TG Каналы
    H(ConversationHandler(
        entry_points=[
            MessageHandler(filters.Regex("^📡 TG Каналы$"),tg_channels_menu),
            MessageHandler(filters.Regex("^📋 Мои TG каналы$"),tg_channels_list),
            MessageHandler(filters.Regex("^➕ Добавить TG канал$"),tg_channels_add_begin),
            MessageHandler(filters.Regex("^➖ Удалить TG канал$"),tg_channels_remove),
        ],
        states={
            TG_CHAN_BROWSE:    [MessageHandler(filters.TEXT&~filters.COMMAND,tg_chan_browse_pick)],
            TG_CHAN_PICK:      [MessageHandler(filters.TEXT&~filters.COMMAND,tg_chan_post_pick)],
            TG_CHAN_SUB_INPUT: [MessageHandler(filters.TEXT&~filters.COMMAND,tg_channels_add_end)],
        },
        fallbacks=[CommandHandler("cancel",cancel_h),
                   MessageHandler(filters.Regex("^« Назад$"),cancel_h)]))

    # Простые хэндлеры
    H(CommandHandler("start",start_command))
    H(MessageHandler(filters.Regex("^📊 Статус$"),status_handler))
    H(MessageHandler(filters.Regex("^ℹ️ Информация$"),info_handler))
    H(MessageHandler(filters.Regex("^▶️ Запустить$"),start_vm))
    H(MessageHandler(filters.Regex("^⏹ Остановить$"),stop_vm))
    H(MessageHandler(filters.Regex("^🔄 Перезапустить$"),restart_vm))
    H(MessageHandler(filters.Regex("^⏰ Расписание$"),schedule_h))
    H(MessageHandler(filters.Regex("^🟢 Автозапуск$|^🔴 Автозапуск$"),toggle_start))
    H(MessageHandler(filters.Regex("^🟢 Автоостановка$|^🔴 Автоостановка$"),toggle_stop))
    H(MessageHandler(filters.Regex("^🟦 VK бот$"),vk_menu))
    H(MessageHandler(filters.Regex("^▶️ Включить VK бота$"),vk_start))
    H(MessageHandler(filters.Regex("^⏹ Выключить VK бота$"),vk_stop))
    H(MessageHandler(filters.Regex("^🟢 VK активен$|^🔴 VK неактивен$"),vk_refresh))
    H(MessageHandler(filters.Regex("^📋 История$"),history_menu))
    H(MessageHandler(filters.Regex("^📜 Последние команды$"),history_show))
    H(MessageHandler(filters.Regex("^🤖 Авто-события$"),auto_events_show))
    H(MessageHandler(filters.Regex("^📊 Статистика БД$"),db_stats))
    H(MessageHandler(filters.Regex("^🗑️ Очистить историю$"),clear_history))
    H(MessageHandler(filters.Regex("^⚙️ Настройки$"),settings_menu))
    H(MessageHandler(filters.Regex("^🔒 Скрыть инструменты$|^🔓 Показать инструменты$"),toggle_sensitive))
    H(MessageHandler(filters.Regex("^🔑 Туннель$"),wg_menu))
    H(MessageHandler(filters.Regex("^👥 Пиры$"),wg_listusers))
    H(MessageHandler(filters.Regex("^📡 Медиасервер$"),vkpanel_menu))
    H(MessageHandler(filters.Regex("^▶️ МС-старт$"),vkpanel_start))
    H(MessageHandler(filters.Regex("^🔄 МС-рестарт$"),vkpanel_restart))
    H(MessageHandler(filters.Regex("^📊 МС-статус$"),vkpanel_status))
    H(MessageHandler(filters.Regex("^📋 МС-логи$"),vkpanel_logs))
    H(MessageHandler(filters.Regex("^📱 МС-QR$"),vkpanel_qr))
    H(MessageHandler(filters.Regex("^⚙️ Ядро$"),xui_menu))
    H(MessageHandler(filters.Regex("^📊 Ядро-статус$"),xui_status))
    H(MessageHandler(filters.Regex("^🔄 Ядро-рестарт$"),xui_restart))
    H(MessageHandler(filters.Regex("^📋 Ядро-логи$"),xui_logs))
    H(MessageHandler(filters.Regex("^🔧 Ядро-настройки$"),xui_settings))
    H(MessageHandler(filters.Regex("^🔧 Инструменты$"),tools_menu))
    H(MessageHandler(filters.Regex("^« Назад$"),back_main))
    # YouTube меню — кнопки внутри меню (вне ConversationHandler)
    H(MessageHandler(filters.Regex("^🔍 Поиск видео$"),yt_search_begin))
    H(MessageHandler(filters.Regex("^▶️ Последние видео канала$"),yt_channel_begin))
    H(MessageHandler(filters.Regex("^📺 Мои подписки$"),yt_unsubscribe_begin))
    H(MessageHandler(filters.Regex("^➕ Подписаться на канал$"),yt_subscribe_begin))
    H(MessageHandler(filters.Regex("^➖ Отписаться от канала$"),yt_unsubscribe_begin))
    # Админ — кнопки

    logger.info("TG бот запущен v5.0"); print("✅ TG бот v5.0 запущен!")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__=="__main__":
    if len(sys.argv)>1:
        if sys.argv[1]=="--start":
            ok,m=YandexCloudVM.start(); db.log_auto_event("auto_start",m,ok); sys.exit(0 if ok else 1)
        elif sys.argv[1]=="--stop":
            ok,m=YandexCloudVM.stop(); db.log_auto_event("auto_stop",m,ok); sys.exit(0 if ok else 1)
    main()

TGEOF
}


# ─────────────────────────────────────────────────────────────
# PYTHON: VK БОТ
# ─────────────────────────────────────────────────────────────

create_vk_bot_script() {
    cat > "$VK_DIR/vk_bot.py" << 'VKEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""VK бот управления ВМ Яндекс.Облака. v5.0
Новое: SSH-загрузка YouTube через NL VPS, подписки на каналы,
       поиск YouTube, система ролей/whitelist, изоляция VM-контроля.
"""

import json,os,random,subprocess,logging,time,sys,threading,io,re,tempfile,glob
from pathlib import Path
import vk_api
from vk_api.bot_longpoll import VkBotLongPoll,VkBotEventType

BASE_DIR=Path("/opt/vm_manager"); VK_DIR=BASE_DIR/"vk"
CONFIG_FILE=BASE_DIR/"config.json"; LOG_FILE=VK_DIR/"bot.log"
ADMIN_FILE=BASE_DIR/"admins.json"; YT_SUBS_FILE=BASE_DIR/"yt_subs.json"
BASE_DIR.mkdir(parents=True,exist_ok=True); VK_DIR.mkdir(parents=True,exist_ok=True)

sys.path.insert(0,str(BASE_DIR))
import db_module as db
db.init_db()

SETTINGS_FILE=BASE_DIR/"settings.json"

def get_sensitive():
    try:
        if SETTINGS_FILE.exists(): return json.load(open(SETTINGS_FILE)).get("sensitive_mode",False)
    except: pass
    return False

def set_sensitive(val):
    s={}
    try:
        if SETTINGS_FILE.exists(): s=json.load(open(SETTINGS_FILE))
    except: pass
    s["sensitive_mode"]=val
    with open(SETTINGS_FILE,"w") as f: json.dump(s,f)

logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s",level=logging.INFO,
    handlers=[logging.FileHandler(LOG_FILE),logging.StreamHandler()])
logger=logging.getLogger(__name__)

def load_cfg():
    with open(CONFIG_FILE) as f: d=json.load(f)
    v=d.get("vk") or {}
    ssh=d.get("ssh_vps") or {}
    return {"vm_id":d.get("vm_id",""),"folder_id":d.get("folder_id",""),
            "admin_pin":d.get("admin_pin",""),
            "group_token":v.get("group_token",""),"group_id":int(v.get("group_id",0)),
            "allowed_users":[int(u) for u in v.get("allowed_users",[])],
            "user_token":v.get("user_token",""),
            "yadisk_token":v.get("yadisk_token",""),
            "tg_installed":"tg" in (d.get("installed") or []),
            "ssh_host":ssh.get("host",""),"ssh_user":ssh.get("user","root"),
            "ssh_port":int(ssh.get("port",22)),"ssh_key":ssh.get("key_path","")}

cfg=load_cfg()
# ── TG Мост: DB helpers ───────────────────────────────────────
import sqlite3 as _sqlite3

BRIDGE_DB = BASE_DIR / "tg_bridge" / "bridge_queue.db"

def _bdb():
    if not BRIDGE_DB.exists(): return None
    c = _sqlite3.connect(str(BRIDGE_DB), timeout=5)
    c.row_factory = _sqlite3.Row
    return c

def bridge_queue_cmd(cmd, chat_id=None, text=None, file_path=None,
                     reply_to=None, fwd_chat=None, fwd_msg=None):
    c = _bdb()
    if not c: return False
    try:
        c.execute("INSERT INTO outgoing (cmd,chat_id,text,file_path,reply_to,fwd_chat,fwd_msg)"
                  " VALUES (?,?,?,?,?,?,?)",
                  (cmd, chat_id, text, file_path, reply_to, fwd_chat, fwd_msg))
        c.commit(); c.close(); return True
    except Exception as e:
        logger.error(f"bridge_queue_cmd: {e}"); return False

def bridge_get_known_chats():
    c = _bdb()
    if not c: return []
    rows = list(c.execute("SELECT chat_id, chat_name, active FROM known_chats ORDER BY chat_name"))
    c.close(); return rows

def bridge_set_active(chat_id, active):
    c = _bdb()
    if not c: return
    c.execute("UPDATE known_chats SET active=? WHERE chat_id=?", (1 if active else 0, chat_id))
    c.commit(); c.close()

def bridge_get_msg(ref):
    c = _bdb()
    if not c: return None
    row = c.execute("SELECT tg_chat_id,tg_msg_id,sender,chat_name FROM msg_map WHERE ref=?",
                    (ref,)).fetchone()
    c.close()
    return dict(row) if row else None

def bridge_get_history(chat_id, limit=100):
    c = _bdb()
    if not c: return []
    rows = list(c.execute(
        "SELECT ref,sender,chat_name,ts FROM msg_map WHERE tg_chat_id=? ORDER BY rowid DESC LIMIT ?",
        (chat_id, limit)))
    c.close(); return rows

def bridge_is_running():
    try:
        r=subprocess.run(["systemctl","is-active","vm-bridge-tg"],capture_output=True,text=True)
        return r.stdout.strip()=="active"
    except: return False

def _show_bridge_chats(vk, uid, chats):
    send(vk, uid,
         "\u0427\u0430\u0442\u044b TG (\u2705 = \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f, \u2b1c = \u0432\u044b\u043a\u043b):",
         kbd_tg_bridge_chats(chats))


states:dict[int,str]={}
pending:dict[int,dict]={}
vk_session_global=None

# ── Система ролей ─────────────────────────────────────────────
def load_admin():
    if ADMIN_FILE.exists():
        try: return json.load(open(ADMIN_FILE))
        except: pass
    # Первый запуск — VM-функции только для владельца
    return {"extra_users":[],"user_labels":{},
            "disabled_features":{},
            "global_disabled":["vm_control","terminal","tunnel","xui","vkpanel"]}

def save_admin(data):
    with open(ADMIN_FILE,"w") as f: json.dump(data,f,indent=2,ensure_ascii=False)

def is_admin(uid):
    return uid in cfg["allowed_users"]

def get_all_users():
    base=list(cfg["allowed_users"])
    extra=load_admin().get("extra_users",[])
    return list(dict.fromkeys(base+[int(u) for u in extra]))

def user_can(uid,feature):
    if is_admin(uid): return True
    data=load_admin()
    if feature in data.get("global_disabled",[]): return False
    return feature not in data.get("disabled_features",{}).get(str(uid),[])

def resolve_vk_user(vk_obj,page_str):
    """VK page URL/username → (uid, display_name)"""
    s=re.sub(r'https?://(www\.)?vk\.com/','',page_str.strip()).strip('/').split('?')[0].strip()
    if s.startswith('id') and s[2:].isdigit():
        uid=int(s[2:])
        try:
            info=vk_obj.users.get(user_ids=uid,fields="first_name,last_name")
            name=f"{info[0]['first_name']} {info[0]['last_name']}" if info else s
        except: name=s
        return uid,name
    try:
        r=vk_obj.utils.resolveScreenName(screen_name=s)
        if r and r.get("type")=="user":
            uid=r["object_id"]
            info=vk_obj.users.get(user_ids=uid,fields="first_name,last_name")
            name=f"{info[0]['first_name']} {info[0]['last_name']}" if info else s
            return uid,name
    except Exception as e:
        logger.warning(f"resolve_vk_user: {e}")
    return None,None

# ── YouTube подписки ──────────────────────────────────────────
def load_yt_subs():
    if YT_SUBS_FILE.exists():
        try: return json.load(open(YT_SUBS_FILE))
        except: pass
    return {"channels":{}}

def save_yt_subs(data):
    with open(YT_SUBS_FILE,"w") as f: json.dump(data,f,indent=2,ensure_ascii=False)


def _normalize_yt_channel(text):
    """Преобразует разные форматы ввода в YouTube URL."""
    text = text.strip()
    # VK-формат: "@id416991442 (@SatiAkura)" → берём username в скобках
    m = re.search(r'\(@([A-Za-z0-9_]+)\)', text)
    if m:
        text = f"@{m.group(1)}"
    # Просто @username → полный URL
    if re.match(r'^@[A-Za-z0-9_]+$', text):
        return f"https://www.youtube.com/{text}"
    # Уже URL — оставляем
    return text

def yt_get_channel_info(channel_url):
    """Возвращает (channel_id, channel_name, latest_5_videos)"""
    try:
        import yt_dlp as yt
        opts={"quiet":True,"no_warnings":True,"extract_flat":"in_playlist",
              "playlist_items":"1-10","noplaylist":False}
        with yt.YoutubeDL(opts) as ydl:
            info=ydl.extract_info(channel_url,download=False)
        cid=info.get("channel_id") or info.get("id","")
        cname=info.get("channel") or info.get("title","")
        videos=[]
        for e in (info.get("entries") or [])[:5]:
            if e:
                videos.append({"id":e.get("id",""),"title":e.get("title","")[:60],
                                "url":e.get("url") or f"https://youtu.be/{e.get('id','')}"})
        return cid,cname,videos
    except Exception as e:
        logger.warning(f"yt_get_channel_info: {e}")
        return None,None,[]

def yt_search(query,n=10):
    """Поиск YouTube. Возвращает список [{id,title,url,channel}]"""
    try:
        import yt_dlp as yt
        opts={"quiet":True,"no_warnings":True,"extract_flat":True,"noplaylist":True}
        with yt.YoutubeDL(opts) as ydl:
            info=ydl.extract_info(f"ytsearch{n}:{query}",download=False)
        results=[]
        for e in (info.get("entries") or []):
            if e:
                results.append({"id":e.get("id",""),"title":e.get("title","")[:60],
                                 "url":f"https://youtu.be/{e.get('id','')}",
                                 "channel":e.get("channel","")[:30]})
        return results
    except Exception as e:
        logger.warning(f"yt_search: {e}")
        return []

def _yt_check_subscriptions_thread():
    """Фоновый поток: каждые 30 мин проверяет новые видео."""
    time.sleep(60)  # старт через минуту после запуска
    while True:
        try:
            if vk_session_global is None: time.sleep(60); continue
            vk=vk_session_global.get_api()
            data=load_yt_subs()
            changed=False
            for cid,ch in data.get("channels",{}).items():
                try:
                    _,_,videos=yt_get_channel_info(ch.get("url","").rstrip('/')+'/videos' if not any(x in ch.get('url','') for x in ['/videos','/playlist','/shorts','/live','list=']) else ch.get('url',''))
                    if not videos: continue
                    latest_id=videos[0]["id"]
                    if latest_id and latest_id!=ch.get("last_video_id"):
                        # новое видео!
                        v=videos[0]
                        msg=(f"🔔 Новое видео на канале {ch.get('name',cid)}!\n\n"
                             f"🎬 {v['title']}\n🔗 {v['url']}")
                        for uid in ch.get("subscribers",[]):
                            try: vk.messages.send(user_id=uid,message=msg,random_id=random.randint(0,2**31))
                            except: pass
                        ch["last_video_id"]=latest_id; changed=True
                        logger.info(f"YT subs notify: {ch.get('name',cid)} → {v['title']}")
                except Exception as e:
                    logger.warning(f"subs check {cid}: {e}")
            if changed: save_yt_subs(data)
        except Exception as e:
            logger.error(f"subs thread: {e}")
        time.sleep(1800)  # 30 минут

# ── SSH-загрузка YouTube ──────────────────────────────────────
def _yt_download_via_ssh(url,fmt,tmp_dir):
    """Скачивает через SSH на NL VPS, SCP обратно. Возвращает (local_path, error_str)."""
    host=cfg.get("ssh_host",""); user=cfg.get("ssh_user","root")
    port=str(cfg.get("ssh_port",22)); key=cfg.get("ssh_key","")
    if not host: return None,"SSH не настроен"

    remote_tmp=f"/tmp/ytdl_{os.getpid()}_{int(time.time())}"
    remote_out=f"{remote_tmp}/%(title)s.%(ext)s"

    ssh_opts=["-o","StrictHostKeyChecking=no","-o","ConnectTimeout=30",
              "-o","BatchMode=yes","-p",port]
    if key: ssh_opts+=["-i",key]
    ssh_base=["ssh"]+ssh_opts+[f"{user}@{host}"]

    # yt-dlp на NL VPS (тот же путь)
    ytdlp_remote="/opt/vm_manager/tg/venv/bin/yt-dlp"
    if_ytdlp=subprocess.run(ssh_base+[f"test -f {ytdlp_remote} && echo ok || echo missing"],
                            capture_output=True,text=True,timeout=15)
    if "missing" in if_ytdlp.stdout:
        # Попробуем системный yt-dlp
        ytdlp_remote="yt-dlp"

    try:
        subprocess.run(ssh_base+[f"mkdir -p '{remote_tmp}'"],timeout=15,capture_output=True)
        yt_cmd=(f'{ytdlp_remote} -f "{fmt}" --merge-output-format mp4 '
                f'--postprocessor-args "ffmpeg:-c:v libx264 -preset ultrafast -crf 23 -c:a aac -threads 2" '
                f'--no-playlist --socket-timeout 30 -o "{remote_out}" --no-part '
                f'--restrict-filenames "{url}"')
        r=subprocess.run(ssh_base+[yt_cmd],capture_output=True,text=True,timeout=900)
        if r.returncode!=0:
            subprocess.run(ssh_base+[f"rm -rf '{remote_tmp}'"],timeout=15,capture_output=True)
            return None,(r.stderr or r.stdout)[-400:]

        # Найти скачанный файл
        ls_r=subprocess.run(ssh_base+[f"ls '{remote_tmp}/'"],capture_output=True,text=True,timeout=15)
        remote_files=[f.strip() for f in ls_r.stdout.strip().split("\n") if f.strip() and f.strip().endswith(".mp4")]
        if not remote_files:
            remote_files=[f.strip() for f in ls_r.stdout.strip().split("\n") if f.strip()]
        if not remote_files:
            subprocess.run(ssh_base+[f"rm -rf '{remote_tmp}'"],timeout=15,capture_output=True)
            return None,"Файл не найден на VPS после скачивания"

        remote_file=f"{remote_tmp}/{remote_files[0]}"
        local_file=os.path.join(tmp_dir,remote_files[0])

        scp_opts=["-o","StrictHostKeyChecking=no","-P",port]
        if key: scp_opts+=["-i",key]
        r2=subprocess.run(["scp"]+scp_opts+[f"{user}@{host}:{remote_file}",local_file],
                          capture_output=True,text=True,timeout=900)
        subprocess.run(ssh_base+[f"rm -rf '{remote_tmp}'"],timeout=15,capture_output=True)
        if r2.returncode!=0: return None,r2.stderr[-300:]
        return local_file,None
    except subprocess.TimeoutExpired:
        try: subprocess.run(ssh_base+[f"rm -rf '{remote_tmp}'"],timeout=10,capture_output=True)
        except: pass
        return None,"⏱ Таймаут SSH-загрузки"
    except Exception as e:
        return None,str(e)

def _show_schedule_vk(vk,uid):
    try:
        sc=json.load(open(BASE_DIR/"schedule.json")) if (BASE_DIR/"schedule.json").exists() else {}
    except: sc={}
    s="🟢" if sc.get("auto_start_enabled") else "🔴"
    p="🟢" if sc.get("auto_stop_enabled") else "🔴"
    send(vk,uid,
        f"⏰ Расписание ВМ\n\n"
        f"{s} Автозапуск: {'включён' if sc.get('auto_start_enabled') else 'выключен'} [{sc.get('start_time','09:00')}]\n"
        f"{p} Автоостановка: {'включена' if sc.get('auto_stop_enabled') else 'выключена'} [{sc.get('stop_time','22:00')}]",
        kbd_schedule_vk())

def _toggle_schedule_vk(key):
    path=BASE_DIR/"schedule.json"
    try: sc=json.load(open(path)) if path.exists() else {}
    except: sc={}
    sc[key]=not sc.get(key,False)
    for k,v in {"auto_start_enabled":False,"auto_stop_enabled":False,"start_time":"09:00","stop_time":"22:00"}.items():
        sc.setdefault(k,v)
    with open(path,"w") as f: json.dump(sc,f,indent=2)
    return sc[key]

def _set_schedule_time_vk(key,val):
    path=BASE_DIR/"schedule.json"
    try: sc=json.load(open(path)) if path.exists() else {}
    except: sc={}
    sc[key]=val
    with open(path,"w") as f: json.dump(sc,f,indent=2)

class VM:
    _ENV={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin:/root/yandex-cloud/bin"}
    @staticmethod
    def _run(cmd,t=60):
        try:
            r=subprocess.run(cmd,capture_output=True,text=True,timeout=t,env=VM._ENV)
            return (True,r.stdout.strip()) if r.returncode==0 else (False,r.stderr.strip())
        except subprocess.TimeoutExpired: return False,f"Таймаут {t}с"
        except Exception as e: return False,str(e)
    @staticmethod
    def status():
        ok,out=VM._run(["yc","compute","instance","get",cfg["vm_id"],"--format","json"])
        if ok:
            try: d=json.loads(out); return True,d.get("status","UNKNOWN"),d
            except: pass
        return False,out,None
    @staticmethod
    def start():
        import time as _t
        ok,s,_=VM.status()
        if not ok: return False,f"Нет статуса: {s}"
        if s=="RUNNING": return True,"ВМ уже запущена"
        if s not in ["STOPPED","STOPPING"]: return False,f"Невозможно: {s}"
        ok,out=VM._run(["yc","compute","instance","start",cfg["vm_id"]])
        return (True,"✅ ВМ запущена") if ok else (False,f"❌ {out}")
    @staticmethod
    def stop():
        ok,s,_=VM.status()
        if not ok: return False,f"Нет статуса: {s}"
        if s=="STOPPED": return True,"ВМ уже остановлена"
        if s not in ["RUNNING","STARTING"]: return False,f"Невозможно: {s}"
        ok,out=VM._run(["yc","compute","instance","stop",cfg["vm_id"]])
        return (True,"✅ ВМ остановлена") if ok else (False,f"❌ {out}")
    @staticmethod
    def restart():
        ok,s,_=VM.status()
        if not ok: return False,f"Нет статуса: {s}"
        if s!="RUNNING": return False,f"Нужен RUNNING, сейчас: {s}"
        ok,out=VM._run(["yc","compute","instance","restart",cfg["vm_id"]])
        return (True,"✅ ВМ перезапускается") if ok else (False,f"❌ {out}")
    @staticmethod
    def info():
        ok,s,d=VM.status()
        if not ok or not d: return False,"Нет данных"
        res=d.get("resources",{}); cores=res.get("cores","N/A")
        try: mem=int(res.get("memory",0))/(1024**3)
        except: mem=0
        ips=[]
        for iface in d.get("network_interfaces",[]):
            pv4=iface.get("primary_v4_address",{})
            if pv4.get("address"): ips.append(f"Внутренний: {pv4['address']}")
            nat=pv4.get("one_to_one_nat",{})
            if nat.get("address"): ips.append(f"Внешний: {nat['address']}")
        return True,(f"Информация о ВМ\nИмя: {d.get('name','?')}\nСтатус: {s}\n"
                     f"Ядра: {cores} | Память: {mem:.1f} GB\n"
                     +("\n".join(ips) or "IP не найдены"))

TG_SVC="vm-bot-tg"; VK_SVC="vm-bot-vk"
def svc_active(svc):
    r=subprocess.run(["systemctl","is-active",svc],capture_output=True,text=True)
    return r.stdout.strip()=="active"
def ctrl_svc(svc,action):
    if action=="stop" and svc==VK_SVC:
        return False,"⛔ Нельзя выключить VK бота через VK!\nИспользуйте Telegram бота."
    try:
        r=subprocess.run(["sudo","systemctl",action,svc],capture_output=True,text=True,timeout=15)
        return (True,f"✅ {svc} {'запущен' if action=='start' else 'остановлен'}") \
            if r.returncode==0 else (False,f"❌ {r.stderr.strip()}")
    except Exception as e: return False,f"❌ {e}"

def run_cmd_vk(cmd_str,timeout=30):
    try:
        r=subprocess.run(cmd_str,shell=True,capture_output=True,text=True,timeout=timeout,
                        env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
        out=(r.stdout+r.stderr).strip()
        return r.returncode==0, out[:4000]
    except subprocess.TimeoutExpired: return False,f"⏱ Таймаут {timeout}с"
    except Exception as e: return False,str(e)

def run_vkpanel_vk(n,timeout=20):
    return run_cmd_vk(f'echo "{n}" | vk-panel',timeout)

def run_xui_vk(n,timeout=20):
    return run_cmd_vk(f'echo "{n}" | x-ui',timeout)

def vk_upload_doc(uid,fpath,filename,title=""):
    import requests as req
    if vk_session_global is None: raise RuntimeError("vk_session_global не инициализирован")
    vk=vk_session_global.get_api()
    upload_info=vk.docs.getMessagesUploadServer(peer_id=uid)
    upload_url=upload_info["upload_url"]
    with open(fpath,"rb") as fp:
        r=req.post(upload_url,files={"file":(filename,fp,"application/octet-stream")},timeout=600)
    r.raise_for_status()
    if not r.text.strip(): raise RuntimeError("VK upload server вернул пустой ответ")
    data=r.json()
    if "file" not in data: raise RuntimeError(f"VK upload error: {data}")
    saved=vk.docs.save(file=data["file"],title=title or filename)
    doc=saved[0] if isinstance(saved,list) else saved.get("doc",saved)
    return f"doc{doc['owner_id']}_{doc['id']}"

def vk_upload_photo(uid,png_bytes):
    if vk_session_global is None: raise RuntimeError("vk_session_global не инициализирован")
    with tempfile.NamedTemporaryFile(delete=False,suffix=".png") as f:
        f.write(png_bytes); fpath=f.name
    try:
        upload=vk_api.VkUpload(vk_session_global)
        photos=upload.photo_messages(fpath,peer_id=uid)
        p=photos[0]
        return f"photo{p['owner_id']}_{p['id']}"
    finally:
        os.unlink(fpath)

def make_qr_bytes_vk(text):
    import qrcode
    buf=io.BytesIO(); qrcode.make(text).save(buf,format="PNG"); buf.seek(0)
    return buf.getvalue()

# ── Клавиатуры ───────────────────────────────────────────────
def _kbd(btns):
    return json.dumps({"one_time":False,"buttons":[
        [{"action":{"type":"text","label":b["l"]},"color":b.get("c","secondary")} for b in row]
        for row in btns]},ensure_ascii=False)

def kbd_main():
    rows=[
        [{"l":"📊 Статус","c":"primary"},{"l":"ℹ️ Информация","c":"primary"}],
        [{"l":"▶️ Запустить","c":"positive"},{"l":"⏹ Остановить","c":"negative"}],
        [{"l":"🔄 Перезапустить"}],
        [{"l":"⏰ Расписание"},{"l":"📋 История"},{"l":"⚙️ Настройки"}],
    ]
    if cfg["tg_installed"]: rows[2].append({"l":"🔵 TG бот","c":"primary"})
    if not get_sensitive(): rows.append([{"l":"🔧 Инструменты","c":"primary"}])
    return _kbd(rows)

def kbd_tg_bridge():
    active=bridge_is_running()
    st="🟢 Мост активен" if active else "🔴 Мост остановлен"
    return _kbd([
        [{"l":"💬 Чаты","c":"primary"},{"l":"✏️ Написать","c":"primary"}],
        [{"l":"↩️ Ответить","c":"primary"},{"l":"↪️ Переслать","c":"primary"}],
        [{"l":"📋 История чата","c":"primary"}],
        [{"l":st,"c":"positive" if active else "negative"}],
        [{"l":"« Назад"}]])

def kbd_tg_bridge_chats(chats):
    rows=[]
    for cid,cname,act in chats:
        emoji="✅" if act else "⬜"
        rows.append([{"l":f"{emoji} {str(cname)[:25]}"}])
    rows.append([{"l":"✅ Готово"},{"l":"« Назад"}])
    return _kbd(rows)

def kbd_schedule_vk():
    try:
        sc=json.load(open(BASE_DIR/"schedule.json")) if (BASE_DIR/"schedule.json").exists() else {}
    except: sc={}
    s="🟢" if sc.get("auto_start_enabled") else "🔴"
    p="🟢" if sc.get("auto_stop_enabled") else "🔴"
    return _kbd([
        [{"l":f"{s} Автозапуск","c":"positive" if sc.get("auto_start_enabled") else "negative"},
         {"l":f"{p} Автоостановка","c":"positive" if sc.get("auto_stop_enabled") else "negative"}],
        [{"l":"🕐 Время запуска"},{"l":"🕐 Время остановки"}],
        [{"l":"« Назад"}]])

def kbd_tools(uid=None):
    rows=[
        [{"l":"💻 Терминал"},{"l":"🔑 Туннель","c":"primary"}],
        [{"l":"📡 Медиасервер"},{"l":"⚙️ Ядро","c":"primary"}],
        [{"l":"🎬 YouTube","c":"positive"},{"l":"📱 TG Мост","c":"primary"}],
    ]
    if cfg.get("yadisk_token"): rows[2].append({"l":"📁 YaDisk видео","c":"primary"})
    rows.append([{"l":"« Назад"}])
    return _kbd(rows)

def kbd_yadisk():
    return _kbd([[{"l":"🗑 Удалить все видео","c":"negative"}],[{"l":"« Назад"}]])

def kbd_youtube():
    ssh_ok=bool(cfg.get("ssh_host",""))
    ssh_lbl="🌍 SSH (NL)" if ssh_ok else "⚠️ SSH не задан"
    return _kbd([
        [{"l":"🔍 Поиск видео","c":"primary"},{"l":"▶️ Последние видео канала"}],
        [{"l":"📺 Мои подписки","c":"primary"},{"l":"➕ Подписаться на канал","c":"positive"}],
        [{"l":"➖ Отписаться от канала","c":"negative"}],
        [{"l":"« Назад"}]])

def kbd_hist():
    days=db.get_setting("retention_days",db.DEFAULT_RETENTION_DAYS)
    return _kbd([
        [{"l":"📜 Последние команды","c":"primary"},{"l":"🤖 Авто-события","c":"primary"}],
        [{"l":f"⏱ Срок: {days}д"},{"l":"📊 Статистика БД"}],
        [{"l":"🗑️ Очистить историю","c":"negative"}],
        [{"l":"« Назад"}]])

def kbd_settings(uid=None):
    lbl="🔒 Скрыть инструменты" if not get_sensitive() else "🔓 Показать инструменты"
    rows=[[{"l":lbl}]]
    if uid and is_admin(uid):
        rows.append([{"l":"👮 Администрирование","c":"primary"}])
    rows+=[
        [{"l":"🗑️ Удалить бота с сервера","c":"negative"}],
        [{"l":"« Назад"}]]
    return _kbd(rows)

def kbd_admin():
    return _kbd([
        [{"l":"➕ Добавить пользователя","c":"positive"},{"l":"➖ Удалить пользователя","c":"negative"}],
        [{"l":"📋 Список пользователей","c":"primary"}],
        [{"l":"🔧 Функции пользователей","c":"primary"}],
        [{"l":"📢 Рассылка","c":"primary"}],
        [{"l":"⬆️ Обновить с GitHub","c":"primary"}],
        [{"l":"« Назад"}]])

def kbd_console():
    return _kbd([[{"l":"« Назад"}]])

def kbd_wg():
    return _kbd([
        [{"l":"👥 Пиры","c":"primary"}],
        [{"l":"➕ Новый пир","c":"positive"},{"l":"📥 Экспорт","c":"primary"},{"l":"🗑 Удалить пир","c":"negative"}],
        [{"l":"« Назад"}]])

def kbd_vkpanel():
    return _kbd([
        [{"l":"▶️ МС-старт","c":"positive"},{"l":"⏹ МС-стоп","c":"negative"},{"l":"🔄 МС-рестарт"}],
        [{"l":"📊 МС-статус","c":"primary"},{"l":"📋 МС-логи"},{"l":"📱 МС-QR","c":"primary"}],
        [{"l":"« Назад"}]])

def kbd_xui():
    return _kbd([
        [{"l":"📊 Ядро-статус","c":"primary"},{"l":"🔄 Ядро-рестарт"}],
        [{"l":"📋 Ядро-логи"},{"l":"🔧 Ядро-настройки","c":"primary"}],
        [{"l":"⏹ Ядро-стоп","c":"negative"},{"l":"🔌 Ядро-порт"},{"l":"🔃 Ядро-сброс","c":"negative"}],
        [{"l":"« Назад"}]])

def kbd_tg():
    a=svc_active(TG_SVC)
    return _kbd([
        [{"l":"🟢 TG активен" if a else "🔴 TG неактивен","c":"positive" if a else "negative"}],
        [{"l":"▶️ Включить TG бота","c":"positive"},{"l":"⏹ Выключить TG бота","c":"negative"}],
        [{"l":"« Назад"}]])

# ── Отправка сообщений ────────────────────────────────────────
def send(vk,uid,text,kbd=None):
    # VK ограничение: 4096 символов
    if len(text)>4096: text=text[:4090]+"…"
    p={"user_id":uid,"message":text,"random_id":random.randint(0,2**31)}
    if kbd: p["keyboard"]=kbd
    vk.messages.send(**p)

def send_attach(vk,uid,text,attachment,kbd=None):
    p={"user_id":uid,"message":text,"attachment":attachment,"random_id":random.randint(0,2**31)}
    if kbd: p["keyboard"]=kbd
    vk.messages.send(**p)

# ── Яндекс.Диск ──────────────────────────────────────────────
YA_API="https://cloud-api.yandex.net/v1/disk/resources"
YA_FOLDER="/yt_bot_videos"

def yadisk_cleanup(token,max_age_days=7,min_free_pct=10):
    import requests as req
    from datetime import datetime,timezone
    h={"Authorization":f"OAuth {token}"}; deleted=0
    try:
        low_space=False
        try:
            ri=req.get("https://cloud-api.yandex.net/v1/disk",headers=h,timeout=30)
            di=ri.json(); total=di.get("total_space",1); used=di.get("used_space",0)
            low_space=(1-used/total)*100 < min_free_pct
        except: pass
        r=req.get(f"{YA_API}",headers=h,timeout=30,
                  params={"path":YA_FOLDER,"fields":"_embedded.items","limit":"100"})
        if r.status_code!=200: return 0
        items=r.json().get("_embedded",{}).get("items",[])
        now=datetime.now(timezone.utc)
        def get_created(x):
            try: return datetime.fromisoformat(x.get("created","").replace("Z","+00:00"))
            except: return now
        for item in sorted(items,key=get_created):
            try:
                age_days=(now-get_created(item)).days
                if age_days>=max_age_days or low_space:
                    req.delete(f"{YA_API}",headers=h,timeout=30,
                               params={"path":item["path"],"permanently":"true"})
                    deleted+=1
                    if low_space:
                        ri2=req.get("https://cloud-api.yandex.net/v1/disk",headers=h,timeout=30)
                        di2=ri2.json(); t2=di2.get("total_space",1); u2=di2.get("used_space",0)
                        if (1-u2/t2)*100>=min_free_pct: low_space=False
            except: pass
    except Exception as e:
        logger.error(f"YaDisk cleanup error: {e}")
    return deleted


def _get_vm_external_ip():
    """Получает внешний IP Яндекс.Облако ВМ через yc CLI."""
    try:
        import json as _json
        r=subprocess.run(
            ["yc","compute","instance","get",cfg["vm_id"],"--format","json"],
            capture_output=True,text=True,timeout=30,
            env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin:/root/yandex-cloud/bin"})
        if r.returncode!=0: return None
        d=_json.loads(r.stdout)
        for iface in d.get("network_interfaces",[]):
            nat=iface.get("primary_v4_address",{}).get("one_to_one_nat",{})
            if nat.get("address"): return nat["address"]
    except Exception as e:
        logger.warning(f"_get_vm_external_ip: {e}")
    return None

def yadisk_upload_via_ssh(token,local_path,filename):
    """Загружает файл на Яндекс.Диск через SSH на российскую ВМ.
    Флоу: SCP → vm:/tmp/ytdl/ → curl Yandex.Disk API → rm → return public_url
    """
    ssh_user=cfg.get("yadisk_ssh_user","ubuntu")
    ssh_key=cfg.get("yadisk_ssh_key","")
    if not ssh_key:
        return None  # нет ключа — фолбек на прямую загрузку

    vm_ip=_get_vm_external_ip()
    if not vm_ip:
        logger.warning("yadisk_upload_via_ssh: не удалось получить IP ВМ")
        return None

    remote_dir="/tmp/ytdl_yadisk"
    remote_file=f"{remote_dir}/{filename}"
    ya_folder="/yt_bot_videos"
    ya_path=f"{ya_folder}/{filename}"

    ssh_opts=["-o","StrictHostKeyChecking=no","-o","ConnectTimeout=15",
              "-o","BatchMode=yes","-i",ssh_key]
    ssh_base=["ssh"]+ssh_opts+[f"{ssh_user}@{vm_ip}"]
    scp_opts=["-o","StrictHostKeyChecking=no","-i",ssh_key]

    try:
        # Создаём tmp папку на ВМ
        subprocess.run(ssh_base+[f"mkdir -p {remote_dir}"],timeout=15,capture_output=True)

        # SCP файл на ВМ
        r=subprocess.run(
            ["scp"]+scp_opts+[local_path,f"{ssh_user}@{vm_ip}:{remote_file}"],
            capture_output=True,text=True,timeout=600)
        if r.returncode!=0:
            logger.warning(f"SCP failed: {r.stderr}")
            return None

        # Создаём папку на Яндекс.Диске (игнорируем ошибку если есть)
        subprocess.run(ssh_base+[
            f"curl -s -X PUT 'https://cloud-api.yandex.net/v1/disk/resources"
            f"?path={ya_folder}' -H 'Authorization: OAuth {token}'"],
            timeout=30,capture_output=True)

        # Получаем URL для загрузки
        r2=subprocess.run(ssh_base+[
            f"curl -s 'https://cloud-api.yandex.net/v1/disk/resources/upload"
            f"?path={ya_path}&overwrite=true' -H 'Authorization: OAuth {token}'"],
            capture_output=True,text=True,timeout=30)
        import json as _j
        upload_url=_j.loads(r2.stdout).get("href","")
        if not upload_url:
            logger.warning(f"yadisk_upload_via_ssh: нет upload URL: {r2.stdout[:200]}")
            subprocess.run(ssh_base+[f"rm -f {remote_file}"],timeout=15,capture_output=True)
            return None

        # Загружаем на Яндекс.Диск с ВМ
        r3=subprocess.run(ssh_base+[
            f"curl -s -T '{remote_file}' '{upload_url}'"],
            capture_output=True,text=True,timeout=900)
        if r3.returncode!=0:
            logger.warning(f"yadisk curl upload failed: {r3.stderr}")
            subprocess.run(ssh_base+[f"rm -f {remote_file}"],timeout=15,capture_output=True)
            return None

        # Публикуем
        subprocess.run(ssh_base+[
            f"curl -s -X PUT 'https://cloud-api.yandex.net/v1/disk/resources/publish"
            f"?path={ya_path}' -H 'Authorization: OAuth {token}'"],
            timeout=30,capture_output=True)

        # Получаем публичную ссылку
        r4=subprocess.run(ssh_base+[
            f"curl -s 'https://cloud-api.yandex.net/v1/disk/resources"
            f"?path={ya_path}' -H 'Authorization: OAuth {token}'"],
            capture_output=True,text=True,timeout=30)
        pub_url=_j.loads(r4.stdout).get("public_url","")

        # Чистим временный файл с ВМ
        subprocess.run(ssh_base+[f"rm -f {remote_file}"],timeout=15,capture_output=True)

        logger.info(f"yadisk_upload_via_ssh: {filename} → {pub_url}")
        return pub_url or None

    except Exception as e:
        logger.error(f"yadisk_upload_via_ssh: {e}")
        try: subprocess.run(ssh_base+[f"rm -f {remote_file}"],timeout=10,capture_output=True)
        except: pass
        return None

def yadisk_upload(token,local_path,filename):
    import requests as req
    h={"Authorization":f"OAuth {token}"}; remote=f"{YA_FOLDER}/{filename}"
    req.put(YA_API,headers=h,params={"path":YA_FOLDER})
    r=req.get(f"{YA_API}/upload",headers=h,params={"path":remote,"overwrite":"true"},timeout=30)
    r.raise_for_status()
    upload_url=r.json()["href"]
    with open(local_path,"rb") as f:
        r=req.put(upload_url,data=f,timeout=600)
    r.raise_for_status()
    req.put(f"{YA_API}/publish",headers=h,params={"path":remote},timeout=30)
    r=req.get(YA_API,headers=h,params={"path":remote},timeout=30)
    r.raise_for_status()
    return r.json().get("public_url","")

def sponsorblock_check(video_id):
    import requests as req
    try:
        r=req.get("https://sponsor.ajay.app/api/skipSegments",
            params={"videoID":video_id,"categories":["sponsor","selfpromo","interaction","intro","outro"]},
            timeout=10)
        if r.status_code==200: return r.json()
        return []
    except: return []

def sponsorblock_cut(vpath,segments,out_path):
    if not segments: return vpath
    try:
        conditions="+".join([f"between(t,{s['segment'][0]},{s['segment'][1]})" for s in segments])
        filter_str=f"select='not({conditions})',setpts=N/FRAME_RATE/TB"
        afilter=f"aselect='not({conditions})',asetpts=N/SR/TB"
        r=subprocess.run([
            "ffmpeg","-y","-i",vpath,
            "-vf",filter_str,"-af",afilter,
            "-c:v","libx264","-c:a","aac","-threads","1",
            out_path],capture_output=True,timeout=300)
        if r.returncode==0: return out_path
    except Exception as e:
        logger.warning(f"SponsorBlock cut error: {e}")
    return vpath

def _yt_download_and_send(vk,uid,url,title,fmt,st):
    """Скачивает YouTube видео через SSH (NL VPS) или локально, отправляет."""
    safe_title=re.sub(r'[\\/*?:"<>|]','',title)[:60].strip() or "video"
    send(vk,uid,f"⏳ Скачиваю «{safe_title}»...")

    use_ssh=bool(cfg.get("ssh_host",""))
    with tempfile.TemporaryDirectory() as tmp:
        try:
            vpath=None
            if use_ssh:
                send(vk,uid,"🌍 Загружаю через NL VPS (обход блокировок)...")
                vpath,err=_yt_download_via_ssh(url,fmt,tmp)
                if vpath is None:
                    send(vk,uid,f"⚠️ SSH-загрузка не удалась: {err}\n⬇️ Пробую локально...")
                    use_ssh=False

            if not use_ssh:
                ytdlp=str(VK_DIR.parent/"tg/venv/bin/yt-dlp")
                out=f"{tmp}/{safe_title}.%(ext)s"
                r=subprocess.run(
                    [ytdlp,"-f",fmt,
                     "--merge-output-format","mp4",
                     "--postprocessor-args","ffmpeg:-c:v libx264 -preset ultrafast -crf 23 -c:a aac -threads 1",
                     "--no-playlist","--socket-timeout","30","--restrict-filenames",
                     "-o",out,"--no-part",url],
                    capture_output=True,text=True,timeout=600,
                    preexec_fn=lambda: os.nice(19),
                    env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
                if r.returncode!=0:
                    send(vk,uid,f"❌ Ошибка:\n{(r.stderr or r.stdout)[-400:]}"); return
                files=glob.glob(f"{tmp}/*.mp4") or glob.glob(f"{tmp}/*.*")
                if not files: send(vk,uid,"❌ Файл не найден после скачивания"); return
                vpath=files[0]

            if not vpath or not os.path.exists(vpath):
                send(vk,uid,"❌ Файл не найден"); return

            # ffprobe: проверяем потоки
            probe=subprocess.run(
                ["ffprobe","-v","error","-show_entries","stream=codec_type",
                 "-of","csv=p=0",vpath],capture_output=True,text=True)
            streams=probe.stdout.strip().split("\n") if probe.returncode==0 else []
            if "audio" not in streams and fmt!="bestvideo+bestaudio/best":
                send(vk,uid,"⚠️ Аудио не найдено в дубляже, скачиваю оригинал...")
                _yt_download_and_send(vk,uid,url,title,"bestvideo+bestaudio/best",st)
                return
            if "video" not in streams:
                send(vk,uid,"❌ Видео-поток не найден в файле"); return

            # SponsorBlock
            vid_m=re.search(r'(?:v=|youtu\.be/)([A-Za-z0-9_-]{11})',url)
            if vid_m:
                segments=sponsorblock_check(vid_m.group(1))
                if segments:
                    times=", ".join([f"{int(s['segment'][0]//60)}:{int(s['segment'][0]%60):02d}–"
                                     f"{int(s['segment'][1]//60)}:{int(s['segment'][1]%60):02d}"
                                     for s in segments[:5]])
                    send(vk,uid,f"⚠️ SponsorBlock: {len(segments)} реклам/спонсоров ({times})\n✂️ Вырезаю...")
                    cut_path=os.path.join(tmp,f"{safe_title}_clean.mp4")
                    vpath=sponsorblock_cut(vpath,segments,cut_path)
                    sz=os.path.getsize(vpath)/(1024*1024)
                    send(vk,uid,f"✅ Реклама вырезана, размер: {sz:.1f} MB")

            sz=os.path.getsize(vpath)/(1024*1024)
            send(vk,uid,f"⬆️ Отправляю ({sz:.1f} MB)...")

            yadisk_token=cfg.get("yadisk_token","")
            fname=f"{safe_title}.mp4"

            if sz>200 and not yadisk_token:
                send(vk,uid,
                    f"❌ Файл {sz:.0f} MB — VK API не принимает >200 MB.\n"
                    f"Добавь Yandex OAuth Token через пункт 7 меню установщика.")
                return

            if yadisk_token and sz>200:
                try: yadisk_cleanup(yadisk_token,max_age_days=7,min_free_pct=15)
                except Exception as e: logger.warning(f"pre-upload cleanup: {e}")

                # Пробуем загрузку через SSH на Яндекс Cloud ВМ (быстрее внутри РФ)
                pub_url=None
                if cfg.get("yadisk_ssh_key",""):
                    send(vk,uid,"☁️ Загружаю на Яндекс.Диск через ВМ (быстрый канал)...")
                    pub_url=yadisk_upload_via_ssh(yadisk_token,vpath,fname)
                    if not pub_url:
                        send(vk,uid,"⚠️ SSH-загрузка не удалась, пробую напрямую...")

                # Фолбек: прямая загрузка с NL VPS
                if not pub_url:
                    send(vk,uid,"⬆️ Загружаю напрямую на Яндекс.Диск...")
                    pub_url=yadisk_upload(yadisk_token,vpath,fname)

                if pub_url:
                    cur_kbd={"main":kbd_main,"tools":kbd_tools,"youtube":kbd_youtube}.get(st,kbd_main)()
                    send(vk,uid,f"📹 {safe_title} ({sz:.1f} MB)\n🔗 Скачать: {pub_url}",cur_kbd)
                    db.log_command("vk",uid,f"yt {url[:80]}",f"yadisk {sz:.1f}MB",True)
                    return
                send(vk,uid,"⚠️ Яндекс.Диск недоступен, пробую через VK...")

            att=vk_upload_doc(uid,vpath,fname,f"YouTube: {safe_title}")
            cur_kbd={"main":kbd_main,"tools":kbd_tools,"youtube":kbd_youtube}.get(st,kbd_main)()
            send_attach(vk,uid,f"📹 {safe_title} ({sz:.1f} MB)",att,cur_kbd)
            db.log_command("vk",uid,f"yt {url[:80]}",f"{sz:.1f}MB",True)
        except subprocess.TimeoutExpired:
            send(vk,uid,"⏱ Таймаут. Видео слишком длинное или сервер перегружен.")
        except Exception as e:
            send(vk,uid,f"❌ {e}")

def _yt_get_meta(url):
    """Возвращает (title, dubbed_list) для URL."""
    title="YouTube"; dubbed=[]
    try:
        import yt_dlp as yt_dlp_lib
        with yt_dlp_lib.YoutubeDL({"quiet":True,"no_warnings":True,"noplaylist":True}) as ydl:
            info=ydl.extract_info(url,download=False)
        title=info.get("title","YouTube")[:60]
        for f in (info.get("formats") or []):
            note=(f.get("format_note") or "").lower()
            lang=f.get("language") or ""
            if f.get("acodec")!="none" and f.get("vcodec")=="none":
                if "dubbed" in note or "дубляж" in note or (lang and lang not in ("en","und","")):
                    dubbed.append({"lang":lang,"label":f"{lang.upper()} дубляж" if lang else note,"fid":f["format_id"]})
    except Exception as e:
        logger.warning(f"yt metadata: {e}")
    return title,dubbed

def handle(vk,uid,text):
    if uid not in get_all_users(): send(vk,uid,"⛔ Нет доступа"); return
    st=states.get(uid,"main"); text=text.strip()

    # ── YouTube: автодетект ссылок в любом состоянии ────────────
    if re.search(r'https?://((www|m)\.)?youtube\.com/\S+|https?://youtu\.be/\S+',text):
        send(vk,uid,"🔍 Получаю информацию о видео...")
        title,dubbed=_yt_get_meta(text)
        if dubbed:
            dub_list="\n".join([f"{i+1}. {d['label']}" for i,d in enumerate(dubbed)])
            send(vk,uid,
                f"🎬 {title}\n\nДоступны дубляжи:\n{dub_list}\n{len(dubbed)+1}. Оригинал\n\n"
                f"Качество:\nMAX) Максимум  A) 1080p  B) 720p  C) 480p  D) 360p\n\n"
                f"Ответь, например: 1A (RU 1080p), {len(dubbed)+1}MAX (оригинал макс) или {len(dubbed)+1}D (360p)")
            states[uid]="yt_dub_choice"
            pending[uid]={"url":text,"dubbed":dubbed,"title":title,"prev_st":st}
        else:
            send(vk,uid,f"🎬 {title}\n\nВыбери качество:\nMAX) Максимум (лучшее доступное)\nA) 1080p\nB) 720p\nC) 480p\nD) 360p")
            states[uid]="yt_quality_choice"
            pending[uid]={"url":text,"title":title,"prev_st":st}
        return

    # ── Состояние: выбор дубляжа ─────────────────────────────────
    if st=="yt_dub_choice":
        if not re.match(r'^\d+[ABCabc]?$',text.strip()):
            pending.pop(uid,None); states[uid]=pending.get(uid,{}).get("prev_st","main")
            handle(vk,uid,text); return
        data=pending.pop(uid,{})
        url=data.get("url",""); dubbed=data.get("dubbed",[]); title=data.get("title","YouTube")
        if not url: send(vk,uid,"❌ Сессия истекла",kbd_main()); states[uid]="main"; return
        m=re.match(r'^(\d+)([ABCabc]?)$',text.strip())
        choice=int(m.group(1))-1; quality=(m.group(2).upper() or "A")
        if quality=="MAX":
            height=None
        else:
            height={"A":"1080","B":"720","C":"480","D":"360"}.get(quality,"720")
        if choice==len(dubbed):
            fmt=f"bestvideo[height<={height}]+bestaudio/bestvideo+bestaudio/best" if height else "bestvideo+bestaudio/best"
        elif 0<=choice<len(dubbed):
            fid=dubbed[choice]['fid']
            fmt=(f"bestvideo[height<={height}]+{fid}/bestvideo[height<={height}]+bestaudio/best" if height
                 else f"bestvideo+{fid}/bestvideo+bestaudio/best")
        else:
            pending[uid]=data; send(vk,uid,"❌ Неверный номер"); return
        prev_st=data.get("prev_st","main")
        states[uid]="main"
        send(vk,uid,f"⏳ Начинаю скачивание «{title}» ({height if height!='MAX' else 'макс. качество'})...\nБот остаётся доступен.")
        threading.Thread(target=_yt_download_and_send,args=(vk,uid,url,title,fmt,prev_st),daemon=True).start()
        return

    # ── Состояние: выбор качества ────────────────────────────────
    if st=="yt_quality_choice":
        t=text.strip().upper()
        if not re.match(r'^(MAX|[ABCDabcd])$',t):
            pending.pop(uid,None); states[uid]=pending.get(uid,{}).get("prev_st","main")
            handle(vk,uid,text); return
        data=pending.pop(uid,{})
        url=data.get("url",""); title=data.get("title","YouTube")
        if not url: send(vk,uid,"❌ Сессия истекла",kbd_main()); states[uid]="main"; return
        if t=="MAX":
            fmt="bestvideo+bestaudio/best"
            height="MAX"
        else:
            height={"A":"1080","B":"720","C":"480","D":"360"}.get(t,"720")
            fmt=f"bestvideo[height<={height}]+bestaudio/bestvideo[height<={height}]+bestaudio/best"
        prev_st=data.get("prev_st","main")
        states[uid]="main"
        send(vk,uid,f"⏳ Начинаю скачивание «{title}» ({height if height!='MAX' else 'макс. качество'})...\nБот остаётся доступен.")
        threading.Thread(target=_yt_download_and_send,args=(vk,uid,url,title,fmt,prev_st),daemon=True).start()
        return

    # ── Состояния YouTube-поиска ──────────────────────────────────
    if st=="yt_search_input":
        if text=="« Назад":
            states[uid]="youtube"; send(vk,uid,"🎬 YouTube:",kbd_youtube()); return
        send(vk,uid,"🔍 Ищу...")
        results=yt_search(text,5)
        if not results:
            send(vk,uid,"❌ Ничего не найдено",kbd_youtube()); states[uid]="youtube"; return
        lines=[f"🔍 Результаты поиска «{text[:40]}»:\n"]
        for i,r in enumerate(results,1):
            lines.append(f"{i}. {r['title']}\n   ▶️ {r['channel']}\n   {r['url']}")
        page=0; page_results=results[:5]
        lines=[f"🔍 Результаты поиска «{text[:40]}» (1-5 из {len(results)}):\n"]
        for i,r in enumerate(page_results,1):
            lines.append(f"{i}. {r['title']}\n   ▶️ {r['channel']}\n   {r['url']}")
        nav=""; 
        if len(results)>5: nav="\n\n▶️ Ещё 5 — напиши 'ещё'"
        send(vk,uid,"\n\n".join(lines)+f"\n\nВведи номер для скачивания или « Назад:{nav}")
        states[uid]="yt_search_results"
        pending[uid]={"results":results,"query":text,"page":0}
        return

    if st=="yt_search_results":
        if text=="« Назад":
            states[uid]="youtube"; send(vk,uid,"🎬 YouTube:",kbd_youtube()); return
        try:
            n=int(text.strip())-1
            data=pending.pop(uid,{}); results=data.get("results",[])
            if not 0<=n<len(results):
                send(vk,uid,"❌ Неверный номер (1-5)"); return
            v=results[n]; url=v["url"]; title=v["title"]
            send(vk,uid,f"🎬 {title}\n\nВыбери качество:\nMAX) Максимум (лучшее доступное)\nA) 1080p\nB) 720p\nC) 480p\nD) 360p")
            states[uid]="yt_quality_choice"
            pending[uid]={"url":url,"title":title,"prev_st":"youtube"}
        except:
            send(vk,uid,"❌ Введи число от 1 до 5")
        return

    # ── Состояния YouTube-канала (последние видео) ────────────────
    if st=="yt_channel_latest_input":
        if text=="« Назад":
            states[uid]="youtube"; send(vk,uid,"🎬 YouTube:",kbd_youtube()); return
        text=_normalize_yt_channel(text)
        send(vk,uid,"⏳ Получаю последние видео...")
        cid,cname,videos=yt_get_channel_info(text)
        if not videos:
            send(vk,uid,"❌ Не удалось получить видео с канала",kbd_youtube())
            states[uid]="youtube"; return
        lines=[f"📺 Последние видео ({len(videos)}) канала {cname or text}:\n"]
        for i,v in enumerate(videos,1):
            lines.append(f"{i}. {v['title']}\n   {v['url']}")
        nav=""
        if len(videos)>5: nav="\n(показано до 10 видео)"
        send(vk,uid,"\n\n".join(lines)+f"\n\nВведи номер для скачивания:{nav}")
        states[uid]="yt_channel_latest_pick"
        pending[uid]={"videos":videos,"cname":cname}
        return

    if st=="yt_channel_latest_pick":
        if text=="« Назад":
            states[uid]="youtube"; send(vk,uid,"🎬 YouTube:",kbd_youtube()); return
        try:
            n=int(text.strip())-1
            data=pending.pop(uid,{}); videos=data.get("videos",[])
            if not 0<=n<len(videos):
                send(vk,uid,f"❌ Неверный номер (1-{len(videos)})"); return
            v=videos[n]; url=v["url"]; title=v["title"]
            send(vk,uid,f"🎬 {title}\n\nВыбери качество:\nMAX) Максимум (лучшее доступное)\nA) 1080p\nB) 720p\nC) 480p\nD) 360p")
            states[uid]="yt_quality_choice"
            pending[uid]={"url":url,"title":title,"prev_st":"youtube"}
        except:
            send(vk,uid,"❌ Введи число")
        return

    # ── Состояния подписки на канал ───────────────────────────────
    if st=="yt_subscribe_input":
        if text=="« Назад":
            states[uid]="youtube"; send(vk,uid,"🎬 YouTube:",kbd_youtube()); return
        text=_normalize_yt_channel(text)
        send(vk,uid,"⏳ Получаю информацию о канале...")
        cid,cname,videos=yt_get_channel_info(text)
        if not cid:
            send(vk,uid,"❌ Не удалось найти канал",kbd_youtube())
            states[uid]="youtube"; return
        data=load_yt_subs()
        if cid not in data["channels"]:
            data["channels"][cid]={"name":cname,"url":text,"subscribers":[],"last_video_id":videos[0]["id"] if videos else "","last_check":""}
        ch=data["channels"][cid]
        if uid not in ch["subscribers"]:
            ch["subscribers"].append(uid)
            save_yt_subs(data)
            send(vk,uid,f"✅ Подписался на канал «{cname}»!\n\nПоследнее видео: {videos[0]['title'] if videos else 'нет'}",kbd_youtube())
        else:
            send(vk,uid,f"ℹ️ Ты уже подписан на «{cname}»",kbd_youtube())
        states[uid]="youtube"
        return

    if st=="yt_unsubscribe_input":
        if text=="« Назад":
            states[uid]="youtube"; send(vk,uid,"🎬 YouTube:",kbd_youtube()); return
        data=load_yt_subs()
        # поиск по номеру из списка
        my_subs=[(cid,ch) for cid,ch in data["channels"].items() if uid in ch.get("subscribers",[])]
        try:
            n=int(text.strip())-1
            if not 0<=n<len(my_subs):
                send(vk,uid,"❌ Неверный номер"); return
            cid,ch=my_subs[n]
            ch["subscribers"].remove(uid)
            if not ch["subscribers"]: del data["channels"][cid]  # никто не подписан — удаляем
            save_yt_subs(data)
            send(vk,uid,f"✅ Отписался от «{ch.get('name',cid)}»",kbd_youtube())
        except:
            send(vk,uid,"❌ Введи номер из списка")
        states[uid]="youtube"
        return

    # ── Состояния администрирования ───────────────────────────────
    if st=="admin_add_user":
        if text=="« Назад":
            states[uid]="admin_menu"; send(vk,uid,"👮 Администрирование:",kbd_admin()); return
        if not is_admin(uid): send(vk,uid,"⛔ Только для администратора"); states[uid]="main"; return
        _btns={"➕ Добавить пользователя","➖ Удалить пользователя","📋 Список пользователей","🔧 Функции пользователей","📢 Рассылка","⬆️ Обновить с GitHub","👮 Администрирование","⚙️ Настройки"}
        if text in _btns: send(vk,uid,"✏️ Введи VK страницу (URL или @username):"); return
        send(vk,uid,"⏳ Ищу пользователя...")
        vk_api_obj=vk_session_global.get_api() if vk_session_global else vk
        new_uid,name=resolve_vk_user(vk_api_obj,text)
        if new_uid is None:
            send(vk,uid,f"❌ Не удалось найти пользователя: {text}"); return
        data=load_admin()
        if new_uid in get_all_users():
            send(vk,uid,f"ℹ️ {name} (ID {new_uid}) уже в списке разрешённых",kbd_admin())
            states[uid]="admin_menu"; return
        pending[uid]={"new_uid":new_uid,"name":name}
        send(vk,uid,f"Добавить «{name}» (ID {new_uid})?\n\nВведи PIN для подтверждения:")
        states[uid]="admin_add_pin"
        return

    if st=="admin_add_pin":
        if not is_admin(uid): states[uid]="main"; return
        data_p=pending.pop(uid,{})
        new_uid=data_p.get("new_uid"); name=data_p.get("name","?")
        if text==cfg["admin_pin"] and new_uid:
            data=load_admin()
            if new_uid not in data["extra_users"]:
                data["extra_users"].append(new_uid)
            data["user_labels"][str(new_uid)]=name
            save_admin(data)
            db.log_command("vk",uid,f"add_user {new_uid}",name,True)
            send(vk,uid,f"✅ {name} (ID {new_uid}) добавлен!\nТеперь может использовать YouTube.",kbd_admin())
        else:
            send(vk,uid,"❌ Неверный PIN. Отменено.",kbd_admin())
            db.log_command("vk",uid,f"add_user","неверный PIN",False)
        states[uid]="admin_menu"
        return

    if st=="admin_remove_user":
        if text=="« Назад":
            states[uid]="admin_menu"; send(vk,uid,"👮 Администрирование:",kbd_admin()); return
        if not is_admin(uid): states[uid]="main"; return
        try:
            rem_uid=int(text.strip())
        except:
            send(vk,uid,"❌ Введи числовой VK ID"); return
        data=load_admin()
        extra=[int(u) for u in data.get("extra_users",[])]
        if rem_uid not in extra:
            send(vk,uid,"❌ Пользователь не найден в вайтлисте"); return
        name=data.get("user_labels",{}).get(str(rem_uid),str(rem_uid))
        pending[uid]={"rem_uid":rem_uid,"name":name}
        send(vk,uid,f"Удалить «{name}» (ID {rem_uid})? Введи PIN:")
        states[uid]="admin_remove_pin"
        return

    if st=="admin_remove_pin":
        if not is_admin(uid): states[uid]="main"; return
        data_p=pending.pop(uid,{})
        rem_uid=data_p.get("rem_uid"); name=data_p.get("name","?")
        if text==cfg["admin_pin"] and rem_uid:
            data=load_admin()
            data["extra_users"]=[u for u in data["extra_users"] if int(u)!=rem_uid]
            data["user_labels"].pop(str(rem_uid),None)
            data["disabled_features"].pop(str(rem_uid),None)
            save_admin(data)
            db.log_command("vk",uid,f"remove_user {rem_uid}",name,True)
            send(vk,uid,f"✅ {name} (ID {rem_uid}) удалён из разрешённых.",kbd_admin())
        else:
            send(vk,uid,"❌ Неверный PIN.",kbd_admin())
        states[uid]="admin_menu"
        return

    if st=="admin_features":
        if text=="« Назад":
            states[uid]="admin_menu"; send(vk,uid,"👮 Администрирование:",kbd_admin()); return
        if not is_admin(uid): states[uid]="main"; return
        # Формат: "ID функция вкл/выкл" или "глобально функция вкл/выкл"
        # Например: "123456 youtube выкл" или "глобально vm_control выкл"
        parts=text.lower().strip().split()
        if len(parts)!=3:
            send(vk,uid,(
                "Формат команды:\n"
                "<ID> <функция> вкл/выкл\n"
                "или: глобально <функция> вкл/выкл\n\n"
                "Функции: youtube, vm_control, terminal, tunnel, xui, vkpanel\n\n"
                "Примеры:\n123456 youtube выкл\nглобально vm_control выкл"))
            return
        target,feature,action=parts
        if feature not in ("youtube","vm_control","terminal","tunnel","xui","vkpanel"):
            send(vk,uid,"❌ Неизвестная функция"); return
        data=load_admin()
        if target=="глобально":
            gd=data.setdefault("global_disabled",[])
            if action in ("выкл","off","0"):
                if feature not in gd: gd.append(feature)
                send(vk,uid,f"✅ {feature} глобально отключена для не-администраторов",kbd_admin())
            else:
                if feature in gd: gd.remove(feature)
                send(vk,uid,f"✅ {feature} глобально включена для всех",kbd_admin())
        else:
            try: t_uid=int(target)
            except: send(vk,uid,"❌ Неверный ID"); return
            ud=data.setdefault("disabled_features",{}).setdefault(str(t_uid),[])
            if action in ("выкл","off","0"):
                if feature not in ud: ud.append(feature)
                send(vk,uid,f"✅ {feature} отключена для ID {t_uid}",kbd_admin())
            else:
                if feature in ud: ud.remove(feature)
                send(vk,uid,f"✅ {feature} включена для ID {t_uid}",kbd_admin())
        save_admin(data)
        return

    if st=="admin_broadcast":
        if text=="« Назад":
            states[uid]="admin_menu"; send(vk,uid,"👮 Администрирование:",kbd_admin()); return
        if not is_admin(uid): states[uid]="main"; return
        users=get_all_users(); sent=0
        for u in users:
            if u==uid: continue
            try: send(vk,u,f"📢 Сообщение от администратора:\n\n{text}"); sent+=1
            except: pass
        send(vk,uid,f"✅ Рассылка отправлена {sent} пользователям",kbd_admin())
        states[uid]="admin_menu"
        return

    if text.lower() in ("начать","start","/start","меню"):
        states[uid]="main"; send(vk,uid,"👋 Панель управления ВМ:",kbd_main()); return

    # ── Состояния: ввод PIN / имён ──────────────────────────────
    if st=="await_pin":
        if text==cfg["admin_pin"]:
            db.log_command("vk",uid,"удаление бота","выполнено",True)
            send(vk,uid,"🗑️ PIN верный. Удаление через 3 секунды...")
            def _del(): time.sleep(3); subprocess.Popen(["sudo","/opt/vm_manager/uninstall.sh"])
            threading.Thread(target=_del,daemon=True).start()
        else:
            db.log_command("vk",uid,"удаление бота","неверный PIN",False)
            states[uid]="settings"; send(vk,uid,"❌ Неверный PIN. Отменено.",kbd_settings(uid))
        return

    if st=="schedule_vk":
        if text=="« Назад":
            states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main()); return
        if text in ("🟢 Автозапуск","🔴 Автозапуск"):
            val=_toggle_schedule_vk("auto_start_enabled")
            send(vk,uid,f"{'🟢 Автозапуск включён' if val else '🔴 Автозапуск выключен'}")
            _show_schedule_vk(vk,uid); return
        if text in ("🟢 Автоостановка","🔴 Автоостановка"):
            val=_toggle_schedule_vk("auto_stop_enabled")
            send(vk,uid,f"{'🟢 Автоостановка включена' if val else '🔴 Автоостановка выключена'}")
            _show_schedule_vk(vk,uid); return
        if text=="🕐 Время запуска":
            states[uid]="schedule_start_time"; send(vk,uid,"Введи время автозапуска (ЧЧ:ММ), например: 09:00"); return
        if text=="🕐 Время остановки":
            states[uid]="schedule_stop_time"; send(vk,uid,"Введи время остановки (ЧЧ:ММ), например: 23:00"); return
        _show_schedule_vk(vk,uid); return

    if st=="schedule_start_time":
        if re.match(r'^\d{1,2}:\d{2}$',text):
            try:
                h,m=text.split(":"); assert 0<=int(h)<24 and 0<=int(m)<60
                _set_schedule_time_vk("start_time",f"{int(h):02d}:{m}")
                states[uid]="schedule_vk"; send(vk,uid,f"✅ Время запуска: {int(h):02d}:{m}")
                _show_schedule_vk(vk,uid)
            except: send(vk,uid,"❌ Неверный формат ЧЧ:ММ")
        else: send(vk,uid,"❌ Формат ЧЧ:ММ, например: 09:00")
        return

    if st=="schedule_stop_time":
        if re.match(r'^\d{1,2}:\d{2}$',text):
            try:
                h,m=text.split(":"); assert 0<=int(h)<24 and 0<=int(m)<60
                _set_schedule_time_vk("stop_time",f"{int(h):02d}:{m}")
                states[uid]="schedule_vk"; send(vk,uid,f"✅ Время остановки: {int(h):02d}:{m}")
                _show_schedule_vk(vk,uid)
            except: send(vk,uid,"❌ Неверный формат ЧЧ:ММ")
        else: send(vk,uid,"❌ Формат ЧЧ:ММ, например: 23:00")
        return

    if st=="set_retention":
        try:
            d=int(text); assert d>=1
            deleted=db.set_retention(d); states[uid]="history"
            send(vk,uid,f"✅ Срок: {d} дн. Удалено: {deleted} записей",kbd_hist())
        except: send(vk,uid,"❌ Целое число ≥ 1")
        return

    # ── 💻 Терминал ──────────────────────────────────────────────
    if st=="tg_bridge":
        if text=="« Назад":
            states[uid]="tools"; send(vk,uid,"🔧 Инструменты:",kbd_tools(uid)); return
        if text=="💬 Чаты":
            chats=[(r[0],r[1],r[2]) for r in bridge_get_known_chats()]
            if not chats:
                send(vk,uid,"📭 Нет известных чатов. Мост должен получить хотя бы одно сообщение.",kbd_tg_bridge()); return
            states[uid]="tg_bridge_chats"
            pending[uid]={"chats":chats}
            _show_bridge_chats(vk,uid,chats)
        elif text=="✏️ Написать":
            chats=[(r[0],r[1],r[2]) for r in bridge_get_known_chats() if r[2]]
            if not chats: send(vk,uid,"❌ Нет активных чатов. Включи в 💬 Чаты.",kbd_tg_bridge()); return
            lines=["✏️ Выбери чат:\n"]
            for i,(cid,cname,_) in enumerate(chats,1): lines.append(f"{i}. {cname}")
            send(vk,uid,"\n".join(lines)+"\n\nВведи номер:")
            states[uid]="tg_bridge_write_pick"; pending[uid]={"chats":chats}
        elif text=="↩️ Ответить":
            send(vk,uid,"↩️ Введи ref (chat_id:msg_id), например: -100123456:789")
            states[uid]="tg_bridge_reply_ref"
        elif text=="↪️ Переслать":
            send(vk,uid,"↪️ Введи ref (chat_id:msg_id) для пересылки:")
            states[uid]="tg_bridge_fwd_ref"
        elif text=="📋 История чата":
            chats=[(r[0],r[1],r[2]) for r in bridge_get_known_chats() if r[2]]
            if not chats: send(vk,uid,"❌ Нет активных чатов.",kbd_tg_bridge()); return
            lines=["📋 Выбери чат:\n"]
            for i,(cid,cname,_) in enumerate(chats,1): lines.append(f"{i}. {cname}")
            send(vk,uid,"\n".join(lines)+"\n\nВведи номер:")
            states[uid]="tg_bridge_history_pick"; pending[uid]={"chats":chats}
        elif "Мост" in text:
            if "активен" in text:
                subprocess.run(["sudo","systemctl","stop","vm-bridge-tg"])
                send(vk,uid,"⏹ Мост остановлен",kbd_tg_bridge())
            else:
                subprocess.run(["sudo","systemctl","start","vm-bridge-tg"])
                send(vk,uid,"▶️ Мост запущен",kbd_tg_bridge())
        else: send(vk,uid,"❓",kbd_tg_bridge())
        return

    if st=="tg_bridge_chats":
        chats=pending.get(uid,{}).get("chats",[])
        if text in ("✅ Готово","« Назад"):
            states[uid]="tg_bridge"; pending.pop(uid,None); send(vk,uid,"📱 TG Мост:",kbd_tg_bridge()); return
        for cid,cname,act in chats:
            for lbl in (("✅ "+str(cname)[:25]),("⬜ "+str(cname)[:25])):
                if text==lbl:
                    bridge_set_active(cid,not act)
                    upd=[(c,n,(not a) if c==cid else a) for c,n,a in chats]
                    pending[uid]["chats"]=upd
                    _show_bridge_chats(vk,uid,upd); return
        _show_bridge_chats(vk,uid,chats)
        return

    if st=="tg_bridge_write_pick":
        if text=="« Назад":
            states[uid]="tg_bridge"; send(vk,uid,"📱 TG Мост:",kbd_tg_bridge()); return
        chats=pending.get(uid,{}).get("chats",[])
        try:
            n=int(text.strip())-1
            if not 0<=n<len(chats): send(vk,uid,f"❌ Номер 1-{len(chats)}"); return
            cid,cname,_=chats[n]
            pending[uid]["sel"]=(cid,cname)
            states[uid]="tg_bridge_write_text"
            send(vk,uid,f"✏️ Пишем в «{cname}»\nВведи текст:")
        except: send(vk,uid,"❌ Введи число")
        return

    if st=="tg_bridge_write_text":
        if text=="« Назад":
            states[uid]="tg_bridge"; send(vk,uid,"📱 TG Мост:",kbd_tg_bridge()); return
        sel=pending.pop(uid,{}).get("sel")
        if not sel: states[uid]="tg_bridge"; send(vk,uid,"❌ Сессия истекла",kbd_tg_bridge()); return
        cid,cname=sel
        if bridge_queue_cmd("send_text",chat_id=cid,text=text):
            send(vk,uid,f"✅ Отправлено в «{cname}»",kbd_tg_bridge())
        else: send(vk,uid,"❌ Мост недоступен",kbd_tg_bridge())
        states[uid]="tg_bridge"; return

    if st=="tg_bridge_reply_ref":
        if text=="« Назад":
            states[uid]="tg_bridge"; send(vk,uid,"📱 TG Мост:",kbd_tg_bridge()); return
        msg=bridge_get_msg(text.strip())
        if not msg: send(vk,uid,"❌ Ref не найден. Формат: chat_id:msg_id"); return
        pending[uid]={"rep_chat":msg["tg_chat_id"],"rep_msg":msg["tg_msg_id"],"sender":msg["sender"]}
        states[uid]="tg_bridge_reply_text"
        send(vk,uid,f"↩️ Ответ {msg['sender']} ({msg['chat_name']})\nВведи текст:")
        return

    if st=="tg_bridge_reply_text":
        if text=="« Назад":
            states[uid]="tg_bridge"; pending.pop(uid,None); send(vk,uid,"📱 TG Мост:",kbd_tg_bridge()); return
        d=pending.pop(uid,{})
        if bridge_queue_cmd("send_text",chat_id=d.get("rep_chat"),text=text,reply_to=d.get("rep_msg")):
            send(vk,uid,"✅ Ответ отправлен",kbd_tg_bridge())
        else: send(vk,uid,"❌ Мост недоступен",kbd_tg_bridge())
        states[uid]="tg_bridge"; return

    if st=="tg_bridge_fwd_ref":
        if text=="« Назад":
            states[uid]="tg_bridge"; send(vk,uid,"📱 TG Мост:",kbd_tg_bridge()); return
        msg=bridge_get_msg(text.strip())
        if not msg: send(vk,uid,"❌ Ref не найден"); return
        chats=[(r[0],r[1],r[2]) for r in bridge_get_known_chats() if r[2]]
        if not chats: send(vk,uid,"❌ Нет активных чатов",kbd_tg_bridge()); states[uid]="tg_bridge"; return
        lines=["↪️ Переслать в:\n"]
        for i,(cid,cname,_) in enumerate(chats,1): lines.append(f"{i}. {cname}")
        pending[uid]={"fwd_chat":msg["tg_chat_id"],"fwd_msg":msg["tg_msg_id"],"to_chats":chats}
        send(vk,uid,"\n".join(lines)+"\n\nВведи номер:")
        states[uid]="tg_bridge_fwd_pick"; return

    if st=="tg_bridge_fwd_pick":
        if text=="« Назад":
            states[uid]="tg_bridge"; pending.pop(uid,None); send(vk,uid,"📱 TG Мост:",kbd_tg_bridge()); return
        d=pending.pop(uid,{}); chats=d.get("to_chats",[])
        try:
            n=int(text.strip())-1
            if not 0<=n<len(chats): send(vk,uid,f"❌ Номер 1-{len(chats)}"); return
            if bridge_queue_cmd("forward",chat_id=chats[n][0],fwd_chat=d["fwd_chat"],fwd_msg=d["fwd_msg"]):
                send(vk,uid,f"✅ Переслано в «{chats[n][1]}»",kbd_tg_bridge())
            else: send(vk,uid,"❌ Мост недоступен",kbd_tg_bridge())
        except: send(vk,uid,"❌ Введи число")
        states[uid]="tg_bridge"; return

    if st=="tg_bridge_history_pick":
        if text=="« Назад":
            states[uid]="tg_bridge"; send(vk,uid,"📱 TG Мост:",kbd_tg_bridge()); return
        chats=pending.pop(uid,{}).get("chats",[])
        try:
            n=int(text.strip())-1
            if not 0<=n<len(chats): send(vk,uid,f"❌ Номер 1-{len(chats)}"); return
            cid,cname,_=chats[n]
            rows=bridge_get_history(cid,100)
            if not rows: send(vk,uid,"📭 История пуста",kbd_tg_bridge()); states[uid]="tg_bridge"; return
            import tempfile as _tf,os as _os
            lines_h=[]
            for r in reversed(list(rows)): lines_h.append(f"[{str(r[3])[:16]}] {r[1]}: ref={r[0]}")
            body=f"История чата: {cname}\n{"="*40}\n"+"\n".join(lines_h)
            with _tf.NamedTemporaryFile(delete=False,suffix=".txt",mode="w",encoding="utf-8") as f:
                f.write(body); fpath=f.name
            try:
                att=vk_upload_doc(uid,fpath,f"history_{cname[:15]}.txt",f"История {cname}")
                send_attach(vk,uid,f"📋 История «{cname}» ({len(rows)} строк)",att,kbd_tg_bridge())
            except: send(vk,uid,body[:4000],kbd_tg_bridge())
            _os.unlink(fpath)
        except Exception as e: send(vk,uid,f"❌ {e}",kbd_tg_bridge())
        states[uid]="tg_bridge"; return

    if st=="console":
        if text=="« Назад":
            states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main()); return
        send(vk,uid,"⏳ Выполняю...")
        ok,out=run_cmd_vk(text,timeout=30)
        result=out or "(нет вывода)"
        send(vk,uid,f"{'✅' if ok else '❌'} $ {text[:100]}\n\n{result}",kbd_console())
        db.log_command("vk",uid,f"console: {text[:100]}",result[:200],ok)
        return

    # ── 🔑 Туннель ────────────────────────────────────────────
    if st=="wg_adduser_name":
        name=text
        if not name or ' ' in name:
            send(vk,uid,"❌ Имя не должно быть пустым или содержать пробелы. Повторите:"); return
        send(vk,uid,f"⏳ Добавляю {name}…")
        ok,out=run_cmd_vk(f"wv adduser {name}")
        states[uid]="wg"
        send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_wg())
        db.log_command("vk",uid,f"wg adduser {name}",out[:100],ok)
        return

    if st=="wg_getuser_name":
        name=text
        send(vk,uid,f"⏳ Получаю конфиг {name}…")
        ok,out=run_cmd_vk(f"wv getuser {name}")
        states[uid]="wg"
        if not ok:
            send(vk,uid,f"❌ {out}",kbd_wg())
            db.log_command("vk",uid,f"wg getuser {name}",out[:100],False)
            return
        try:
            import zipfile
            conf_bytes=out.encode()
            with tempfile.NamedTemporaryFile(delete=False,suffix=f"_{name}.conf") as cf:
                cf.write(conf_bytes); cpath=cf.name
            att=vk_upload_doc(uid,cpath,f"{name}.conf",f"WG {name}.conf")
            os.unlink(cpath)
            send_attach(vk,uid,f"🔑 Туннель конфиг: {name}",att,kbd_wg())
            with tempfile.NamedTemporaryFile(delete=False,suffix=".zip") as zf_tmp:
                zpath=zf_tmp.name
            with zipfile.ZipFile(zpath,'w',zipfile.ZIP_DEFLATED) as zf:
                zf.writestr(f"{name}.conf",out)
            att2=vk_upload_doc(uid,zpath,f"{name}.zip",f"WG {name}.zip")
            os.unlink(zpath)
            send_attach(vk,uid,f"📦 ZIP архив: {name}",att2)
            db.log_command("vk",uid,f"wg getuser {name}","отправлен .conf+.zip",True)
        except Exception as e:
            send(vk,uid,f"❌ Ошибка загрузки файла: {e}",kbd_wg())
        return

    if st=="wg_deluser_name":
        pending[uid]={'wg_del_name':text}; states[uid]="wg_deluser_pin"
        send(vk,uid,f"🔐 Удалить {text}? Введите PIN:"); return

    if st=="wg_deluser_pin":
        name=pending.get(uid,{}).get('wg_del_name','?')
        if text==cfg["admin_pin"]:
            send(vk,uid,f"⏳ Удаляю {name}…")
            ok,out=run_cmd_vk(f"wv deluser {name}")
            states[uid]="wg"
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_wg())
            db.log_command("vk",uid,f"wg deluser {name}",out[:100],ok)
        else:
            db.log_command("vk",uid,f"wg deluser {name}","неверный PIN",False)
            states[uid]="wg"; send(vk,uid,"❌ Неверный PIN. Отменено.",kbd_wg())
        return

    # ── 📡 Медиасервер ──────────────────────────────────────────────
    if st=="vkpanel_stop_pin":
        if text==cfg["admin_pin"]:
            send(vk,uid,"⏳ Остановка МС…")
            ok,out=run_vkpanel_vk(2)
            states[uid]="vkpanel"
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_vkpanel())
            db.log_command("vk",uid,"vkpanel stop",out[:100],ok)
        else:
            db.log_command("vk",uid,"vkpanel stop","неверный PIN",False)
            states[uid]="vkpanel"; send(vk,uid,"❌ Неверный PIN.",kbd_vkpanel())
        return

    # ── ⚙️ Ядро ─────────────────────────────────────────────────
    if st=="xui_stop_pin":
        if text==cfg["admin_pin"]:
            send(vk,uid,"⏳ Остановка ядра…")
            ok,out=run_xui_vk(12)
            states[uid]="xui"
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_xui())
            db.log_command("vk",uid,"xui stop",out[:100],ok)
        else:
            db.log_command("vk",uid,"xui stop","неверный PIN",False)
            states[uid]="xui"; send(vk,uid,"❌ Неверный PIN.",kbd_xui())
        return

    if st=="xui_port_pin":
        if text==cfg["admin_pin"]:
            pending[uid]={'xui_port_auth':True}; states[uid]="xui_port_input"
            send(vk,uid,"🔌 Введите новый порт (1–65535):")
        else:
            db.log_command("vk",uid,"xui port","неверный PIN",False)
            states[uid]="xui"; send(vk,uid,"❌ Неверный PIN.",kbd_xui())
        return

    if st=="xui_port_input":
        try:
            port=int(text); assert 1<=port<=65535
        except:
            send(vk,uid,"❌ Неверный порт (1–65535):"); return
        send(vk,uid,f"⏳ Меняю порт ядра на {port}…")
        try:
            r=subprocess.run(f'printf "9\\n{port}\\n" | x-ui',shell=True,
                            capture_output=True,text=True,timeout=20,
                            env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
            out=(r.stdout+r.stderr).strip()[:4000]; ok=r.returncode==0
        except Exception as e: ok=False; out=str(e)
        states[uid]="xui"
        send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_xui())
        db.log_command("vk",uid,f"xui port {port}",out[:100],ok)
        return

    if st=="xui_reset_pin":
        if text==cfg["admin_pin"]:
            send(vk,uid,"⏳ Сброс ядра…")
            ok,out=run_xui_vk(8)
            states[uid]="xui"
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_xui())
            db.log_command("vk",uid,"xui reset",out[:100],ok)
        else:
            db.log_command("vk",uid,"xui reset","неверный PIN",False)
            states[uid]="xui"; send(vk,uid,"❌ Неверный PIN.",kbd_xui())
        return

    # ── Навигация по меню ────────────────────────────────────────
    if st=="main":
        if text=="📊 Статус":
            if not user_can(uid,"vm_control"):
                send(vk,uid,"⛔ Управление ВМ доступно только администратору",kbd_main()); return
            ok,s,_=VM.status()
            e={"RUNNING":"🟢","STOPPED":"🔴","STARTING":"🟡","STOPPING":"🟡"}.get(s,"⚪") if ok else "❌"
            r=f"{e} Статус ВМ: {s}" if ok else f"❌ {s}"
            db.log_command("vk",uid,"статус",r,ok); send(vk,uid,r,kbd_main())
        elif text=="ℹ️ Информация":
            if not user_can(uid,"vm_control"):
                send(vk,uid,"⛔ Управление ВМ доступно только администратору",kbd_main()); return
            ok,info=VM.info(); db.log_command("vk",uid,"информация","ОК" if ok else info,ok)
            send(vk,uid,info if ok else f"❌ {info}",kbd_main())
        elif text=="▶️ Запустить":
            if not user_can(uid,"vm_control"):
                send(vk,uid,"⛔ Управление ВМ доступно только администратору",kbd_main()); return
            send(vk,uid,"⏳ Запуск ВМ...",kbd_main()); ok,m=VM.start()
            db.log_command("vk",uid,"запуск ВМ",m,ok); send(vk,uid,m,kbd_main())
        elif text=="⏹ Остановить":
            if not user_can(uid,"vm_control"):
                send(vk,uid,"⛔ Управление ВМ доступно только администратору",kbd_main()); return
            send(vk,uid,"⏳ Остановка ВМ...",kbd_main()); ok,m=VM.stop()
            db.log_command("vk",uid,"остановка ВМ",m,ok); send(vk,uid,m,kbd_main())
        elif text=="🔄 Перезапустить":
            if not user_can(uid,"vm_control"):
                send(vk,uid,"⛔ Управление ВМ доступно только администратору",kbd_main()); return
            send(vk,uid,"⏳ Перезапуск...",kbd_main()); ok,m=VM.restart()
            db.log_command("vk",uid,"перезапуск ВМ",m,ok); send(vk,uid,m,kbd_main())
        elif text=="🔵 TG бот":
            if not cfg["tg_installed"]: send(vk,uid,"❌ TG бот не установлен",kbd_main()); return
            states[uid]="tg_control"; a=svc_active(TG_SVC)
            send(vk,uid,f"🔵 Telegram бот\nСтатус: {'🟢 активен' if a else '🔴 неактивен'}",kbd_tg())
        elif text=="📋 История": states[uid]="history"; send(vk,uid,"📋 История и БД:",kbd_hist())
        elif text=="⚙️ Настройки": states[uid]="settings"; send(vk,uid,"⚙️ Настройки:",kbd_settings(uid))
        elif text=="🔧 Инструменты":
            states[uid]="tools"; send(vk,uid,"🔧 Инструменты:",kbd_tools(uid))
        elif text=="⏰ Расписание":
            if not user_can(uid,"vm_control"):
                send(vk,uid,"⛔ Расписание доступно только администратору",kbd_main()); return
            states[uid]="schedule_vk"; _show_schedule_vk(vk,uid)
        else: send(vk,uid,"❓ Используйте кнопки.",kbd_main())

    elif st=="tools":
        if text=="💻 Терминал":
            if not user_can(uid,"terminal"):
                send(vk,uid,"⛔ Терминал доступен только администратору",kbd_tools(uid)); return
            states[uid]="console"
            send(vk,uid,"💻 Терминал\nВведите команду. Таймаут: 30с | Лимит: 4000 символов\n\nИли «Назад»",kbd_console())
        elif text=="🔑 Туннель":
            if not user_can(uid,"tunnel"):
                send(vk,uid,"⛔ Туннель доступен только администратору",kbd_tools(uid)); return
            states[uid]="wg"; send(vk,uid,"🔑 Туннель:",kbd_wg())
        elif text=="📡 Медиасервер":
            if not user_can(uid,"vkpanel"):
                send(vk,uid,"⛔ Медиасервер доступен только администратору",kbd_tools(uid)); return
            states[uid]="vkpanel"; send(vk,uid,"📡 Медиасервер:",kbd_vkpanel())
        elif text=="⚙️ Ядро":
            if not user_can(uid,"xui"):
                send(vk,uid,"⛔ Ядро доступно только администратору",kbd_tools(uid)); return
            states[uid]="xui"; send(vk,uid,"⚙️ Ядро:",kbd_xui())
        elif text=="📱 TG Мост":
            if not is_admin(uid):
                send(vk,uid,"⛔ TG Мост только для администратора",kbd_tools(uid)); return
            if not BRIDGE_DB.exists():
                send(vk,uid,"❌ TG Мост не установлен\nПункт 10 в меню установщика",kbd_tools(uid)); return
            states[uid]="tg_bridge"; send(vk,uid,"📱 TG Мост:",kbd_tg_bridge())
        elif text=="🎬 YouTube":
            if not user_can(uid,"youtube"):
                send(vk,uid,"⛔ YouTube-функции вам недоступны",kbd_tools(uid)); return
            states[uid]="youtube"; send(vk,uid,"🎬 YouTube:",kbd_youtube())
        elif text=="📁 YaDisk видео":
            token=cfg.get("yadisk_token","")
            if not token: send(vk,uid,"❌ Yandex токен не задан",kbd_tools(uid)); return
            try:
                import requests as req
                from datetime import datetime,timezone
                h={"Authorization":f"OAuth {token}"}
                r=req.get(YA_API,headers=h,timeout=30,
                          params={"path":YA_FOLDER,"fields":"_embedded.items","limit":"100"})
                if r.status_code==404:
                    send(vk,uid,"📁 Папка пуста — видео ещё не загружались",kbd_tools(uid)); return
                items=r.json().get("_embedded",{}).get("items",[])
                if not items:
                    send(vk,uid,"📁 Нет сохранённых видео",kbd_tools(uid)); return
                now=datetime.now(timezone.utc)
                lines=[]; total_mb=0
                for i,item in enumerate(sorted(items,key=lambda x:x.get("created",""),reverse=True),1):
                    sz=item.get("size",0)/(1024*1024); total_mb+=sz
                    try:
                        cr=datetime.fromisoformat(item["created"].replace("Z","+00:00"))
                        age=f"{(now-cr).days}д назад"
                    except: age="?"
                    lines.append(f"{i}. {item.get('name','?')[:40]}\n   📦 {sz:.1f} MB · 🕐 {age}")
                msg=f"📁 Видео на Яндекс.Диске ({len(items)} шт, {total_mb:.0f} MB):\n\n"+"\n\n".join(lines)
                states[uid]="yadisk_menu"
                send(vk,uid,msg,kbd_yadisk())
            except Exception as e:
                send(vk,uid,f"❌ {e}",kbd_tools(uid))
        else: send(vk,uid,"❓",kbd_tools(uid))

    elif st=="youtube":
        if text=="🔍 Поиск видео":
            states[uid]="yt_search_input"
            send(vk,uid,"🔍 Введи поисковый запрос:")
        elif text=="▶️ Последние видео канала":
            states[uid]="yt_channel_latest_input"
            send(vk,uid,"📺 Введи ссылку на YouTube канал или @username:")
        elif text=="📺 Мои подписки":
            data=load_yt_subs()
            my_subs=[(cid,ch) for cid,ch in data["channels"].items() if uid in ch.get("subscribers",[])]
            if not my_subs:
                send(vk,uid,"📭 Ты не подписан ни на один канал\n\nИспользуй «➕ Подписаться на канал»",kbd_youtube())
                return
            lines=["📺 Твои подписки:\n"]
            for i,(cid,ch) in enumerate(my_subs,1):
                lines.append(f"{i}. {ch.get('name',cid)}")
            send(vk,uid,"\n".join(lines)+"\n\nВведи номер для просмотра последних видео:")
            states[uid]="yt_subs_pick"
            pending[uid]={"subs":my_subs}
        elif text=="➕ Подписаться на канал":
            states[uid]="yt_subscribe_input"
            send(vk,uid,"📺 Введи ссылку на YouTube канал или @username:")
        elif text=="➖ Отписаться от канала":
            data=load_yt_subs()
            my_subs=[(cid,ch) for cid,ch in data["channels"].items() if uid in ch.get("subscribers",[])]
            if not my_subs:
                send(vk,uid,"📭 Ты не подписан ни на один канал",kbd_youtube()); return
            lines=["📺 Твои подписки:\n"]
            for i,(cid,ch) in enumerate(my_subs,1):
                lines.append(f"{i}. {ch.get('name',cid)}")
            send(vk,uid,"\n".join(lines)+"\n\nВведи номер для отписки:")
            states[uid]="yt_unsubscribe_input"
        elif text=="« Назад":
            states[uid]="tools"; send(vk,uid,"🔧 Инструменты:",kbd_tools(uid))
        else:
            send(vk,uid,"❓",kbd_youtube())

    elif st=="yt_subs_pick":
        if text=="« Назад":
            states[uid]="youtube"; send(vk,uid,"🎬 YouTube:",kbd_youtube()); return
        data_p=pending.pop(uid,{}); my_subs=data_p.get("subs",[])
        try:
            n=int(text.strip())-1
            if not 0<=n<len(my_subs):
                send(vk,uid,f"❌ Неверный номер (1-{len(my_subs)})"); return
            cid,ch=my_subs[n]
            send(vk,uid,f"⏳ Получаю последние видео «{ch.get('name',cid)}»...")
            _,_,videos=yt_get_channel_info(ch.get("url",cid))
            if not videos:
                send(vk,uid,"❌ Не удалось получить видео",kbd_youtube())
                states[uid]="youtube"; return
            lines=[f"📺 Последние видео:\n"]
            for i,v in enumerate(videos,1):
                lines.append(f"{i}. {v['title']}\n   {v['url']}")
            send(vk,uid,"\n\n".join(lines)+"\n\nВведи номер для скачивания:")
            states[uid]="yt_channel_latest_pick"
            pending[uid]={"videos":videos}
        except:
            send(vk,uid,"❌ Введи число")
        return

    elif st=="yadisk_menu":
        if text=="🗑 Удалить все видео":
            token=cfg.get("yadisk_token","")
            if not token: send(vk,uid,"❌ Токен не задан",kbd_tools(uid)); states[uid]="tools"; return
            send(vk,uid,"⏳ Удаляю все видео...")
            try:
                n=yadisk_cleanup(token,max_age_days=0)
                send(vk,uid,f"✅ Удалено {n} видео с Яндекс.Диска",kbd_tools(uid))
            except Exception as e:
                send(vk,uid,f"❌ {e}",kbd_tools(uid))
            states[uid]="tools"
        elif text=="« Назад":
            states[uid]="tools"; send(vk,uid,"🔧 Инструменты:",kbd_tools(uid))

    elif st=="tg_control":
        if text in ("🟢 TG активен","🔴 TG неактивен"):
            a=svc_active(TG_SVC); send(vk,uid,f"🔵 TG: {'🟢 активен' if a else '🔴 неактивен'}",kbd_tg())
        elif text=="▶️ Включить TG бота":
            ok,m=ctrl_svc(TG_SVC,"start"); db.log_command("vk",uid,"включить TG",m,ok); send(vk,uid,m,kbd_tg())
        elif text=="⏹ Выключить TG бота":
            ok,m=ctrl_svc(TG_SVC,"stop"); db.log_command("vk",uid,"выключить TG",m,ok); send(vk,uid,m,kbd_tg())
        elif text=="« Назад": states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_tg())

    elif st=="history":
        if text=="📜 Последние команды":
            rows=db.get_history(10)
            if not rows: send(vk,uid,"📭 История пуста",kbd_hist()); return
            lines=["📜 Последние 10 команд:\n"]
            for r in rows:
                lines.append(f"{'✅' if r['success'] else '❌'} {r['timestamp']}\n"
                             f"  [{r['platform'].upper()}] {r['command']}\n  ↳ {r['result'] or '—'}")
            send(vk,uid,"\n".join(lines),kbd_hist())
        elif text=="🤖 Авто-события":
            rows=db.get_auto_events(8)
            if not rows: send(vk,uid,"📭 Нет событий",kbd_hist()); return
            lines=["🤖 Авто-события:\n"]
            for r in rows:
                lines.append(f"{'✅' if r['success'] else '❌'} {r['timestamp']} [{r['event_type']}]\n  {r['details']}")
            send(vk,uid,"\n".join(lines),kbd_hist())
        elif text.startswith("⏱ Срок:"):
            days=db.get_setting("retention_days",db.DEFAULT_RETENTION_DAYS)
            states[uid]="set_retention"
            send(vk,uid,f"⏱ Текущий срок: {days} дней\nВведите новое значение (≥1):\n⚠️ Старые записи удалятся сразу.")
        elif text=="📊 Статистика БД":
            s=db.get_stats()
            send(vk,uid,(f"📊 Статистика БД\n\nКоманд: {s['total']} (TG:{s['tg']} VK:{s['vk']})\n"
                         f"Авто-событий: {s['auto']}\nСрок: {s['retention']} дн.\n"
                         f"Старейшая: {s['oldest']}\nНовейшая: {s['newest']}"),kbd_hist())
        elif text=="🗑️ Очистить историю":
            n=db.clear_all_history()
            db.log_auto_event("manual_clear",f"Ручная очистка VK: {n} записей")
            send(vk,uid,f"✅ Удалено {n} записей",kbd_hist())
        elif text=="« Назад":
            states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_hist())

    elif st=="settings":
        if text in ("🔒 Скрыть инструменты","🔓 Показать инструменты"):
            new_val=not get_sensitive(); set_sensitive(new_val)
            send(vk,uid,f"{'🔒 Инструменты скрыты' if new_val else '🔓 Инструменты видны'}",kbd_settings(uid))
        elif text=="👮 Администрирование":
            if not is_admin(uid):
                send(vk,uid,"⛔ Только для администратора",kbd_settings(uid)); return
            states[uid]="admin_menu"; send(vk,uid,"👮 Администрирование:",kbd_admin())
        elif text=="🗑️ Удалить бота с сервера":
            states[uid]="await_pin"
            send(vk,uid,"🔐 Введите PIN-код для удаления бота с сервера:")
        elif text=="« Назад":
            states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_settings(uid))

    elif st=="admin_menu":
        if not is_admin(uid):
            states[uid]="main"; send(vk,uid,"⛔",kbd_main()); return
        if text=="➕ Добавить пользователя":
            states[uid]="admin_add_user"
            send(vk,uid,"➕ Введи VK страницу пользователя\n(URL или @username, например: https://vk.com/durov или durov):")
        elif text=="➖ Удалить пользователя":
            data=load_admin()
            extra=data.get("extra_users",[])
            labels=data.get("user_labels",{})
            if not extra:
                send(vk,uid,"📭 Вайтлист пуст",kbd_admin()); return
            lines=["➖ Пользователи в вайтлисте:\n"]
            for u in extra:
                lines.append(f"• {labels.get(str(u),str(u))} (ID {u})")
            lines.append("\nВведи числовой VK ID для удаления:")
            send(vk,uid,"\n".join(lines))
            states[uid]="admin_remove_user"
        elif text=="📋 Список пользователей":
            data=load_admin()
            labels=data.get("user_labels",{}); gd=data.get("global_disabled",[])
            lines=["📋 Все разрешённые пользователи:\n",
                   "👑 Администраторы (из конфига):"]
            for u in cfg["allowed_users"]:
                lines.append(f"  • ID {u} (все права)")
            lines.append("\n🔓 Вайтлист:")
            extra=data.get("extra_users",[])
            if not extra:
                lines.append("  (пусто)")
            for u in extra:
                dis=data.get("disabled_features",{}).get(str(u),[])
                tag=f" [блок: {','.join(dis)}]" if dis else ""
                lines.append(f"  • {labels.get(str(u),str(u))} (ID {u}){tag}")
            lines.append(f"\n🚫 Глобально отключено для не-админов: {', '.join(gd) or 'ничего'}")
            send(vk,uid,"\n".join(lines),kbd_admin())
        elif text=="🔧 Функции пользователей":
            states[uid]="admin_features"
            send(vk,uid,(
                "🔧 Управление функциями\n\n"
                "Формат:\n<ID> <функция> вкл/выкл\nглобально <функция> вкл/выкл\n\n"
                "Функции: youtube, vm_control, terminal, tunnel, xui, vkpanel\n\n"
                "Примеры:\n"
                "123456 youtube выкл\n"
                "глобально vm_control выкл\n\n"
                "По умолчанию vm_control/terminal/tunnel/xui/vkpanel\nглобально выключены (только для админа)."))
        elif text=="📢 Рассылка":
            states[uid]="admin_broadcast"
            send(vk,uid,"📢 Введи текст рассылки (получат все пользователи из вайтлиста):")
        elif text=="⬆️ Обновить с GitHub":
            send(vk,uid,"⏳ Запускаю обновление с GitHub...\n\nБот перезапустится автоматически. Подожди ~30 секунд.",kbd_admin())
            def _do_github_update():
                try:
                    r=subprocess.run(
                        ["bash","/root/yabot_installer.sh","--github-force"],
                        capture_output=True,text=True,timeout=120,
                        env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
                    logger.info(f"github update: rc={r.returncode} {(r.stdout+r.stderr)[-200:]}")
                except Exception as e:
                    logger.error(f"github update error: {e}")
            threading.Thread(target=_do_github_update,daemon=True).start()
        elif text=="« Назад":
            states[uid]="settings"; send(vk,uid,"⚙️ Настройки:",kbd_settings(uid))
        else: send(vk,uid,"❓",kbd_admin())

    elif st in ("wg","wg_adduser","wg_getuser","wg_deluser"):
        if text=="👥 Пиры":
            ok,out=run_cmd_vk("wv listusers")
            send(vk,uid,f"👥 Пиры:\n{out or '—'}",kbd_wg())
            db.log_command("vk",uid,"wg listusers",out[:100],ok)
        elif text=="➕ Новый пир":
            states[uid]="wg_adduser_name"; send(vk,uid,"➕ Имя нового пира (без пробелов):")
        elif text=="📥 Экспорт":
            states[uid]="wg_getuser_name"; send(vk,uid,"📥 Имя пира для экспорта:")
        elif text=="🗑 Удалить пир":
            states[uid]="wg_deluser_name"; send(vk,uid,"🗑 Имя пира для удаления:")
        elif text=="« Назад":
            states[uid]="tools"; send(vk,uid,"🔧 Инструменты:",kbd_tools(uid))
        else: send(vk,uid,"❓",kbd_wg())

    elif st=="vkpanel":
        if text=="▶️ МС-старт":
            send(vk,uid,"⏳")
            ok,out=run_vkpanel_vk(1)
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_vkpanel())
            db.log_command("vk",uid,"vkpanel start",out[:100],ok)
        elif text=="⏹ МС-стоп":
            states[uid]="vkpanel_stop_pin"; send(vk,uid,"🔐 PIN для остановки МС:")
        elif text=="🔄 МС-рестарт":
            send(vk,uid,"⏳")
            ok,out=run_vkpanel_vk(3)
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_vkpanel())
            db.log_command("vk",uid,"vkpanel restart",out[:100],ok)
        elif text=="📊 МС-статус":
            send(vk,uid,"⏳")
            ok,out=run_vkpanel_vk(4)
            send(vk,uid,f"📊 Статус МС:\n{out or '—'}",kbd_vkpanel())
            db.log_command("vk",uid,"vkpanel status",out[:100],ok)
        elif text=="📋 МС-логи":
            send(vk,uid,"⏳ Получаю логи…")
            ok,out=run_vkpanel_vk(5)
            send(vk,uid,f"📋 Логи МС:\n{out or '—'}",kbd_vkpanel())
            db.log_command("vk",uid,"vkpanel logs",out[:50],ok)
        elif text=="📱 МС-QR":
            send(vk,uid,"⏳ Генерирую QR…")
            ok,out=run_vkpanel_vk(13,timeout=25)
            urls=re.findall(r'https?://\S+',out)
            url=urls[0].rstrip(')') if urls else None
            if url:
                try:
                    png=make_qr_bytes_vk(url)
                    att=vk_upload_photo(uid,png)
                    send_attach(vk,uid,f"📱 QR МС\n{url}",att,kbd_vkpanel())
                    db.log_command("vk",uid,"vkpanel qr",f"url={url[:80]}",True)
                except Exception as e:
                    send(vk,uid,f"❌ Ошибка QR: {e}",kbd_vkpanel())
            else:
                send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_vkpanel())
                db.log_command("vk",uid,"vkpanel qr","url не найден",False)
        elif text=="« Назад": states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_vkpanel())

    elif st=="xui":
        if text=="📊 Ядро-статус":
            send(vk,uid,"⏳")
            ok,out=run_xui_vk(15)
            send(vk,uid,f"📊 Статус ядра:\n{out or '—'}",kbd_xui())
            db.log_command("vk",uid,"xui status",out[:100],ok)
        elif text=="🔄 Ядро-рестарт":
            send(vk,uid,"⏳ Рестарт ядра…")
            ok,out=run_xui_vk(13)
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_xui())
            db.log_command("vk",uid,"xui restart",out[:100],ok)
        elif text=="📋 Ядро-логи":
            send(vk,uid,"⏳ Получаю логи…")
            ok,out=run_xui_vk(16)
            send(vk,uid,f"📋 Логи ядра:\n{out or '—'}",kbd_xui())
            db.log_command("vk",uid,"xui logs",out[:50],ok)
        elif text=="🔧 Ядро-настройки":
            send(vk,uid,"⏳")
            ok,out=run_xui_vk(10)
            send(vk,uid,f"⚙️ Настройки ядра:\n{out or '—'}",kbd_xui())
            db.log_command("vk",uid,"xui settings",out[:100],ok)
        elif text=="⏹ Ядро-стоп":
            states[uid]="xui_stop_pin"; send(vk,uid,"🔐 PIN для остановки ядра:")
        elif text=="🔌 Ядро-порт":
            states[uid]="xui_port_pin"; send(vk,uid,"🔐 PIN для смены порта:")
        elif text=="🔃 Ядро-сброс":
            states[uid]="xui_reset_pin"; send(vk,uid,"🔐 PIN для сброса:")
        elif text=="« Назад": states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_xui())

    else:
        states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())

def main():
    global vk_session_global
    if not cfg["group_token"]: print("❌ Нет токена VK"); return
    if not cfg["group_id"]: print("❌ Нет ID группы VK"); return
    vk_session_global=vk_api.VkApi(token=cfg["group_token"])
    vk=vk_session_global.get_api(); longpoll=VkBotLongPoll(vk_session_global,cfg["group_id"])
    logger.info(f"VK бот запущен v5.0. Group: {cfg['group_id']}"); print("✅ VK бот v5.0 запущен!")
    if cfg.get("ssh_host"): print(f"🌍 SSH NL VPS: {cfg['ssh_user']}@{cfg['ssh_host']}:{cfg['ssh_port']}")
    else: print("⚠️ SSH не настроен — YouTube загрузка локальная")

    # Фоновые потоки
    threading.Thread(target=_yt_check_subscriptions_thread,daemon=True).start()
    def _yadisk_weekly():
        while True:
            time.sleep(7*24*3600)
            token=cfg.get("yadisk_token","")
            if token:
                try:
                    n=yadisk_cleanup(token,max_age_days=7)
                    logger.info(f"YaDisk еженедельная очистка: удалено {n} файлов")
                except Exception as e:
                    logger.error(f"YaDisk cleanup scheduler: {e}")
    threading.Thread(target=_yadisk_weekly,daemon=True).start()

    while True:
        try:
            for event in longpoll.listen():
                if event.type==VkBotEventType.MESSAGE_NEW and event.from_user:
                    uid=event.message.from_id; text=event.message.text or ""
                    logger.info(f"VK [{uid}]: {text!r}")
                    try: handle(vk,uid,text)
                    except Exception as e:
                        logger.error(f"Ошибка [{uid}]: {e}")
                        try: send(vk,uid,f"❌ Ошибка: {e}")
                        except: pass
        except Exception as e:
            logger.error(f"Long Poll ошибка: {e}"); time.sleep(5)

if __name__=="__main__":
    main()

VKEOF
}


# ─────────────────────────────────────────────────────────────
# SYSTEMD + SUDOERS
# ─────────────────────────────────────────────────────────────

create_services() {
    echo -e "${YELLOW}🔧 Создание systemd служб...${NC}"
    ACTUAL_USER=${SUDO_USER:-root}
    if $INSTALL_TG; then
        cat > /etc/systemd/system/${TG_SERVICE}.service << EOF
[Unit]
Description=Yandex Cloud VM Telegram Bot v4.2
After=network.target
[Service]
Type=simple
User=$ACTUAL_USER
WorkingDirectory=$TG_DIR
Environment="PATH=/usr/local/bin:$TG_DIR/venv/bin:/usr/bin:/bin"
ExecStart=$TG_DIR/venv/bin/python3 $TG_DIR/vm_bot.py
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
    fi
    if $INSTALL_VK; then
        cat > /etc/systemd/system/${VK_SERVICE}.service << EOF
[Unit]
Description=Yandex Cloud VM VK Bot v4.2
After=network.target
[Service]
Type=simple
User=$ACTUAL_USER
WorkingDirectory=$VK_DIR
Environment="PATH=/usr/local/bin:$VK_DIR/venv/bin:/usr/bin:/bin"
ExecStart=$VK_DIR/venv/bin/python3 $VK_DIR/vk_bot.py
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
    fi
    chown -R $ACTUAL_USER:$ACTUAL_USER "$BOT_DIR"
    systemctl daemon-reload
    $INSTALL_TG && systemctl enable $TG_SERVICE && systemctl start $TG_SERVICE
    $INSTALL_VK && systemctl enable $VK_SERVICE && systemctl start $VK_SERVICE
    sleep 4
    $INSTALL_TG && { systemctl is-active --quiet $TG_SERVICE \
        && echo -e "${GREEN}✅ TG бот запущен${NC}" \
        || { echo -e "${RED}❌ Ошибка TG бота:${NC}"; journalctl -u $TG_SERVICE -n 10; }; }
    $INSTALL_VK && { systemctl is-active --quiet $VK_SERVICE \
        && echo -e "${GREEN}✅ VK бот запущен${NC}" \
        || { echo -e "${RED}❌ Ошибка VK бота:${NC}"; journalctl -u $VK_SERVICE -n 10; }; }
    echo ""
}

setup_sudoers() {
    echo -e "${YELLOW}🔐 Настройка sudoers...${NC}"
    ACTUAL_USER=${SUDO_USER:-root}
    SC=$(which systemctl)
    {
        echo "# vm-bot: cross-control and uninstall"
        $INSTALL_TG && echo "$ACTUAL_USER ALL=(ALL) NOPASSWD: $SC start $TG_SERVICE"
        $INSTALL_TG && echo "$ACTUAL_USER ALL=(ALL) NOPASSWD: $SC stop $TG_SERVICE"
        $INSTALL_VK && echo "$ACTUAL_USER ALL=(ALL) NOPASSWD: $SC start $VK_SERVICE"
        $INSTALL_VK && echo "$ACTUAL_USER ALL=(ALL) NOPASSWD: $SC stop $VK_SERVICE"
        echo "$ACTUAL_USER ALL=(ALL) NOPASSWD: $UNINSTALL_SCRIPT"
    } > /etc/sudoers.d/vm-bot
    chmod 440 /etc/sudoers.d/vm-bot
    echo -e "${GREEN}✅ Sudoers настроен${NC}"; echo ""
}

# ─────────────────────────────────────────────────────────────
# ОБНОВЛЕНИЕ КОНФИГУРАЦИИ
# ─────────────────────────────────────────────────────────────

update_config() {
    print_header
    echo -e "${CYAN}⚙️  ОБНОВЛЕНИЕ КОНФИГУРАЦИИ${NC}"; echo ""
    [ ! -f "$SHARED_CONFIG" ] && echo -e "${RED}❌ Боты не установлены${NC}" && sleep 2 && main_menu && return

    CUR_VM=$(jq -r '.vm_id' "$SHARED_CONFIG")
    CUR_INST=$(jq -r '.installed|join(", ")' "$SHARED_CONFIG")
    echo -e "${YELLOW}Установлено: $CUR_INST  |  VM: $CUR_VM${NC}"; echo ""

    if is_installed tg; then
        CUR_TG_TOK=$(jq -r '.tg.bot_token' "$SHARED_CONFIG")
        CUR_TG_USR=$(jq -r '.tg.allowed_users|join(",")' "$SHARED_CONFIG")
        echo -e "${BLUE}── 🔵 Telegram ──${NC}"
        read -p "TG токен [Enter — не менять]: " NTG_TOK; NTG_TOK=${NTG_TOK:-$CUR_TG_TOK}
        read -p "TG пользователи [$CUR_TG_USR]: " NTG_USR; NTG_USR=${NTG_USR:-$CUR_TG_USR}
        echo ""
    fi

    if is_installed vk; then
        CUR_VK_TOK=$(jq -r '.vk.group_token' "$SHARED_CONFIG")
        CUR_VK_GRP=$(jq -r '.vk.group_id' "$SHARED_CONFIG")
        CUR_VK_USR=$(jq -r '.vk.allowed_users|join(",")' "$SHARED_CONFIG")
        CUR_VK_UTOK=$(jq -r '.vk.user_token // ""' "$SHARED_CONFIG")
        CUR_YADISK=$(jq -r '.vk.yadisk_token // ""' "$SHARED_CONFIG")
        echo -e "${BLUE}── 🟦 ВКонтакте ──${NC}"
        read -p "VK токен [Enter — не менять]: " NVK_TOK; NVK_TOK=${NVK_TOK:-$CUR_VK_TOK}
        read -p "VK группа ID [$CUR_VK_GRP]: " NVK_GRP; NVK_GRP=${NVK_GRP:-$CUR_VK_GRP}
        NVK_GRP="${NVK_GRP#-}"  # убираем минус если вставили из API
        read -p "VK пользователи [$CUR_VK_USR]: " NVK_USR; NVK_USR=${NVK_USR:-$CUR_VK_USR}
        read -p "Yandex OAuth Token [Enter — не менять]: " NYADISK; NYADISK=${NYADISK:-$CUR_YADISK}
        CUR_SSH_USER=$(jq -r '.vk.yadisk_ssh_user // "ubuntu"' "$SHARED_CONFIG")
        CUR_SSH_KEY=$(jq -r '.vk.yadisk_ssh_key // ""' "$SHARED_CONFIG")
        echo -e "${YELLOW}SSH загрузка на Яндекс.Диск через ВМ:${NC}"
        read -p "SSH пользователь [$CUR_SSH_USER]: " NSSH_USER; NSSH_USER=${NSSH_USER:-$CUR_SSH_USER}
        read -p "SSH ключ [$CUR_SSH_KEY]: " NSSH_KEY; NSSH_KEY=${NSSH_KEY:-$CUR_SSH_KEY}
        if [ -n "$NSSH_KEY" ] && [ ! -f "$NSSH_KEY" ]; then
            echo -e "${RED}⚠️  Файл ключа не найден: $NSSH_KEY${NC}"
        fi
        echo ""
    fi

    read -p "VM ID [$CUR_VM]: " NVM_ID; NVM_ID=${NVM_ID:-$CUR_VM}
    CUR_PIN=$(jq -r '.admin_pin' "$SHARED_CONFIG")
    read -s -p "Новый PIN (Enter — не менять): " NPIN; echo ""
    if [ -n "$NPIN" ]; then
        if [[ ! "$NPIN" =~ ^[0-9]{4,}$ ]]; then echo -e "${RED}❌ PIN не изменён${NC}"; NPIN="$CUR_PIN"
        else read -s -p "Повторите: " NPIN2; echo ""
             [ "$NPIN" != "$NPIN2" ] && echo -e "${RED}❌ Не совпадают, PIN не изменён${NC}" && NPIN="$CUR_PIN"
        fi
    else NPIN="$CUR_PIN"; fi

    FOLDER_ID=$(yc config get folder-id 2>/dev/null || jq -r '.folder_id' "$SHARED_CONFIG")
    INST_JSON=$(jq -r '.installed' "$SHARED_CONFIG")

    TG_BLOCK='"tg":null'
    if is_installed tg; then
        TGU=$(echo "$NTG_USR"|tr ','  '\n'|sed 's/^[[:space:]]*//'|jq -R 'tonumber'|jq -s '.')
        TG_BLOCK="\"tg\":{\"bot_token\":\"$NTG_TOK\",\"allowed_users\":$TGU}"
    fi

    VK_BLOCK='"vk":null'
    if is_installed vk; then
        VKU=$(echo "$NVK_USR"|tr ','  '\n'|sed 's/^[[:space:]]*//'|jq -R 'tonumber'|jq -s '.')
        VK_BLOCK="\"vk\":{\"group_token\":\"$NVK_TOK\",\"group_id\":$NVK_GRP,\"allowed_users\":$VKU,\"user_token\":\"$NVK_UTOK\",\"yadisk_token\":\"$NYADISK\",\"yadisk_ssh_user\":\"$NSSH_USER\",\"yadisk_ssh_key\":\"$NSSH_KEY\"}"
    fi

    printf '{"installed":%s,"vm_id":"%s","folder_id":"%s","admin_pin":"%s",%s,%s}\n' \
        "$INST_JSON" "$NVM_ID" "$FOLDER_ID" "$NPIN" "$TG_BLOCK" "$VK_BLOCK" > "$SHARED_CONFIG"
    chmod 600 "$SHARED_CONFIG"
    echo -e "${GREEN}✅ Конфигурация обновлена${NC}"; echo ""
    is_installed tg && systemctl restart $TG_SERVICE 2>/dev/null && echo -e "${GREEN}✅ TG бот перезапущен${NC}"
    is_installed vk && systemctl restart $VK_SERVICE 2>/dev/null && echo -e "${GREEN}✅ VK бот перезапущен${NC}"
    echo ""; read -p "Нажмите Enter..."; main_menu
}

# ─────────────────────────────────────────────────────────────
# УДАЛЕНИЕ
# ─────────────────────────────────────────────────────────────

uninstall_bot_silent() {
    for svc in $TG_SERVICE $VK_SERVICE; do
        systemctl stop $svc 2>/dev/null || true
        systemctl disable $svc 2>/dev/null || true
        rm -f /etc/systemd/system/$svc.service
    done
    systemctl daemon-reload
    crontab -l 2>/dev/null | grep -v "# VM_BOT" | crontab - 2>/dev/null || true
    rm -f /etc/sudoers.d/vm-bot; rm -rf "$BOT_DIR"
}

uninstall_bot() {
    print_header; echo -e "${RED}🗑️  УДАЛЕНИЕ БОТОВ${NC}"; echo ""
    local inst=false
    [ -d "$BOT_DIR" ] && inst=true
    systemctl is-active --quiet $TG_SERVICE 2>/dev/null && inst=true
    systemctl is-active --quiet $VK_SERVICE 2>/dev/null && inst=true
    if ! $inst; then echo -e "${YELLOW}Боты не установлены${NC}"; sleep 2; main_menu; return; fi
    echo -e "${YELLOW}⚠️  Будет удалено всё: боты, БД, конфиг, cron, sudoers${NC}"; echo ""
    read -p "Вы уверены? (yes/no): " c
    [ "$c" != "yes" ] && echo -e "${GREEN}Отменено${NC}" && sleep 2 && main_menu && return
    for svc in $TG_SERVICE $VK_SERVICE; do
        systemctl stop $svc 2>/dev/null && echo -e "${GREEN}✅ $svc остановлен${NC}" || true
        systemctl disable $svc 2>/dev/null || true
        rm -f /etc/systemd/system/$svc.service
    done
    systemctl daemon-reload
    crontab -l 2>/dev/null | grep -v "# VM_BOT" | crontab - 2>/dev/null || true
    rm -f /etc/sudoers.d/vm-bot; rm -rf "$BOT_DIR"
    echo -e "${GREEN}✅ Всё удалено${NC}"; echo ""; read -p "Enter..."; main_menu
}

# ─────────────────────────────────────────────────────────────
# СТАТУС / ЛОГИ / ПЕРЕЗАПУСК
# ─────────────────────────────────────────────────────────────

check_status() {
    print_header; echo -e "${CYAN}📊 СТАТУС${NC}"; echo ""
    if [ ! -d "$BOT_DIR" ]; then
        echo -e "${RED}❌ Боты не установлены${NC}"; echo ""; read -p "Enter..."; main_menu; return
    fi
    is_installed tg && { echo -e "${YELLOW}🔵 Telegram:${NC}"; svc_status_line $TG_SERVICE "  Служба"; echo ""; }
    is_installed vk && { echo -e "${YELLOW}🟦 ВКонтакте:${NC}"; svc_status_line $VK_SERVICE "  Служба"; echo ""; }
    echo -e "${YELLOW}Файлы:${NC}"
    [ -f "$SHARED_CONFIG" ] && echo -e "  Конфиг: ${GREEN}✓${NC}" || echo -e "  Конфиг: ${RED}✗${NC}"
    [ -f "$DB_FILE" ]       && echo -e "  БД:     ${GREEN}✓${NC}" || echo -e "  БД:     ${RED}✗${NC}"
    echo ""
    if [ -f "$DB_FILE" ]; then
        echo -e "${YELLOW}База данных:${NC}"
        python3 "$BOT_DIR/db_module.py" --stats 2>/dev/null | while read l; do echo "  $l"; done
        echo ""
    fi
    echo -e "${YELLOW}Cron:${NC}"
    crontab -l 2>/dev/null | grep "# VM_BOT" | while read l; do echo -e "  ${GREEN}✓${NC} $l"; done
    echo ""; read -p "Enter..."; main_menu
}

view_logs() {
    print_header; echo -e "${CYAN}📋 ЛОГИ${NC}"; echo ""
    is_installed tg && echo -e "  ${GREEN}1)${NC} Telegram бот"
    is_installed vk && echo -e "  ${GREEN}2)${NC} VK бот"
    echo -e "  ${RED}0)${NC} Назад"; echo ""
    read -p "Выберите: " c
    show_log() {
        echo ""; [ -f "$1" ] && tail -n 50 "$1" || echo -e "${RED}❌ Лог не найден${NC}"
        echo ""; echo -e "${YELLOW}Онлайн:${NC} ${BLUE}journalctl -u $2 -f${NC}"; echo ""
        read -p "Enter..."; view_logs
    }
    case $c in
        1) is_installed tg && show_log "$TG_DIR/bot.log" $TG_SERVICE || { echo -e "${RED}TG не установлен${NC}"; sleep 2; view_logs; } ;;
        2) is_installed vk && show_log "$VK_DIR/bot.log" $VK_SERVICE || { echo -e "${RED}VK не установлен${NC}"; sleep 2; view_logs; } ;;
        0) main_menu ;;
        *) echo -e "${RED}Неверный выбор!${NC}"; sleep 2; view_logs ;;
    esac
}

restart_bot() {
    print_header; echo -e "${CYAN}🔄 ПЕРЕЗАПУСК${NC}"; echo ""
    is_installed tg && echo -e "  ${GREEN}1)${NC} Telegram бот"
    is_installed vk && echo -e "  ${GREEN}2)${NC} VK бот"
    ( is_installed tg && is_installed vk ) && echo -e "  ${GREEN}3)${NC} Оба бота"
    echo -e "  ${RED}0)${NC} Назад"; echo ""; read -p "Выберите: " c
    _rs() {
        if systemctl is-active --quiet $1; then
            systemctl restart $1; sleep 3
            systemctl is-active --quiet $1 \
                && echo -e "${GREEN}✅ $2 перезапущен${NC}" \
                || echo -e "${RED}❌ Ошибка перезапуска $2${NC}"
        else
            echo -e "${YELLOW}$2 не запущен${NC}"; read -p "Запустить? (y/n): " yn
            [ "$yn" == "y" ] && systemctl start $1
        fi
    }
    case $c in
        1) is_installed tg && _rs $TG_SERVICE "TG бот" ;;
        2) is_installed vk && _rs $VK_SERVICE "VK бот" ;;
        3) is_installed tg && _rs $TG_SERVICE "TG бот"; is_installed vk && _rs $VK_SERVICE "VK бот" ;;
        0) main_menu; return ;;
        *) echo -e "${RED}Неверный выбор!${NC}"; sleep 2; restart_bot; return ;;
    esac
    echo ""; read -p "Enter..."; main_menu
}

# ─────────────────────────────────────────────────────────────
# АВТОВКЛЮЧЕНИЕ ВМ
# ─────────────────────────────────────────────────────────────

setup_auto_power() {
    print_header; echo -e "${CYAN}⚡ АВТОВКЛЮЧЕНИЕ ВМ${NC}"; echo ""
    [ ! -d "$BOT_DIR" ] && echo -e "${RED}❌ Боты не установлены${NC}" && sleep 2 && main_menu && return
    if [ -f "$SCHEDULE_FILE" ]; then
        AE=$(jq -r '.auto_start_enabled' "$SCHEDULE_FILE")
        AS=$(jq -r '.auto_stop_enabled'  "$SCHEDULE_FILE")
        ST=$(jq -r '.start_time' "$SCHEDULE_FILE")
        PT=$(jq -r '.stop_time'  "$SCHEDULE_FILE")
    else AE="false"; AS="false"; ST="09:00"; PT="22:00"; fi

    [ "$AE" == "true" ] && AE_S="${GREEN}ВКЛ${NC}" || AE_S="${RED}ВЫКЛ${NC}"
    [ "$AS" == "true" ] && AS_S="${GREEN}ВКЛ${NC}" || AS_S="${RED}ВЫКЛ${NC}"
    echo -e "  Автозапуск:    $(echo -e $AE_S) ($ST МСК)"
    echo -e "  Автоостановка: $(echo -e $AS_S) ($PT МСК)"; echo ""
    echo -e "  ${GREEN}1)${NC} Вкл/выкл автозапуск     ${GREEN}2)${NC} Время запуска"
    echo -e "  ${GREEN}3)${NC} Вкл/выкл автоостановку  ${GREEN}4)${NC} Время остановки"
    echo -e "  ${GREEN}5)${NC} Cron задачи  ${RED}0)${NC} Назад"; echo ""
    read -p "Выберите: " ac

    sv() {
        printf '{"auto_start_enabled":%s,"auto_stop_enabled":%s,"start_time":"%s","stop_time":"%s"}\n' \
            "$AE" "$AS" "$ST" "$PT" > "$SCHEDULE_FILE"
        upd_cron
    }

    case $ac in
        1) [ "$AE" == "true" ] && AE="false" || AE="true"; sv; sleep 1; setup_auto_power ;;
        2) read -p "Время запуска (ЧЧ:ММ): " T
           [[ $T =~ ^[0-9]{2}:[0-9]{2}$ ]] && ST="$T" && sv && echo -e "${GREEN}✅ $T МСК${NC}" \
               || echo -e "${RED}❌ Неверный формат${NC}"; sleep 2; setup_auto_power ;;
        3) [ "$AS" == "true" ] && AS="false" || AS="true"; sv; sleep 1; setup_auto_power ;;
        4) read -p "Время остановки (ЧЧ:ММ): " T
           [[ $T =~ ^[0-9]{2}:[0-9]{2}$ ]] && PT="$T" && sv && echo -e "${GREEN}✅ $T МСК${NC}" \
               || echo -e "${RED}❌ Неверный формат${NC}"; sleep 2; setup_auto_power ;;
        5) echo ""; crontab -l 2>/dev/null | grep "# VM_BOT" || echo -e "${YELLOW}Нет задач${NC}"
           echo ""; read -p "Enter..."; setup_auto_power ;;
        0) main_menu ;;
        *) echo -e "${RED}Неверный выбор!${NC}"; sleep 2; setup_auto_power ;;
    esac
}

upd_cron() {
    [ ! -f "$SCHEDULE_FILE" ] && return
    AE=$(jq -r '.auto_start_enabled' "$SCHEDULE_FILE")
    AS=$(jq -r '.auto_stop_enabled'  "$SCHEDULE_FILE")
    ST=$(jq -r '.start_time' "$SCHEDULE_FILE")
    PT=$(jq -r '.stop_time'  "$SCHEDULE_FILE")
    crontab -l 2>/dev/null | grep -v "# VM_BOT" | crontab - 2>/dev/null || true
    PY="$TG_DIR/venv/bin/python3"; SC="$TG_DIR/vm_bot.py"; DB="$BOT_DIR/db_module.py"
    CRON=$(crontab -l 2>/dev/null || echo "")
    [ "$AE" == "true" ] && {
        H=$(echo $ST|cut -d: -f1); M=$(echo $ST|cut -d: -f2)
        CRON="$CRON
$M $H * * * PATH=/usr/local/bin:/usr/bin:/bin $PY $SC --start # VM_BOT"; }
    [ "$AS" == "true" ] && {
        H=$(echo $PT|cut -d: -f1); M=$(echo $PT|cut -d: -f2)
        CRON="$CRON
$M $H * * * PATH=/usr/local/bin:/usr/bin:/bin $PY $SC --stop # VM_BOT"; }
    CRON="$CRON
0 3 * * * $PY $DB --cleanup # VM_BOT"
    echo "$CRON" | crontab -
    echo -e "${GREEN}✅ Cron обновлён${NC}"
}

# ─────────────────────────────────────────────────────────────
# ОБНОВЛЕНИЕ УСТАНОВЩИКА С GITHUB
# ─────────────────────────────────────────────────────────────

GITHUB_INSTALLER="https://raw.githubusercontent.com/z3552/z3552_yabot/main/yabot_installer.sh"
GITHUB_VERSION="https://raw.githubusercontent.com/z3552/z3552_yabot/main/version.json"

update_from_github() {
    local FORCE="${1:-}"
    print_header
    echo -e "${CYAN}⬆️  ОБНОВЛЕНИЕ С GITHUB${NC}"; echo ""
    echo -e "${YELLOW}Источник:${NC} $GITHUB_RAW"; echo ""

    # Текущая версия
    CUR_VER=$(grep -oP 'yabot_installer v\K[0-9.]+' "$0" 2>/dev/null || echo "?")
    echo -e "${YELLOW}Текущая версия:${NC} v$CUR_VER"

    # Проверяем version.json (маленький файл ~100 байт)
    echo -e "${YELLOW}Проверяем version.json на GitHub...${NC}"
    TMP_VER=$(mktemp)
    if ! curl -fsSL "$GITHUB_VERSION" -o "$TMP_VER" 2>/dev/null; then
        echo -e "${RED}❌ Ошибка: файл version.json не найден в репозитории.${NC}"
        rm -f "$TMP_VER"; echo ""; read -p "Enter..."; main_menu; return
    fi
    NEW_VER=$(python3 -c "import json; d=json.load(open('$TMP_VER')); print(d.get('version','?'))" 2>/dev/null || echo "?")
    CHANGELOG=$(python3 -c "
import json
d=json.load(open('$TMP_VER'))
for x in d.get('changelog',[]): print('  •',x)
" 2>/dev/null || echo "")
    rm -f "$TMP_VER"
    echo -e "${YELLOW}Версия на GitHub:${NC}  v$NEW_VER"; echo ""

    if [ "${NON_INTERACTIVE:-}" = "1" ]; then
        echo -e "${YELLOW}🔃 Принудительное обновление (non-interactive) v$CUR_VER → v$NEW_VER${NC}"; echo ""
    elif [ "$CUR_VER" = "$NEW_VER" ] && [ "$FORCE" != "force" ]; then
        echo -e "${GREEN}✅ Уже последняя версия (v$CUR_VER)${NC}"
        echo ""
        read -p "Принудительно переустановить текущую версию? (y/n): " force_confirm
        if [ "$force_confirm" != "y" ]; then
            echo -e "${GREEN}Отменено${NC}"; sleep 1; main_menu; return
        fi
        echo -e "${YELLOW}🔃 Принудительное обновление v$CUR_VER...${NC}"; echo ""
    elif [ "$CUR_VER" = "$NEW_VER" ] && [ "$FORCE" = "force" ]; then
        echo -e "${YELLOW}🔃 Принудительное обновление v$CUR_VER → v$NEW_VER${NC}"; echo ""
    else
        echo -e "${CYAN}Доступно: v$CUR_VER → v$NEW_VER${NC}"
        [ -n "$CHANGELOG" ] && echo -e "${YELLOW}Изменения:${NC}\n$CHANGELOG"
        echo ""
        read -p "Скачать и применить? (y/n): " confirm
        [ "$confirm" != "y" ] && echo -e "${GREEN}Отменено${NC}" && sleep 1 && main_menu && return
    fi

    # Скачиваем установщик
    TMP=$(mktemp)
    echo -e "${YELLOW}Загружаем установщик...${NC}"
    if ! curl -fsSL "$GITHUB_INSTALLER" -o "$TMP" 2>/dev/null; then
        echo -e "${RED}❌ Ошибка загрузки установщика.${NC}"
        rm -f "$TMP"; echo ""; read -p "Enter..."; main_menu; return
    fi
    cp "$TMP" /root/yabot_installer.sh
    chmod +x /root/yabot_installer.sh
    ln -sf /root/yabot_installer.sh /usr/local/bin/yabot
    rm -f "$TMP"
    echo -e "${GREEN}✅ Установщик обновлён до v$NEW_VER${NC}"; echo ""

    # Применяем новые скрипты ботов
    echo -e "${YELLOW}Применяем обновления ботов...${NC}"; echo ""
    # Перезапускаем себя с опцией 8 через exec
    exec bash /root/yabot_installer.sh --update-scripts
}

# ─────────────────────────────────────────────────────────────
# ОБНОВЛЕНИЕ СКРИПТОВ БОТОВ (без переустановки)
# ─────────────────────────────────────────────────────────────

update_bot_scripts() {
    print_header
    echo -e "${CYAN}🔄 ОБНОВЛЕНИЕ СКРИПТОВ БОТОВ${NC}"; echo ""
    [ ! -f "$SHARED_CONFIG" ] && echo -e "${RED}❌ Боты не установлены${NC}" && sleep 2 && main_menu && return

    echo -e "${YELLOW}Заменяет Python-файлы ботов на версию из этого установщика.${NC}"
    echo -e "${YELLOW}Config, БД и venv останутся нетронутыми.${NC}"; echo ""
    read -p "Продолжить? (y/n): " confirm
    [ "$confirm" != "y" ] && echo -e "${GREEN}Отменено${NC}" && sleep 1 && main_menu && return
    echo ""

    # Останавливаем ботов перед обновлением файлов
    echo -e "${YELLOW}⏹  Останавливаем ботов...${NC}"
    is_installed tg && { systemctl stop $TG_SERVICE 2>/dev/null; echo -e "  ${GREEN}✅ TG остановлен${NC}"; } || true
    is_installed vk && { systemctl stop $VK_SERVICE 2>/dev/null; echo -e "  ${GREEN}✅ VK остановлен${NC}"; } || true
    sleep 1
    echo ""

    # Новые pip-зависимости
    echo -e "${YELLOW}📦 Устанавливаем новые зависимости (Pillow, qrcode)...${NC}"
    if is_installed tg && [ -f "$TG_DIR/venv/bin/pip" ]; then
        "$TG_DIR/venv/bin/pip" install --quiet Pillow qrcode \
            && echo -e "  ${GREEN}✅ TG venv: Pillow qrcode${NC}" \
            || echo -e "  ${RED}❌ Ошибка установки TG зависимостей${NC}"
    fi
    if is_installed vk && [ -f "$VK_DIR/venv/bin/pip" ]; then
        "$VK_DIR/venv/bin/pip" install --quiet Pillow qrcode yt-dlp requests \
            && echo -e "  ${GREEN}✅ VK venv: Pillow qrcode yt-dlp${NC}" \
            || echo -e "  ${RED}❌ Ошибка установки VK зависимостей${NC}"
    fi
    echo ""

    # Перезаписываем Python-скрипты
    echo -e "${YELLOW}📝 Обновляем скрипты ботов...${NC}"
    ACTUAL_USER=${SUDO_USER:-root}
    if is_installed tg; then
        create_tg_bot_script
        chmod +x "$TG_DIR/vm_bot.py"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$TG_DIR/vm_bot.py"
        echo -e "  ${GREEN}✅ $TG_DIR/vm_bot.py обновлён ($(wc -l < $TG_DIR/vm_bot.py) строк)${NC}"
    fi
    if is_installed vk; then
        create_vk_bot_script
        chmod +x "$VK_DIR/vk_bot.py"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$VK_DIR/vk_bot.py"
        echo -e "  ${GREEN}✅ $VK_DIR/vk_bot.py обновлён ($(wc -l < $VK_DIR/vk_bot.py) строк)${NC}"
    fi
    echo ""

    # Обновляем симлинк yabot на текущий файл
    THIS_SCRIPT="$(readlink -f "$0")"
    if [ "$THIS_SCRIPT" != "/root/yabot_installer.sh" ]; then
        cp "$THIS_SCRIPT" /root/yabot_installer.sh
        chmod +x /root/yabot_installer.sh
    fi
    ln -sf /root/yabot_installer.sh /usr/local/bin/yabot
    chmod +x /usr/local/bin/yabot
    echo -e "  ${GREEN}✅ yabot симлинк обновлён${NC}"; echo ""

    # Запускаем ботов (restart гарантирует перезагрузку даже если был запущен)
    echo -e "${YELLOW}▶️  Перезапускаем ботов...${NC}"
    if is_installed tg; then
        systemctl restart $TG_SERVICE 2>/dev/null || systemctl start $TG_SERVICE; sleep 4
        systemctl is-active --quiet $TG_SERVICE \
            && echo -e "  ${GREEN}✅ TG бот перезапущен${NC}" \
            || { echo -e "  ${RED}❌ Ошибка TG бота:${NC}"; journalctl -u $TG_SERVICE -n 15 --no-pager; }
    fi
    if is_installed vk; then
        systemctl restart $VK_SERVICE 2>/dev/null || systemctl start $VK_SERVICE; sleep 4
        systemctl is-active --quiet $VK_SERVICE \
            && echo -e "  ${GREEN}✅ VK бот перезапущен${NC}" \
            || { echo -e "  ${RED}❌ Ошибка VK бота:${NC}"; journalctl -u $VK_SERVICE -n 15 --no-pager; }
    fi
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅ Обновление завершено! Новые разделы:                     ║${NC}"
    echo -e "${GREEN}║   💻 Терминал  🔑 Туннель  📡 Медиасервер  ⚙️ Ядро             ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""; read -p "Нажмите Enter..."; main_menu
}

# ─────────────────────────────────────────────────────────────
check_root || true
[ "$1" = "--update-scripts" ] && update_bot_scripts && exit 0
main_menu
