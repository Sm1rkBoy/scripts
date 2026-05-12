#!/usr/bin/env bash

set -e

# ==========================================
# sing-box 自动安装/卸载脚本
# Version: 1.13.11
# Mixed Inbound (SOCKS5 + HTTP)
# 安装目录: /usr/local/bin/singbox
# 配置目录: /usr/local/bin/singbox
# ==========================================

# =========================
# 配置区
# =========================
VERSION="1.13.11"

INSTALL_DIR="/usr/local/bin/singbox"
CONFIG_DIR="/usr/local/bin/singbox"

MIXED_PORT="50800"
MIXED_USER=""
MIXED_PASS=""

ARCH=$(uname -m)
ACTION="install"

usage() {
    cat <<EOF
用法:
  bash singbox.sh --username <用户名> --password <密码>
  bash singbox.sh --username=<用户名> --password=<密码>
  bash singbox.sh --uninstall

选项:
  --username, -u     Mixed 代理用户名，安装时必填
  --password, -p     Mixed 代理密码，安装时必填
  --port             Mixed 代理端口，默认 ${MIXED_PORT}
  --install          安装或覆盖安装 sing-box，默认动作
  --uninstall        停止并删除 sing-box
  --help, -h         显示帮助
EOF
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    printf '%s' "${value}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --username|-u)
            if [ $# -lt 2 ]; then
                echo "缺少 --username 的值"
                exit 1
            fi
            MIXED_USER="$2"
            shift 2
            ;;
        --username=*)
            MIXED_USER="${1#*=}"
            shift
            ;;
        --password|-p)
            if [ $# -lt 2 ]; then
                echo "缺少 --password 的值"
                exit 1
            fi
            MIXED_PASS="$2"
            shift 2
            ;;
        --password=*)
            MIXED_PASS="${1#*=}"
            shift
            ;;
        --port)
            if [ $# -lt 2 ]; then
                echo "缺少 --port 的值"
                exit 1
            fi
            MIXED_PORT="$2"
            shift 2
            ;;
        --port=*)
            MIXED_PORT="${1#*=}"
            shift
            ;;
        --install)
            ACTION="install"
            shift
            ;;
        --uninstall|--remove|--delete)
            ACTION="uninstall"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户运行，或使用 sudo/bash 提权运行。"
    exit 1
fi

uninstall_singbox() {
    echo "========================================="
    echo "删除 sing-box"
    echo "========================================="

    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop sing-box >/dev/null 2>&1 || true
        systemctl disable sing-box >/dev/null 2>&1 || true
    fi

    rm -f /etc/systemd/system/sing-box.service

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl reset-failed sing-box >/dev/null 2>&1 || true
    fi

    if [ -n "${INSTALL_DIR}" ] && [ "${INSTALL_DIR}" != "/" ]; then
        rm -rf "${INSTALL_DIR}"
    fi

    if [ "${CONFIG_DIR}" != "${INSTALL_DIR}" ] && [ -n "${CONFIG_DIR}" ] && [ "${CONFIG_DIR}" != "/" ]; then
        rm -rf "${CONFIG_DIR}"
    fi

    echo "sing-box 已删除"
}

if [ "${ACTION}" = "uninstall" ]; then
    uninstall_singbox
    exit 0
fi

if [ -z "${MIXED_USER}" ]; then
    echo "用户名不能为空"
    exit 1
fi

if [ -z "${MIXED_PASS}" ]; then
    echo "密码不能为空"
    exit 1
fi

if ! [[ "${MIXED_PORT}" =~ ^[0-9]+$ ]] || [ "${MIXED_PORT}" -lt 1 ] || [ "${MIXED_PORT}" -gt 65535 ]; then
    echo "端口必须是 1-65535 的数字"
    exit 1
fi

MIXED_USER_JSON=$(json_escape "${MIXED_USER}")
MIXED_PASS_JSON=$(json_escape "${MIXED_PASS}")

