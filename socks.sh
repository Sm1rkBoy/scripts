#!/usr/bin/env bash

set -e

# ==========================================
# Mixed 代理自动安装/卸载脚本
# 支持 Clash/mihomo 和 sing-box
# ==========================================

CLASH_VERSION="latest"
SINGBOX_VERSION="1.13.11"

CLASH_DIR="/usr/local/bin/clash"
SINGBOX_DIR="/usr/local/bin/singbox"

MIXED_PORT="50800"
MIXED_USER=""
MIXED_PASS=""

ARCH=$(uname -m)
ACTION="install"
CORE="clash"
VERSION_OVERRIDE=""
PKG_ARCH=""

usage() {
    cat <<EOF
用法:
  bash socks.sh --core clash --username <用户名> --password <密码>
  bash socks.sh --core singbox --username <用户名> --password <密码>
  bash socks.sh --uninstall

选项:
  --core            安装内核: clash 或 singbox，默认 clash
  --username, -u    Mixed 代理用户名，安装时必填
  --password, -p    Mixed 代理密码，安装时必填
  --port            Mixed 代理端口，默认 ${MIXED_PORT}
  --version         指定内核版本；clash 默认 latest，singbox 默认 ${SINGBOX_VERSION}
  --install         安装或覆盖安装，默认动作
  --uninstall       停止并删除 Clash/mihomo 和 sing-box
  --help, -h        显示帮助
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

yaml_single_quote_escape() {
    local value="$1"
    value=${value//\'/\'\'}
    printf '%s' "${value}"
}

require_cmds() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "缺少依赖: ${cmd}"
            exit 1
        fi
    done
}

detect_arch() {
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
}

stop_service() {
    local service="$1"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop "${service}" >/dev/null 2>&1 || true
        systemctl disable "${service}" >/dev/null 2>&1 || true
    fi
}

remove_dir() {
    local dir="$1"
    if [ -n "${dir}" ] && [ "${dir}" != "/" ]; then
        rm -rf "${dir}"
    fi
}

uninstall_clash() {
    echo "删除 Clash/mihomo"
    stop_service clash
    rm -f /etc/systemd/system/clash.service
    remove_dir "${CLASH_DIR}"
}

uninstall_singbox() {
    echo "删除 sing-box"
    stop_service sing-box
    rm -f /etc/systemd/system/sing-box.service
    remove_dir "${SINGBOX_DIR}"
}

uninstall_all() {
    echo "========================================="
    echo "删除 Clash/mihomo 和 sing-box"
    echo "========================================="

    uninstall_clash
    uninstall_singbox

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl reset-failed clash >/dev/null 2>&1 || true
        systemctl reset-failed sing-box >/dev/null 2>&1 || true
    fi

    echo "Clash/mihomo 和 sing-box 已删除"
}

install_clash() {
    local version="$1"
    local tmp_dir="$2"
    local asset_pattern
    local download_url
    local version_with_v
    local file_name
    local user_yaml
    local pass_yaml

    require_cmds curl gzip systemctl
    cd "${tmp_dir}"

    if [ "${PKG_ARCH}" = "amd64" ]; then
        asset_pattern="mihomo-linux-amd64-compatible-v[^\"]*\\.gz"
    else
        asset_pattern="mihomo-linux-arm64-v[^\"]*\\.gz"
    fi

    if [ "${version}" = "latest" ]; then
        download_url=$(curl -fsSL "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" \
            | grep -Eo "https://github.com/MetaCubeX/mihomo/releases/download/[^\"]+/${asset_pattern}" \
            | head -n1)
    else
        version_with_v="${version}"
        case "${version_with_v}" in
            v*) ;;
            *) version_with_v="v${version_with_v}" ;;
        esac

        if [ "${PKG_ARCH}" = "amd64" ]; then
            file_name="mihomo-linux-amd64-compatible-${version_with_v}.gz"
        else
            file_name="mihomo-linux-arm64-${version_with_v}.gz"
        fi

        download_url="https://github.com/MetaCubeX/mihomo/releases/download/${version_with_v}/${file_name}"
    fi

    if [ -z "${download_url}" ]; then
        echo "无法获取 mihomo 下载地址"
        exit 1
    fi

    echo "========================================="
    echo "下载 Clash/mihomo ${version}"
    echo "架构: ${PKG_ARCH}"
    echo "========================================="

    curl -L -o mihomo.gz "${download_url}"

    echo "解压文件..."
    gzip -dc mihomo.gz > mihomo
    if [ ! -s mihomo ]; then
        echo "解压失败"
        exit 1
    fi

    echo "安装 Clash/mihomo ..."
    mkdir -p "${CLASH_DIR}"
    stop_service clash
    stop_service sing-box

    cp mihomo "${CLASH_DIR}/clash.new"
    chmod +x "${CLASH_DIR}/clash.new"
    mv -f "${CLASH_DIR}/clash.new" "${CLASH_DIR}/clash"

    user_yaml=$(yaml_single_quote_escape "${MIXED_USER}")
    pass_yaml=$(yaml_single_quote_escape "${MIXED_PASS}")

    cat > "${CLASH_DIR}/config.yaml" <<EOF
