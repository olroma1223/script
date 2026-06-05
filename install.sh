#!/usr/bin/env bash

clear

# =========================
# CHECK ROOT
# =========================
if [[ "$EUID" -ne 0 ]]; then
    echo "Run as root"
    exit 1
fi

# =========================
# CHECK DEBIAN
# =========================
if [[ ! -f /etc/debian_version ]]; then
    echo "Debian 11/12 only"
    exit 1
fi

CONFIG="/etc/sockd.conf"

# =========================
# FUNCTIONS
# =========================

add_user() {

    echo
    read -p "Username: " -e -i proxyuser USER

    while true; do
        read -s -p "Password: " PASS
        echo
        read -s -p "Repeat: " PASS2
        echo
        [[ "$PASS" == "$PASS2" ]] && break
        echo "Mismatch"
    done

    if id "$USER" >/dev/null 2>&1; then
        echo "User exists"
        return
    fi

    useradd -M -s /usr/sbin/nologin \
        -p "$(openssl passwd -6 "$PASS")" "$USER"

    echo "User added"
}

remove_user() {

    echo
    read -p "User to delete: " U

    if id "$U" >/dev/null 2>&1; then
        userdel "$U"
        echo "Deleted"
    else
        echo "Not found"
    fi
}

remove_all() {

    echo
    read -p "Remove proxy? [y/n]: " -e -i n R

    [[ "$R" != "y" ]] && return

    systemctl stop sockd 2>/dev/null
    systemctl disable sockd 2>/dev/null

    apt-get -y remove dante-server

    rm -f /etc/sockd.conf
    rm -f /etc/systemd/system/sockd.service

    systemctl daemon-reload

    echo "Removed"
}

# =========================
# MENU IF INSTALLED
# =========================

if [[ -f "$CONFIG" ]]; then
    while true; do
        clear
        echo "Dante SOCKS installed"
        echo
        echo "1) Add user"
        echo "2) Delete user"
        echo "3) Remove proxy"
        echo "4) Exit"
        echo

        read -p "Select: " O

        case "$O" in
            1) add_user; exit ;;
            2) remove_user; exit ;;
            3) remove_all; exit ;;
            4) exit ;;
        esac
    done
fi

# =========================
# INSTALL
# =========================

echo "Installing Dante..."

INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

read -p "Port: " -e -i 1080 PORT
read -p "User: " -e -i proxyuser USER

while true; do
    read -s -p "Password: " PASS
    echo
    read -s -p "Repeat: " PASS2
    echo
    [[ "$PASS" == "$PASS2" ]] && break
done

apt-get update
apt-get -y install dante-server openssl curl ufw

useradd -M -s /usr/sbin/nologin \
    -p "$(openssl passwd -6 "$PASS")" \
    "$USER"

cat > /etc/sockd.conf <<EOF
internal: ${INTERFACE} port = ${PORT}
external: ${INTERFACE}

user.privileged: root
user.unprivileged: nobody

socksmethod: username

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect bind udpassociate
    socksmethod: username
}
EOF

# =========================
# AUTO DETECT BINARY
# =========================

SOCKD_BIN=""

if [[ -x /usr/sbin/sockd ]]; then
    SOCKD_BIN="/usr/sbin/sockd"
elif [[ -x /usr/sbin/danted ]]; then
    SOCKD_BIN="/usr/sbin/danted"
else
    echo "Dante not installed correctly"
    exit 1
fi

# =========================
# SYSTEMD SERVICE
# =========================

cat > /etc/systemd/system/sockd.service <<EOF
[Unit]
Description=Dante SOCKS5 Proxy
After=network.target

[Service]
Type=forking
ExecStart=${SOCKD_BIN} -D -f /etc/sockd.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sockd
systemctl restart sockd

# =========================
# FIREWALL
# =========================

if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp >/dev/null 2>&1
    ufw allow ${PORT}/udp >/dev/null 2>&1
fi

IP=$(curl -4 -s https://api.ipify.org)

clear

echo "============================"
echo "SOCKS5 READY (NO LOGS)"
echo "============================"
echo "IP: $IP"
echo "PORT: $PORT"
echo "USER: $USER"
echo "PASS: $PASS"
echo "============================"
