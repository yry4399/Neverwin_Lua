--[[========================================================================
  freecam.lua  — CS2 存活自由视角（Neverwin）
  --------------------------------------------------------------------------
  原理：events.override_view 每帧拿到 CViewSetup 指针，改写 origin / angles，
        把渲染相机从第一人称眼睛位置脱离。不写 m_iObserverMode，不走网络同步。

  使用：侧边栏 "Freecam" 里填按键名（默认 f），按住即开启，松开恢复。
        WASD 平移 | Space/Ctrl 升降 | Shift 加速 | 鼠标 转视角
        调试：打开「强制开启（调试）」可绕过绑键直接验证相机写入是否生效。

  放置：C:\neverwin\scripts\freecam.lua（在 Neverwin 里勾选加载）
==========================================================================]]

local DEBUG = false

-- ============================================================ 默认值
local DEFAULTS = {
    vk        = 0x46,    -- F（Windows 虚拟键码，1 = 鼠标左键）
    speed     = 8,       -- 相机速度：单位 / tick（64 tick 约 512 u/s）
    boost     = 3,       -- 按住 Shift 的倍率
    freeze    = true,
}

-- ============================================================ 状态
local st = {
    on          = false,
    initialized = false,
    pos         = nil,   -- Vector
    ang         = nil,   -- QAngle
    speed       = DEFAULTS.speed,
    freeze      = DEFAULTS.freeze,
    view_ang    = nil,   -- 从 override_view 读到的渲染相机角度（含鼠标转动）
    ov_calls    = 0,
    re_calls    = 0,
    logged      = 0,
    broken      = false,   -- 写入彻底失败后锁住，松开按键才重试
}

-- 控制台输出已关闭
local function log() end
local function dlog() end

-- ============================================================ 侧边栏菜单
ui.sidebar("Freecam", "crosshairs")

-- 这个客户端的正确绑键 API：ui.keybind，值为 VK 码，用 input.key_down 查询按住状态
local kb_hold = ui.keybind("Freecam 按住开启", DEFAULTS.vk)

local tab       = ui.tab("自由视角")
local g_key     = tab:group("按键")
local g_cam     = tab:group("相机")

g_key:label("按住绑定的按键开启（默认 F，在绑键列表里可改）")

local sl_speed  = g_cam:slider("速度 (u/tick)", 1, 50, DEFAULTS.speed)
local tg_freeze = g_cam:toggle("冻结人物移动", DEFAULTS.freeze)
local tg_force  = g_cam:toggle("强制开启（调试）", false)

-- ============================================================ 工具
local function copy_vec(v) return vector(v.x, v.y, v.z) end
local function copy_ang(a) return { x = a.x, y = a.y, z = a.z or 0 } end

-- 相机移动用的按键（虚拟键码）
local VK = {
    fwd   = 0x57,   -- W
    back  = 0x53,   -- S
    left  = 0x41,   -- A
    right = 0x44,   -- D
    up    = 0x20,   -- Space
    down  = 0x11,   -- Ctrl
    boost = 0x10,   -- Shift
}

local function key_down(vk)
    local ok, d = pcall(function() return input.key_down(vk) end)
    return ok and d == true
end

-- cmd 可用字段/方法探测（只跑一次），不同客户端 cmd 接口差异很大
local cmd_probed = false
local CMD_NAMES = {
    "buttons", "set_buttons", "set_move", "set_upmove", "move",
    "view_angles", "set_view_angles", "viewangles",
    "forwardmove", "sidemove", "upmove",
    "in_jump", "in_forward", "in_back", "in_moveleft", "in_moveright",
    "move_yaw", "subtick_moves",
}

