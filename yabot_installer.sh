#!/bin/bash
# Менеджер установки/удаления ботов для управления ВМ Яндекс.Облака
# Автор: z3552[Reenpak]  |  yabot_installer v5.3
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
        7) update_config ;; 8) update_bot_scripts ;; 9) update_from_github ;; 10) update_from_github force ;; 0) exit 0 ;;
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
    apt install -y python3 python3-pip python3-venv jq curl wget >/dev/null 2>&1
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
    # Убираем минус если вдруг вставили из API-ответа (например -12345678 → 12345678)
    VK_GROUP_ID="${VK_GROUP_ID#-}"
    [[ ! "$VK_GROUP_ID" =~ ^[0-9]+$ ]] && echo -e "${RED}❌ ID должен быть числом${NC}" && exit 1
    echo ""; read -p "VK User ID(s) через запятую: " VK_USER_IDS
    [ -z "$VK_USER_IDS" ] && echo -e "${RED}❌ Нужен хотя бы один ID${NC}" && exit 1
    VK_USER_IDS=$(echo "$VK_USER_IDS" | tr -d ' ')
    echo -e "${GREEN}✅ Данные VK собраны${NC}"; echo ""
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
        TG_BLOCK="\"tg\":{\"bot_token\":\"$TG_BOT_TOKEN\",\"allowed_users\":$TG_USERS_JSON}"
    else
        TG_BLOCK='"tg":null'
    fi

    if $INSTALL_VK; then
        VK_USERS_JSON=$(echo "$VK_USER_IDS"|tr ','  '\n'|sed 's/^[[:space:]]*//'|jq -R 'tonumber'|jq -s '.')
        VK_BLOCK="\"vk\":{\"group_token\":\"$VK_TOKEN\",\"group_id\":$VK_GROUP_ID,\"allowed_users\":$VK_USERS_JSON}"
    else
        VK_BLOCK='"vk":null'
    fi

    printf '{"installed":%s,"vm_id":"%s","folder_id":"%s","admin_pin":"%s",%s,%s}\n' \
        "$INSTALLED_JSON" "$VM_ID" "$FOLDER_ID" "$ADMIN_PIN" "$TG_BLOCK" "$VK_BLOCK" \
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
"""Telegram бот управления ВМ Яндекс.Облака. v4.2"""

import asyncio, json, logging, os, subprocess, sys, io, re, tempfile
from pathlib import Path
import pytz
from telegram import Update, ReplyKeyboardMarkup, KeyboardButton, ReplyKeyboardRemove
from telegram.ext import (Application, CommandHandler, MessageHandler,
                           ContextTypes, filters, ConversationHandler)

BASE_DIR = Path("/opt/vm_manager"); TG_DIR = BASE_DIR / "tg"
CONFIG_FILE = BASE_DIR / "config.json"; LOG_FILE = TG_DIR / "bot.log"
BASE_DIR.mkdir(parents=True, exist_ok=True); TG_DIR.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(BASE_DIR))
import db_module as db
db.init_db()

SETTINGS_FILE = BASE_DIR / "settings.json"

def get_sensitive():
    try:
        if SETTINGS_FILE.exists():
            return json.load(open(SETTINGS_FILE)).get("sensitive_mode", False)
    except: pass
    return False

def set_sensitive(val):
    s = {}
    try:
        if SETTINGS_FILE.exists(): s = json.load(open(SETTINGS_FILE))
    except: pass
    s["sensitive_mode"] = val
    with open(SETTINGS_FILE,"w") as f: json.dump(s,f)

(SET_START_TIME, SET_STOP_TIME, SET_RETENTION, AWAIT_DELETE_PIN,
 CONSOLE_INPUT,
 WG_ADDUSER_NAME, WG_GETUSER_NAME, WG_DELUSER_NAME, WG_DELUSER_PIN,
 VKPANEL_STOP_PIN,
 XUI_STOP_PIN, XUI_PORT_PIN, XUI_PORT_INPUT, XUI_RESET_PIN,
 YT_URL_STATE) = range(15)

logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s", level=logging.INFO,
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler()])
logger = logging.getLogger(__name__)

class Config:
    def __init__(self):
        self.bot_token=""; self.allowed_users=[]; self.vm_id=""
        self.folder_id=""; self.admin_pin=""; self.vk_installed=False
        self.load()
    def load(self):
        try:
            with open(CONFIG_FILE) as f: d = json.load(f)
            self.vm_id=d.get("vm_id",""); self.folder_id=d.get("folder_id","")
            self.admin_pin=d.get("admin_pin","")
            tg=d.get("tg") or {}
            self.bot_token=tg.get("bot_token",""); self.allowed_users=tg.get("allowed_users",[])
            self.vk_installed="vk" in (d.get("installed") or [])
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
        import time
        ok,s,_=YandexCloudVM.get_status()
        if not ok: return False,f"Нет статуса: {s}"
        if s=="RUNNING": return True,"ВМ уже запущена"
        if s=="STARTING": return True,"ВМ уже запускается"
        if s not in ["STOPPED","STOPPING"]: return False,f"Запуск невозможен: {s}"
        if s=="STOPPING":
            for _ in range(12):
                time.sleep(10); ok,s,_=YandexCloudVM.get_status()
                if ok and s=="STOPPED": break
            else: return False,"ВМ не остановилась за 2 мин"
        ok,out=YandexCloudVM._run(["yc","compute","instance","start",config.vm_id])
        return (True,"✅ ВМ запущена") if ok else (False,f"Ошибка: {out}")
    @staticmethod
    def stop():
        import time
        ok,s,_=YandexCloudVM.get_status()
        if not ok: return False,f"Нет статуса: {s}"
        if s=="STOPPED": return True,"ВМ уже остановлена"
        if s=="STOPPING": return True,"ВМ уже останавливается"
        if s not in ["RUNNING","STARTING"]: return False,f"Остановка невозможна: {s}"
        if s=="STARTING":
            for _ in range(12):
                time.sleep(10); ok,s,_=YandexCloudVM.get_status()
                if ok and s=="RUNNING": break
            else: return False,"ВМ не запустилась за 2 мин"
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

