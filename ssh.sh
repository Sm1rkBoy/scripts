#!/bin/bash

# 用户公钥映射（根据需要添加更多）
declare -A USER_PUBKEYS=(
    ["SM"]="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOzTqT/s3C4xHE3sGwnxBPIzxlzSxaUMXXPPZJ8LhQWW"
    ["MS"]="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJeHnxT+fxgLz30mKUNU9DMJW1342Ifkq6dGsCpGh317"
    ["FJ"]="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCTx+lsXjrmzFyUY+BMiGIGTf1mfPmbAcjb83hk8D4fI9oYB4ugVFftL5ApZE02bIgOn7fy++0kQAf6CjVmkK7BzxwOU8MRXzGA4KxbVRLCmYDMfcyM89WDHViXCHYvapaP4Cln4gWmcTaLXmAqQqZIjgaZAxgVII3vQ9acHlf1eL3tywjXzKXr5NeJqW0OtMXTs+/4jVBIstPndkncxtZNTCNOjJ7SKMCeG3JgHzilJhffY9otoMaQoSjhzzFegeg42JFFjrfz8Y4/E8sybq4wKuiZq1FMyuO03NBmWSD14GmV7y9BYgY8I8s01yNwRtJgiR7Z72ZZgskJQektZlChQIWnobAYS9BtILEuSqPMuWxTyQ/CjlqlEyhCvmXrCpn+nbBoy5JuPStn3M7GjkxMCprc4IItgVRCUgVlwhuWD7sI2JVIb8xHrFYMbFqPJp5ywjGQ/mhXz16hqmcThSGGs7PtkdpZd5Q6ZIWFD3GAxfvmWhxwKiKdylrpgKYKO1gINVPT2qfQIKb1k0Ta4dBGhSBAHmvKeO3rL/9Vwp1sSN4o9VDHTUjj1x5d47RljgRzS/euXFECrqJhMZj6h726peV9ipQ6CBhpcEPieW1MmBzJlBjvbSdtXSAzYxOhPyp8kJryVMnuzYAXMYO26XBTFt1E1GvNX5Uuj9OraXo5EQ=="
    ["POI"]="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDFUVCh9g0Dal9MFV9K/hR92c0xdQzDl2AKz4lF7dcumXlO9UwMT/2syzyHgLvRFCbjw9ozU9vVipedscHTnc2ndWOV/NdFZyre5AktMgZuFIv8FKgzMq1uqDwAMMrqUW3Z1U/JsKWkxrsVTZpyHTTP9vadc7zl0aKcS4/Bry0RjUo7l1bEKZXwxaHb3VQKdmxguMMMNaKtwFxlfFBIlAL5lbC7E+oOtt6tKD8a0MNT7o0lWWaMTIeJSX5cuAOoAz6sDefcTtwJW7HWc9gGTNPUObMRnBWhe+ChqOpoUw6ZrpI8Z1gbSGo/5lqYLFtW8+tCbDvMwiaMURITZNdzJp8d"
    ["XY"]="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHU/qpTbebWNuHCu2q5TjrK+YFiyjwtyBNzkvOUTgZXe"
    ["EZI"]="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBGMxRitFKR5lWyVI0n4SlCZkuoHn84jh4zJi1nSBk3Q"
    ["HA"]="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA5LUncItJUDJEdJmBaKBytQvLvSlFjbWUmwnftgZG0D"
)

# 默认参数
USERNAME=""
SSH_PORT=22

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            USERNAME="$2"
            shift 2
            ;;
        --port)
            SSH_PORT="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 校验用户名
if [[ -z "$USERNAME" ]]; then
    echo "必须指定 --user"
    exit 1
fi

if [[ -z "${USER_PUBKEYS[$USERNAME]}" ]]; then
    echo "未配置用户 $USERNAME 的公钥"
    exit 1
fi

echo "更新系统组件..."
apt update && apt install -y rsyslog fail2ban nftables && apt full-upgrade -y

echo "配置 SSH 服务（端口: $SSH_PORT）..."
cat >/etc/ssh/sshd_config <<EOF
Port $SSH_PORT
ListenAddress 0.0.0.0
ListenAddress ::
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 30s
PermitRootLogin prohibit-password
PasswordAuthentication no
PermitEmptyPasswords no
StrictModes yes
MaxAuthTries 6
MaxSessions 10
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
PrintLastLog yes
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

echo "为 root 用户部署 ${USERNAME} 的公钥..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "${USER_PUBKEYS[$USERNAME]}" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
chown -R root:root /root/.ssh

echo "重启 SSH 和 Fail2ban 服务..."
systemctl restart sshd
systemctl restart fail2ban
systemctl enable fail2ban

echo "配置完成：SSH端口=$SSH_PORT，公钥用户=$USERNAME"