# =========================
# 创建临时目录
# =========================
TMP_DIR=$(mktemp -d)

# 自动清理临时目录
trap 'rm -rf "${TMP_DIR}"' EXIT

# =========================
# 判断架构
# =========================
case "${ARCH}" in
    x86_64)
        PKG_ARCH="amd64"
        ;;
    aarch64|arm64)
        PKG_ARCH="arm64"
        ;;
    *)
        echo "不支持的架构: ${ARCH}"
        exit 1
        ;;
esac

# =========================
# 检查依赖
# =========================
for cmd in curl tar systemctl; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "缺少依赖: $cmd"
        exit 1
    fi
done

# =========================
# 下载 sing-box
# =========================
cd "${TMP_DIR}"

FILE_NAME="sing-box-${VERSION}-linux-${PKG_ARCH}.tar.gz"

DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${FILE_NAME}"

echo "========================================="
echo "下载 sing-box ${VERSION}"
echo "架构: ${PKG_ARCH}"
echo "========================================="

curl -L -o "${FILE_NAME}" "${DOWNLOAD_URL}"

# =========================
# 解压
# =========================
echo "解压文件..."

tar -xzf "${FILE_NAME}"

EXTRACT_DIR=$(find . -maxdepth 1 -type d -name "sing-box*" | head -n1)

if [ -z "${EXTRACT_DIR}" ]; then
    echo "解压失败"
    exit 1
fi

# =========================
# 安装
# =========================
echo "安装 sing-box ..."

mkdir -p "${INSTALL_DIR}"

if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box >/dev/null 2>&1 || true
fi

NEW_BIN="${INSTALL_DIR}/sing-box.new"
cp "${EXTRACT_DIR}/sing-box" "${NEW_BIN}"
chmod +x "${NEW_BIN}"
mv -f "${NEW_BIN}" "${INSTALL_DIR}/sing-box"

# =========================
# 创建配置目录
# =========================
mkdir -p "${CONFIG_DIR}"

cat > "${CONFIG_DIR}/config.json" <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": ${MIXED_PORT},
      "users": [
        {
          "username": "${MIXED_USER_JSON}",
          "password": "${MIXED_PASS_JSON}"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

# =========================
# 创建 systemd service
# =========================
echo "创建 systemd 服务..."

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# =========================
# 重载 systemd
# =========================
systemctl daemon-reload

# =========================
# 设置开机自启
# =========================
systemctl enable sing-box

# =========================
# 重启服务
# =========================
systemctl restart sing-box

# =========================
# 获取公网 IP
# =========================
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || echo "YOUR_SERVER_IP")

# =========================
# 输出结果
# =========================
echo ""
echo "========================================="
echo "sing-box 安装完成"
echo "========================================="
echo ""
echo "安装目录:"
echo "${INSTALL_DIR}"
echo ""
echo "配置文件:"
echo "${CONFIG_DIR}/config.json"
echo ""
echo "Mixed 代理信息 (SOCKS5 + HTTP):"
echo "地址: ${PUBLIC_IP}"
echo "端口: ${MIXED_PORT}"
echo "用户名: ${MIXED_USER}"
echo "密码: ${MIXED_PASS}"
echo ""
echo "SOCKS5 测试:"
echo "curl --socks5 ${MIXED_USER}:${MIXED_PASS}@127.0.0.1:${MIXED_PORT} https://ip.sb"
echo ""
echo "HTTP 代理测试:"
echo "curl -x http://${MIXED_USER}:${MIXED_PASS}@127.0.0.1:${MIXED_PORT} https://ip.sb"
echo ""
echo "查看服务状态:"
echo "systemctl status sing-box"
echo ""
echo "查看实时日志:"
echo "journalctl -u sing-box -f"
echo ""
echo "重启服务:"
echo "systemctl restart sing-box"
echo ""
echo "停止服务:"
echo "systemctl stop sing-box"
echo ""
echo "========================================="