# ── Утилиты для новых разделов ───────────────────────────────
def run_cmd(cmd_str, timeout=30):
    """Неинтерактивная shell-команда. Возвращает (ok, output[≤4000])."""
    try:
        r=subprocess.run(cmd_str,shell=True,capture_output=True,text=True,timeout=timeout,
                        env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
        out=(r.stdout+r.stderr).strip()
        return r.returncode==0, out[:4000]
    except subprocess.TimeoutExpired: return False,f"⏱ Таймаут {timeout}с"
    except Exception as e: return False,str(e)

def run_vkpanel(n, timeout=20):
    return run_cmd(f'echo "{n}" | vk-panel', timeout)

def run_xui(n, timeout=20):
    return run_cmd(f'echo "{n}" | x-ui', timeout)

def make_qr_bytes(text):
    import qrcode
    buf=io.BytesIO(); qrcode.make(text).save(buf,format="PNG"); buf.seek(0)
    return buf.getvalue()

# ── Проверка доступа ─────────────────────────────────────────
def check_access(func):
    async def wrapper(update:Update,context:ContextTypes.DEFAULT_TYPE):
        if update.effective_user.id not in config.allowed_users:
            await update.message.reply_text("⛔️ Нет доступа"); return ConversationHandler.END
        return await func(update,context)
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
    rows = [
        [KeyboardButton("💻 Терминал"),     KeyboardButton("🔑 Туннель")],
        [KeyboardButton("📡 Медиасервер"),  KeyboardButton("⚙️ Ядро")],
    ]
    if not get_sensitive():
        rows.append([KeyboardButton("📹 YouTube")])
    rows.append([KeyboardButton("« Назад")])
    return ReplyKeyboardMarkup(rows, resize_keyboard=True)

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

def kbd_settings():
    lbl="🔒 Скрыть инструменты" if not get_sensitive() else "🔓 Показать инструменты"
    return ReplyKeyboardMarkup([
        [KeyboardButton(lbl)],
        [KeyboardButton("🗑️ Удалить бота с сервера")],
        [KeyboardButton("« Назад")],
    ],resize_keyboard=True)

def kbd_console():
    return ReplyKeyboardMarkup([[KeyboardButton("« Назад")]],resize_keyboard=True)

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

# ── Существующие обработчики ──────────────────────────────────
@check_access
async def start_command(u,c): await u.message.reply_text("👋 Панель управления ВМ v4.5",reply_markup=kbd_main())

@check_access
async def status_handler(u,c):
    msg=await u.message.reply_text("⏳")
    ok,s,_=YandexCloudVM.get_status()
    e={"RUNNING":"🟢","STOPPED":"🔴","STARTING":"🟡","STOPPING":"🟡"}.get(s,"⚪") if ok else "❌"
    r=f"{e} Статус ВМ: <b>{s}</b>" if ok else f"❌ {s}"
    await msg.edit_text(r,parse_mode="HTML")
    db.log_command("tg",u.effective_user.id,"статус",r,ok)

@check_access
async def info_handler(u,c):
    msg=await u.message.reply_text("⏳")
    ok,info=YandexCloudVM.get_info()
    await msg.edit_text(info if ok else f"❌ {info}",parse_mode="HTML" if ok else None)
    db.log_command("tg",u.effective_user.id,"информация","ОК" if ok else info,ok)

@check_access
async def start_vm(u,c):
    msg=await u.message.reply_text("⏳ Запуск ВМ...")
    ok,m=YandexCloudVM.start(); await msg.edit_text(m)
    db.log_command("tg",u.effective_user.id,"запуск ВМ",m,ok)

@check_access
async def stop_vm(u,c):
    msg=await u.message.reply_text("⏳ Остановка ВМ...")
    ok,m=YandexCloudVM.stop(); await msg.edit_text(m)
    db.log_command("tg",u.effective_user.id,"остановка ВМ",m,ok)

@check_access
async def restart_vm(u,c):
    msg=await u.message.reply_text("⏳ Перезапуск ВМ...")
    ok,m=YandexCloudVM.restart(); await msg.edit_text(m)
    db.log_command("tg",u.effective_user.id,"перезапуск ВМ",m,ok)

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
    await u.message.reply_text("Статус:",reply_markup=kbd_vk())

@check_access
async def vk_refresh(u,c): await vk_menu(u,c)

@check_access
async def schedule_h(u,c):
    t=(f"⏰ <b>Расписание</b>\n\n"
       f"Автозапуск: {'🟢 Вкл' if schedule_config.auto_start_enabled else '🔴 Выкл'} ({schedule_config.start_time} МСК)\n"
       f"Автоостановка: {'🟢 Вкл' if schedule_config.auto_stop_enabled else '🔴 Выкл'} ({schedule_config.stop_time} МСК)")
    await u.message.reply_text(t,parse_mode="HTML",reply_markup=kbd_schedule())

@check_access
async def toggle_start(u,c):
    schedule_config.auto_start_enabled=not schedule_config.auto_start_enabled
    schedule_config.save(); update_cron()
    s="включён" if schedule_config.auto_start_enabled else "выключен"
    await u.message.reply_text(f"✅ Автозапуск {s}",reply_markup=kbd_schedule())

@check_access
async def toggle_stop(u,c):
    schedule_config.auto_stop_enabled=not schedule_config.auto_stop_enabled
    schedule_config.save(); update_cron()
    s="включена" if schedule_config.auto_stop_enabled else "выключена"
    await u.message.reply_text(f"✅ Автоостановка {s}",reply_markup=kbd_schedule())

@check_access
async def set_start_begin(u,c):
    await u.message.reply_text("🕐 Введите время запуска ЧЧ:ММ (МСК). /cancel для отмены",
                               reply_markup=ReplyKeyboardRemove()); return SET_START_TIME

@check_access
async def set_start_end(u,c):
    try:
        h,m=map(int,u.message.text.strip().split(":"))
        if not(0<=h<=23 and 0<=m<=59): raise ValueError
        schedule_config.start_time=f"{h:02d}:{m:02d}"; schedule_config.save(); update_cron()
        await u.message.reply_text(f"✅ Время запуска: {schedule_config.start_time} МСК",reply_markup=kbd_main())
        return ConversationHandler.END
    except: await u.message.reply_text("❌ Формат: ЧЧ:ММ"); return SET_START_TIME

@check_access
async def set_stop_begin(u,c):
    await u.message.reply_text("🕐 Введите время остановки ЧЧ:ММ (МСК). /cancel для отмены",
                               reply_markup=ReplyKeyboardRemove()); return SET_STOP_TIME

@check_access
async def set_stop_end(u,c):
    try:
        h,m=map(int,u.message.text.strip().split(":"))
        if not(0<=h<=23 and 0<=m<=59): raise ValueError
        schedule_config.stop_time=f"{h:02d}:{m:02d}"; schedule_config.save(); update_cron()
        await u.message.reply_text(f"✅ Время остановки: {schedule_config.stop_time} МСК",reply_markup=kbd_main())
        return ConversationHandler.END
    except: await u.message.reply_text("❌ Формат: ЧЧ:ММ"); return SET_STOP_TIME

@check_access
async def history_menu(u,c):
    await u.message.reply_text("📋 <b>История и БД</b>",parse_mode="HTML",reply_markup=kbd_history())

@check_access
async def history_show(u,c):
    rows=db.get_history(15)
    if not rows: await u.message.reply_text("📭 История пуста",reply_markup=kbd_history()); return
    lines=["📜 <b>Последние 15 команд:</b>\n"]
    for r in rows:
        lines.append(f"{'✅' if r['success'] else '❌'} <code>{r['timestamp']}</code>\n"
                     f"   [{r['platform'].upper()}] uid:{r['user_id']} — {r['command']}\n"
                     f"   ↳ {r['result'] or '—'}\n")
    await u.message.reply_text("\n".join(lines),parse_mode="HTML",reply_markup=kbd_history())

@check_access
async def auto_events_show(u,c):
    rows=db.get_auto_events(10)
    if not rows: await u.message.reply_text("📭 Нет авто-событий",reply_markup=kbd_history()); return
    lines=["🤖 <b>Авто-события:</b>\n"]
    for r in rows:
        lines.append(f"{'✅' if r['success'] else '❌'} <code>{r['timestamp']}</code> [{r['event_type']}]\n   {r['details']}\n")
    await u.message.reply_text("\n".join(lines),parse_mode="HTML",reply_markup=kbd_history())

@check_access
async def db_stats(u,c):
    s=db.get_stats()
    await u.message.reply_text(
        f"📊 <b>Статистика БД</b>\n\n• Команд: {s['total']} (TG:{s['tg']} VK:{s['vk']})\n"
        f"• Авто-событий: {s['auto']}\n• Срок хранения: {s['retention']} дн.\n"
        f"• Старейшая: {s['oldest']}\n• Новейшая: {s['newest']}",
        parse_mode="HTML",reply_markup=kbd_history())

@check_access
async def set_retention_begin(u,c):
    days=db.get_setting("retention_days",db.DEFAULT_RETENTION_DAYS)
    await u.message.reply_text(
        f"⏱ Текущий срок: <b>{days} дней</b>\n\nВведите новое значение (≥1).\n"
        "⚠️ Записи старше лимита удалятся немедленно.\n\n/cancel для отмены",
        parse_mode="HTML",reply_markup=ReplyKeyboardRemove()); return SET_RETENTION

@check_access
async def set_retention_end(u,c):
    try:
        days=int(u.message.text.strip())
        if days<1: raise ValueError
        deleted=db.set_retention(days)
        await u.message.reply_text(f"✅ Срок хранения: {days} дн. Удалено: {deleted} записей",reply_markup=kbd_main())
        return ConversationHandler.END
    except: await u.message.reply_text("❌ Введите целое число ≥ 1"); return SET_RETENTION

@check_access
async def clear_history(u,c):
    deleted=db.clear_all_history()
    await u.message.reply_text(f"🗑️ Очищено: {deleted} записей",reply_markup=kbd_history())

@check_access
async def settings_menu(u,c):
    mode="🔒 Скрыт" if get_sensitive() else "🔓 Виден"
    await u.message.reply_text(f"⚙️ <b>Настройки</b>\n\n🔧 Инструменты: <b>{mode}</b>",parse_mode="HTML",reply_markup=kbd_settings())

@check_access
async def toggle_sensitive(u,c):
    val=not get_sensitive(); set_sensitive(val)
    mode="скрыты 🔒" if val else "видны 🔓"
    await u.message.reply_text(f"✅ Инструменты {mode}",reply_markup=kbd_settings())
    await u.message.reply_text("↩️ Меню:",reply_markup=kbd_main())

@check_access
async def delete_bot_begin(u,c):
    await u.message.reply_text("⚠️ <b>Удаление бота с сервера</b>\n\nВведите PIN:",
                               parse_mode="HTML",reply_markup=ReplyKeyboardRemove()); return AWAIT_DELETE_PIN

@check_access
async def delete_bot_pin(u,c):
    if u.message.text.strip()!=config.admin_pin:
        db.log_command("tg",u.effective_user.id,"удаление бота","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN. Отменено.",reply_markup=kbd_main())
        return ConversationHandler.END
    await u.message.reply_text("🗑️ PIN верный. Удаление через 3 секунды...")
    db.log_command("tg",u.effective_user.id,"удаление бота","выполнено",True)
    async def _del():
        await asyncio.sleep(3); subprocess.Popen(["sudo","/opt/vm_manager/uninstall.sh"])
    asyncio.create_task(_del()); return ConversationHandler.END

async def cancel_h(u,c):
    await u.message.reply_text("❌ Отменено",reply_markup=kbd_main()); return ConversationHandler.END

@check_access
async def back_main(u,c): await u.message.reply_text("Главное меню",reply_markup=kbd_main())

@check_access
async def tools_menu(u,c):
    await u.message.reply_text("🔧 <b>Инструменты</b>",parse_mode="HTML",reply_markup=kbd_tools())

# ── 💻 КОНСОЛЬ ───────────────────────────────────────────────
@check_access
async def console_menu(u,c):
    await u.message.reply_text(
        "💻 <b>Консоль</b>\n\nВведите команду (неинтерактивную).\n"
        "⏱ Таймаут: 30с | ✂️ Лимит вывода: 4000 символов\n\n/cancel для выхода",
        parse_mode="HTML", reply_markup=kbd_console())
    return CONSOLE_INPUT

@check_access
async def console_exec(u,c):
    cmd=u.message.text.strip()
    if cmd=="« Назад":
        await u.message.reply_text("Главное меню",reply_markup=kbd_main())
        return ConversationHandler.END
    msg=await u.message.reply_text("⏳ Выполняю...")
    ok,out=run_cmd(cmd,timeout=30)
    result=out or "(нет вывода)"
    disp=f"<code>$ {cmd[:150]}</code>\n\n<pre>{result}</pre>"
    # Telegram limit 4096 per message
    if len(disp)>4096: disp=disp[:4090]+"…</pre>"
    await msg.edit_text(disp,parse_mode="HTML")
    db.log_command("tg",u.effective_user.id,f"console: {cmd[:100]}",result[:200],ok)
    await u.message.reply_text("Следующая команда или /cancel:",reply_markup=kbd_console())
    return CONSOLE_INPUT

# ── 🔐 WIREGUARD ─────────────────────────────────────────────
@check_access
async def wg_menu(u,c):
    await u.message.reply_text("🔑 <b>Туннель</b>",parse_mode="HTML",reply_markup=kbd_wg())

@check_access
async def wg_listusers(u,c):
    msg=await u.message.reply_text("⏳")
    ok,out=run_cmd("wv listusers")
    await msg.edit_text(f"👥 <b>Пользователи WG:</b>\n<pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_wg())
    db.log_command("tg",u.effective_user.id,"wg listusers",out[:100],ok)

@check_access
async def wg_adduser_begin(u,c):
    await u.message.reply_text("➕ Введите имя нового пользователя:\n/cancel для отмены",
                               reply_markup=ReplyKeyboardRemove())
    return WG_ADDUSER_NAME

@check_access
async def wg_adduser_end(u,c):
    name=u.message.text.strip()
    if not name or ' ' in name:
        await u.message.reply_text("❌ Имя не должно быть пустым или содержать пробелы. Повторите:")
        return WG_ADDUSER_NAME
    msg=await u.message.reply_text(f"⏳ Добавляю {name}…")
    ok,out=run_cmd(f"wv adduser {name}")
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_wg())
    db.log_command("tg",u.effective_user.id,f"wg adduser {name}",out[:100],ok)
    return ConversationHandler.END

@check_access
async def wg_getuser_begin(u,c):
    await u.message.reply_text("📥 Введите имя пользователя для получения конфига:\n/cancel для отмены",
                               reply_markup=ReplyKeyboardRemove())
    return WG_GETUSER_NAME

@check_access
async def wg_getuser_end(u,c):
    name=u.message.text.strip()
    msg=await u.message.reply_text(f"⏳ Получаю конфиг {name}…")
    ok,out=run_cmd(f"wv getuser {name}")
    if not ok:
        await msg.edit_text(f"❌ <pre>{out}</pre>",parse_mode="HTML",reply_markup=kbd_wg())
        db.log_command("tg",u.effective_user.id,f"wg getuser {name}",out[:100],False)
        return ConversationHandler.END
    # Отправляем как .conf-файл и zip
    try:
        import zipfile
        conf_bytes=out.encode()
        with tempfile.NamedTemporaryFile(suffix=f"_{name}.conf",delete=False,mode='wb') as cf:
            cf.write(conf_bytes); conf_path=cf.name
        zip_path=conf_path+".zip"
        with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as zf:
            zf.write(conf_path,f"{name}.conf")
        await msg.delete()
        await u.message.reply_document(document=open(conf_path,'rb'),filename=f"{name}.conf",
                                       caption=f"🔑 Туннель конфиг: <b>{name}</b>",
                                       parse_mode="HTML",reply_markup=kbd_wg())
        await u.message.reply_document(document=open(zip_path,'rb'),filename=f"{name}.zip",
                                       caption=f"📦 ZIP: {name}.conf")
        os.unlink(conf_path); os.unlink(zip_path)
        db.log_command("tg",u.effective_user.id,f"wg getuser {name}","отправлен .conf+.zip",True)
    except Exception as e:
        await u.message.reply_text(f"❌ Ошибка отправки файла: {e}",reply_markup=kbd_wg())
    return ConversationHandler.END

@check_access
async def wg_deluser_begin(u,c):
    await u.message.reply_text("🗑 Введите имя пользователя для удаления:\n/cancel для отмены",
                               reply_markup=ReplyKeyboardRemove())
    return WG_DELUSER_NAME

@check_access
async def wg_deluser_name(u,c):
    c.user_data['wg_del_name']=u.message.text.strip()
    await u.message.reply_text(
        f"🔐 Удалить пользователя <b>{c.user_data['wg_del_name']}</b>?\nВведите PIN для подтверждения:",
        parse_mode="HTML")
    return WG_DELUSER_PIN

@check_access
async def wg_deluser_pin(u,c):
    name=c.user_data.get('wg_del_name','?')
    if u.message.text.strip()!=config.admin_pin:
        db.log_command("tg",u.effective_user.id,f"wg deluser {name}","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN. Отменено.",reply_markup=kbd_wg())
        return ConversationHandler.END
    msg=await u.message.reply_text(f"⏳ Удаляю {name}…")
    ok,out=run_cmd(f"wv deluser {name}")
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_wg())
    db.log_command("tg",u.effective_user.id,f"wg deluser {name}",out[:100],ok)
    return ConversationHandler.END