local function probe_cmd(cmd)
    if cmd_probed then return end
    cmd_probed = true

    local keys = {}
    pcall(function()
        for k, v in pairs(cmd) do
            keys[#keys + 1] = tostring(k) .. ":" .. type(v)
        end
    end)
    dlog("cmd keys -> ", table.concat(keys, ", "))

    for _, n in ipairs(CMD_NAMES) do
        local ok, v = pcall(function() return cmd[n] end)
        dlog("cmd.", n, " ok=", ok, " type=", type(v), " value=", tostring(v))
    end

    pcall(function()
        local b = cmd.forwardmove
        cmd.forwardmove = 0
        dlog("cmd write forwardmove: ", tostring(b), " -> ", tostring(cmd.forwardmove))
    end)
    pcall(function()
        local b = cmd.in_jump
        cmd.in_jump = false
        dlog("cmd write in_jump: ", tostring(b), " -> ", tostring(cmd.in_jump))
    end)
end

-- 这个客户端的相机对象：读用 view:origin() / view:angles()
local function read_view_pos(view)
    local ok, o = pcall(function() return view:origin() end)
    if ok and o ~= nil and type(o.x) == "number" then return o end
    return nil
end

local function read_view_ang(view)
    local ok, a = pcall(function() return view:angles() end)
    if ok and a ~= nil and type(a.x) == "number" then return a end
    return nil
end

-- 本地 pawn 多路探测：这个客户端的取值函数和文档不完全一致
local pawn_src_logged = false
local function find_pawn()
    local try = {
        { "local_pawn",     function() return entity.local_pawn() end },
        { "get_local_pawn", function() return entity.get_local_pawn() end },
        { "get_local_player", function() return entity.get_local_player() end },
        { "local_player",   function() return select(2, entity.local_player()) end },
    }
    for _, t in ipairs(try) do
        local ok, p = pcall(t[2])
        if ok and p ~= nil then
            if DEBUG and not pawn_src_logged then
                pawn_src_logged = true
                dlog("pawn via ", t[1], " -> ", tostring(p))
            end
            return p
        end
    end
    return nil
end

-- 本地玩家是否存活，第二个返回值是诊断信息
local function local_alive()
    local p = find_pawn()
    if p == nil then return false, "pawn=nil (all getters failed)" end

    local ok, v = pcall(function() return p:is_alive() end)
    if ok and type(v) == "boolean" then return v, "is_alive=" .. tostring(v) end

    local ok2, v2 = pcall(function() return p:alive() end)
    if ok2 and type(v2) == "boolean" then return v2, "alive()=" .. tostring(v2) end

    local ok3, v3 = pcall(function() return p:health() end)
    if ok3 and type(v3) == "number" then return v3 > 0, "health=" .. tostring(v3) end

    local ok4, v4 = pcall(function() return p.m_iHealth end)
    if ok4 and type(v4) == "number" then return v4 > 0, "m_iHealth=" .. tostring(v4) end

    return false, "no alive accessor on pawn"
end

-- 当前绑定的键是否按住
local logged_bind = false
local function bind_down()
    local ok, v = pcall(function() return kb_hold:get() end)
    if DEBUG and not logged_bind then
        logged_bind = true
        dlog("bind get ok=", ok, " value=", tostring(v), " type=", type(v))
    end
    if not ok then return false end

    if type(v) == "boolean" then return v end
    if type(v) == "number" and v > 0 then
        local ok2, d = pcall(function() return input.key_down(v) end)
        return ok2 and d == true
    end

    local ok3, active = pcall(function() return kb_hold:is_active() end)
    if ok3 and type(active) == "boolean" then return active end
    return false
end

-- ============================================================ 开关
local blocked_logged = false
local function engage()
    if st.on or st.broken then return end

    local alive, info = local_alive()
    if not alive then
        if DEBUG and not blocked_logged then
            blocked_logged = true
            dlog("engage blocked: ", info)
        end
        return
    end
    blocked_logged = false

    local ok = pcall(function()
        st.speed  = sl_speed:get()
        st.freeze = tg_freeze:get() == true
    end)
    if not ok then dlog("读取菜单参数失败") end

    st.on          = true
    st.initialized = false
    st.logged      = 0
    st.view_ang    = nil
    log("on  speed=", st.speed, " freeze=", st.freeze)
end

local function disengage()
    if not st.on then return end
    st.on          = false
    st.initialized = false
    log("off")
end

-- ============================================================ 视角钩子
local function apply_view(view)
    st.ov_calls = st.ov_calls + 1
    if DEBUG and st.ov_calls % 300 == 0 then
        dlog("override_view calls=", st.ov_calls, " on=", st.on, " init=", st.initialized)
    end

    if not st.on then return end

    if not local_alive() then
        disengage()
        return
    end

    if not st.initialized then
        local p = read_view_pos(view)
        if p == nil then
            dlog("读取相机位置失败：view:origin() 不可用")
            st.broken = true
            disengage()
            return
        end
        st.pos = copy_vec(p)
        st.ang = read_view_ang(view)          -- 可能为 nil：只移动位置
        st.initialized = true
        dlog("初始视角 origin=", tostring(st.pos), " angles=", tostring(st.ang))
    end

    local ok = pcall(function() view:set_origin(st.pos) end)
    if not ok then
        ok = pcall(function() view.origin = st.pos end)
    end
    if not ok then
        ok = pcall(function()
            view.origin.x = st.pos.x
            view.origin.y = st.pos.y
            view.origin.z = st.pos.z
        end)
    end

    -- 渲染相机的朝向就是玩家真实视角（含鼠标转动），下一 tick 给移动方向用
    local va = read_view_ang(view)
    if va ~= nil then st.view_ang = { x = va.x, y = va.y } end

    if DEBUG and st.logged < 3 then
        st.logged = st.logged + 1
        local rp = read_view_pos(view)
        local ra = read_view_ang(view)
        local function fmt(v)
            if v == nil then return "nil" end
            return tostring(v.x) .. "," .. tostring(v.y) .. "," .. tostring(v.z)
        end
        dlog("write pos_ok=", ok,
             " target=", fmt(st.pos), " readback=", fmt(rp), " view_ang=", fmt(ra))
    end
end

-- ============================================================ 输入与移动
local function update_camera(cmd)
    -- 朝向优先用 override_view 读到的渲染角度（含鼠标），cmd:view_angles() 不放鼠标输入
    local cur = nil
    if st.view_ang ~= nil then
        st.ang = { x = st.view_ang.x, y = st.view_ang.y }
    else
        pcall(function() cur = cmd:view_angles() end)
        if cur ~= nil and type(cur.y) == "number" then
            st.ang = copy_ang(cur)
        end
    end
    if st.ang == nil then st.ang = { x = 0, y = 0 } end

    -- 手写方向：不依赖 angle:forward()，确保用的是 st.ang 的实时值
    local yaw   = math.rad(st.ang.y)
    local pitch = math.rad(st.ang.x)
    local cp    = math.cos(pitch)
    local fwd   = vector(math.cos(yaw) * cp, math.sin(yaw) * cp, -math.sin(pitch))

    -- 水平右向量；归一化，斜着看时横移速度不衰减
    local hl = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
    if hl < 0.001 then hl = 0.001 end
    local rx, ry = fwd.y / hl, -fwd.x / hl

    local dx, dy2, dz = 0, 0, 0
    if key_down(VK.fwd)   then dx, dy2, dz = dx + fwd.x, dy2 + fwd.y, dz + fwd.z end
    if key_down(VK.back)  then dx, dy2, dz = dx - fwd.x, dy2 - fwd.y, dz - fwd.z end
    if key_down(VK.right) then dx, dy2 = dx + rx, dy2 + ry end
    if key_down(VK.left)  then dx, dy2 = dx - rx, dy2 - ry end
    if key_down(VK.up)    then dz = dz + 1 end
    if key_down(VK.down)  then dz = dz - 1 end

    local spd = st.speed
    if key_down(VK.boost) then spd = spd * DEFAULTS.boost end

    st.pos.x = st.pos.x + dx  * spd
    st.pos.y = st.pos.y + dy2 * spd
    st.pos.z = st.pos.z + dz  * spd

    if DEBUG then
        st.dbg = (st.dbg or 0) + 1
        if st.dbg % 40 == 0 then
            log(string.format(
                "cam ang=(%.1f,%.1f) fwd=(%.2f,%.2f,%.2f) d=(%.2f,%.2f,%.2f) W=%s A=%s S=%s D=%s pos=(%.1f,%.1f,%.1f)",
                st.ang.x, st.ang.y, fwd.x, fwd.y, fwd.z, dx, dy2, dz,
                tostring(key_down(VK.fwd)), tostring(key_down(VK.left)),
                tostring(key_down(VK.back)), tostring(key_down(VK.right)),
                st.pos.x, st.pos.y, st.pos.z))
        end
    end

    if st.freeze then
        pcall(function() cmd.forwardmove  = 0 end)
        pcall(function() cmd.sidemove     = 0 end)
        pcall(function() cmd.upmove       = 0 end)
        pcall(function() cmd.in_forward   = false end)
        pcall(function() cmd.in_back      = false end)
        pcall(function() cmd.in_moveleft  = false end)
        pcall(function() cmd.in_moveright = false end)
        pcall(function() cmd.in_jump      = false end)

        if DEBUG then
            st.frz = (st.frz or 0) + 1
            if st.frz % 40 == 0 then
                dlog("freeze fwd=", tostring(cmd.forwardmove), " side=", tostring(cmd.sidemove),
                     " jump=", tostring(cmd.in_jump))
            end
        end
    end
end

-- ============================================================ 绑键轮询
local last_want = false

local function poll_bind()
    local forced = false
    pcall(function() forced = tg_force:get() == true end)
    local want = bind_down() or forced
    if want ~= last_want then
        last_want = want
        dlog("bind want=", want)
        if not want then blocked_logged = false; st.broken = false end
    end
    if want then
        local ok, err = pcall(engage)
        if not ok then dlog("engage error: ", err) end
    else
        pcall(disengage)
    end
end

-- ============================================================ 环境探测（只跑一次）
local probed = false
local function probe_env()
    if probed then return end
    probed = true

    local keys = {}
    pcall(function()
        for k, v in pairs(entity) do
            if type(k) == "string"
                and (string.find(k, "pawn", 1, true)
                  or string.find(k, "player", 1, true)
                  or string.find(k, "local", 1, true)) then
                keys[#keys + 1] = k .. ":" .. type(v)
            end
        end
    end)
    dlog("entity keys -> ", table.concat(keys, ", "))

    for _, name in ipairs({ "local_pawn", "get_local_pawn", "get_local_player", "local_player" }) do
        local f = nil
        pcall(function() f = entity[name] end)
        if type(f) == "function" then
            local ok, a, b = pcall(f)
            dlog("entity.", name, "() ok=", ok,
                 " a=", tostring(a), " b=", tostring(b))
        else
            dlog("entity.", name, " type=", type(f))
        end
    end
end

-- ============================================================ 事件
local function reg(name, obj, fn)
    if obj == nil then
        log("事件不存在: ", name)
        return
    end
    local ok, err = pcall(function() obj:set(fn) end)
    if not ok then log("注册失败 ", name, ": ", err) end
end

reg("override_view", events.override_view, function(view)
    local ok, err = pcall(apply_view, view)
    if not ok then dlog("apply_view error: ", err) end
end)

reg("createmove", events.createmove, function(cmd)
    poll_bind()                              -- 绑键在 tick 上轮询，最可靠
    if not st.on or not st.initialized then return end
    local ok, err = pcall(update_camera, cmd)
    if not ok then dlog("update_camera error: ", err) end
end)

reg("render", events.render, function()
    st.re_calls = st.re_calls + 1
    if DEBUG and st.re_calls % 300 == 0 then
        dlog("render calls=", st.re_calls, " on=", st.on)
    end
    poll_bind()                              -- render 也在的话双保险，幂等
end)

reg("shutdown", events.shutdown, function()
    st.on = false
    st.initialized = false
    log("已卸载，视角已恢复")
end)

log("loaded | 侧边栏 Freecam 填按键名，按住开启（DEBUG=", DEBUG, "）")
