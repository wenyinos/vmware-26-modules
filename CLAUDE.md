# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

VMware Workstation **26.0.0** 内核模块源码（vmmon / vmnet），经版本伪装后供 **VMware Workstation 17.5.0** 在 Fedora 44（内核 7.1.8-200.fc44）上使用，通过 DKMS 实现内核升级后自动重编译。

背景：17.5.0 官方模块源码无法在 7.1.x 内核编译（vmnet 引用已移除的 `dev_base_lock`；vmmon 缺 `driver-config.h`），26.0.0 源码原生兼容新内核，故复用之。

## 版本伪装（核心机制，勿破坏）

全仓库唯一的源码修改在 `vmmon-only/include/iocontrols.h:149`：

```c
#define VMMON_VERSION           (416 << 16 | 0)
```

原始值为 `418`。`VMMON_VERSION` 是 vmmon 暴露给用户空间（vmware-vmx）的 ioctl 接口版本号；17.5.0 的 vmx 精确校验该值（不匹配则报 "Version mismatch with vmmon module"）。模块实现是 416 接口的超集，伪装安全。vmnet 无独立版本校验，未做修改。

**修改该文件任何内容前，先评估对 17.5.0 vmx 版本校验的影响。** VMware 程序升级（如 17.5→17.6）时需重新确定目标版本号。

## 常用命令

```bash
# 编译（对当前运行内核；VM_UNAME 覆盖 uname -r，指定目标内核，DKMS 构建依赖此参数）
make -C vmmon-only VM_UNAME=$(uname -r)
make -C vmnet-only VM_UNAME=$(uname -r)

# 手动安装（root）
sudo cp vmmon-only/vmmon.ko vmnet-only/vmnet.ko /lib/modules/$(uname -r)/misc/
sudo depmod -a

# DKMS 一键注册/重装（源码有变化后重跑即可，脚本先 remove 再重建，幂等）
sudo bash install-dkms.sh

# DKMS 状态与手动重建
dkms status | grep vm
sudo dkms build vmmon/26.0.0 -k $(uname -r)
```

### 验证

```bash
# 接口版本校验：加载模块后应输出 416
sudo python3 -c "
import os, fcntl
fd = os.open('/dev/vmmon', os.O_RDWR)
print(fcntl.ioctl(fd, 2001, bytearray(4)))
os.close(fd)"
```

本仓库无单元测试；验证方式 = 编译成功 + `modinfo` 检查 + 加载 + 上述 ioctl 校验。`install-dkms.sh` 内置版本伪装校验（VMMON_VERSION 非 416 会拒绝执行）。

## 架构

两个模块目录各自独立编译，互不依赖：

- **`vmmon-only/`** — hypervisor 监控模块（/dev/vmmon），CPU 与内存虚拟化后端。`linux/` 平台特定代码（driver、hostif），`common/` 跨平台核心（apic、cpuid、memtrack、phystrack 等），`bootstrap/` 含 VMM 引导代码（`vmmblob.c` 是二进制 blob 嵌入），`autoconf/geninclude.c` 是编译期内核兼容性探测（生成 `compat_autoconf.h`），`include/` 为公共头文件（含关键文件 `iocontrols.h`）。
- **`vmnet-only/`** — 虚拟网络模块，扁平结构。`bridge.c`（桥接模式）、`hub.c`（NAT/仅主机模式）、`userif.c`（用户态接口）、`smac.c`/`smac_compat.c`（MAC 地址管理）、`netif.c`、`procfs.c`。兼容性由 `compat_*.h` 与 `vm_basic_*.h` 系列头文件处理。

### 构建系统

顶层 `Makefile` 检测内核构建目录存在与否，在 **kbuild**（`Makefile.kernel`，现代路径，M= 方式）与 **standalone**（`Makefile.normal`，无内核源码时）之间切换。当前环境走 kbuild。`VM_UNAME` 环境变量覆盖目标内核版本（默认 `uname -r`），编译时会把 `VMW_CFLAGS` 探测结果（如 `TIMER_DELETE_SYNC_MISSING`）传给内核构建。

## 仓库状态与约定

- Git 仓库**尚无任何提交**，所有文件处于未跟踪状态。
- 源码目录内混有编译产物（`*.o`、`*.ko`、`Module.symvers`、`modules.order`），编辑源码时注意区分；这些产物由 kbuild 生成，改动源码后需重新 `make` 才生效。
- 模块安装到 `/lib/modules/<kver>/misc/`；DKMS 源码副本在 `/usr/src/vmmon-26.0.0/`、`/usr/src/vmnet-26.0.0/`（由脚本复制，改动仓库源码后必须重跑 `install-dkms.sh` 才会同步）。
- DKMS 模块版本号统一为 `26.0.0`，在 `install-dkms.sh` 顶部 `VER` 变量定义。
- `/etc/dkms/framework.conf` 中 `post_transaction`（dracut 重建 initramfs）已被注释禁用——模块由用户会话加载，无需进 initramfs。不要恢复该配置，否则每次 DKMS 操作耗时数分钟。
- 源码原始来源：`VMware-Workstation-Full-26H1-25388281.x86_64.bundle` 内的 `vmware-vmx/lib/modules/source/vmmon.tar`、`vmnet.tar`。

## 维护场景

- **内核升级**：无需任何操作，DKMS hook（`/usr/lib/kernel/install.d/40-dkms.install`）自动重编译。
- **VMware 程序升级**：重新评估 `VMMON_VERSION` 目标值 → 修改 `iocontrols.h` → `sudo bash install-dkms.sh`。
- **内核头文件缺失**：Makefile 会警告 "kernel header directory seems invalid"，Fedora 下需 `kernel-devel` 包（或 `LINUXINCLUDE` 手动指定路径）。