# ── 📡 Медиасервер ───────────────────────────────────────────────
@check_access
async def vkpanel_menu(u,c):
    await u.message.reply_text("📡 <b>Медиасервер</b>",parse_mode="HTML",reply_markup=kbd_vkpanel())

@check_access
async def vkpanel_start(u,c):
    msg=await u.message.reply_text("⏳ Старт МС…")
    ok,out=run_vkpanel(1)
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_vkpanel())
    db.log_command("tg",u.effective_user.id,"vkpanel start",out[:100],ok)

@check_access
async def vkpanel_restart(u,c):
    msg=await u.message.reply_text("⏳ Рестарт МС…")
    ok,out=run_vkpanel(3)
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_vkpanel())
    db.log_command("tg",u.effective_user.id,"vkpanel restart",out[:100],ok)

@check_access
async def vkpanel_status(u,c):
    ok,out=run_cmd("systemctl status whitelist-bypass 2>&1 | head -25 || "
                   "pgrep -fa vk-panel 2>&1 || echo 'Сервис не найден'")
    await u.message.reply_text(f"📊 <b>Статус МС:</b>\n<pre>{out}</pre>",
                               parse_mode="HTML",reply_markup=kbd_vkpanel())
    db.log_command("tg",u.effective_user.id,"vkpanel status",out[:100],ok)

