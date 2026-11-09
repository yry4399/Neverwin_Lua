# Neverwin_Lua — Neverwin CS2 Lua 脚本合集

运行于 Neverwin 平台的 CS2 Lua 脚本仓库。

## 脚本

### grenade_helper.lua — 道具点位助手

由 [AMWRV6 - Grenade Helper](https://github.com/Anybody4506/AMWRV6/blob/main/Grenade%20Helper) 移植、修复并改动而来（原作基于 Aimware 平台）。

- **回放执行**：按住执行按键自动瞄准点位视角并投掷（站投 / 跳投 / 走投 / 蹲投 / 宏点位），支持左键/双键/右键投掷模式
- **自动寻路**：自动走到最近的匹配点位，目标锁定、高度差加权、卡住自动跳过
- **世界标签**：3D 点位名称 + 距离显示、点位圆环、FOV 范围圆环、回放状态显示
- **录制**：保存当前点位（名称/跳投/走投方向与时长/投掷模式）、宏录制（逐帧 usercmd 回放）
- **点位管理（右侧独立分组）**：地图选择 + 道具分类筛选 + **点位名称搜索**，滚轮翻页，行内改名与删除（直接写回数据文件）
- **数据文件**：`helper_data.txt` 存放点位（de_dust2 / de_mirage / de_nuke 等），改名/删除/新增均保留原格式

### spoof_hook.lua — 主菜单伪造套件（自主开发）

完全自主开发，通过 client.dll 特征码定位 + 内存写入实现，**仅自己可见**，不影响真实账户数据：

- **虚假等级**：1-40 级 + 经验值（资料卡军衔图标、服役勋章按钮同步变化）
- **虚假优先分数**：0-99999 分数 + 胜场
- **虚假搭档段位**：白银 I ~ 全球精英 18 段 + 胜场
- **虚假冷却**：4 种时长 × 23 种冷却原因（被踢/中途退出/作弊定罪/GSLT 违规/VACNet 等，横幅显示对应原因文本）
- **虚假封禁**：VAC 封禁 / 游戏封禁横幅
- **虚假未封禁**：一键消除真实封禁/冷却的图标显示（仅本地视觉）
- **虚假延迟**：本地记分板假 ping（0-999999ms）

许可证：与仓库其它内容不同，本脚本使用单独许可证，见 [LICENSE.spoof_hook](LICENSE.spoof_hook)。

## 配套组件

### neverlose_core_newad_ffi.dll

脚本运行所需的 FFI 支持库，放置到 Neverwin 安装目录（通常为 `C:\neverwin\`）。

## 安装

1. 将需要的 `.lua` 脚本放入 `C:\neverwin\scripts\`
2. `helper_data.txt` 放入 `C:\neverwin\scripts\data\`（仅 grenade_helper 需要）
3. 在 Neverwin 脚本列表中启用，并勾选 **Allow Insecure**

## 致谢

- AMWRV6 / Anybody4506 — grenade_helper 原作
