-- @author vitma
-- @uid 1
-- =========================================================================
--     spoof_hook.lua — PluginSense 主菜单伪造复现（纯内存写版 v3）
--     全部为内存读写，零 detour：
--       等级:     写全局 level (GetCurrentLevel 快速路径, flags bit13 已置位)
--       优先分数: 写槽位 type==11 的 +0x54(分数)/+0x58(胜场)
--       搭档段位: 写槽位 type==7  的 +0x54(段位)/+0x58(胜场)
--       冷却:     flags 置 bit9 + cd_end = os.time()+28800+剩余(游戏用本地
--                 时间当 UTC) + cd_type 写原因枚举(23 种)
--       封禁:     banA 写非零、cd_type 写 0
--     每帧覆盖写入防游戏回写；关闭开关恢复原值。仅自己可见。
-- =========================================================================

local ffi = rawget(_G, "ffi")

local MOD = "client.dll"

-- 特征码 -> rip 相对全局（2026-11-05 版本实测命中）
local SIG_COOLDOWN = "48 83 EC ?? 8B 05 ?? ?? ?? ?? C1 E8 ?? A8 ?? 74 ?? 48 8D 4C 24" -- +4: flags
local SIG_LEVEL    = "8B 1D ?? ?? ?? ?? 48 8D 4C 24 ?? FF 15 ?? ?? ?? ?? 2B D8"        -- +0: cd_end
local SIG_BAN      = "8B 05 ?? ?? ?? ?? 85 C0 74 ?? 83 3D ?? ?? ?? ?? 00 74 ?? 33 C0 C3" -- +0: banA, +0xA: cd_type
-- 等级全局 level = banA + 8（0x2581824，GetCurrentLevel 快速路径），由 banA 推导，无需特征码

local SLOT_BASE_RVA = 0x25F1800    -- qword 槽位数组指针
local SLOT_TYPE_OFF = 0x10         -- 槽位段位类型（11=优先 7=搭档）
local SLOT_V54_OFF  = 0x54         -- 段位值/分数
local SLOT_V58_OFF  = 0x58         -- 胜场

local COOLDOWN_BIT  = 0x200        -- flags bit9：冷却有效位
local TZ_OFFSET     = 28800        -- 游戏 now = os.time() + 8h
local COOLDOWN_SECS = { 30 * 60, 2 * 3600, 24 * 3600, 7 * 24 * 3600 }

-- 冷却原因枚举（client.dll 0xF9D160 跳表提取；12/13/17 类冷却 fn 返回 0 无倒计时）
local CD_REASONS = {
    "默认（无原因）", "被踢出比赛", "误伤队友达上限", "出生点伤害队友",
    "断线过久", "中途退出", "伤害队友达上限", "出生点攻击队友",
    "官方封禁", "被踢次数过多", "作弊定罪", "行为定罪",
    "中途退出-宽限(无倒计时)", "断线-宽限(无倒计时)", "官方封禁 II",
    "原因 15", "连接失败", "踢人滥用(无倒计时)", "段位校准",
    "GSLT 违规", "GSLT 违规 II", "恶意行为举报", "VACNet 罪魁", "VACNet 连坐",
}

local RANK_NAMES = {
    "白银 I", "白银 II", "白银 III", "白银 IV", "白银精英", "白银精英大师",
    "黄金新星 I", "黄金新星 II", "黄金新星 III", "黄金新星大师",
    "大师守卫 I", "大师守卫 II", "大师守卫精英", "杰出大师守卫",
    "传奇之鹰", "传奇之鹰大师", "无上之首席大师", "全球精英",
}

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------
local tab = ui.tab("虚假")
local g = tab:group("主菜单伪造")

local en_level = g:checkbox("虚假等级", false)
local ui_level = g:slider_float("等级", 1, 40, 40, "%.0f")
local ui_xp    = g:slider_float("经验", 0, 4999, 2500, "%.0f")

local en_premier = g:checkbox("虚假优先分数", false)
local ui_rating  = g:slider_float("优先分数", 0, 99999, 25000, "%.0f")
local ui_pwins   = g:slider_float("优先胜场", 0, 9999, 250, "%.0f")

local en_wingman = g:checkbox("虚假搭档段位", false)
local ui_wrank   = g:combo("搭档段位", RANK_NAMES)
local ui_wwins   = g:slider_float("搭档胜场", 0, 9999, 150, "%.0f")