mixed-port: ${MIXED_PORT}
allow-lan: true
bind-address: '*'
mode: rule
log-level: info
ipv6: true
authentication:
  - '${user_yaml}:${pass_yaml}'
profile:
  store-selected: true
  store-fake-ip: true
rules:
  - MATCH,DIRECT
EOF

    echo "创建 systemd 服务..."
    cat > /etc/systemd/system/clash.service <<EOF
[Unit]
Description=Clash/mihomo Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=${CLASH_DIR}/clash -d ${CLASH_DIR} -f ${CLASH_DIR}/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable clash
    systemctl restart clash

    print_result "Clash/mihomo" "${CLASH_DIR}" "${CLASH_DIR}/config.yaml" "clash"
}

install_singbox() {
    local version="$1"
    local tmp_dir="$2"
    local version_no_v
    local file_name
    local download_url
    local extract_dir
    local user_json
    local pass_json

    require_cmds curl tar systemctl
    cd "${tmp_dir}"

    version_no_v="${version#v}"
    file_name="sing-box-${version_no_v}-linux-${PKG_ARCH}.tar.gz"
    download_url="https://github.com/SagerNet/sing-box/releases/download/v${version_no_v}/${file_name}"

    echo "========================================="
    echo "下载 sing-box ${version_no_v}"
    echo "架构: ${PKG_ARCH}"
    echo "========================================="

    curl -L -o "${file_name}" "${download_url}"

    echo "解压文件..."
    tar -xzf "${file_name}"

    extract_dir=$(find . -maxdepth 1 -type d -name "sing-box*" | head -n1)
    if [ -z "${extract_dir}" ]; then
        echo "解压失败"
        exit 1
    fi

    echo "安装 sing-box ..."
    mkdir -p "${SINGBOX_DIR}"
    stop_service sing-box
    stop_service clash

    cp "${extract_dir}/sing-box" "${SINGBOX_DIR}/sing-box.new"
    chmod +x "${SINGBOX_DIR}/sing-box.new"
    mv -f "${SINGBOX_DIR}/sing-box.new" "${SINGBOX_DIR}/sing-box"

    user_json=$(json_escape "${MIXED_USER}")
    pass_json=$(json_escape "${MIXED_PASS}")

    cat > "${SINGBOX_DIR}/config.json" <<EOF
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
          "username": "${user_json}",
          "password": "${pass_json}"
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

    echo "创建 systemd 服务..."
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=${SINGBOX_DIR}/sing-box run -c ${SINGBOX_DIR}/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box
    systemctl restart sing-box

    print_result "sing-box" "${SINGBOX_DIR}" "${SINGBOX_DIR}/config.json" "sing-box"
}

print_result() {
    local name="$1"
    local install_dir="$2"
    local config_file="$3"
    local service="$4"
    local public_ip

    public_ip=$(curl -s --max-time 5 ifconfig.me || echo "YOUR_SERVER_IP")

    echo ""
    echo "========================================="
    echo "${name} 安装完成"
    echo "========================================="
    echo ""
    echo "安装目录:"
    echo "${install_dir}"
    echo ""
    echo "配置文件:"
    echo "${config_file}"
    echo ""
    echo "Mixed 代理信息 (SOCKS5 + HTTP):"
    echo "地址: ${public_ip}"
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
    echo "systemctl status ${service}"
    echo ""
    echo "查看实时日志:"
    echo "journalctl -u ${service} -f"
    echo ""
    echo "重启服务:"
    echo "systemctl restart ${service}"
    echo ""
    echo "停止服务:"
    echo "systemctl stop ${service}"
    echo ""
    echo "========================================="
}

while [ $# -gt 0 ]; do
    case "$1" in
        --core)
            if [ $# -lt 2 ]; then
                echo "缺少 --core 的值"
                exit 1
            fi
            CORE="$2"
            shift 2
            ;;
        --core=*)
            CORE="${1#*=}"
            shift
            ;;
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
        --version)
            if [ $# -lt 2 ]; then
                echo "缺少 --version 的值"
                exit 1
            fi
            VERSION_OVERRIDE="$2"
            shift 2
            ;;
        --version=*)
            VERSION_OVERRIDE="${1#*=}"
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

if [ "${ACTION}" = "uninstall" ]; then
    uninstall_all
    exit 0
fi

case "${CORE}" in
    clash|mihomo)
        CORE="clash"
        ;;
    singbox|sing-box)
        CORE="singbox"
        ;;
    *)
        echo "--core 只支持 clash 或 singbox"
        exit 1
        ;;
esac

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

detect_arch

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

if [ "${CORE}" = "clash" ]; then
    install_clash "${VERSION_OVERRIDE:-${CLASH_VERSION}}" "${TMP_DIR}"
else
    install_singbox "${VERSION_OVERRIDE:-${SINGBOX_VERSION}}" "${TMP_DIR}"
fi
