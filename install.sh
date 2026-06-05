#!/usr/bin/env bash

# Dante SOCKS5 Installer for Debian 11/12
# Version: 2.0

clear

# Root check
if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script as root"
    exit 1
fi

# Debian check
if [[ ! -f /etc/debian_version ]]; then
    echo "This installer supports Debian 11/12 only"
    exit 1
fi

CONFIG="/etc/sockd.conf"

add_user() {

    echo
    read -p "Enter username: " -e -i proxyuser USERNAME

    while true; do
        read -s -p "Enter password: " PASSWORD
        echo
        read -s -p "Repeat password: " PASSWORD2
        echo

        [[ "$PASSWORD" == "$PASSWORD2" ]] && break

        echo
        echo "Passwords do not match"
        echo
    done

    if id "$USERNAME" >/dev/null 2>&1; then
        echo
        echo "User already exists"
        return
    fi

    useradd -M -s /usr/sbin/nologin \
        -p "$(openssl passwd -6 "$PASSWORD")" \
        "$USERNAME"

    echo
    echo "User created successfully"
}

remove_user() {

    echo
    read -p "Enter username to delete: " DELUSER

    if id "$DELUSER" >/dev/null 2>&1; then
        userdel "$DELUSER"
        echo
        echo "User deleted"
    else
        echo
        echo "User not found"
    fi
}

remove_proxy() {

    echo
    read -p "Remove Dante SOCKS5 completely? [y/n]: " -e -i n REMOVE

    if [[ "$REMOVE" != "y" ]]; then
        echo
        echo "Cancelled"
        return
    fi

    systemctl stop sockd 2>/dev/null
    systemctl disable sockd 2>/dev/null

    apt-get -y remove dante-server

    rm -f /etc/systemd/system/sockd.service
    rm -f /etc/sockd.conf

    systemctl daemon-reload

    echo
    echo "Dante removed"
}

if [[ -f "$CONFIG" ]]; then

    while true; do

        clear

        echo "Dante SOCKS5 already installed"
        echo
        echo "1) Add user"
        echo "2) Delete user"
        echo "3) Remove Dante"
        echo "4) Exit"
        echo

        read -p "Select option [1-4]: " OPTION

        case "$OPTION" in
            1)
                add_user
                exit
                ;;
            2)
                remove_user
                exit
                ;;
            3)
                remove_proxy
                exit
                ;;
            4)
                exit
                ;;
        esac

    done
fi

echo "Installing Dante SOCKS5..."

INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

read -p "Enter SOCKS5 port: " -e -i 1080 PORT

echo

read -p "Enter username: " -e -i proxyuser USERNAME

while true; do

    read -s -p "Enter password: " PASSWORD
    echo

    read -s -p "Repeat password: " PASSWORD2
    echo

    [[ "$PASSWORD" == "$PASSWORD2" ]] && break

    echo
    echo "Passwords do not match"
    echo

done

apt-get update

apt-get -y install \
    dante-server \
    openssl \
    curl \
    ufw

useradd -M -s /usr/sbin/nologin \
    -p "$(openssl passwd -6 "$PASSWORD")" \
    "$USERNAME"

cat > /etc/sockd.conf << EOF
logoutput: syslog

internal: ${INTERFACE} port = ${PORT}
external: ${INTERFACE}

user.privileged: root
user.unprivileged: nobody

socksmethod: username

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect bind udpassociate
    socksmethod: username
    log: connect disconnect error
}
EOF

cat > /etc/systemd/system/sockd.service << 'EOF'
[Unit]
Description=Dante SOCKS5 Proxy
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/sockd -D -f /etc/sockd.conf
ExecReload=/bin/kill -HUP $MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sockd
systemctl restart sockd

if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp >/dev/null 2>&1
    ufw allow ${PORT}/udp >/dev/null 2>&1
fi

SERVER_IP=$(curl -4 -s https://api.ipify.org)

clear

echo "======================================"
echo "Dante SOCKS5 installed successfully"
echo "======================================"
echo
echo "IP       : ${SERVER_IP}"
echo "PORT     : ${PORT}"
echo "USERNAME : ${USERNAME}"
echo "PASSWORD : ${PASSWORD}"
echo
echo "SOCKS5 is ready to use"
echo
