#!/usr/bin/env bash
#
# install-dkms.sh
# 将本目录（vmware-26-modules）的 vmmon/vmnet 源码注册为 DKMS 模块，
# 实现内核升级后自动重编译，供 VMware Workstation 17.5.0 使用。
#
# 前置条件：
#   - dkms 已安装（sudo dnf install dkms）
#   - 源码已含版本伪装（vmmon-only/include/iocontrols.h 中 VMMON_VERSION=416）
#
# 用法：sudo bash install-dkms.sh
#
set -euo pipefail

VER="26.0.0"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# 校验版本伪装（防止误用未修改的 418 源码）
if ! grep -q "define VMMON_VERSION           (416 << 16 | 0)" \
        "${SRC_DIR}/vmmon-only/include/iocontrols.h"; then
    echo "错误: vmmon-only/include/iocontrols.h 中 VMMON_VERSION 不是 416"
    echo "请先按 README.md 完成版本伪装（418 → 416）"
    exit 1
fi
echo "== 版本伪装校验通过 (VMMON_VERSION=416)"

install_module() {
    local MOD="$1"
    local SRC="/usr/src/${MOD}-${VER}"

    echo "== 处理模块 ${MOD}"
    # 清理旧版本（源码变化时需重新 add）
    dkms remove "${MOD}/${VER}" --all 2>/dev/null || true
    sudo rm -rf "${SRC}"
    sudo mkdir -p "${SRC}/${MOD}-only"
    sudo cp -a "${SRC_DIR}/${MOD}-only/." "${SRC}/${MOD}-only/"

    sudo tee "${SRC}/dkms.conf" > /dev/null <<EOF
PACKAGE_NAME="${MOD}"
PACKAGE_VERSION="${VER}"
BUILT_MODULE_NAME[0]="${MOD}"
BUILT_MODULE_LOCATION[0]="${MOD}-only/"
DEST_MODULE_LOCATION[0]="/kernel/drivers/misc"
MAKE[0]="make -C ${MOD}-only VM_UNAME=\${kernelver}"
AUTOINSTALL="yes"
EOF

    sudo dkms add "${MOD}/${VER}"
    sudo dkms build "${MOD}/${VER}" -k "$(uname -r)"
    sudo dkms install "${MOD}/${VER}" -k "$(uname -r)"
    echo "== ${MOD} 安装完成"
}

install_module vmmon
install_module vmnet

echo
echo "== DKMS 状态:"
dkms status | grep -E "vmmon|vmnet" || true
echo
echo "完成。后续内核升级后 dkms 将自动为新内核编译 vmmon/vmnet。"
echo "查看状态: dkms status | grep vm"
echo "手动重建: sudo dkms build vmmon/26.0.0 -k \$(uname -r) && sudo dkms install vmmon/26.0.0 -k \$(uname -r)"
