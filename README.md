# vmware-26-modules

VMware Workstation 26.0.0 内核模块源码（vmmon / vmnet），经版本伪装后供 **VMware Workstation 17.5.0** 在 Fedora 44（内核 7.1.8-200.fc44）上使用，并注册 DKMS 实现内核升级后自动重编译。

## 背景

VMware Workstation 17.5.0（2024 年初）的官方内核模块源码无法在新内核（7.1.8，2026 年）上编译：

- vmnet 引用了内核 6.5 已移除的 `dev_base_lock`（编译失败）
- vmmon 缺少 `driver-config.h`（构建配置缺失）

而 VMware Workstation 26.0.0 的模块源码原生兼容新内核（无需补丁即可编译），因此采用「26.0.0 源码 + 版本伪装」方案，让 17.5.0 程序复用 26.0.0 的模块。

## 唯一源码修改

| 文件 | 位置 | 修改 |
|---|---|---|
| `vmmon-only/include/iocontrols.h` | 第 149 行 | `VMMON_VERSION` 由 `(418 << 16 \| 0)` 改为 `(416 << 16 \| 0)` |

`VMMON_VERSION` 是 vmmon 驱动暴露给用户空间（vmware-vmx）的**接口版本号**。17.5.0 的 vmx 精确校验该值（期望 416，报错信息 "Version mismatch with vmmon module"），26.0.0 源码返回 418，必须伪装为 416。模块实现为 416 接口的超集（向后兼容），功能不受影响。

vmnet 无独立版本校验，无需修改。

## 目录结构

```
vmware-26-modules/
├── vmmon-only/          # vmmon 内核模块源码（修改版）
└── vmnet-only/          # vmnet 内核模块源码（原始）
```

## 手动编译与安装

```bash
# 编译（对当前运行内核）
make -C vmmon-only VM_UNAME=$(uname -r)
make -C vmnet-only VM_UNAME=$(uname -r)

# 安装（root）
sudo cp vmmon-only/vmmon.ko vmnet-only/vmnet.ko /lib/modules/$(uname -r)/misc/
sudo depmod -a
```

## DKMS 集成（推荐）

源码已注册 DKMS（`/usr/src/vmmon-26.0.0`、`/usr/src/vmnet-26.0.0`），内核升级后自动为新内核重编译。

### 一键安装脚本

项目内 `install-dkms.sh` 可完成「源码复制 → 写 dkms.conf → add/build/install」全流程，并自动校验版本伪装是否生效：

```bash
sudo bash install-dkms.sh          # 首次注册 / 重装 VMware 后重新注册
```

脚本特性：

- **版本伪装校验**：执行前检查 `iocontrols.h` 中 `VMMON_VERSION=416`，误用未修改源码会报错中止
- **幂等可重跑**：先 `dkms remove` 清理旧注册再重建，源码变化后无需手动清理
- **运行后验证**：输出 `dkms status` 供确认两个模块均 `installed`

### 手动管理命令

```bash
dkms status | grep vm          # 查看状态
sudo dkms build vmmon/26.0.0   # 手动重建
```

dkms.conf 关键配置：

```conf
MAKE[0]="make -C vmmon-only VM_UNAME=${kernelver}"   # 覆盖 uname -r，编译目标内核
BUILT_MODULE_LOCATION[0]="vmmon-only/"               # 模块生成于子目录
```

> 注：`/etc/dkms/framework.conf` 中 `post_transaction`（`dracut --regenerate-all --force`）已注释禁用——vmmon/vmnet 由用户会话加载，无需写入 initramfs，避免每次 DKMS 操作耗时数分钟。

## 版本校验

```bash
# 模块加载后验证接口版本（应返回 416，major=416）
sudo python3 -c "
import os, fcntl
fd = os.open('/dev/vmmon', os.O_RDWR)
print(fcntl.ioctl(fd, 2001, bytearray(4)))
os.close(fd)"
```

## 维护注意

1. **内核升级**：无需操作，DKMS 自动编译（hook：`/usr/lib/kernel/install.d/40-dkms.install`）
2. **VMware 程序升级**（如 17.5→17.6）：需重新评估 `VMMON_VERSION` 目标值并修改 `iocontrols.h`，然后 `dkms build/install`
3. **源码原始来源**：VMware Workstation 26.0.0 bundle（`VMware-Workstation-Full-26H1-25388281.x86_64.bundle`）中的 `vmware-vmx/lib/modules/source/vmmon.tar`、`vmnet.tar`

## 环境

| 项 | 值 |
|---|---|
| 发行版 | Fedora 44 |
| 内核 | 7.1.8-200.fc44.x86_64 |
| VMware | Workstation 17.5.0 build-22583795 |
| 模块源码版本 | Workstation 26.0.0 build-25388281 |