local en_cd   = g:checkbox("虚假冷却", false)
local ui_cd   = g:combo("冷却时长", { "30 分钟", "2 小时", "24 小时", "7 天" })
local ui_cdr  = g:combo("冷却原因", CD_REASONS)

local en_ban = g:checkbox("虚假封禁", false)
local ui_ban = g:combo("封禁类型", { "VAC 封禁", "游戏封禁" })

local en_unban  = g:checkbox("虚假未封禁（消除封禁/冷却）", false)
local en_ping   = g:checkbox("虚假延迟", false)
local ui_ping   = g:slider_float("延迟 (ms)", 0, 999999, 5, "%.0f")

-- ---------------------------------------------------------------------------
-- 地址解析
-- ---------------------------------------------------------------------------
local resolved = false
local mod_base = nil
local addr_flags, addr_cdend, addr_banA, addr_cdt, addr_level, addr_xp

local function read_u64(addr)
    local ok, v = pcall(memory.read, "ptr", addr)
    if not ok or v == nil then return nil end
    if type(v) == "cdata" then
        if ffi == nil then return nil end
        return tonumber(ffi.cast("uintptr_t", v))
    end
    return tonumber(v)
end

-- rip 相对指令解析全局地址：disp32 在 off+2 处，ilen 为整条指令长度
local function rip_global(addr, off, ilen)
    local disp = memory.read("int", addr + off + 2)
    if disp == nil then return nil end
    return addr + off + ilen + disp
end

local last_try = 0

local function resolve()
    -- 失败节流：5 秒才重试一次，避免每帧全模块扫描卡死
    local now = globals.realtime()
    if now < last_try then return false end
    last_try = now + 5

    local base = memory.module(MOD)
    if base == nil then
        print("[spoof_hook] 无法获取 client.dll 基址")
        return false
    end
    mod_base = base

    -- 全局连续布局，只需 SIG_BAN 一条特征码定位 banA，其余相对推导：
    -- flags = banA-0x9C, cd_end = banA-8, cd_type = banA-4, level = banA+8
    local a_bn = memory.find_pattern(MOD, SIG_BAN)
    if a_bn == nil then
        print("[spoof_hook] 特征码未命中（CS2 已更新？）")
        return false
    end

    addr_banA  = rip_global(a_bn, 0, 6)
    addr_cdt   = rip_global(a_bn, 0xA, 7)
    if addr_banA == nil or addr_cdt == nil then
        print("[spoof_hook] 全局地址解析失败")
        return false
    end
    addr_flags = addr_banA - 0x9C
    addr_cdend = addr_banA - 8
    addr_level = addr_banA + 8
    addr_xp    = addr_banA + 0xC

    print(string.format("[spoof_hook] flags=0x%X cd_end=0x%X banA=0x%X cd_type=0x%X level=0x%X",
        addr_flags, addr_cdend, addr_banA, addr_cdt, addr_level))
    return true
end

-- ---------------------------------------------------------------------------
-- 写入逻辑
-- ---------------------------------------------------------------------------
local cd_until = 0
local saved_level = nil
local saved_xp = nil
local saved_slots = {}   -- [i] = {v54, v58}

-- 遍历槽位数组，向 type 匹配的槽写 +0x54/+0x58（首次写前保存原值）
local function write_slots_by_type(rtype, v54, v58)
    local arr = read_u64(mod_base + SLOT_BASE_RVA)
    if arr == nil or arr == 0 then return end
    for i = 0, 9 do
        local slot = arr + i * 0x88
        if memory.read("int", slot + SLOT_TYPE_OFF) == rtype then
            if saved_slots[i] == nil then
                saved_slots[i] = {
                    memory.read("int", slot + SLOT_V54_OFF),
                    memory.read("int", slot + SLOT_V58_OFF),
                }
            end
            if v54 ~= nil then memory.write("int", slot + SLOT_V54_OFF, v54) end
            if v58 ~= nil then memory.write("int", slot + SLOT_V58_OFF, v58) end
        end
    end
end

local function has_bit(f, b)
    return math.floor(f / b) % 2 == 1
end

