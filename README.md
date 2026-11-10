# Neverwin_Lua — Neverwin CS2 Lua 脚本合集

运行于 Neverwin 平台的 CS2 Lua 脚本仓库。

## 脚本

### grenade_helper.lua — 道具点位助手

由 [AMWRV6 - Grenade Helper](https://github.com/Anybody4506/AMWRV6/blob/main/Grenade%20Helper) 移植、修复并改动而来（原作基于 Aimware 平台）。

- **回放执行**：按住执行按键自动瞄准点位视角并投掷（站投 / 跳投 / 走投 / 蹲投 / 宏点位），支持左键/双键/右键投掷模式
- **自动寻路**：寻路/停脚/投掷时序已对齐原版 AW 实现，自动走到最近点位并停稳执行
- **世界标签**：3D 点位名称 + 距离显示、点位圆环、FOV 范围圆环、回放状态显示、待机/就绪双色瞄准点
- **录制**：绑键式宏录制（逐帧 usercmd 回放，自动跳过前导静止段）、手动创建点位（跳投/走投方向与时长/投掷模式）
- **点位管理（右侧独立分组）**：地图选择 + 道具分类筛选 + **点位名称搜索**，滚轮翻页，行内改名与删除（直接写回数据文件）
- **数据文件**：`helper_data.txt` 存放点位（de_dust2 / de_mirage / de_nuke 等），改名/删除/新增均保留原格式

### FortniteDamage.lua — 堡垒之夜伤害数字

原作者 **1-star**，汉化 + 资源内嵌整合。

- **单文件**：190 张伤害数字贴图已内嵌进脚本（base64 + RLE 压缩），**无需再放 images 资源包**
- 爆头/身体/护甲伤害数字，支持独立颜色、缩放、显示时长、垂直偏移
- 四种动画样式：经典堡垒之夜 / 弹跳 / 漂浮 / 分裂
- 按目标过滤：自己 / 队友 / 敌人
- 内置状态组：Allow Insecure 开关 + 一键重载

许可证：整合版本适用仓库根目录 CC BY-NC 4.0 许可证；原作权利归 1-star。

### spoof_hook.lua — 主菜单伪造套件（自主开发）

完全自主开发，通过 client.dll 特征码定位 + 内存写入实现，**仅自己可见**，不影响真实账户数据：

- **虚假等级**：1-40 级 + 经验值（资料卡军衔图标、服役勋章按钮同步变化）
- **虚假优先分数**：0-99999 分数 + 胜场
- **虚假搭档段位**：白银 I ~ 全球精英 18 段 + 胜场
- **虚假冷却**：4 种时长 × 23 种冷却原因（被踢/中途退出/作弊定罪/GSLT 违规/VACNet 等，横幅显示对应原因文本）
- **虚假封禁**：VAC 封禁 / 游戏封禁横幅
- **虚假未封禁**：一键消除真实封禁/冷却的图标显示（仅本地视觉）
- **虚假延迟**：本地记分板假 ping（0-999999ms）

许可证：完全自主开发，适用仓库根目录 CC BY-NC 4.0 许可证，见 [LICENSE](LICENSE)。

### spammer.lua — 自动刷屏整合

刷屏功能合集，每个刷屏功能独立拥有：启用开关 / 发送频道（公屏 say / 队伍 say_team）/ 发送间隔（0.1-10 秒）/ 随机顺序 / 控制台发送记录：

- **内置文案池**：辱骂台独（5 条）、中二刷屏（24 条）、嘴臭刷屏（80 条）、辱骂绿玩（26 条）
- **自定义刷屏**：三个自定义消息池（A/B/C，英文逗号分隔），随机模式一轮发完才重新洗牌（不重复），池内容修改后自动重置进度（整合自 zdmar.lua）
- **状态组**（移植自道具助手）：Allow Insecure 开关 + 一键重载 + 闲鱼链接

许可证：适用仓库根目录 CC BY-NC 4.0 许可证，见 [LICENSE](LICENSE)。

## 配套组件

### neverlose_core_newad_ffi.dll

脚本运行所需的 FFI 支持库，放置到 Neverwin 安装目录（通常为 `C:\neverwin\`）。

## 安装

1. 将需要的 `.lua` 脚本放入 `C:\neverwin\scripts\`
2. `helper_data.txt` 放入 `C:\neverwin\scripts\data\`（仅 grenade_helper 需要）
3. 在 Neverwin 脚本列表中启用，并勾选 **Allow Insecure**

## 许可证

本仓库内容采用 **CC BY-NC 4.0**（署名-非商业性使用），详见 [LICENSE](LICENSE)：

- 转载/二次创作**必须注明出处**（作者 yry4399 + 本仓库链接）
- **禁止商用**（不得出售、捆绑收费产品或以任何形式收费）
- 例外：grenade_helper 移植部分权利归 [AMWRV6](https://github.com/Anybody4506/AMWRV6) 原作者；FortniteDamage 原作权利归 1-star；neverlose_core_newad_ffi.dll 权利归其原发行方

## 致谢

- AMWRV6 / Anybody4506 — grenade_helper 原作
- 1-star — FortniteDamage 原作
- zdmar — 自定义刷屏功能原作