@check_access
async def vkpanel_logs(u,c):
    msg=await u.message.reply_text("⏳ Получаю логи…")
    ok,out=run_vkpanel(16)
    await msg.edit_text(f"📋 <b>Логи МС:</b>\n<pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_vkpanel())
    db.log_command("tg",u.effective_user.id,"vkpanel logs",out[:50],ok)

@check_access
async def vkpanel_qr(u,c):
    msg=await u.message.reply_text("⏳ Генерирую QR…")
    ok,out=run_vkpanel(13,timeout=25)
    urls=re.findall(r'https?://\S+',out)
    url=urls[0].rstrip(')') if urls else None
    if url:
        try:
            png=make_qr_bytes(url)
            f=io.BytesIO(png); f.name="vkturn_qr.png"
            await msg.delete()
            await u.message.reply_document(document=f,filename="vkturn_qr.png",
                                           caption=f"📱 QR МС\n<code>{url}</code>",
                                           parse_mode="HTML",reply_markup=kbd_vkpanel())
            db.log_command("tg",u.effective_user.id,"vkpanel qr",f"url={url[:80]}",True)
        except Exception as e:
            await msg.edit_text(f"❌ Ошибка генерации QR: {e}",reply_markup=kbd_vkpanel())
    else:
        await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                            parse_mode="HTML",reply_markup=kbd_vkpanel())
        db.log_command("tg",u.effective_user.id,"vkpanel qr","url не найден",False)

@check_access
async def vkpanel_stop_begin(u,c):
    await u.message.reply_text("🔐 Введите PIN для остановки МС:",
                               reply_markup=ReplyKeyboardRemove())
    return VKPANEL_STOP_PIN

@check_access
async def vkpanel_stop_pin(u,c):
    if u.message.text.strip()!=config.admin_pin:
        db.log_command("tg",u.effective_user.id,"vkpanel stop","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN. Отменено.",reply_markup=kbd_vkpanel())
        return ConversationHandler.END
    msg=await u.message.reply_text("⏳ Остановка МС…")
    ok,out=run_vkpanel(2)
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_vkpanel())
    db.log_command("tg",u.effective_user.id,"vkpanel stop",out[:100],ok)
    return ConversationHandler.END