local function apply()
    -- 等级+经验：写 GetCurrentLevel/GetCurrentXp 快速路径全局
    -- xp 全局打包 = (升级所需<<16)|当前经验，total=5000 时函数直接返回低 16 位
    if en_level:get() then
        if saved_level == nil then
            saved_level = memory.read("int", addr_level)
            saved_xp = memory.read("int", addr_xp)
        end
        memory.write("int", addr_level, math.floor(ui_level:get()))
        memory.write("int", addr_xp, 5000 * 65536 + math.floor(ui_xp:get()))
    end

    -- 优先分数（type==11）：+0x54 分数 +0x58 胜场
    if en_premier:get() then
        write_slots_by_type(11, math.floor(ui_rating:get()), math.floor(ui_pwins:get()))
    end

    -- 搭档段位（type==7）：+0x54 段位(1-18) +0x58 胜场
    if en_wingman:get() then
        write_slots_by_type(7, (ui_wrank:get() or 0) + 1, math.floor(ui_wwins:get()))
    end

    -- 虚假未封禁：持续清零封禁/冷却状态（与其它伪造互斥，优先级最高）
    if en_unban:get() then
        memory.write("int", addr_banA, 0)
        memory.write("int", addr_cdt, 0)
        memory.write("int", addr_cdend, 0)
        local f = memory.read("int", addr_flags)
        if f ~= nil and has_bit(f, COOLDOWN_BIT) then
            memory.write("int", addr_flags, f - COOLDOWN_BIT)
        end
        return
    end

    -- 冷却：flags 置 bit9 + 结束时间戳 + 原因枚举
    if en_cd:get() then
        local left = cd_until - globals.realtime()
        if left > 0 then
            local f = memory.read("int", addr_flags)
            if f ~= nil and not has_bit(f, COOLDOWN_BIT) then
                memory.write("int", addr_flags, f + COOLDOWN_BIT)
            end
            memory.write("int", addr_cdend, os.time() + TZ_OFFSET + math.floor(left))
            memory.write("int", addr_cdt, ui_cdr:get() or 0)
        end
    end

    -- 封禁：banA 非零、cd_type 为 0（与冷却原因互斥）
    if en_ban:get() then
        memory.write("int", addr_banA, (ui_ban:get() or 0) + 1)
        memory.write("int", addr_cdt, 0)
    end
end

-- 恢复所有原值（等级/槽位/冷却/封禁）
local function restore_all()
    if saved_level ~= nil then
        memory.write("int", addr_level, saved_level)
        saved_level = nil
    end
    if saved_xp ~= nil then
        memory.write("int", addr_xp, saved_xp)
        saved_xp = nil
    end
    local arr = read_u64(mod_base + SLOT_BASE_RVA)
    if arr ~= nil and arr ~= 0 then
        for i, sv in pairs(saved_slots) do
            local slot = arr + i * 0x88
            if sv[1] ~= nil then memory.write("int", slot + SLOT_V54_OFF, sv[1]) end
            if sv[2] ~= nil then memory.write("int", slot + SLOT_V58_OFF, sv[2]) end
        end
    end
    saved_slots = {}
end

events.on("paint", function()
    pcall(function()
        if not client.insecure() then return end
        if not resolved then
            resolved = resolve()
            if not resolved then return end
        end
        apply()
    end)
end)

-- ---------------------------------------------------------------------------
-- 虚假延迟（fake_misc.lua 同款独立路径：不走特征码解析，主菜单/局内每帧写）
-- ---------------------------------------------------------------------------
events.on("paint", function()
    pcall(function()
        if not en_ping:get() then return end
        local ok, ctrl = pcall(entity.local_controller)
        if not ok or ctrl == nil then return end
        ctrl:set("CCSPlayerController", "m_iPing", "int", math.floor(ui_ping:get()))
    end)
end)

-- 开关边沿处理
local cd_prev, ban_prev = false, false
events.on("frame_stage", function()
    pcall(function()
        if not resolved then return end

        local on_cd = en_cd:get()
        if on_cd and not cd_prev then
            cd_until = globals.realtime() + COOLDOWN_SECS[(ui_cd:get() or 0) + 1]
        elseif not on_cd and cd_prev then
            memory.write("int", addr_cdend, 0)
            memory.write("int", addr_cdt, 0)
            local f = memory.read("int", addr_flags)
            if f ~= nil and has_bit(f, COOLDOWN_BIT) then
                memory.write("int", addr_flags, f - COOLDOWN_BIT)
            end
        end
        cd_prev = on_cd

        local on_ban = en_ban:get()
        if not on_ban and ban_prev then
            memory.write("int", addr_banA, 0)
        end
        ban_prev = on_ban

        -- 等级/分数/段位全关时才恢复（避免反复读写）
        if not en_level:get() and not en_premier:get() and not en_wingman:get() then
            restore_all()
        end
    end)
end)

if not client.insecure() then
    print("[spoof_hook] 需要开启 Allow Insecure")
    client.notify("请开启 Allow Insecure", "spoof_hook")
end
