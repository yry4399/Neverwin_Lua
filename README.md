# 道具助手 (Grenade Helper) — Neverwin CS2

CS2 道具（手雷）点位助手 Lua 脚本，运行于 Neverwin 平台。

本项目由 [AMWRV6 - Grenade Helper](https://github.com/Anybody4506/AMWRV6/blob/main/Grenade%20Helper) 移植、修复并改动而来，原作基于 Aimware 平台。

## 功能

- **回放执行**：按住执行按键自动瞄准点位视角并投掷（站投 / 跳投 / 走投 / 蹲投 / 宏点位），支持左键/双键/右键投掷模式
- **自动寻路**：自动走到最近的匹配点位，目标锁定、高度差加权、卡住自动跳过
- **世界标签**：3D 点位名称 + 距离显示、点位圆环、FOV 范围圆环、回放状态显示
- **统一 FOV**：菜单滑块统一控制所有点位的触发 FOV
- **录制**：保存当前点位（名称/跳投/走投方向与时长/投掷模式）、宏录制（逐帧 usercmd 回放）
- **点位管理**：地图选择 + 道具分类（烟雾/闪光/高爆/燃烧/诱饵）筛选，滚动条 + 滚轮翻页，行内改名与删除（直接写回数据文件）
- **数据文件**：`helper_data.txt` 存放点位（de_dust2 / de_mirage / de_nuke 等），改名/删除/新增均保留原格式

## 安装

1. 将 `grenade_helper.lua` 放入 `C:\neverwin\scripts\`
2. 将 `helper_data.txt` 放入 `C:\neverwin\scripts\data\`
3. 在 Neverwin 脚本列表中启用，并勾选 **Allow Insecure**（数据文件读写需要）

## 使用

- 手持手雷类道具，靠近点位后按住执行按键（默认鼠标左键）即可自动瞄准投掷
- 开启“自动走到最近点位”后，按住执行按键会自动走向最近匹配点位
- 点位管理列表中点击行载入名称，修改文本框后点【改名】写回文件；【删除】直接移除该点位

## 致谢

- 原始脚本：[Anybody4506/AMWRV6](https://github.com/Anybody4506/AMWRV6) 的 Grenade Helper（Aimware 版）