# ── 🛡 X-UI ──────────────────────────────────────────────────
@check_access
async def xui_menu(u,c):
    await u.message.reply_text("⚙️ <b>Ядро</b>",parse_mode="HTML",reply_markup=kbd_xui())

@check_access
async def xui_status(u,c):
    msg=await u.message.reply_text("⏳")
    ok,out=run_xui(15)
    await msg.edit_text(f"📊 <b>Статус ядра:</b>\n<pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_xui())
    db.log_command("tg",u.effective_user.id,"xui status",out[:100],ok)

@check_access
async def xui_restart(u,c):
    msg=await u.message.reply_text("⏳ Рестарт ядра…")
    ok,out=run_xui(13)
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_xui())
    db.log_command("tg",u.effective_user.id,"xui restart",out[:100],ok)

@check_access
async def xui_logs(u,c):
    msg=await u.message.reply_text("⏳ Получаю логи…")
    ok,out=run_xui(16)
    await msg.edit_text(f"📋 <b>Логи ядра:</b>\n<pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_xui())
    db.log_command("tg",u.effective_user.id,"xui logs",out[:50],ok)

@check_access
async def xui_settings(u,c):
    msg=await u.message.reply_text("⏳")
    ok,out=run_xui(10)
    await msg.edit_text(f"⚙️ <b>Настройки ядра:</b>\n<pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_xui())
    db.log_command("tg",u.effective_user.id,"xui settings",out[:100],ok)

@check_access
async def xui_stop_begin(u,c):
    await u.message.reply_text("🔐 PIN для остановки ядра:",reply_markup=ReplyKeyboardRemove())
    return XUI_STOP_PIN

@check_access
async def xui_stop_pin(u,c):
    if u.message.text.strip()!=config.admin_pin:
        db.log_command("tg",u.effective_user.id,"xui stop","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN.",reply_markup=kbd_xui())
        return ConversationHandler.END
    msg=await u.message.reply_text("⏳ Остановка ядра…")
    ok,out=run_xui(12)
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_xui())
    db.log_command("tg",u.effective_user.id,"xui stop",out[:100],ok)
    return ConversationHandler.END

@check_access
async def xui_port_begin(u,c):
    await u.message.reply_text("🔐 PIN для смены порта:",reply_markup=ReplyKeyboardRemove())
    return XUI_PORT_PIN

@check_access
async def xui_port_pin(u,c):
    if u.message.text.strip()!=config.admin_pin:
        db.log_command("tg",u.effective_user.id,"xui port","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN.",reply_markup=kbd_xui())
        return ConversationHandler.END
    await u.message.reply_text("🔌 Введите новый порт (1–65535):")
    return XUI_PORT_INPUT

@check_access
async def xui_port_input(u,c):
    try:
        port=int(u.message.text.strip())
        if not(1<=port<=65535): raise ValueError
    except ValueError:
        await u.message.reply_text("❌ Неверный порт (1–65535):")
        return XUI_PORT_INPUT
    msg=await u.message.reply_text(f"⏳ Меняю порт ядра на {port}…")
    try:
        r=subprocess.run(f'printf "9\\n{port}\\n" | x-ui',shell=True,
                        capture_output=True,text=True,timeout=20,
                        env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
        out=(r.stdout+r.stderr).strip()[:4000]; ok=r.returncode==0
    except Exception as e: ok=False; out=str(e)
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_xui())
    db.log_command("tg",u.effective_user.id,f"xui port {port}",out[:100],ok)
    return ConversationHandler.END

@check_access
async def xui_reset_begin(u,c):
    await u.message.reply_text("⚠️ <b>Сброс настроек x-ui!</b>\n🔐 Введите PIN:",
                               parse_mode="HTML",reply_markup=ReplyKeyboardRemove())
    return XUI_RESET_PIN

@check_access
async def xui_reset_pin(u,c):
    if u.message.text.strip()!=config.admin_pin:
        db.log_command("tg",u.effective_user.id,"xui reset","неверный PIN",False)
        await u.message.reply_text("❌ Неверный PIN.",reply_markup=kbd_xui())
        return ConversationHandler.END
    msg=await u.message.reply_text("⏳ Сброс ядра…")
    ok,out=run_xui(8)
    await msg.edit_text(f"{'✅' if ok else '❌'} <pre>{out or '—'}</pre>",
                        parse_mode="HTML",reply_markup=kbd_xui())
    db.log_command("tg",u.effective_user.id,"xui reset",out[:100],ok)
    return ConversationHandler.END

# ── YouTube download ─────────────────────────────────────────
@check_access
async def yt_begin(u,c):
    await u.message.reply_text(
        "📹 Отправь ссылку на YouTube-видео — бот пришлёт её через встроенный плеер Telegram.\n\nИли /cancel для отмены",
        reply_markup=ReplyKeyboardRemove())
    return YT_URL_STATE

@check_access
async def yt_download(u,c):
    text=u.message.text.strip()
    uid=u.effective_user.id
    if not text.startswith("http"):
        await u.message.reply_text("❌ Введи корректную ссылку (http...):")
        return YT_URL_STATE
    # Telegram автоматически встраивает YouTube через внутренний плеер
    await u.message.reply_text(text, reply_markup=kbd_main())
    db.log_command("tg",uid,f"yt {text[:80]}","embedded",True)
    return ConversationHandler.END

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
    app.add_handler(CommandHandler("start",start_command))

    # ── Существующие ConversationHandlers ──
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🕐 Время запуска$"),set_start_begin)],
        states={SET_START_TIME:[MessageHandler(filters.TEXT&~filters.COMMAND,set_start_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🕐 Время остановки$"),set_stop_begin)],
        states={SET_STOP_TIME:[MessageHandler(filters.TEXT&~filters.COMMAND,set_stop_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex(r"^⏱ Срок:"),set_retention_begin)],
        states={SET_RETENTION:[MessageHandler(filters.TEXT&~filters.COMMAND,set_retention_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🗑️ Удалить бота с сервера$"),delete_bot_begin)],
        states={AWAIT_DELETE_PIN:[MessageHandler(filters.TEXT&~filters.COMMAND,delete_bot_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))

    # ── 💻 Терминал ──
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^💻 Терминал$"),console_menu)],
        states={CONSOLE_INPUT:[MessageHandler(filters.TEXT&~filters.COMMAND,console_exec)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))

    # ── 🔑 Туннель ──
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^➕ Новый пир$"),wg_adduser_begin)],
        states={WG_ADDUSER_NAME:[MessageHandler(filters.TEXT&~filters.COMMAND,wg_adduser_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^📥 Экспорт$"),wg_getuser_begin)],
        states={WG_GETUSER_NAME:[MessageHandler(filters.TEXT&~filters.COMMAND,wg_getuser_end)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🗑 Удалить пир$"),wg_deluser_begin)],
        states={WG_DELUSER_NAME:[MessageHandler(filters.TEXT&~filters.COMMAND,wg_deluser_name)],
                WG_DELUSER_PIN: [MessageHandler(filters.TEXT&~filters.COMMAND,wg_deluser_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))

    # ── 📡 Медиасервер ──
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^⏹ МС-стоп$"),vkpanel_stop_begin)],
        states={VKPANEL_STOP_PIN:[MessageHandler(filters.TEXT&~filters.COMMAND,vkpanel_stop_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))

    # ── ⚙️ Ядро ──
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^⏹ Ядро-стоп$"),xui_stop_begin)],
        states={XUI_STOP_PIN:[MessageHandler(filters.TEXT&~filters.COMMAND,xui_stop_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🔌 Ядро-порт$"),xui_port_begin)],
        states={XUI_PORT_PIN:  [MessageHandler(filters.TEXT&~filters.COMMAND,xui_port_pin)],
                XUI_PORT_INPUT:[MessageHandler(filters.TEXT&~filters.COMMAND,xui_port_input)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^🔃 Ядро-сброс$"),xui_reset_begin)],
        states={XUI_RESET_PIN:[MessageHandler(filters.TEXT&~filters.COMMAND,xui_reset_pin)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))
    app.add_handler(ConversationHandler(
        entry_points=[MessageHandler(filters.Regex("^📹 YouTube$"),yt_begin)],
        states={YT_URL_STATE:[MessageHandler(filters.TEXT&~filters.COMMAND,yt_download)]},
        fallbacks=[CommandHandler("cancel",cancel_h)]))

    H=app.add_handler
    # ── Обычные обработчики ──
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
    # ── Новые разделы ──
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
    logger.info("TG бот запущен v4.4"); print("✅ TG бот запущен!")
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
"""VK бот управления ВМ Яндекс.Облака. v4.2"""

import json,os,random,subprocess,logging,time,sys,threading,io,re,tempfile
from pathlib import Path
import vk_api
from vk_api.bot_longpoll import VkBotLongPoll,VkBotEventType

BASE_DIR=Path("/opt/vm_manager"); VK_DIR=BASE_DIR/"vk"
CONFIG_FILE=BASE_DIR/"config.json"; LOG_FILE=VK_DIR/"bot.log"
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
    return {"vm_id":d.get("vm_id",""),"folder_id":d.get("folder_id",""),
            "admin_pin":d.get("admin_pin",""),
            "group_token":v.get("group_token",""),"group_id":int(v.get("group_id",0)),
            "allowed_users":[int(u) for u in v.get("allowed_users",[])],
            "tg_installed":"tg" in (d.get("installed") or [])}

cfg=load_cfg()
# Состояния пользователей
states:dict[int,str]={}
# Временные данные между состояниями (имена для WG/xui)
pending:dict[int,dict]={}
# Глобальная сессия VK (инициализируется в main)
vk_session_global=None

class VM:
    E={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin:/root/yandex-cloud/bin"}
    @staticmethod
    def run(cmd,t=60):
        try:
            r=subprocess.run(cmd,capture_output=True,text=True,timeout=t,env=VM.E)
            return (True,r.stdout.strip()) if r.returncode==0 else (False,r.stderr.strip())
        except subprocess.TimeoutExpired: return False,f"Таймаут {t}с"
        except Exception as e: return False,str(e)
    @staticmethod
    def status():
        ok,out=VM.run(["yc","compute","instance","get",cfg["vm_id"],"--format","json"])
        if ok:
            try: d=json.loads(out); return True,d.get("status","UNKNOWN"),d
            except: pass
        return False,out,None
    @staticmethod
    def start():
        ok,s,_=VM.status()
        if not ok: return False,f"Нет статуса: {s}"
        if s=="RUNNING": return True,"ВМ уже запущена"
        if s=="STARTING": return True,"ВМ уже запускается"
        if s not in ["STOPPED","STOPPING"]: return False,f"Запуск невозможен: {s}"
        if s=="STOPPING":
            for _ in range(12):
                time.sleep(10); ok,s,_=VM.status()
                if ok and s=="STOPPED": break
            else: return False,"ВМ не остановилась"
        ok,out=VM.run(["yc","compute","instance","start",cfg["vm_id"]])
        return (True,"✅ ВМ запущена") if ok else (False,f"Ошибка: {out}")
    @staticmethod
    def stop():
        ok,s,_=VM.status()
        if not ok: return False,f"Нет статуса: {s}"
        if s=="STOPPED": return True,"ВМ уже остановлена"
        if s=="STOPPING": return True,"ВМ уже останавливается"
        if s not in ["RUNNING","STARTING"]: return False,f"Остановка невозможна: {s}"
        if s=="STARTING":
            for _ in range(12):
                time.sleep(10); ok,s,_=VM.status()
                if ok and s=="RUNNING": break
            else: return False,"ВМ не запустилась"
        ok,out=VM.run(["yc","compute","instance","stop",cfg["vm_id"]])
        return (True,"✅ ВМ остановлена") if ok else (False,f"Ошибка: {out}")
    @staticmethod
    def restart():
        ok,s,_=VM.status()
        if not ok: return False,f"Нет статуса: {s}"
        if s!="RUNNING": return False,f"Нужен RUNNING, сейчас: {s}"
        ok,out=VM.run(["yc","compute","instance","restart",cfg["vm_id"]])
        return (True,"✅ ВМ перезапускается") if ok else (False,f"Ошибка: {out}")
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

# ── Утилиты для новых разделов ───────────────────────────────
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

def vk_upload_doc(uid,content_bytes,filename,title=""):
    """Загружает файл как VK-документ, возвращает attachment-строку."""
    if vk_session_global is None: raise RuntimeError("vk_session_global не инициализирован")
    with tempfile.NamedTemporaryFile(delete=False,suffix="_"+filename) as f:
        f.write(content_bytes); fpath=f.name
    try:
        upload=vk_api.VkUpload(vk_session_global)
        result=upload.document_message(fpath,peer_id=uid,title=title or filename)
        doc=result[0]["doc"] if isinstance(result,list) else result.get("doc",result)
        return f"doc{doc['owner_id']}_{doc['id']}"
    finally:
        os.unlink(fpath)

def vk_upload_photo(uid,png_bytes):
    """Загружает PNG-байты как VK-фото, возвращает attachment-строку."""
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

def kbd_tools():
    rows=[
        [{"l":"💻 Терминал"},{"l":"🔑 Туннель","c":"primary"}],
        [{"l":"📡 Медиасервер"},{"l":"⚙️ Ядро","c":"primary"}],
    ]
    if not get_sensitive(): rows.append([{"l":"📹 YouTube","c":"primary"}])
    rows.append([{"l":"« Назад"}])
    return _kbd(rows)

def kbd_tg():
    a=svc_active(TG_SVC)
    return _kbd([
        [{"l":"🟢 TG активен" if a else "🔴 TG неактивен","c":"positive" if a else "negative"}],
        [{"l":"▶️ Включить TG бота","c":"positive"},{"l":"⏹ Выключить TG бота","c":"negative"}],
        [{"l":"« Назад"}]])

def kbd_hist():
    days=db.get_setting("retention_days",db.DEFAULT_RETENTION_DAYS)
    return _kbd([
        [{"l":"📜 Последние команды","c":"primary"},{"l":"🤖 Авто-события","c":"primary"}],
        [{"l":f"⏱ Срок: {days}д"},{"l":"📊 Статистика БД"}],
        [{"l":"🗑️ Очистить историю","c":"negative"}],
        [{"l":"« Назад"}]])

def kbd_settings():
    lbl="🔒 Скрыть инструменты" if not get_sensitive() else "🔓 Показать инструменты"
    return _kbd([[{"l":lbl}],[{"l":"🗑️ Удалить бота с сервера","c":"negative"}],[{"l":"« Назад"}]])

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

# ── Отправка сообщений ────────────────────────────────────────
def send(vk,uid,text,kbd=None):
    p={"user_id":uid,"message":text,"random_id":random.randint(0,2**31)}
    if kbd: p["keyboard"]=kbd
    vk.messages.send(**p)

def send_attach(vk,uid,text,attachment,kbd=None):
    p={"user_id":uid,"message":text,"attachment":attachment,"random_id":random.randint(0,2**31)}
    if kbd: p["keyboard"]=kbd
    vk.messages.send(**p)

# ── Основной обработчик ───────────────────────────────────────
def handle(vk,uid,text):
    if uid not in cfg["allowed_users"]: send(vk,uid,"⛔ Нет доступа"); return
    st=states.get(uid,"main"); text=text.strip()

    if text.lower() in ("начать","start","/start","меню"):
        states[uid]="main"; send(vk,uid,"👋 Панель управления ВМ:",kbd_main()); return

    # ── Состояния: ввод PIN / имён ──────────────────────────────

    if st=="await_pin":  # удаление бота
        if text==cfg["admin_pin"]:
            db.log_command("vk",uid,"удаление бота","выполнено",True)
            send(vk,uid,"🗑️ PIN верный. Удаление через 3 секунды...")
            def _del(): time.sleep(3); subprocess.Popen(["sudo","/opt/vm_manager/uninstall.sh"])
            threading.Thread(target=_del,daemon=True).start()
        else:
            db.log_command("vk",uid,"удаление бота","неверный PIN",False)
            states[uid]="settings"; send(vk,uid,"❌ Неверный PIN. Отменено.",kbd_settings())
        return

    if st=="set_retention":
        try:
            d=int(text); assert d>=1
            deleted=db.set_retention(d); states[uid]="history"
            send(vk,uid,f"✅ Срок: {d} дн. Удалено: {deleted} записей",kbd_hist())
        except: send(vk,uid,"❌ Целое число ≥ 1")
        return

    # ── 💻 Терминал ──────────────────────────────────────────────
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
        # Отправляем .conf как документ
        try:
            import zipfile
            conf_bytes=out.encode()
            att=vk_upload_doc(uid,conf_bytes,f"{name}.conf",f"WG {name}.conf")
            send_attach(vk,uid,f"🔑 Туннель конфиг: {name}",att,kbd_wg())
            # Дополнительно zip
            with tempfile.NamedTemporaryFile(delete=False,suffix=".zip") as zf_tmp:
                zpath=zf_tmp.name
            with zipfile.ZipFile(zpath,'w',zipfile.ZIP_DEFLATED) as zf:
                zf.writestr(f"{name}.conf",out)
            with open(zpath,'rb') as f: zip_bytes=f.read()
            os.unlink(zpath)
            att2=vk_upload_doc(uid,zip_bytes,f"{name}.zip",f"WG {name}.zip")
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
            ok,s,_=VM.status()
            e={"RUNNING":"🟢","STOPPED":"🔴","STARTING":"🟡","STOPPING":"🟡"}.get(s,"⚪") if ok else "❌"
            r=f"{e} Статус ВМ: {s}" if ok else f"❌ {s}"
            db.log_command("vk",uid,"статус",r,ok); send(vk,uid,r,kbd_main())
        elif text=="ℹ️ Информация":
            ok,info=VM.info(); db.log_command("vk",uid,"информация","ОК" if ok else info,ok)
            send(vk,uid,info if ok else f"❌ {info}",kbd_main())
        elif text=="▶️ Запустить":
            send(vk,uid,"⏳ Запуск ВМ...",kbd_main()); ok,m=VM.start()
            db.log_command("vk",uid,"запуск ВМ",m,ok); send(vk,uid,m,kbd_main())
        elif text=="⏹ Остановить":
            send(vk,uid,"⏳ Остановка ВМ...",kbd_main()); ok,m=VM.stop()
            db.log_command("vk",uid,"остановка ВМ",m,ok); send(vk,uid,m,kbd_main())
        elif text=="🔄 Перезапустить":
            send(vk,uid,"⏳ Перезапуск...",kbd_main()); ok,m=VM.restart()
            db.log_command("vk",uid,"перезапуск ВМ",m,ok); send(vk,uid,m,kbd_main())
        elif text=="🔵 TG бот":
            if not cfg["tg_installed"]: send(vk,uid,"❌ TG бот не установлен",kbd_main()); return
            states[uid]="tg_control"; a=svc_active(TG_SVC)
            send(vk,uid,f"🔵 Telegram бот\nСтатус: {'🟢 активен' if a else '🔴 неактивен'}",kbd_tg())
        elif text=="📋 История": states[uid]="history"; send(vk,uid,"📋 История и БД:",kbd_hist())
        elif text=="⚙️ Настройки": states[uid]="settings"; send(vk,uid,"⚙️ Настройки:",kbd_settings())
        elif text=="🔧 Инструменты":
            states[uid]="tools"; send(vk,uid,"🔧 Инструменты:",kbd_tools())
        else: send(vk,uid,"❓ Используйте кнопки.",kbd_main())

    elif st=="tools":
        if text=="💻 Терминал":
            states[uid]="console"
            send(vk,uid,"💻 Терминал\n\nВведите команду (неинтерактивную).\n"
                        "⏱ Таймаут: 30с | ✂️ Лимит: 4000 символов\n\nИли нажмите «Назад»",kbd_console())
        elif text=="🔑 Туннель":
            states[uid]="wg"; send(vk,uid,"🔑 Туннель:",kbd_wg())
        elif text=="📡 Медиасервер":
            states[uid]="vkpanel"; send(vk,uid,"📡 Медиасервер:",kbd_vkpanel())
        elif text=="⚙️ Ядро":
            states[uid]="xui"; send(vk,uid,"⚙️ Ядро:",kbd_xui())
        elif text=="📹 YouTube":
            states[uid]="yt_url"; send(vk,uid,"📹 Отправь ссылку на YouTube-видео.\n⚠️ Лимит 45 MB | до 480p\n\nИли нажми «Назад»")
        elif text=="« Назад":
            states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_tools())

    elif st=="yt_url":
        if text=="« Назад":
            states[uid]="tools"; send(vk,uid,"🔧 Инструменты:",kbd_tools()); return
        if not text.startswith("http"):
            send(vk,uid,"❌ Введи корректную ссылку (http...):"); return
        send(vk,uid,"⏳ Скачиваю видео...")
        ytdlp=str(VK_DIR.parent/"tg/venv/bin/yt-dlp")
        import tempfile,glob
        with tempfile.TemporaryDirectory() as tmp:
            out=f"{tmp}/video.%(ext)s"
            try:
                r=subprocess.run([ytdlp,
                    "-f","best[ext=mp4]/bestvideo[ext=mp4]+bestaudio/best",
                    "--no-playlist","--socket-timeout","30",
                    "-o",out,"--no-part",text],
                    capture_output=True,text=True,timeout=300,
                    env={**os.environ,"PATH":"/usr/local/bin:/usr/bin:/bin"})
                if r.returncode!=0:
                    err=(r.stderr or r.stdout)[-400:]
                    send(vk,uid,f"❌ Ошибка:\n{err}",kbd_tools())
                    states[uid]="tools"; return
                files=glob.glob(f"{tmp}/video.*")
                if not files:
                    send(vk,uid,"❌ Файл не найден",kbd_tools()); states[uid]="tools"; return
                vpath=files[0]; sz=os.path.getsize(vpath)/(1024*1024)
                send(vk,uid,f"⬆️ Загружаю в VK ({sz:.1f} MB)...")
                upload=vk_api.VkUpload(vk_session_global)
                video=upload.video(vpath,name=f"YouTube ({sz:.1f} MB)",is_private=1)
                att=f"video{video['owner_id']}_{video['video_id']}"
                send_attach(vk,uid,f"📹 YouTube ({sz:.1f} MB)",att,kbd_tools())
                db.log_command("vk",uid,f"yt {text[:80]}",f"{sz:.1f}MB",True)
            except subprocess.TimeoutExpired:
                send(vk,uid,"⏱ Таймаут. Попробуй более короткое видео.",kbd_tools())
            except Exception as e:
                send(vk,uid,f"❌ {e}",kbd_tools())
        states[uid]="tools"

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
            deleted=db.clear_all_history(); send(vk,uid,f"🗑️ Очищено: {deleted} записей",kbd_hist())
        elif text=="« Назад": states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_hist())

    elif st=="settings":
        if text in ("🔒 Скрыть инструменты","🔓 Показать инструменты"):
            val=not get_sensitive(); set_sensitive(val)
            mode="скрыты 🔒" if val else "видны 🔓"
            send(vk,uid,f"✅ Инструменты {mode}",kbd_settings())
            send(vk,uid,"↩️ Меню:",kbd_main())
        elif text=="🗑️ Удалить бота с сервера":
            states[uid]="await_pin"
            send(vk,uid,"⚠️ Удаление бота с сервера!\nЭто удалит всё. Введите PIN:")
        elif text=="« Назад": states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_settings())

    elif st=="wg":
        if text=="👥 Пиры":
            send(vk,uid,"⏳ Получаю список…")
            ok,out=run_cmd_vk("wv listusers")
            send(vk,uid,f"👥 Пользователи WG:\n{out or '—'}",kbd_wg())
            db.log_command("vk",uid,"wg listusers",out[:100],ok)
        elif text=="➕ Новый пир":
            states[uid]="wg_adduser_name"; send(vk,uid,"➕ Введите имя нового пользователя:")
        elif text=="📥 Экспорт":
            states[uid]="wg_getuser_name"; send(vk,uid,"📥 Введите имя пользователя:")
        elif text=="🗑 Удалить пир":
            states[uid]="wg_deluser_name"; send(vk,uid,"🗑 Введите имя пользователя для удаления:")
        elif text=="« Назад": states[uid]="main"; send(vk,uid,"Главное меню:",kbd_main())
        else: send(vk,uid,"❓",kbd_wg())

    elif st=="vkpanel":
        if text=="▶️ МС-старт":
            send(vk,uid,"⏳ Старт МС…")
            ok,out=run_vkpanel_vk(1)
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_vkpanel())
            db.log_command("vk",uid,"vkpanel start",out[:100],ok)
        elif text=="⏹ МС-стоп":
            states[uid]="vkpanel_stop_pin"; send(vk,uid,"🔐 PIN для остановки МС:")
        elif text=="🔄 МС-рестарт":
            send(vk,uid,"⏳ Рестарт МС…")
            ok,out=run_vkpanel_vk(3)
            send(vk,uid,f"{'✅' if ok else '❌'} {out or '—'}",kbd_vkpanel())
            db.log_command("vk",uid,"vkpanel restart",out[:100],ok)
        elif text=="📊 МС-статус":
            ok,out=run_cmd_vk("systemctl status whitelist-bypass 2>&1 | head -20 || "
                             "pgrep -fa vk-panel 2>&1 || echo 'Сервис не найден'")
            send(vk,uid,f"📊 Статус МС:\n{out}",kbd_vkpanel())
            db.log_command("vk",uid,"vkpanel status",out[:100],ok)
        elif text=="📋 МС-логи":
            send(vk,uid,"⏳ Получаю логи…")
            ok,out=run_vkpanel_vk(16)
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
    logger.info(f"VK бот запущен v4.4. Group: {cfg['group_id']}"); print("✅ VK бот запущен!")
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
        echo -e "${BLUE}── 🟦 ВКонтакте ──${NC}"
        read -p "VK токен [Enter — не менять]: " NVK_TOK; NVK_TOK=${NVK_TOK:-$CUR_VK_TOK}
        read -p "VK группа ID [$CUR_VK_GRP]: " NVK_GRP; NVK_GRP=${NVK_GRP:-$CUR_VK_GRP}
        NVK_GRP="${NVK_GRP#-}"  # убираем минус если вставили из API
        read -p "VK пользователи [$CUR_VK_USR]: " NVK_USR; NVK_USR=${NVK_USR:-$CUR_VK_USR}
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
        VK_BLOCK="\"vk\":{\"group_token\":\"$NVK_TOK\",\"group_id\":$NVK_GRP,\"allowed_users\":$VKU}"
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

    if [ "$CUR_VER" = "$NEW_VER" ] && [ "$FORCE" != "force" ]; then
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
        "$VK_DIR/venv/bin/pip" install --quiet Pillow qrcode \
            && echo -e "  ${GREEN}✅ VK venv: Pillow qrcode${NC}" \
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
