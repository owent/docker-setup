# PVE 设置 AMD P-State Powersave / EPP 节能模式


- [PVE 设置 AMD P-State Powersave / EPP 节能模式](#pve-设置-amd-p-state-powersave--epp-节能模式)
  - [1. 先理解几个概念](#1-先理解几个概念)
    - [1.1 amd\_pstate=active](#11-amd_pstateactive)
    - [1.2 scaling\_governor](#12-scaling_governor)
    - [1.3 energy\_performance\_preference / EPP](#13-energy_performance_preference--epp)
    - [1.4 BIOS TDP Config](#14-bios-tdp-config)
  - [2. 检查当前内核启动参数](#2-检查当前内核启动参数)
  - [3. 什么时候需要手动添加 amd\_pstate=active](#3-什么时候需要手动添加-amd_pstateactive)
  - [4. 判断 PVE 使用 GRUB 还是 systemd-boot / proxmox-boot-tool](#4-判断-pve-使用-grub-还是-systemd-boot--proxmox-boot-tool)
  - [5. GRUB 启动方式：添加 amd\_pstate=active](#5-grub-启动方式添加-amd_pstateactive)
    - [5.1 备份](#51-备份)
    - [5.2 编辑](#52-编辑)
    - [5.3 更新 GRUB 并重启](#53-更新-grub-并重启)
    - [5.4 验证](#54-验证)
  - [6. systemd-boot / proxmox-boot-tool 启动方式：添加 amd\_pstate=active](#6-systemd-boot--proxmox-boot-tool-启动方式添加-amd_pstateactive)
    - [6.1 备份](#61-备份)
    - [6.2 查看当前内容](#62-查看当前内容)
    - [6.3 编辑](#63-编辑)
    - [6.4 刷新启动项并重启](#64-刷新启动项并重启)
    - [6.5 验证](#65-验证)
  - [7. 内核参数回滚](#7-内核参数回滚)
    - [7.1 GRUB 回滚](#71-grub-回滚)
    - [7.2 systemd-boot / proxmox-boot-tool 回滚](#72-systemd-boot--proxmox-boot-tool-回滚)
    - [7.3 回滚后验证](#73-回滚后验证)
  - [8. BIOS 相关设置](#8-bios-相关设置)
  - [9. 检查当前 governor 和 EPP](#9-检查当前-governor-和-epp)
  - [10. 临时设置 powersave + balance\_power](#10-临时设置-powersave--balance_power)
  - [11. 验证是否设置成功](#11-验证是否设置成功)
  - [12. 实时观察频率变化](#12-实时观察频率变化)
  - [13. 安装测试工具](#13-安装测试工具)
  - [14. 如果响应变慢，改成 balance\_performance](#14-如果响应变慢改成-balance_performance)
  - [15. 持久化设置：systemd service](#15-持久化设置systemd-service)
  - [16. 修改持久化策略](#16-修改持久化策略)
  - [17. 回滚 powersave / EPP 持久化设置](#17-回滚-powersave--epp-持久化设置)
  - [18. 常见问题](#18-常见问题)
    - [18.1 为什么一开始 EPP 只有 performance？](#181-为什么一开始-epp-只有-performance)
    - [18.2 为什么没有 schedutil？](#182-为什么没有-schedutil)
    - [18.3 powersave 会不会锁低频？](#183-powersave-会不会锁低频)
    - [18.4 这能明显降低待机功耗吗？](#184-这能明显降低待机功耗吗)
    - [18.5 我现在已经 active，但 /proc/cmdline 没有 amd\_pstate=active，要不要补上？](#185-我现在已经-active但-proccmdline-没有-amd_pstateactive要不要补上)
  - [19. 一键检查脚本](#19-一键检查脚本)
  - [20. 最终建议](#20-最终建议)

本文记录在 Proxmox VE / Debian 系统上，将 AMD Ryzen 平台设置为 `amd-pstate-epp` + `powersave` + `balance_power` 的步骤，并整理内核启动参数 `amd_pstate=active` 的检查、设置和回滚方法。

环境参考：

```text
CPU: AMD Ryzen 9 9950X
主板: MSI MPG X870E Carbon WiFi
用途: PVE 管理软路由，多 VM / LXC 服务
服务: Nextcloud, Caddy, Syncthing, Authentik, UniFi UOS, Gitea, P4D, Emby 等
```

推荐组合：

```text
BIOS TDP Config: 95W 或 105W
amd_pstate status: active
scaling_driver: amd-pstate-epp
scaling_governor: powersave
energy_performance_preference: balance_power
```

如果觉得交互响应变慢，可以把 `balance_power` 改成：

```text
balance_performance
```

---

## 1. 先理解几个概念

### 1.1 amd_pstate=active

`amd_pstate=active` 是 Linux 内核启动参数，用于让 AMD Ryzen 使用 AMD P-State 的 active/EPP 模式。

在 active/EPP 模式下，常见驱动是：

```text
amd-pstate-epp
```

该模式下通常只有两个 governor：

```text
performance powersave
```

没有 `schedutil` 是正常现象。

### 1.2 scaling_governor

查看命令：

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
```

常见输出：

```text
performance powersave
```

推荐设置：

```text
powersave
```

注意：在 `amd-pstate-epp` 下，`powersave` 不等于锁低频。CPU 有负载时仍然会 boost，只是整体策略更偏能效。

### 1.3 energy_performance_preference / EPP

查看命令：

```bash
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_available_preferences
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference
```

切到 `powersave` governor 后，常见 EPP 可选项：

```text
default performance balance_performance balance_power power
```

建议优先使用：

```text
balance_power
```

如果响应偏慢，改用：

```text
balance_performance
```

### 1.4 BIOS TDP Config

对于 9950X + PVE 常驻服务，建议 BIOS 里使用：

```text
TDP Config: 95W 或 105W
```

大致选择：

```text
95W: 更偏低温、低噪、低满载功耗
105W: 性能和功耗更平衡，推荐默认选择
120W/125W: 偏性能，适合经常有 CPU 重负载
65W: 极低满载功耗，但多 VM / 编码 / 索引 / 同步时性能损失较明显
```

---

## 2. 检查当前内核启动参数

```bash
cat /proc/cmdline
```

示例输出：

```text
BOOT_IMAGE=/vmlinuz-7.0.12-1-pve root=ZFS=/ROOT/pve-1 ro root=ZFS=rpool/ROOT/pve-1 boot=zfs quiet iommu=pt
```

即使 `/proc/cmdline` 里没有显式写 `amd_pstate=active`，只要下面检查结果显示 `active` 和 `amd-pstate-epp`，就说明当前系统已经进入 AMD P-State active/EPP 模式。

检查 amd-pstate 当前状态：

```bash
cat /sys/devices/system/cpu/amd_pstate/status
```

理想输出：

```text
active
```

检查 CPU 频率驱动：

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
```

理想输出：

```text
amd-pstate-epp
```

检查可用 governor：

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
```

常见输出：

```text
performance powersave
```

如果看到：

```text
active
amd-pstate-epp
```

说明已经处于 `amd_pstate=active` 等效状态，通常不需要再改内核启动参数。

---

## 3. 什么时候需要手动添加 amd_pstate=active

只有在下面情况才建议手动添加：

```text
/sys/devices/system/cpu/amd_pstate/status 不存在
或 status 不是 active
或 scaling_driver 不是 amd-pstate-epp
或系统回退到了 acpi-cpufreq
```

检查命令：

```bash
cat /sys/devices/system/cpu/amd_pstate/status 2>/dev/null || echo "amd_pstate status not found"
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null
```

如果输出是：

```text
active
amd-pstate-epp
```

就不需要额外添加 `amd_pstate=active`。

如果输出类似：

```text
acpi-cpufreq
```

再考虑添加内核启动参数，并检查 BIOS 的 CPPC 设置。

---

## 4. 判断 PVE 使用 GRUB 还是 systemd-boot / proxmox-boot-tool

PVE 上内核参数修改位置取决于启动方式。

先执行：

```bash
proxmox-boot-tool status
```

如果能看到 ESP、kernel 同步状态等输出，通常是：

```text
systemd-boot / proxmox-boot-tool
```

这类场景常见于：

```text
PVE + UEFI + ZFS root
```

也可以执行：

```bash
efibootmgr -v | grep -Ei 'proxmox|systemd|grub'
```

大致规则：

```text
GRUB 启动: 修改 /etc/default/grub，然后 update-grub
systemd-boot / proxmox-boot-tool: 修改 /etc/kernel/cmdline，然后 proxmox-boot-tool refresh
```

---

## 5. GRUB 启动方式：添加 amd_pstate=active

### 5.1 备份

```bash
sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%F)
```

### 5.2 编辑

```bash
sudo nano /etc/default/grub
```

找到类似：

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
```

加入 `amd_pstate=active`：

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_pstate=active"
```

如果原本已经有 IOMMU 参数，例如：

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
```

则改成：

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt amd_pstate=active"
```

### 5.3 更新 GRUB 并重启

```bash
sudo update-grub
sudo reboot
```

### 5.4 验证

```bash
cat /proc/cmdline | tr ' ' '\n' | grep amd_pstate
cat /sys/devices/system/cpu/amd_pstate/status
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
```

理想输出：

```text
amd_pstate=active
active
amd-pstate-epp
```

---

## 6. systemd-boot / proxmox-boot-tool 启动方式：添加 amd_pstate=active

如果你的 `/proc/cmdline` 类似：

```text
BOOT_IMAGE=/vmlinuz-7.0.12-1-pve root=ZFS=/ROOT/pve-1 ro root=ZFS=rpool/ROOT/pve-1 boot=zfs quiet iommu=pt
```

并且系统是 PVE + ZFS root，那么通常要改：

```text
/etc/kernel/cmdline
```

而不是 `/etc/default/grub`。

### 6.1 备份

```bash
sudo cp /etc/kernel/cmdline /etc/kernel/cmdline.bak.$(date +%F)
```

### 6.2 查看当前内容

```bash
cat /etc/kernel/cmdline
```

示例：

```text
root=ZFS=rpool/ROOT/pve-1 boot=zfs quiet iommu=pt
```

注意：

- `/etc/kernel/cmdline` 通常必须是一整行；
- 不要拆成多行；
- 不要随意删除已有的 `root=ZFS=...`、`boot=zfs`、`iommu=pt` 等参数；
- 只在末尾追加 `amd_pstate=active`。

### 6.3 编辑

```bash
sudo nano /etc/kernel/cmdline
```

改成类似：

```text
root=ZFS=rpool/ROOT/pve-1 boot=zfs quiet iommu=pt amd_pstate=active
```

### 6.4 刷新启动项并重启

```bash
sudo proxmox-boot-tool refresh
sudo reboot
```

### 6.5 验证

```bash
cat /proc/cmdline | tr ' ' '\n' | grep amd_pstate
cat /sys/devices/system/cpu/amd_pstate/status
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
```

理想输出：

```text
amd_pstate=active
active
amd-pstate-epp
```

---

## 7. 内核参数回滚

### 7.1 GRUB 回滚

编辑：

```bash
sudo nano /etc/default/grub
```

从 `GRUB_CMDLINE_LINUX_DEFAULT` 中删除：

```text
amd_pstate=active
```

更新 GRUB：

```bash
sudo update-grub
sudo reboot
```

### 7.2 systemd-boot / proxmox-boot-tool 回滚

编辑：

```bash
sudo nano /etc/kernel/cmdline
```

删除：

```text
amd_pstate=active
```

刷新启动项：

```bash
sudo proxmox-boot-tool refresh
sudo reboot
```

### 7.3 回滚后验证

```bash
cat /proc/cmdline | tr ' ' '\n' | grep amd_pstate || echo "no amd_pstate parameter"
cat /sys/devices/system/cpu/amd_pstate/status 2>/dev/null || true
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null
```

---

## 8. BIOS 相关设置

如果系统没有进入 `amd-pstate-epp`，或者回退到了 `acpi-cpufreq`，优先检查 BIOS。

建议检查：

```text
CPPC: Enabled
CPPC Preferred Cores: Enabled
Global C-State Control: Enabled / Auto
Power Supply Idle Control: Low Current Idle / Auto
```

微星主板大致可能在：

```text
BIOS
→ OC
→ Advanced CPU Configuration
→ AMD CBS
→ NBIO Common Options
→ SMU Common Options
```

不同 BIOS 版本菜单位置可能不同，以实际界面为准。

---

## 9. 检查当前 governor 和 EPP

```bash
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_available_preferences
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference
```

如果当前 governor 是：

```text
performance
```

建议改成：

```text
powersave
```

注意：

```text
scaling_governor 里的 powersave
energy_performance_preference 里的 balance_power
```

这两个不是同一个东西。

---

## 10. 临时设置 powersave + balance_power

该设置重启后会失效，适合先测试。

先切换 governor：

```bash
sudo bash -c '
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo powersave > "$p/scaling_governor"
done
'
```

然后查看 EPP 可选项：

```bash
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_available_preferences
```

切换到 `powersave` governor 后，通常会出现：

```text
default performance balance_performance balance_power power
```

设置 EPP 为 `balance_power`：

```bash
sudo bash -c '
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo balance_power > "$p/energy_performance_preference"
done
'
```

---

## 11. 验证是否设置成功

```bash
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo "== ${p##*/} =="
  echo -n "governor: "; cat "$p/scaling_governor"
  echo -n "epp: "; cat "$p/energy_performance_preference"
done
```

理想输出类似：

```text
== policy0 ==
governor: powersave
epp: balance_power
== policy1 ==
governor: powersave
epp: balance_power
...
```

---

## 12. 实时观察频率变化

```bash
watch -n1 '
echo "amd_pstate: $(cat /sys/devices/system/cpu/amd_pstate/status 2>/dev/null)"
echo
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  gov=$(cat "$p/scaling_governor" 2>/dev/null)
  epp=$(cat "$p/energy_performance_preference" 2>/dev/null)
  mhz=$(awk "{printf \"%.0f\", \$1/1000}" "$p/scaling_cur_freq" 2>/dev/null)
  printf "%-8s gov=%-10s epp=%-18s cur=%s MHz\n" "${p##*/}" "$gov" "$epp" "$mhz"
done
'
```

正常现象：

- 空闲时频率会跳动，不一定长期保持很低；
- 有负载时仍然会 boost；
- `powersave + balance_power` 不等于锁低频；
- 它只是让 CPU 更偏能效，不那么激进抢频。

---

## 13. 安装测试工具

```bash
sudo apt update
sudo apt install -y stress-ng lm-sensors linux-cpupower
```

查看 CPU 调频信息：

```bash
cpupower frequency-info
```

查看温度：

```bash
sensors
```

实时观察温度：

```bash
watch -n1 'sensors | grep -Ei "Tctl|Tdie|Package|CPU|k10temp"'
```

压测 60 秒：

```bash
stress-ng --cpu 32 --cpu-method matrixprod --timeout 60s --metrics-brief
```

对于 16 核 32 线程 CPU，例如 9950X，可以使用：

```bash
stress-ng --cpu 32 --timeout 60s --metrics-brief
```

---

## 14. 如果响应变慢，改成 balance_performance

如果 PVE Web UI、Nextcloud、Authentik、UniFi、Gitea 等服务响应不够跟手，可以改成：

```bash
sudo bash -c '
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo powersave > "$p/scaling_governor"
  echo balance_performance > "$p/energy_performance_preference"
done
'
```

建议优先级：

```text
首选: powersave + balance_power
响应偏慢: powersave + balance_performance
不推荐常驻: performance governor
不建议一开始使用: power EPP
```

---

## 15. 持久化设置：systemd service

临时 `echo` 设置重启后会失效。确认稳定后，创建 systemd 服务。

```bash
sudo nano /etc/systemd/system/amd-pstate-epp-tune.service
```

写入：

```ini
[Unit]
Description=Tune AMD P-State EPP for PVE
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for p in /sys/devices/system/cpu/cpufreq/policy*; do echo powersave > "$p/scaling_governor"; [ -w "$p/energy_performance_preference" ] && echo balance_power > "$p/energy_performance_preference"; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

启用服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now amd-pstate-epp-tune.service
```

检查服务状态：

```bash
systemctl status amd-pstate-epp-tune.service
```

验证设置：

```bash
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference
```

理想输出：

```text
powersave
balance_power
```

---

## 16. 修改持久化策略

如果想从 `balance_power` 改成 `balance_performance`：

```bash
sudo nano /etc/systemd/system/amd-pstate-epp-tune.service
```

把这一段里的：

```text
balance_power
```

改成：

```text
balance_performance
```

然后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart amd-pstate-epp-tune.service
```

验证：

```bash
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference
```

---

## 17. 回滚 powersave / EPP 持久化设置

如果不想再使用该服务：

```bash
sudo systemctl disable --now amd-pstate-epp-tune.service
sudo rm /etc/systemd/system/amd-pstate-epp-tune.service
sudo systemctl daemon-reload
```

然后手动切回 performance：

```bash
sudo bash -c '
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo performance > "$p/scaling_governor"
  [ -w "$p/energy_performance_preference" ] && echo performance > "$p/energy_performance_preference"
done
'
```

验证：

```bash
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference
```

---

## 18. 常见问题

### 18.1 为什么一开始 EPP 只有 performance？

如果当前 governor 是 `performance`，可能会看到：

```text
energy_performance_available_preferences = performance
energy_performance_preference = performance
```

先切换 governor：

```bash
sudo bash -c '
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo powersave > "$p/scaling_governor"
done
'
```

再查看：

```bash
cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_available_preferences
```

通常会出现：

```text
default performance balance_performance balance_power power
```

### 18.2 为什么没有 schedutil？

在 `amd-pstate-epp` / `active` 模式下，常见 governor 只有：

```text
performance powersave
```

没有 `schedutil` 是正常的。

如果需要 `schedutil`，通常要使用：

```text
amd_pstate=guided
```

或：

```text
amd_pstate=passive
```

但对于 PVE 常驻服务器，一般不需要切换，保留：

```text
amd-pstate-epp + powersave + balance_power
```

更简单稳定。

### 18.3 powersave 会不会锁低频？

不会。

在 `amd-pstate-epp` 下，`powersave` 不等于传统意义上的固定低频。CPU 仍然会根据负载 boost，只是整体策略更偏能效。

### 18.4 这能明显降低待机功耗吗？

不一定。

AMD Ryzen 桌面平台的待机功耗通常受这些因素影响更大：

```text
主板芯片组
内存电压 / EXPO
PCIe 设备
网卡
SATA / USB 控制器
RGB / Wi-Fi / 蓝牙
ASPM / C-State
```

`powersave + balance_power` 更主要影响：

```text
轻载调度倾向
短突发升频积极程度
温度波动
风扇波动
满载前的行为
```

真正限制满载功耗，主要还是 BIOS 里的：

```text
TDP Config / PPT / TDC / EDC
```

### 18.5 我现在已经 active，但 /proc/cmdline 没有 amd_pstate=active，要不要补上？

不需要。

只要下面结果是：

```text
active
amd-pstate-epp
```

就说明当前系统已经进入 active/EPP 模式。没有必要为了“看起来完整”去改启动项。

---

## 19. 一键检查脚本

```bash
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo "== ${p##*/} =="
  echo -n "driver: "; cat "$p/scaling_driver" 2>/dev/null
  echo -n "governor: "; cat "$p/scaling_governor" 2>/dev/null
  echo -n "available governors: "; cat "$p/scaling_available_governors" 2>/dev/null
  echo -n "available EPP: "; cat "$p/energy_performance_available_preferences" 2>/dev/null
  echo -n "current EPP: "; cat "$p/energy_performance_preference" 2>/dev/null
  echo
done

echo "== amd_pstate =="
cat /sys/devices/system/cpu/amd_pstate/status 2>/dev/null
cat /sys/devices/system/cpu/amd_pstate/dynamic_epp 2>/dev/null || true

echo "== kernel cmdline =="
cat /proc/cmdline
```

---

## 20. 最终建议

对于我的 PVE / 软路由 / 多服务常驻环境：

```text
BIOS TDP Config: 105W 优先，想更省电可用 95W
amd_pstate: active
driver: amd-pstate-epp
governor: powersave
EPP: balance_power
```

如果出现服务交互延迟、Web UI 响应不够快：

```text
EPP 改为 balance_performance
governor 仍保持 powersave
```

如果系统已经自动进入：

```text
active
amd-pstate-epp
```

就不要改内核启动参数；只需要持久化 governor 和 EPP 即可。
