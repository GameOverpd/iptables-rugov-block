#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Пути к файлам с IP-адресами
OLD_IP_FILE="/var/log/rugov_blacklist/old_blacklist.txt"
NEW_IP_FILE="/var/log/rugov_blacklist/blacklist.txt"
FMT_LOGS=""
if [[ -f "/etc/rsyslog.d/51-iptables-rugov.conf" ]]; then
    FMT_LOGS="do"
fi

# Проверяем существование файлов
if [[ ! -f "$OLD_IP_FILE" ]]; then
    echo "Error: $OLD_IP_FILE does not exist."
    exit 1
fi

# Сохраняем старый список в отдельный файл
mv "$NEW_IP_FILE" "$OLD_IP_FILE"

# Загружаем новый список
if ! sudo wget -O "$NEW_IP_FILE" https://github.com/GameOverpd/AS_Network_List/blob/main/blacklists/blacklist.txt; then
    echo "Failed to load new blacklist. Lets leave the old list unchanged."
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Failed to load new blacklist. Lets leave the old list unchanged." >> /var/log/rugov_blacklist/blacklist_updater.log
    exit 1
fi

# Читаем IP-адреса из старого файла
old_addresses=($(< "$OLD_IP_FILE"))

# Читаем IP-адреса из нового файла
new_addresses=($(< "$NEW_IP_FILE"))

# Добавляем новые адреса и удаляем старые из правил
added=0
removed=0
for addr in "${new_addresses[@]}"; do
    if ! sudo iptables -t raw -C PREROUTING -s "$addr" -j DROP &>/dev/null; then
        if [[ "$FMT_LOGS" ]]; then
            iptables -t raw -A PREROUTING -s "$addr" -j LOG --log-prefix "Blocked RUGOV IP attempt: "
        fi
        iptables -t raw -A PREROUTING -s "$addr" -j DROP
        ((added++)) || true
    fi
done

# Удаляем адреса, которых уже нет в новом списке
for addr in "${old_addresses[@]}"; do
    if ! grep -q "$addr" "$NEW_IP_FILE"; then
        sudo iptables -t raw -D PREROUTING -s "$addr" -j LOG --log-prefix "Blocked RUGOV IP attempt: " || true
        sudo iptables -t raw -D PREROUTING -s "$addr" -j DROP
        ((removed++)) || true
    fi
done

# Сохраняем правила брандмауэра в файл
sudo iptables-save > /etc/iptables/rules.v4

# Выводим информацию о добавленных и удаленных адресах
echo "Added addresses to the blacklist: $added"
echo "Addresses removed from the blacklist: $removed"

# Добавляем запись в файл лога
echo "$(date +"%Y-%m-%d %H:%M:%S") - Added addresses to the blacklist: $added, addresses removed from the blacklist: $removed" >> /var/log/rugov_blacklist/blacklist_updater.log
