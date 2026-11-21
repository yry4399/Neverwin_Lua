-- @author LKY0112
-- @uid 1

-- HUD Misc (Neverwin 移植版) — MC Cheat HUD 合并 APHRODITE 全境封锁 HUD
-- 原作: XFL.MC HUD (Neverlose CSGO)
-- 移植: Awa Subaru
-- 合并: HUD.lua (APHRODITE 全息风格) 整合进 MC Cheat HUD
-- 总控件多选：可同时勾选 全境封锁HUD / MC HUD；未勾选时只显示总控件与游戏 HUD 组

ui.sidebar("HUD Misc", "keyboard")

local tab = ui.tab("HUD")

-- ════════════════════════════════════════════════════════════════
-- 组代理：Neverwin 的 group:visible() 不可靠，改为记录组内每个控件
-- 并按需逐控件 visible()，实现真正的组显示/隐藏
-- ════════════════════════════════════════════════════════════════
local GROUP_REAL = {}
local GROUP_CTRLS = {}

local function mk_group(parent, name)
    local g = parent:group(name)
    local list = {}
    local proxy = setmetatable({}, {
        __index = function(_, key)
            local fn = g[key]
            if type(fn) ~= 'function' then return fn end
            return function(_, ...)
                local c = fn(g, ...)
                if c ~= nil then list[#list + 1] = c end
                return c
            end
        end,
    })
    GROUP_REAL[proxy] = g
    GROUP_CTRLS[proxy] = list
    return proxy
end

-- group:visible(bool) 在 Neverwin 里不可用（visible 是字段而非方法）。
-- 正确写法是给字段赋值；同时逐控件设置 visible 作为兜底。
local function group_visible(proxy, on)
    local g = GROUP_REAL[proxy]
    if g == nil then return end
    pcall(function() g.visible = on end)
    local list = GROUP_CTRLS[proxy]
    if list ~= nil then
        for i = 1, #list do
            pcall(function() list[i]:visible(on) end)
        end
    end
end

-- ════════════════════════════════════════════════════════════════
-- 总控件：多选下拉，勾选哪个 HUD 就显示对应组（可同时勾选）
-- ════════════════════════════════════════════════════════════════
local g_master = mk_group(tab, "总控件（两者）")
local hud_select = g_master:multi_combo("启用 HUD", { "全境封锁HUD", "MC HUD" })
local layout_store = g_master:textbox("布局数据", "")
layout_store:set_visible(false)

-- ════════════════════════════════════════════════════════════════
-- 游戏 HUD（总控制，常显示，不受总控件约束）
-- ════════════════════════════════════════════════════════════════
local g_hud = mk_group(tab, "游戏 HUD（常显）")
local hide_status    = g_hud:checkbox("隐藏底部状态条", true)
local hide_weapons   = g_hud:checkbox("隐藏武器列表", true)
local hide_telemetry = g_hud:checkbox("隐藏网络/遥测面板", true)
local hide_map       = g_hud:checkbox("隐藏小地图", false)
local hide_score     = g_hud:checkbox("隐藏比分", false)
local hide_warmup    = g_hud:checkbox("隐藏热身时间", false)
local hide_killfeed  = g_hud:checkbox("隐藏击杀信息", false)
local hide_money     = g_hud:checkbox("隐藏金钱", false)
local hide_chat      = g_hud:checkbox("隐藏聊天", false)
local hud_scale      = g_hud:slider_float("HUD 等比例缩放", 0.5, 2.0, 1.0, "%.2fx")

-- ════════════════════════════════════════════════════════════════
-- MC HUD 控件组（选择 MC HUD 时显示）
-- ════════════════════════════════════════════════════════════════
local g_keys = mk_group(tab, "按键显示（MC HUD）")
local g_weap = mk_group(tab, "武器状态（MC HUD）")
local g_style = mk_group(tab, "外观（MC HUD）")

local sw_keys = g_keys:checkbox("按键显示", false)
local mc_hide = g_keys:multi_combo("隐藏项目", { "移动", "跳跃", "鼠标", "CPS" })
local cp_pressed = g_keys:color("按下颜色", color(255, 205, 253, 255))
local sl_ks = g_keys:slider_float("按键缩放", 0.5, 2.0, 1.0, "%.2f")
local sl_ka = g_keys:slider_int("按键不透明度", 20, 100, 100)

local sw_weap = g_weap:checkbox("武器状态", false)
local sl_ws = g_weap:slider_float("面板缩放", 0.5, 2.0, 1.0, "%.2f")
local sl_wa = g_weap:slider_int("面板不透明度", 20, 100, 100)
g_weap:label("分块调整")
local sl_throw_scale = g_weap:slider_float("投掷物缩放", 0.5, 3.0, 1.0, "%.2f")
local sl_throw_dx = g_weap:slider_float("投掷物 X", -200, 200, 0, "%.1f")
local sl_throw_dy = g_weap:slider_float("投掷物 Y", -200, 200, 0, "%.1f")

local cp_shadow = g_style:color("投影颜色", color(0, 0, 0, 0))
local cp_overlay = g_style:color("面板遮罩颜色", color(46, 52, 46, 46))
local sw_blur = g_style:checkbox("毛玻璃", true)
local cp_wicon = g_style:color("武器图标颜色", color(255, 255, 255, 255))
local cp_wtext = g_style:color("武器文字颜色", color(252, 254, 252, 255))

mc_hide:depends(sw_keys)
cp_pressed:depends(sw_keys)
sl_ks:depends(sw_keys)
sl_ka:depends(sw_keys)
sl_ws:depends(sw_weap)
sl_wa:depends(sw_weap)

-- ════════════════════════════════════════════════════════════════
-- 全境封锁 HUD 控件组（选择 全境封锁HUD 时显示；已移除顶栏组与游戏 HUD 组）
-- ════════════════════════════════════════════════════════════════
local g_pan = mk_group(tab, "面板（全境封锁HUD）")
local left_on   = g_pan:checkbox("武器面板", true)
local weapon_side = g_pan:combo("武器面板位置", { "左", "右" }, 0)
local weapon_scale = g_pan:slider_float("武器面板缩放", 0.5, 3.0, 2.0, "%.2fx")
-- 固定值（已移除的控件）
local WPN_Y     = 222
local WPN_ANIM  = true
-- 每类武器图标：{ 缩放, X, Y }
local WICON = {
    knife  = { 2.00, 0.0, 0.0 },
    pistol = { 1.50, -4.0, 0.0 },
    taser  = { 1.33, -2.0, 0.0 },
    smg    = { 2.00, 0.0, 0.0 },
    sniper = { 1.00, 0.0, 0.0 },
    other  = { 2.50, -3.0, 0.0 },
    util   = { 1.00, 0.0, 0.0 },
}

local g_center = mk_group(tab, "中心数据簇（全境封锁HUD）")
local center_on = g_center:checkbox("中心数据簇", true)
local center_scale = g_center:slider_float("数据簇缩放", 0.5, 2.0, 1.25, "%.2fx")
local center_anchor = g_center:combo("数据簇锚点", { "屏幕", "武器" }, 1)
-- 武器位移跟随：只影响数据簇（锚点为“屏幕”时），所以放在这里
local sway_on   = g_center:checkbox("武器位移跟随", true)
-- 固定值（已移除的控件），数据簇 X/Y 也会被拖动改写
local CL_DX, CL_DY = 106, 118
local ARMOR_SCALE, ARMOR_DX, ARMOR_DY = 0.80, 0.0, -4.8

local g_util = mk_group(tab, "道具（全境封锁HUD）")
local util_on    = g_util:checkbox("启用", true)
local util_scale = g_util:slider_float("道具框缩放", 0.5, 2.0, 2.0, "%.2fx")
local util_empty = g_util:checkbox("显示空槽位", true)
-- 固定值（已移除的控件）
local UTIL_Y = 155
local UTIL_DEBUG = false
-- 每个道具图标的固定微调：{ X, Y }（控件已移除）
local UICOFF = {
    he    = { 0.0, -6.0 },
    flash = { -1.0, -6.0 },
    smoke = { 3.0, -6.0 },
    fire  = { 2.0, -6.0 },
    inc   = { 3.0, -6.0 },
    decoy = { 0.0, -6.0 },
    zeus  = { 0.0, -6.0 },
}

local g_st = mk_group(tab, "风格（全境封锁HUD）")
local scale      = g_st:slider_float("全局缩放", 0.6, 2.0, 1.0, "%.2f")
local opacity    = g_st:slider_int("不透明度", 15, 100, 88)
local col_main   = g_st:color("主色", color(238, 242, 246))
local col_dim    = g_st:color("次色", color(150, 158, 168))
local col_accent = g_st:color("强调色", color(255, 172, 64))
local col_bg     = g_st:color("背景色", color(6, 10, 14))
local scan_on    = g_st:checkbox("扫描线", true)
local flick_on   = g_st:checkbox("闪烁", true)
local bob_on     = g_st:checkbox("浮动", true)
local glow_on    = g_st:checkbox("文字辉光", true)
local bracket_on = g_st:checkbox("四角括号", true)

-- ════════════════════════════════════════════════════════════════
-- 可见性绑定：根据总控件多选切换各组显示
-- 游戏 HUD（常显）组不参与切换，始终显示
-- ════════════════════════════════════════════════════════════════
local function sel_on(sel, name, idx)
    if sel == nil then return false end
    local ts = type(sel)
    if ts == "number" then
        local bit = 2 ^ (idx - 1)
        return math.floor(sel / bit) % 2 == 1
    end
    if ts == "string" then return sel == name end
    if ts == "table" then
        local v = sel[name]
        if v == true or v == 1 or v == name then return true end
        local v2 = sel[idx]
        if v2 == true or v2 == 1 or v2 == name then return true end
        for i = 1, #sel do
            local item = sel[i]
            if item == name or item == idx then return true end
        end
    end
    return false
end

-- idx: 1 = 全境封锁HUD, 2 = MC HUD
local function hud_selected(name, idx)
    local ok, sel = pcall(function() return hud_select:get() end)
    if not ok then return false end
    return sel_on(sel, name, idx)
end

local function update_visibility()
    local apho = hud_selected("全境封锁HUD", 1)
    local mc   = hud_selected("MC HUD", 2)
    group_visible(g_keys, mc)
    group_visible(g_weap, mc)
    group_visible(g_style, mc)
    group_visible(g_pan, apho)
    group_visible(g_center, apho)
    group_visible(g_util, apho)
    group_visible(g_st, apho)
end
hud_select:callback(update_visibility)
update_visibility()

-- ════════════════════════════════════════════════════════════════
-- 面板拖动：拖动布局开启时，左键可拖动上一帧登记过的面板矩形
-- ════════════════════════════════════════════════════════════════
local DRAG = { rects = {}, act = nil, ox = 0, oy = 0, dirty = false }
local DRAG_KEY = { weapon = { 'wx', 'wy' }, util = { 'ux', 'uy' }, cluster = { 'cx', 'cy' } }

local function drag_rect(id, x, y, w, h)
    if w == nil or h == nil or w <= 0 or h <= 0 then return end
    DRAG.rects[#DRAG.rects + 1] = { id = id, x = x, y = y, w = w, h = h }
end

local function drag_update(ed, store)
    -- 仅在作弊菜单打开时可拖动，避免游戏内开枪误拖
    local open = false
    pcall(function() open = (ui.alpha() or 0) > 0.01 end)
    if not open then
        DRAG.act = nil
        DRAG.rects = {}
        return
    end
    local mx, my = nil, nil
    local okc, cx, cy = pcall(input.cursor)
    if okc and cx ~= nil and cy ~= nil then
        mx, my = tonumber(cx) or 0, tonumber(cy) or 0
    end
    if mx == nil then
        -- 兼容返回 Vector2D 的版本
        pcall(function() local c = ui.cursor(); mx, my = c.x, c.y end)
    end
    local down = false
    pcall(function() down = input.key_down(1) == true end)
    if down and (os.clock() - (DRAG.dbg_t or 0)) > 1.0 then
        -- 临时诊断：按住左键时每秒打印一次状态
        DRAG.dbg_t = os.clock()
        print(string.format('[MC HUD] drag open=true mx=%s my=%s down=%s rects=%d',
            tostring(mx), tostring(my), tostring(down), #DRAG.rects))
    end
    if mx == nil or my == nil then
        DRAG.rects = {}
        return
    end
    if DRAG.act == nil then
        if down then
            for i = 1, #DRAG.rects do
                local r = DRAG.rects[i]
                if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                    DRAG.act, DRAG.ox, DRAG.oy = r.id, mx, my
                    break
                end
            end
        end
    else
        local dx, dy = mx - DRAG.ox, my - DRAG.oy
        DRAG.ox, DRAG.oy = mx, my
        local k = DRAG_KEY[DRAG.act]
        if k ~= nil then
            ed[k[1]] = ed[k[1]] + dx
            ed[k[2]] = ed[k[2]] + dy
            DRAG.dirty = true
        end
        if not down then DRAG.act = nil end
    end
    DRAG.rects = {}
    if DRAG.act == nil and DRAG.dirty then
        DRAG.dirty = false
        local s = string.format('%.1f,%.1f;%.1f,%.1f;%.1f,%.1f',
            ed.wx, ed.wy, ed.ux, ed.uy, ed.cx, ed.cy)
        pcall(function() store:set_value(s) end)
    end
end

-- 解析已保存的布局（空串保持默认）
local function layout_load(ed, store)
    local ok, raw = pcall(function() return tostring(store:get() or '') end)
    if not ok or raw == nil or raw == '' then return end
    local segs = {}
    for seg in string.gmatch(raw, '[^;]+') do segs[#segs + 1] = seg end
    local keys = { { 'wx', 'wy' }, { 'ux', 'uy' }, { 'cx', 'cy' } }
    for i = 1, math.min(#segs, 3) do
        local a, b = string.match(segs[i], '(-?%d+%.?%d*),(-?%d+%.?%d*)')
        if a ~= nil then
            ed[keys[i][1]] = tonumber(a) or ed[keys[i][1]]
            ed[keys[i][2]] = tonumber(b) or ed[keys[i][2]]
        end
    end
end

-- ============================================================
-- HUD 控件表（已移除顶栏控件；游戏 HUD 控件在总组里）
-- Lua 5.1 单个函数最多 60 个 upvalue，统一通过 U 表引用
-- ============================================================
local U = {
    scale = scale, opacity = opacity,
    col_main = col_main, col_dim = col_dim, col_accent = col_accent, col_bg = col_bg,
    scan_on = scan_on, flick_on = flick_on, bob_on = bob_on,
    glow_on = glow_on, bracket_on = bracket_on,
    left_on = left_on, weapon_side = weapon_side, weapon_scale = weapon_scale,
    wpn_y = WPN_Y, wpn_anim = WPN_ANIM, wicon = WICON,
    center_on = center_on, center_scale = center_scale,
    center_anchor = center_anchor,
    cl_dx = CL_DX, cl_dy = CL_DY,
    armor_scale = ARMOR_SCALE, armor_dx = ARMOR_DX, armor_dy = ARMOR_DY,
    sway_on = sway_on,
    util_on = util_on, util_scale = util_scale,
    util_y = UTIL_Y, util_debug = UTIL_DEBUG, util_empty = util_empty,
    ed = { wx = 0, wy = 0, ux = 0, uy = 0, cx = 0, cy = 0 },
    layout_store = layout_store,
    drag_update = drag_update, drag_rect = drag_rect,
    util_off = UICOFF,
    hide_status = hide_status, hide_weapons = hide_weapons,
    hide_telemetry = hide_telemetry, hide_map = hide_map, hide_score = hide_score,
    hide_warmup = hide_warmup,
    hide_killfeed = hide_killfeed,
    hide_money = hide_money, hide_chat = hide_chat,
    hud_scale = hud_scale,
}

-- ════════════════════════════════════════════════════════════════
-- APHRODITE 子系统（工厂函数：所有辅助函数与状态闭包在此作用域内，
-- 避免主块超过 Lua 5.1 的 200 局部变量上限）
-- ════════════════════════════════════════════════════════════════
local HUD_SYS = (function(U)
    local FEED_MAX, FEED_TTL = 5, 7
    local killfeed = {}
    local fps_smooth = 0
    local wpn_anim = 1
    local wpn_last_label = nil
    local last_frame_t = nil

    local function value(v)
        if type(v) == 'function' then
            local ok, r = pcall(v)
            if ok then return r end
            return nil
        end
        return v
    end

    local clock_acc = 0

    local function to_index(v, names, fallback)
        if type(v) == 'number' then return math.floor(v) end
        if type(v) == 'string' then
            for i = 1, #names do
                if names[i] == v then return i - 1 end
            end
        end
        return fallback or 0
    end

    local function T()
        if globals then
            local rt = value(globals.realtime)
            if type(rt) == 'number' then return rt end
        end
        if os and os.clock then
            local c = value(os.clock)
            if type(c) == 'number' then return c end
        end
        clock_acc = clock_acc + 0.016
        return clock_acc
    end

    local function with_a(c, mul)
        mul = mul or 1
        if mul >= 0.999 then return c end
        local r, g, b, a = c:unpack()
        return color(r, g, b, math.floor(a * mul))
    end

    local glyph_cache = {}
    local function gw(ch, size)
        local k = ch .. '|' .. tostring(size)
        local v = glyph_cache[k]
        if v == nil then
            v = render.text_size(ch, nil, size)
            glyph_cache[k] = v
        end
        return v
    end

    local function tw(s, size, track)
        track = track or 0
        local w = 0
        for i = 1, #s do
            w = w + gw(s:sub(i, i), size) + track
        end
        return w - track
    end

    local function tracked(x, y, col, s, size, track, flags)
        track = track or 0
        local cx = x
        for i = 1, #s do
            local ch = s:sub(i, i)
            render.text(cx, y, col, ch, flags, size)
            cx = cx + gw(ch, size) + track
        end
        return cx
    end

    local function icon_user(x, cy, s, col)
        render.circle(x + s * 0.5, cy - s * 0.22, s * 0.21, col, 10, 1)
        render.arc(x + s * 0.5, cy + s * 0.14, s * 0.36, 200, 340, col, 1, 12)
    end

    local function icon_diamond(x, cy, s, col)
        local r = s * 0.42
        local cx = x + s * 0.5
        render.poly_filled({ { cx, cy - r }, { cx + r, cy }, { cx, cy + r }, { cx - r, cy } }, col)
    end

    local function icon_ping(x, cy, s, col)
        local base = cy + s * 0.4
        for i = 1, 3 do
            local h = s * (0.22 * i)
            render.rect_filled(x + (i - 1) * s * 0.3, base - h, s * 0.18, h, col)
        end
    end

    local function icon_clock(x, cy, s, col)
        local cx = x + s * 0.5
        render.circle(cx, cy, s * 0.42, col, 16, 1)
        render.line(cx, cy, cx, cy - s * 0.24, col, 1)
        render.line(cx, cy, cx + s * 0.2, cy + s * 0.06, col, 1)
    end

    local function icon_cross(x, cy, s, col)
        local cx = x + s * 0.5
        render.line(cx - s * 0.4, cy, cx - s * 0.12, cy, col, 1)
        render.line(cx + s * 0.12, cy, cx + s * 0.4, cy, col, 1)
        render.line(cx, cy - s * 0.4, cx, cy - s * 0.12, col, 1)
        render.line(cx, cy + s * 0.12, cx, cy + s * 0.4, col, 1)
    end

    local function icon_fps(x, cy, s, col)
        local cx = x + s * 0.5
        render.arc(cx, cy, s * 0.42, 205, 335, col, 1, 14)
        render.line(cx, cy, cx - s * 0.14, cy - s * 0.3, col, 1)
    end

    local function icon_he(x, cy, s, col)
        render.circle_filled(x + s * 0.5, cy, s * 0.3, col, 16)
    end

    local function icon_flash(x, cy, s, col)
        local cx = x + s * 0.5
        render.triangle_filled(cx, cy - s * 0.45, cx + s * 0.24, cy + s * 0.16, cx - s * 0.24, cy + s * 0.16, col)
        render.triangle_filled(cx, cy + s * 0.45, cx + s * 0.24, cy - s * 0.16, cx - s * 0.24, cy - s * 0.16, col)
    end

    local function icon_smoke(x, cy, s, col)
        local cx = x + s * 0.5
        render.circle(cx, cy, s * 0.36, col, 14, 1)
        render.circle_filled(cx, cy, s * 0.1, col, 8)
    end

    local function icon_fire(x, cy, s, col)
        -- 火焰形（底部圆 + 上方尖角），避免燃烧瓶显示成一个纯三角形
        local cx = x + s * 0.5
        render.circle_filled(cx, cy + s * 0.16, s * 0.3, col, 16)
        render.triangle_filled(cx, cy - s * 0.46, cx + s * 0.3, cy + s * 0.18, cx - s * 0.3, cy + s * 0.18, col)
        render.circle_filled(cx + s * 0.04, cy + s * 0.1, s * 0.12, col, 10)
    end

    local function icon_decoy(x, cy, s, col)
        -- 诱饵弹：中间方块 + 两侧声波
        local cx = x + s * 0.5
        render.rect_filled(cx - s * 0.14, cy - s * 0.2, s * 0.28, s * 0.4, col, 2)
        render.circle(cx + s * 0.36, cy, s * 0.18, col, 10, 1)
        render.circle(cx - s * 0.36, cy, s * 0.18, col, 10, 1)
    end

    local function icon_zeus(x, cy, s, col)
        local cx = x + s * 0.5
        render.triangle_filled(cx + s * 0.16, cy - s * 0.45, cx - s * 0.26, cy + s * 0.04, cx + s * 0.04, cy + s * 0.04, col)
        render.triangle_filled(cx - s * 0.16, cy + s * 0.45, cx + s * 0.26, cy - s * 0.04, cx - s * 0.04, cy - s * 0.04, col)
    end

    local function brackets(x, y, w, h, len, col, t)
        render.line(x, y, x + len, y, col, t)
        render.line(x, y, x, y + len, col, t)
        render.line(x + w - len, y, x + w, y, col, t)
        render.line(x + w, y, x + w, y + len, col, t)
        render.line(x, y + h, x + len, y + h, col, t)
        render.line(x, y + h - len, x, y + h, col, t)
        render.line(x + w - len, y + h, x + w, y + h, col, t)
        render.line(x + w, y + h - len, x + w, y + h, col, t)
    end

    local function scanlines(x, y, w, h, col, step, offset)
        local yy = y - step + (offset % step)
        while yy < y + h do
            local y1 = math.max(y, yy)
            local y2 = math.min(y + h, yy + 1)
            if y2 > y1 then
                render.rect_filled(x, y1, w, y2 - y1, col)
            end
            yy = yy + step
        end
    end

    local function sep_line(x, cy, h, col)
        render.rect_filled(x, cy - h * 0.5, 1, h, col)
    end

    local function push_feed(att, vic)
        killfeed[#killfeed + 1] = { att = att, vic = vic, t = T() }
        while #killfeed > FEED_MAX do
            table.remove(killfeed, 1)
        end
    end

    events.on('player_death', function(e)
        pcall(function()
            local vic = e:get_pawn('userid')
            local att = e:get_pawn('attacker')
            local vn = (vic and vic:name()) or '?'
            local an = (att and att:name()) or '?'
            if an == '' then an = '?' end
            if vn == '' then vn = '?' end
            push_feed(an, vn)
        end)
    end)

    -- ── 检视判定：m_bInspectPending 在这个版本恒为 false（实测），改用检视按键 ──
    -- 先在常见按键里找 binding 含 lookatweapon 的那个，找不到就用默认 F
    local inspect_key = nil
    local function inspect_down()
        if inspect_key == nil then
            inspect_key = 'f'
            pcall(function()
                local cands = { 'f', 'mouse4', 'mouse5', 'v', 'x', 'c', 'z', 't', 'g', 'h', 'b', 'n',
                                'q', 'e', 'r', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
                                'space', 'shift', 'ctrl', 'alt' }
                for i = 1, #cands do
                    local btn = input.buttons[cands[i]]
                    if btn ~= nil then
                        local ok, bd = pcall(function() return btn.binding end)
                        if ok and type(bd) == 'string' and bd:find('lookatweapon', 1, true) then
                            inspect_key = cands[i]
                            return
                        end
                    end
                end
            end)
        end
        local ok, btn = pcall(function() return input.buttons[inspect_key] end)
        if not ok or btn == nil then return false end
        local okd, d = pcall(function() return btn.down end)
        return (okd and d == true)
    end

    -- ── 武器锚点：把视图模型（枪）投到屏幕上，作为数据簇的真实锚点 ──
    -- 路径：当前武器 → m_hViewmodelAttachment(handle) → entity.handle() → :origin() → world_to_screen
    local anchor_px, anchor_py = nil, nil
    local function weapon_anchor(pawn, k)
        local wpn = nil
        pcall(function() wpn = pawn:weapon() end)
        if wpn == nil then return nil end
        local hh = nil
        pcall(function() hh = wpn:get('C_EconEntity', 'm_hViewmodelAttachment', 'handle') end)
        if hh == nil then return nil end
        local vm = nil
        pcall(function() vm = entity.handle(hh) end)
        if vm == nil then return nil end
        local pos = nil
        pcall(function() pos = vm:origin() end)
        if pos == nil then return nil end
        local sp = nil
        pcall(function() sp = render.world_to_screen(pos) end)
        if sp == nil then return nil end
        local x, y = nil, nil
        pcall(function() x, y = sp.x, sp.y end)
        if x == nil or y == nil then return nil end
        if anchor_px == nil then anchor_px, anchor_py = x, y end
        local f = k or 0.35
        anchor_px = anchor_px + (x - anchor_px) * f
        anchor_py = anchor_py + (y - anchor_py) * f
        return anchor_px, anchor_py
    end

    local sway_sx, sway_sy = 0, 0
    local insp_on, insp_t0 = false, 0
    -- 诊断用：统计一秒内的峰值（瞬时采样经常抓到静止帧）
    local dbg_peak, dbg_insp_seen = 0, false
    local function weapon_sway(pawn, sc, t)
        local tx, ty = 0, 0
        -- 速度分量：velocity 需要场景节点，全部 pcall，失败就当 0
        local okv, vel = pcall(function() return pawn:velocity() end)
        if okv and vel then
            local vx, vy = 0, 0
            pcall(function() vx = vel.x or 0; vy = vel.y or 0 end)
            local yaw = nil
            local oka, ang = pcall(function() return engine.view_angles() end)
            if oka and ang then
                local oku, _, y_ = pcall(function() return ang:unpack() end)
                if oku then yaw = y_ end
            end
            if yaw == nil then
                local oke, ea = pcall(function() return pawn:eye_angles() end)
                if oke and ea then
                    local oku2, _, y2 = pcall(function() return ea:unpack() end)
                    if oku2 then yaw = y2 end
                end
            end
            local lateral
            if yaw ~= nil then
                local rad = math.rad(yaw)
                lateral = vx * math.cos(rad) + vy * math.sin(rad)
            else
                -- 拿不到视角时用绝对速度兜底，方向取 x 分量
                lateral = math.sqrt(vx * vx + vy * vy)
                if vx < 0 then lateral = -lateral end
            end
            tx = tx - lateral * 0.05 * sc
        end
        -- 后坐力（view punch）
        local okp, punch = pcall(function() return pawn:aim_punch() end)
        if okp and punch then
            local oku, pitch, pun_yaw = pcall(function() return punch:unpack() end)
            if oku then
                tx = tx + (pun_yaw or 0) * 5 * sc
                ty = ty + (pitch or 0) * 5 * sc
            end
        end
        -- 检视武器：枪在屏幕上划动时，数据簇跟着一起动
        local now = t or 0
        if inspect_down() then
            if not insp_on then insp_on, insp_t0 = true, now end
        elseif insp_on and (now - insp_t0) > 2.4 then
            insp_on = false
        end
        if insp_on then
            -- 2.4s 一趟：先向左下带出，再回落
            local p = math.min(math.max((now - insp_t0) / 2.4, 0), 1)
            local k = math.sin(p * math.pi)
            tx = tx - k * 26 * sc
            ty = ty + k * 9 * sc
        end
        sway_sx = sway_sx + (tx - sway_sx) * 0.2
        sway_sy = sway_sy + (ty - sway_sy) * 0.2
        if insp_on then dbg_insp_seen = true end
        local mag = math.abs(sway_sx) + math.abs(sway_sy)
        if mag > dbg_peak then dbg_peak = mag end
        return sway_sx, sway_sy
    end

    -- ── 投掷物数量来源：CPlayer_WeaponServices::m_iAmmo[32] ──
    -- 该版本 entity:__index 只查实体自身类的字段（不向上查基类），所以
    -- pawn.m_pWeaponServices / w.m_iClip1 这类继承字段读出来是 nil；
    -- 必须用 :get("声明该字段的类", 字段, 类型) 才拿得到。
    -- m_iAmmo 是 uint16[32]，:get 不支持数组，只能先取 services 指针再按偏移读。
    local FFI = nil
    pcall(function() FFI = rawget(_G, 'ffi') end)
    if FFI == nil then pcall(function() FFI = require('ffi') end) end

    local AMMO_OFF = 104  -- CPlayer_WeaponServices::m_iAmmo（uint16[32]）
    local AMMO_OFF_CACHE = nil
    -- CS2 的 AmmoIndex_t 与 CS:GO 相差 +2（实测闪光弹在 14 号槽），
    -- 每个类型给出 [CS2 索引, CS:GO 索引] 两个候选，运行时取第一个非 0 的。
    local GRENADE_AMMO_IDX = {
        he    = { 13, 11 },
        flash = { 14, 12 },
        smoke = { 15, 13 },
        fire  = { 16, 14 },
        inc   = { 16, 14 },
        decoy = { 17 },
    }

    local function ammo_off()
        if AMMO_OFF_CACHE ~= nil then return AMMO_OFF_CACHE end
        local off = nil
        pcall(function()
            local f = schema.find('CPlayer_WeaponServices', 'm_iAmmo')
            if type(f) == 'number' and f >= 64 and f <= 512 then off = math.floor(f) end
        end)
        AMMO_OFF_CACHE = off or AMMO_OFF
        return AMMO_OFF_CACHE
    end

    local function to_addr(p)
        if p == nil or FFI == nil then return nil end
        local ok, n = pcall(function() return tonumber(FFI.cast('uintptr_t', p)) end)
        if ok and type(n) == 'number' then return n end
        local ok2, s = pcall(function() return tostring(FFI.cast('uintptr_t', p)) end)
        if ok2 and type(s) == 'string' then
            local h = s:match('0x(%x+)')
            if h then return tonumber(h, 16) end
            local d = tonumber(s)
            if d then return d end
        end
        return nil
    end

    local function read_ammo_slots(pawn)
        if FFI == nil or pawn == nil then return nil end
        local okws, p = pcall(function()
            return pawn:get('C_BasePlayerPawn', 'm_pWeaponServices', 'ptr')
        end)
        if not okws then return nil end
        local base = to_addr(p)
        if base == nil or base < 0x10000 or base > 0x7FF000000000 then return nil end
        local slots = {}
        local ok = pcall(function()
            local arr = FFI.cast('uint16_t*', base + ammo_off())
            for i = 0, 31 do slots[i] = tonumber(arr[i]) end
        end)
        if not ok then return nil end
        for i = 0, 31 do
            local v = slots[i]
            if type(v) ~= 'number' or v < 0 or v > 4096 then return nil end
        end
        return slots
    end

    -- 优先读 vdata 的 m_nPrimaryAmmoType（数据驱动），失败再用固定表
    local function vdata_ammo_index(ent)
        if ent == nil then return nil end
        local okv, vd = pcall(function() return ent:vdata() end)
        if not okv or vd == nil then return nil end
        local tries = {
            function() return vd.m_nPrimaryAmmoType end,
            function() return vd:get('CBasePlayerWeaponVData', 'm_nPrimaryAmmoType', 'int') end,
            function() return vd:get('CBasePlayerWeaponVData', 'm_nPrimaryAmmoType', 'byte') end,
        }
        for i = 1, #tries do
            local ok, iv = pcall(tries[i])
            if ok and type(iv) == 'number' and iv >= 0 and iv <= 31 then
                return math.floor(iv)
            end
        end
        return nil
    end

    -- ── 调试输出到控制台：武器实体 + m_iAmmo 全部非零槽位 ──
    local dbg_next_t = 0
    local function dump_debug(pawn)
        local out = {}
        out[#out + 1] = '[MC HUD DEBUG] ===== weapons ====='
        local okw, list = pcall(function() return pawn:weapons() end)
        if okw and list ~= nil then
            local cnt = 0
            local okc, c = pcall(function() return #list end)
            if okc and type(c) == 'number' then cnt = c end
            local items = {}
            if cnt > 0 then
                for i = 1, cnt do items[#items + 1] = list[i] end
            else
                for _, v in pairs(list) do items[#items + 1] = v end
            end
            for i = 1, #items do
                local w = items[i]
                if type(w) == 'number' then
                    local oke, e = pcall(entity.from_handle, w)
                    if oke then w = e end
                end
                if w ~= nil and type(w) ~= 'number' then
                    local nm, cl, cl_n, rs = '?', '?', '?', '?'
                    local winf = nil
                    pcall(function()
                        local inf = w:weapon_info()
                        if inf then
                            winf = inf
                            nm = tostring(inf.name)
                            cl_n = tostring(inf.clip)
                            rs = tostring(inf.reserve)
                        end
                    end)
                    pcall(function() cl = tostring(w:class_name()) end)
                    local r0 = '?'
                    pcall(function() r0 = tostring(w.m_pReserveAmmo[0]) end)
                    local gclip = '?'
                    pcall(function() gclip = tostring(w:get("C_BasePlayerWeapon", "m_iClip1", "int")) end)
                    local gclip2 = '?'
                    pcall(function() gclip2 = tostring(w:get("C_BasePlayerWeapon", "m_iClip2", "int")) end)
                    local gres = '?'
                    pcall(function() gres = tostring(w.m_pReserveAmmo[0]) end)
                    local m1 = '?'
                    pcall(function() m1 = tostring(w.m_iClip1) end)
                    out[#out + 1] = '  ' .. nm .. ' [' .. cl .. '] clip=' .. cl_n
                        .. ' res=' .. rs .. ' reserve0=' .. r0
                        .. ' getClip1=' .. gclip .. ' getClip2=' .. gclip2
                        .. ' getRes=' .. gres .. ' m_iClip1=' .. m1
                        .. ' vdIdx=' .. tostring(vdata_ammo_index(w))
                        .. ' type=' .. tostring(winf and winf.type) .. ' def=' .. tostring(winf and winf.def)
                    if i == 1 then
                        pcall(function()
                            local inf = w:weapon_info()
                            if inf then
                                local ks = {}
                                for k in pairs(inf) do ks[#ks + 1] = tostring(k) end
                                table.sort(ks)
                                out[#out + 1] = '  weapon_info keys: ' .. table.concat(ks, ',')
                            end
                        end)
                    end
                end
            end
        else
            out[#out + 1] = '  weapons() failed: ' .. tostring(list)
        end
        local okws, wsv = pcall(function()
            return pawn:get("C_BasePlayerPawn", "m_pWeaponServices", "ptr")
        end)
        out[#out + 1] = '  ffi=' .. tostring(FFI ~= nil)
            .. ' wsGet ok=' .. tostring(okws) .. ' type=' .. type(wsv) .. ' val=' .. tostring(wsv)
        local okd, wsd = pcall(function() return pawn.m_pWeaponServices end)
        out[#out + 1] = '  pawn.m_pWeaponServices direct ok=' .. tostring(okd)
            .. ' type=' .. type(wsd) .. ' val=' .. tostring(wsd)
        local okhh, hh = pcall(function() return pawn.m_iHealth end)
        out[#out + 1] = '  pawn.m_iHealth direct=' .. tostring(hh) .. ' ok=' .. tostring(okhh)
        local okpg, pg = pcall(function()
            return pawn:get("C_CSPlayerPawn", "m_nPrevGrenadeAmmoCount", "int")
        end)
        out[#out + 1] = '  m_nPrevGrenadeAmmoCount=' .. tostring(pg) .. ' ok=' .. tostring(okpg)
        out[#out + 1] = '  ammoOff=' .. tostring(ammo_off())
        local slots = read_ammo_slots(pawn)
        if slots ~= nil then
            local s = {}
            for i = 0, 31 do
                if slots[i] ~= 0 then s[#s + 1] = i .. '=' .. tostring(slots[i]) end
            end
            out[#out + 1] = '  m_iAmmo(ffi): ' .. table.concat(s, ' ')
        else
            out[#out + 1] = '  m_iAmmo(ffi): N/A'
        end
        print(table.concat(out, '\n'))
    end

    local function tally_weapon(counts, w, dbg, pawn)
        local info = nil
        local ent = nil
        local tw_ = type(w)
        if tw_ == 'table' or tw_ == 'userdata' then
            ent = w
        elseif tw_ == 'number' then
            local ok, e = pcall(function() return entity.from_handle(w) end)
            if ok then ent = e end
        end
        if ent then
            local ok, r = pcall(function() return ent:weapon_info() end)
            if ok then info = r end
        end
        -- 同时收集 internal name 和 class name，做小写匹配
        local name = nil
        if info and info.name then name = tostring(info.name) end
        local cls = nil
        if ent then
            local ok, cn = pcall(function() return ent:class_name() end)
            if ok and cn then cls = tostring(cn) end
        end
        if dbg and #dbg < 8 then
            dbg[#dbg + 1] = tw_ .. ' name=' .. tostring(name) .. ' cls=' .. tostring(cls)
                .. ' clip=' .. tostring(info and info.clip)
                .. ' res=' .. tostring(info and info.reserve)
        end
        if not name and not cls then return end
        local n = string.lower(name or '')
        local c = string.lower(cls or '')
        local key = n .. '|' .. c

        -- 判定是否为投掷物类型（手雷/燃烧瓶/烟雾/闪光）
        local is_grenade = key:find('hegrenade') or key:find('he_grenade')
            or key:find('flash') or key:find('smoke')
            or key:find('molotov') or key:find('incendiary') or key:find('decoy')

        -- 投掷物数量：CS2 里同类投掷物只生成一个武器实体，实体上的 m_iClip1 恒为 -1，
        -- 真正的持有数量在玩家的 CPlayer_WeaponServices::m_iAmmo[] 里。
        local res_n = (info and type(info.reserve) == 'number' and info.reserve or 0)
        local clip_n = (info and type(info.clip) == 'number') and info.clip or 0
        local ammo_idx, ammo_hit, ammo_raw = nil, false, nil
        local total
        if is_grenade then
            local kind = 'he'
            if key:find('flash') then kind = 'flash'
            elseif key:find('smoke') then kind = 'smoke'
            elseif key:find('molotov') then kind = 'fire'
            elseif key:find('incendiary') then kind = 'inc'
            elseif key:find('decoy') then kind = 'decoy' end
            local slots = read_ammo_slots(pawn)
            if slots ~= nil then
                local cands = GRENADE_AMMO_IDX[kind] or {}
                local cv = nil
                local vd_idx = vdata_ammo_index(ent)
                if vd_idx and type(slots[vd_idx]) == 'number' and slots[vd_idx] > 0 then
                    cv, ammo_idx = slots[vd_idx], vd_idx
                end
                if cv == nil then
                    for i = 1, #cands do
                        local v = slots[cands[i]]
                        if type(v) == 'number' and v > 0 then
                            cv, ammo_idx = v, cands[i]
                            break
                        end
                    end
                end
                if type(cv) == 'number' then
                    ammo_raw = cv
                    clip_n = cv
                    res_n = 0
                    ammo_hit = true
                end
            end
            if not ammo_hit then
                -- 兜底：实体上的 clip（组合数未知，至少保持旧行为显示 1）
                local okg, gv = pcall(function()
                    return ent:get("C_BasePlayerWeapon", "m_iClip1", "int")
                end)
                if okg and type(gv) == 'number' and gv > 0 then clip_n = gv end
                if clip_n <= 0 then clip_n = 1 end
                res_n = 0
            end
            total = clip_n
            if total > 5 then total = 5 end
            if total < 0 then total = 0 end
        else
            total = ((clip_n > 0) and clip_n or 1) + res_n
            if total > 5 then total = 5 end
            if total < 1 then total = 1 end
        end
        if dbg and #dbg < 12 and is_grenade then
            dbg[#dbg + 1] = 'total=' .. tostring(total) .. ' clip_n=' .. tostring(clip_n)
                .. ' ammoIdx=' .. tostring(ammo_idx) .. ' raw=' .. tostring(ammo_raw)
                .. ' ammo=' .. tostring(ammo_hit)
        end

        if key:find('hegrenade') or key:find('he_grenade') or key:find('high explosive') then
            counts.he = counts.he + total
        elseif key:find('flash') then
            counts.flash = counts.flash + total
        elseif key:find('smoke') then
            counts.smoke = counts.smoke + total
        elseif key:find('molotov') then
            counts.fire = counts.fire + total
        elseif key:find('incendiary') then
            counts.inc = counts.inc + total
        elseif key:find('decoy') then
            counts.decoy = counts.decoy + total
        elseif key:find('taser') or key:find('zeus') then
            counts.zeus = counts.zeus + 1
        end
    end

    -- ── 游戏原版 HUD 隐藏（Panorama 注入）+ 等比例缩放 ──
    local HUD_STATUS_IDS = { 'jsHudHealthArmorAmmoMore' }
    local HUD_WEAPON_IDS = { 'HudBottomRight' }
    local HUD_TELEMETRY_IDS = {
        'fps_row', 'net_numbers_basic', 'net_numbers_detailed',
        'frametime_graph', 'net_quality_in_graph', 'net_quality_out_graph',
        'cq_graph', 'problems_label', 'trueview_row',
    }
    local HUD_MAP_IDS = { 'HudRadar', 'Radar' }
    local HUD_SCORE_IDS = { 'HudTopCenter', 'HudTeamCounter' }
    -- 热身时间（顶部居中的「热身时间」横幅/倒计时）
    local HUD_WARMUP_IDS = {
        'Warmup', 'warmup', 'HudWarmup', 'HudWarmupPanel', 'WarmupPanel',
        'WarmupTimer', 'warmup_timer', 'warmup_timer_container',
        'WarmupStatus', 'HudWarmupStatus', 'HudWarmupTimer',
    }
    local HUD_KILL_IDS = { 'HudDeathNotice', 'DeathNotice', 'HudKillFeed' }
    local HUD_MONEY_IDS = { 'HudMoney', 'hudmoney', 'BuyMenuMoney', 'buymenumoney' }
    local HUD_CHAT_IDS = { 'ChatPanel', 'HudChat', 'ChatContainer', 'HudChatPanel', 'chat', 'Chat' }
    local HUD_KEEP_BASE = { 'HudTopLeft' }

    local hud_hidden = false
    local chat_hidden_by_us = false
    local hud_tick = 0
    local hud_sig = nil
    local hud_scale_sig = nil
    local hud_status = '待命'

    local function collect_ids()
        local t = {}
        if U.hide_status:get() then
            for i = 1, #HUD_STATUS_IDS do t[#t + 1] = HUD_STATUS_IDS[i] end
        end
        if U.hide_weapons:get() then
            for i = 1, #HUD_WEAPON_IDS do t[#t + 1] = HUD_WEAPON_IDS[i] end
        end
        if U.hide_telemetry:get() then
            for i = 1, #HUD_TELEMETRY_IDS do t[#t + 1] = HUD_TELEMETRY_IDS[i] end
        end
        if U.hide_map:get() then
            for i = 1, #HUD_MAP_IDS do t[#t + 1] = HUD_MAP_IDS[i] end
        end
        if U.hide_score:get() then
            for i = 1, #HUD_SCORE_IDS do t[#t + 1] = HUD_SCORE_IDS[i] end
        end
        if U.hide_warmup:get() then
            for i = 1, #HUD_WARMUP_IDS do t[#t + 1] = HUD_WARMUP_IDS[i] end
        end
        if U.hide_killfeed:get() then
            for i = 1, #HUD_KILL_IDS do t[#t + 1] = HUD_KILL_IDS[i] end
        end
        if U.hide_money:get() then
            for i = 1, #HUD_MONEY_IDS do t[#t + 1] = HUD_MONEY_IDS[i] end
        end
        if U.hide_chat:get() then
            for i = 1, #HUD_CHAT_IDS do t[#t + 1] = HUD_CHAT_IDS[i] end
        end
        return t
    end

    local function quote_list(t)
        local p = {}
        for i = 1, #t do p[i] = '"' .. t[i] .. '"' end
        return table.concat(p, ',')
    end

    local function set_hud_hidden(on)
        if type(panorama) ~= 'table' or type(panorama.run) ~= 'function' then
            hud_status = 'panorama 不可用: ' .. type(panorama)
            return
        end
        local vis = on and 'collapse' or 'visible'
        local parts = {}
        parts[#parts + 1] = '(function(){var root=$.GetContextPanel();'
        local ids
        local chat_fix = nil
        if on then
            ids = collect_ids()
            if U.hide_chat:get() then chat_hidden_by_us = true end
        else
            ids = {}
            for i = 1, #HUD_STATUS_IDS do ids[#ids + 1] = HUD_STATUS_IDS[i] end
            for i = 1, #HUD_WEAPON_IDS do ids[#ids + 1] = HUD_WEAPON_IDS[i] end
            for i = 1, #HUD_TELEMETRY_IDS do ids[#ids + 1] = HUD_TELEMETRY_IDS[i] end
            for i = 1, #HUD_MAP_IDS do ids[#ids + 1] = HUD_MAP_IDS[i] end
            for i = 1, #HUD_SCORE_IDS do ids[#ids + 1] = HUD_SCORE_IDS[i] end
            for i = 1, #HUD_WARMUP_IDS do ids[#ids + 1] = HUD_WARMUP_IDS[i] end
            for i = 1, #HUD_KILL_IDS do ids[#ids + 1] = HUD_KILL_IDS[i] end
            for i = 1, #HUD_MONEY_IDS do ids[#ids + 1] = HUD_MONEY_IDS[i] end
            -- 聊天面板只有确实被我们收起来过才恢复；且只清空内联样式而不强制 visible，
            -- 否则加载脚本时会把聊天输入框顶出来（未勾选“隐藏聊天”时尤其明显）
            if chat_hidden_by_us then
                chat_fix = {}
                for i = 1, #HUD_CHAT_IDS do chat_fix[#chat_fix + 1] = HUD_CHAT_IDS[i] end
                chat_hidden_by_us = false
            end
        end
        local keep = {}
        for i = 1, #HUD_KEEP_BASE do keep[#keep + 1] = HUD_KEEP_BASE[i] end
        if not U.hide_map:get() then
            for i = 1, #HUD_MAP_IDS do keep[#keep + 1] = HUD_MAP_IDS[i] end
        end
        if not U.hide_score:get() then
            for i = 1, #HUD_SCORE_IDS do keep[#keep + 1] = HUD_SCORE_IDS[i] end
        end
        parts[#parts + 1] = 'var ids=[' .. quote_list(ids) .. '];'
        parts[#parts + 1] = 'for(var i=0;i<ids.length;i++){var p=root.FindChildTraverse(ids[i]);'
        parts[#parts + 1] = 'if(p)p.style.visibility="' .. vis .. '";}'
        if chat_fix ~= nil then
            parts[#parts + 1] = 'var cids=[' .. quote_list(chat_fix) .. '];'
            parts[#parts + 1] = 'for(var i=0;i<cids.length;i++){var p=root.FindChildTraverse(cids[i]);'
            parts[#parts + 1] = 'if(p)p.style.visibility="";}'
        end
        -- 金钱：连同旁边的购物车/商店按钮整行隐藏
        -- 聊天：只隐藏以 "[T]" 这类前缀开头的接收消息文本，不碰输入框
        local mvis = U.hide_money:get() and 'collapse' or 'visible'
        local cvis = U.hide_chat:get() and 'collapse' or 'visible'
        parts[#parts + 1] = 'function killmoney(el,v){el.style.visibility=v;'
        parts[#parts + 1] = 'var par=el.GetParent?el.GetParent():null;if(!par||par===root)return;'
        parts[#parts + 1] = 'var sb=par.Children?par.Children():[];var hit=0;'
        parts[#parts + 1] = 'for(var j=0;j<sb.length;j++){var sid=String(sb[j].id||"");'
        parts[#parts + 1] = 'if(/shop|cart|store|basket/i.test(sid)){sb[j].style.visibility=v;hit++;}}'
        parts[#parts + 1] = 'if(hit===0&&sb.length<=3&&!/^(buymenu|hud|root)$/i.test(String(par.id||"")))'
        parts[#parts + 1] = '{par.style.visibility=v;}}'
        parts[#parts + 1] = 'function walkmoney(p,d,v){if(d>16)return;var ks=(p.Children?p.Children():[]);'
        parts[#parts + 1] = 'for(var i=0;i<ks.length;i++){var k=ks[i];'
        parts[#parts + 1] = 'if(/money/i.test(String(k.id||"")))killmoney(k,v);'
        parts[#parts + 1] = 'walkmoney(k,d+1,v);}}'
        parts[#parts + 1] = 'walkmoney(root,0,"' .. mvis .. '");'
        parts[#parts + 1] = 'function walkchat(p,d,inc,v){if(d>16)return;'
        parts[#parts + 1] = 'var pid=String(p.id||"");var pt=String(p.paneltype||"");'
        parts[#parts + 1] = 'var c=inc||(/chat/i.test(pid)&&!/input/i.test(pid)&&pt!=="TextEntry");'
        parts[#parts + 1] = 'var ks=(p.Children?p.Children():[]);'
        parts[#parts + 1] = 'for(var i=0;i<ks.length;i++){var k=ks[i];var t=null;try{t=k.text;}catch(e){}'
        parts[#parts + 1] = 'var okstr=(typeof t==="string"&&/^\\s*\\[/.test(t));'
        parts[#parts + 1] = 'if(v==="visible"){if(okstr){k.style.visibility=v;}}'
        parts[#parts + 1] = 'else if(c&&okstr&&t.indexOf(": ")>=0){k.style.visibility=v;}'
        parts[#parts + 1] = 'walkchat(k,d+1,c,v);}}'
        parts[#parts + 1] = 'walkchat(root,0,false,"' .. cvis .. '");'
        -- 热身时间：按面板文本匹配（各版本 id 不一致，文本更稳），仅在开启该选项时执行
        if U.hide_warmup:get() then
            local wvis = on and 'collapse' or 'visible'
            parts[#parts + 1] = 'function walkwarm(p,d,par,v){if(!p||d>20)return;'
            parts[#parts + 1] = 'var pid=String(p.id||"");var pt=String(p.paneltype||"");var tx="";'
            parts[#parts + 1] = 'try{tx=String(p.text||"");}catch(e){}'
            parts[#parts + 1] = 'var hit=(tx!==""&&/(热身|\\bwarm)/i.test(tx))||/warmup/i.test(pid);'
            parts[#parts + 1] = 'if(hit&&pt!=="TextEntry"){try{p.style.visibility=v;}catch(e){}'
            parts[#parts + 1] = 'try{if(!root.__warmRep){root.__warmRep=1;'
            parts[#parts + 1] = '$.Msg("[MC HUD] warmup panel: "+pid+" ["+pt+"] text="+tx.substr(0,24));}}catch(e){}'
            parts[#parts + 1] = 'if(par){var pc=(par.Children?par.Children():[]);'
            parts[#parts + 1] = 'if(pc.length<=2){try{par.style.visibility=v;}catch(e){}}}}'
            parts[#parts + 1] = 'var ks=(p.Children?p.Children():[]);'
            parts[#parts + 1] = 'for(var i=0;i<ks.length;i++)walkwarm(ks[i],d+1,p,v);}'
            parts[#parts + 1] = 'walkwarm(root,0,null,"' .. wvis .. '");'
        end
        if U.hide_telemetry:get() then
            parts[#parts + 1] = 'var anc=root.FindChildTraverse("fps_row");'
            parts[#parts + 1] = 'if(anc&&anc.GetParent){var par=anc.GetParent();'
            parts[#parts + 1] = 'if(par&&par!==root){par.style.visibility="' .. vis .. '";}}'
        end
        parts[#parts + 1] = 'var keep=[' .. quote_list(keep) .. '];'
        parts[#parts + 1] = 'for(var m=0;m<keep.length;m++){var q=root.FindChildTraverse(keep[m]);'
        parts[#parts + 1] = 'if(q)q.style.visibility="visible";}'
        if not on then
            parts[#parts + 1] = 'function fixp(p,d){if(d>4)return;var ks=(p.Children?p.Children():[]);'
            parts[#parts + 1] = 'for(var i=0;i<ks.length;i++){var k=ks[i];var id=k.id||"";'
            parts[#parts + 1] = 'if(/^player[0-9]+$/i.test(id)){k.style.visibility="visible";}'
            parts[#parts + 1] = 'fixp(k,d+1);}}fixp(root,0);'
        end
        parts[#parts + 1] = '})();'
        local js = table.concat(parts)
        local ok, err = pcall(function() panorama.run(js) end)
        if ok then
            hud_status = '已应用'
        else
            hud_status = '执行失败: ' .. tostring(err)
        end
    end

    local function apply_hud_scale(s)
        if type(panorama) ~= 'table' or type(panorama.run) ~= 'function' then
            return
        end
        local s_num = tonumber(s) or 1
        if s_num < 0.5 then s_num = 0.5 end
        if s_num > 2.0 then s_num = 2.0 end
        -- 尝试多种方式找到 HUD 根面板：CSGOHud / Hud / 上下文面板 / 根面板
        -- 同时尝试多种缩放写法（transform / scaleX+scaleY / scale）
        local js = '(function()'
            .. 'var ctx=$.GetContextPanel();'
            .. 'var root=null;'
            .. 'var ids=["CSGOHud","Hud","hud"];'
            .. 'for(var i=0;i<ids.length&&ctx;i++){'
            .. '  var found=ctx.FindChildTraverse(ids[i]);'
            .. '  if(found){root=found;break;}'
            .. '}'
            .. 'if(!root)root=ctx;'
            .. 'if(!root&&$.GetRootPanel)root=$.GetRootPanel();'
            .. 'if(!root)return;'
            .. 'var s=' .. s_num .. ';'
            .. 'try{root.style.transform="scale("+s+")";}catch(e){}'
            .. 'try{root.style.scaleX=s;root.style.scaleY=s;}catch(e){}'
            .. 'try{root.style.scale=s;}catch(e){}'
            .. 'try{root.style.transformOrigin="0% 0%";}catch(e){}'
            .. 'try{root.style.transformBox="view-box";}catch(e){}'
            .. '})();'
        pcall(panorama.run, js)
    end

    local function update_game_hud()
        local any_hide = U.hide_status:get() or U.hide_weapons:get() or U.hide_telemetry:get()
            or U.hide_map:get() or U.hide_score:get() or U.hide_killfeed:get()
            or U.hide_money:get() or U.hide_chat:get() or U.hide_warmup:get()
        local sig = (U.hide_status:get() and '1' or '0')
            .. (U.hide_weapons:get() and '1' or '0')
            .. (U.hide_telemetry:get() and '1' or '0')
            .. (U.hide_map:get() and '1' or '0')
            .. (U.hide_score:get() and '1' or '0')
            .. (U.hide_killfeed:get() and '1' or '0')
            .. (U.hide_money:get() and '1' or '0')
            .. (U.hide_chat:get() and '1' or '0')
            .. (U.hide_warmup:get() and '1' or '0')
        if sig ~= hud_sig then
            hud_sig = sig
            set_hud_hidden(false)
            hud_hidden = any_hide
            if any_hide then set_hud_hidden(true) end
            hud_tick = 0
        else
            hud_tick = hud_tick + 1
            if hud_hidden and hud_tick % 90 == 0 then set_hud_hidden(true) end
        end
        local sc = U.hud_scale:get()
        local sc_sig = tostring(sc)
        if sc_sig ~= hud_scale_sig then
            hud_scale_sig = sc_sig
            apply_hud_scale(sc)
        elseif hud_tick % 600 == 0 then
            -- 面板可能重建，定时重新应用缩放
            apply_hud_scale(sc)
        end
    end

    local str_w_cache = {}
    local str_w_count = 0

    local function text_size(s, _flags, size)
        local key = tostring(size) .. '|' .. tostring(s)
        local v = str_w_cache[key]
        if v == nil then
            v = render.text_size(s, nil, size)
            str_w_count = str_w_count + 1
            if str_w_count > 800 then
                str_w_cache = {}
                str_w_count = 0
            end
            str_w_cache[key] = v
        end
        return v
    end

    local M = {
        with_a = with_a, tw = tw, tracked = tracked,
        brackets = brackets, scanlines = scanlines, sep_line = sep_line,
        value = value, T = T, text_size = text_size,
        weapon_sway = weapon_sway, tally_weapon = tally_weapon,
        icon_user = icon_user, icon_diamond = icon_diamond, icon_ping = icon_ping,
        icon_clock = icon_clock, icon_cross = icon_cross, icon_fps = icon_fps,
        icon_he = icon_he, icon_flash = icon_flash, icon_smoke = icon_smoke,
        icon_fire = icon_fire, icon_zeus = icon_zeus,
    }

    -- ── 武器名映射（internal name → 可读中文名）────────────────
    local WNAME = {
        ak47 = 'AK-47', aug = 'AUG', famas = '法玛斯', galilar = '加利尔 AR',
        m4a1 = 'M4A4', m4a1_silencer = 'M4A1 消音', sg556 = 'SG 553',
        awp = 'AWP', g3sg1 = 'G3SG1', scar20 = 'SCAR-20', ssg08 = 'SSG 08',
        mac10 = 'MAC-10', mp5sd = 'MP5-SD', mp7 = 'MP7', mp9 = 'MP9',
        bizon = 'PP-野牛', p90 = 'P90', ump45 = 'UMP-45',
        m249 = 'M249', negev = '内格夫', nova = '新星', sawedoff = '截短霰弹',
        xm1014 = 'XM1014', mag7 = 'MAG-7',
        deagle = '沙鹰', elite = '双持贝瑞塔', fiveseven = 'FN57', glock = '格洛克',
        p250 = 'P250', tec9 = 'Tec-9', usp_silencer = 'USP 消音', cz75a = 'CZ75',
        revolver = 'R8 左轮', hkp2000 = 'P2000',
        hegrenade = '手雷', flashbang = '闪光', smokegrenade = '烟雾',
        decoygrenade = '诱饵', molotovgrenade = '燃烧瓶', incgrenade = '燃烧弹',
        tagrenade = '探测雷', c4 = 'C4', taser = '电击枪', zeus = '电击枪',
        knife = '匕首', knife_t = 'T 匕首', knife_ct = 'CT 匕首',
        knife_karambit = '爪子刀', knife_m9_bayonet = 'M9 刺刀', knife_bayonet = '刺刀',
        knife_flip = '折刀', knife_gut = '穿肠刀', knife_butterfly = '蝴蝶刀',
        knife_falchion = '弯刀', knife_huntsman = '猎杀者', knife_navaja = '折叠刀',
        knife_stiletto = '短剑', knife_talon = '鹰爪刀', knife_ursus = '熊刀',
        knife_skeleton = '骷髅匕首', knife_classic = '经典匕首', knife_paracord = '伞绳匕首',
        knife_survival = '求生匕首', knife_canis = '犬齿匕首', knife_voss = '沃斯匕首',
        knife_kukri = '廓尔喀刀', knife_cord = '绳索匕首', knife_outdoor = '户外匕首',
        knife_trench = '战壕刀', knife_push = '推匕首', knife_gypsy = '吉普赛匕首',
        knife_skinfix = '匕首', knife_default = '匕首',
    }

    -- ── 特殊武器（手雷/匕首）辅助：class 名 → 名称 / 图标 / 数量 ──
    -- 这个版本投掷物 weapon_info 的 name 是空串、clip 恒为 -1，只能靠 class name 兜底。
    -- 收进一个表引用，避免给绘制函数增加过多 upvalue（Lua 5.1 上限 60）。
    local WK = {}
    WK.CLASS_KEY = {
        c_flashbang = 'flashbang', c_hegrenade = 'hegrenade',
        c_smokegrenade = 'smokegrenade', c_molotovgrenade = 'molotovgrenade',
        c_incendiarygrenade = 'incgrenade', c_decoygrenade = 'decoygrenade',
        c_tagrenade = 'tagrenade', c_knife = 'knife',
    }
    WK.KIND = {
        hegrenade = 'he', flashbang = 'flash', smokegrenade = 'smoke',
        molotovgrenade = 'fire', incgrenade = 'inc', decoygrenade = 'decoy',
        taser = 'zeus',
    }
    WK.icon = { he = icon_he, flash = icon_flash, smoke = icon_smoke,
                fire = icon_fire, inc = icon_fire, decoy = icon_decoy, zeus = icon_zeus }
    -- 与道具面板一致的游戏图标名候选（武器面板复用，保证两边图标相同）
    WK.NAMES = {
        he    = { 'weapon_hegrenade', 'hegrenade', 'he_grenade' },
        flash = { 'weapon_flashbang', 'flashbang', 'flash_bang' },
        smoke = { 'weapon_smokegrenade', 'smokegrenade', 'smoke_grenade' },
        fire  = { 'weapon_molotov', 'molotov', 'molotovgrenade', 'weapon_molotovgrenade', 'molotov_grenade' },
        inc   = { 'weapon_incgrenade', 'incgrenade', 'weapon_incendiarygrenade',
                  'incendiarygrenade', 'incendiary' },
        decoy = { 'weapon_decoy', 'decoy', 'weapon_decoygrenade', 'decoygrenade', 'decoy_grenade' },
        zeus  = { 'weapon_taser', 'taser', 'weapon_zeus', 'zeus' },
    }

    function WK.class_key(wpn)
        if not wpn then return nil end
        local ok, cn = pcall(function() return wpn:class_name() end)
        if not ok or not cn then return nil end
        local raw = string.lower(tostring(cn))
        local mapped = WK.CLASS_KEY[raw]
        if mapped then return mapped end
        return (raw:gsub('^c_weapon', ''):gsub('^cweapon', ''):gsub('^c_', ''):gsub('^weapon_', ''))
    end

    function WK.gcount(pawn, kind)
        if kind == nil then return nil end
        local slots = read_ammo_slots(pawn)
        if slots == nil then return nil end
        local cands = GRENADE_AMMO_IDX[kind]
        if cands == nil then return nil end
        for i = 1, #cands do
            local v = slots[cands[i]]
            if type(v) == 'number' and v > 0 then return v end
        end
        return 0
    end

    local function weapon_display_name(wpn)
        if not wpn then return '--' end
        local info = nil
        local ok, r = pcall(function() return wpn:weapon_info() end)
        if ok then info = r end
        -- 优先用 display 字段
        if info and info.display and info.display ~= '' then return info.display end
        -- 用 internal name 查表（投掷物这里通常是空串，跳过）
        local intkey = nil
        if info and info.name and info.name ~= '' then
            intkey = string.lower(tostring(info.name)):gsub('^weapon_', '')
            if WNAME[intkey] then return WNAME[intkey] end
        end
        -- 用 class name 查表（C_Flashbang → flashbang 等）
        local ckey = WK.class_key(wpn)
        if ckey and WNAME[ckey] then return WNAME[ckey] end
        if intkey then return tostring(info.name) end
        if ckey and ckey ~= '' then return ckey end
        return '--'
    end

    -- ── 游戏内置图标（道具用，与 MC HUD 同款）──────────────────
    local icon_set = nil
    local icon_cache_t = {}
    local HAS_ICONS = false

    local function build_icon_set()
        if icon_set ~= nil then return end
        icon_set = {}
        local ok, list = pcall(render.icons)
        if ok and type(list) == 'table' then
            for i = 1, #list do
                local nm = tostring(list[i])
                icon_set[string.lower(nm)] = nm
            end
        end
        -- 探测多种图标：武器、手雷、护甲，只要任一种存在即认为图标系统可用
        for _, probe in ipairs({
            'weapon_ak47', 'ak47', 'weapon_knife', 'knife',
            'weapon_hegrenade', 'hegrenade', 'weapon_smokegrenade', 'smokegrenade',
            'item_kevlar', 'item_assaultsuit',
        }) do
            if icon_set[probe] ~= nil then
                HAS_ICONS = true
                break
            end
        end
    end

    local function game_icon(names, size)
        if not HAS_ICONS then return nil end
        for i = 1, #names do
            local real = icon_set[string.lower(names[i])]
            if real ~= nil then
                local key = real .. '|' .. tostring(size)
                local hit = icon_cache_t[key]
                if hit == nil then
                    local ok, t = pcall(render.icon, real, size)
                    hit = (ok and t) or false
                    icon_cache_t[key] = hit
                end
                if hit then return hit end
            end
        end
        return nil
    end

    local function icon_dims(tex, s)
        local w, h = s, s
        local ok, tw_, th_ = pcall(function() return tex:size() end)
        if ok and tonumber(tw_) ~= nil and tonumber(th_) ~= nil and tw_ > 0 and th_ > 0 then
            if tw_ >= th_ then w = s; h = s * th_ / tw_
            else h = s; w = s * tw_ / th_ end
        end
        return w, h
    end

    -- 诊断：找出游戏图标集里护甲相关的图标名，并打印比分栏里的护甲 Image 面板
    local armor_dbg_done = false
    local function dump_armor_icons()
        if armor_dbg_done then return end
        armor_dbg_done = true
        build_icon_set()
        local hits = {}
        for k, v in pairs(icon_set or {}) do
            if k:find('armor', 1, true) or k:find('kevlar', 1, true)
                or k:find('helmet', 1, true) or k:find('suit', 1, true) then
                hits[#hits + 1] = v
            end
        end
        table.sort(hits)
        print('[MC HUD DEBUG] armor icons(' .. #hits .. '): ' .. table.concat(hits, ', '))
        pcall(function()
            panorama.run([[
                (function(){
                    var root=$.GetContextPanel();var out=[];var warm=[];
                    function walk(p,d){if(d>22)return;
                        var pid=String(p.id||"");var pt=String(p.paneltype||"");
                        if(pt==="Image"){
                            var s="";try{s=String(p.src||p.image||"");}catch(e){}
                            if(/armor|kevlar|equipment/i.test(s)||/armor|kevlar|helmet|suit/i.test(pid))
                                out.push(pid+" src="+s);
                        }
                        if(/warm|round_status|roundstatus/i.test(pid)) warm.push(pid+" ["+pt+"]");
                        var ks=p.Children?p.Children():[];
                        for(var i=0;i<ks.length;i++)walk(ks[i],d+1);}
                    walk(root,0);
                    $.Msg("=== ARMOR IMAGES "+out.length+" ===");
                    for(var j=0;j<out.length&&j<80;j++)$.Msg(out[j]);
                    $.Msg("=== WARMUP IDS "+warm.length+" ===");
                    for(var k=0;k<warm.length&&k<40;k++)$.Msg(warm[k]);
                })();
            ]])
        end)
    end

    -- 检测玩家是否有头盔（CS2 netvar: m_bHasHelmet）
    local function pawn_has_helmet(pawn)
        if not pawn then return false end
        -- 优先尝试方法调用
        local ok1, h = pcall(function() return pawn:has_helmet() end)
        if ok1 and type(h) == 'boolean' then return h end
        -- 回退到 netvar 读取
        local ok2, hv = pcall(function()
            return pawn:get('C_CSPlayerPawn', 'm_bHasHelmet', 'bool')
        end)
        if ok2 then
            if type(hv) == 'boolean' then return hv end
            if type(hv) == 'number' then return hv ~= 0 end
        end
        return false
    end

    -- 护甲/头盔图标：优先用游戏内置图标，失败用矢量绘制
    local function draw_armor_icon(x, cy, s, col, with_helmet)
        build_icon_set()
        -- 游戏内置图标：item_assaultsuit = 头甲，item_kevlar = 单护甲
        local icon_names = with_helmet
            and { 'item_assaultsuit', 'assaultsuit', 'heavyassaultsuit' }
            or  { 'item_kevlar', 'kevlar', 'assaultsuit' }
        local tex = game_icon(icon_names, s)
        if tex then
            local iw, ih = icon_dims(tex, s)
            render.image(tex, x, cy - ih * 0.5, iw, ih, col)
            return
        end
        -- 矢量兜底
        local cx = x + s * 0.5
        local top = cy - s * 0.42
        render.poly_filled({
            { cx - s * 0.32, top },
            { cx + s * 0.32, top },
            { cx + s * 0.28, cy + s * 0.32 },
            { cx, cy + s * 0.44 },
            { cx - s * 0.28, cy + s * 0.32 },
        }, col)
        render.line(cx, top + s * 0.06, cx, cy + s * 0.38, with_a(U.col_bg:get(), 0.6), math.max(1, s * 0.08))
        if with_helmet then
            -- 头盔：在护甲上方画一个半圆
            render.arc(cx, top + s * 0.02, s * 0.30, 180, 360, col, 1, 12)
        end
    end

    -- APHRODITE 绘制（已移除顶栏块）
    local function draw_apho()
        local pawn = entity.local_pawn()
        if not pawn then return end
        local w, h = render.screen_size()
        local sc = U.scale:get()
        local op = U.opacity:get() / 100
        local t = T()
        local dt = 0.016
        if last_frame_t then
            local d = t - last_frame_t
            if d > 0 and d < 0.5 then dt = d end
        end
        last_frame_t = t
        -- 面板拖动：使用上一帧登记的矩形判断左键命中，更新偏移并回写
        U.drag_update(U.ed, U.layout_store)
        local flick = 1
        if U.flick_on:get() then
            flick = 0.86 + 0.14 * math.abs(math.sin(t * 5.3) * math.sin(t * 1.7))
        end
        local a_main = op * flick
        local c_main = with_a(U.col_main:get(), a_main)
        local c_dim  = with_a(U.col_dim:get(), a_main * 0.9)
        local c_acc  = with_a(U.col_accent:get(), a_main)
        local glow   = U.glow_on:get()
        local phase  = (t * 30) % (3 * sc)
        local ctrl = entity.local_controller()
        local hp = pawn:health() or 0
        local ap = pawn:armor() or 0

        -- 武器面板
        if U.left_on:get() then
            build_icon_set()
            local wsc = sc * U.weapon_scale:get()
            local wpn = pawn:weapon()
            local info = wpn and wpn:weapon_info() or nil
            local line_h = 17 * wsc
            local box_w = 92 * wsc
            local side = to_index(U.weapon_side:get(), { '左', '右' }, 1)
            local px
            if side == 1 then
                px = w - 16 * wsc - box_w
            else
                px = 16 * wsc
            end
            local py = h * 0.5 - 22 * wsc + (U.wpn_y + U.ed.wy) * wsc
                        + (U.bob_on:get() and math.sin(t * 1.6) * 1.2 * wsc or 0)
            local label = weapon_display_name(wpn)
            local clip = info and info.clip or 0
            local reserve = info and info.reserve or 0
            -- max_clip 用于弹药条比例；取不到时用 clip 自身兜底避免除零
            local max_clip = (info and info.max_clip and info.max_clip > 0) and info.max_clip or 30
            -- 投掷物：weapon_info 的 clip 恒为 -1，真实持有数量在 m_iAmmo
            local gkind = WK.KIND[WK.class_key(wpn) or '']
            if gkind then
                local gc = WK.gcount(pawn, gkind)
                if gc ~= nil and gc > 0 then
                    clip = gc
                    reserve = 0
                    max_clip = gc
                end
            end
            if label ~= wpn_last_label then
                wpn_last_label = label
                wpn_anim = 0
            end
            if U.wpn_anim then
                if wpn_anim < 1 then
                    wpn_anim = math.min(1, wpn_anim + dt / 0.22)
                end
            else
                wpn_anim = 1
            end
            local ease = 1 - (1 - wpn_anim) * (1 - wpn_anim)
            local slide = (1 - ease) * -18 * wsc
            local fade = 0.1 + 0.9 * ease
            py = py + slide
            local f_main = with_a(c_main, fade)
            local f_dim  = with_a(c_dim, fade)
            local f_acc  = with_a(c_acc, fade)
            local bar_x = (side == 1) and (px + box_w - math.max(1, wsc)) or px
            render.rect_filled(bar_x, py - 4 * wsc, math.max(1, wsc), 34 * wsc, with_a(U.col_main:get(), a_main * 0.22 * fade))
            local tick_x = (side == 1) and (px + box_w - 6 * wsc) or px
            render.rect_filled(tick_x, py - 4 * wsc, 6 * wsc, math.max(1, wsc), f_acc)
            render.rect_filled(tick_x, py + 29 * wsc, 6 * wsc, math.max(1, wsc), with_a(U.col_main:get(), a_main * 0.22 * fade))

            -- 武器游戏图标（刀 / 手枪 / 电击枪 / 冲锋枪 / 狙击枪 / 其他武器 / 道具）
            local ckey = WK.class_key(wpn) or ''
            local has = function(t) return ckey:find(t, 1, true) ~= nil end
            local wtype = info and info.type
            -- 注意：WK.KIND 里 taser 也映射成 zeus，所以电击枪必须优先判定
            local is_taser = has('taser') or has('zeus') or (info and info.def == 31) or (wtype == 8)
            local is_knife = (not is_taser) and has('knife')
            local is_pistol = (not is_taser) and (wtype == 1
                or has('glock') or has('usp') or has('hkp2000') or has('p250') or has('deagle')
                or has('revolver') or has('elite') or has('fiveseven') or has('tec9') or has('cz75'))
            local is_smg = (not is_taser) and (wtype == 2
                or has('mac10') or has('mp9') or has('mp7') or has('mp5') or has('ump45')
                or has('p90') or has('bizon'))
            local is_sniper = (not is_taser) and (wtype == 5
                or has('awp') or has('ssg08') or has('scar20') or has('g3sg1'))
            local cfg
            if is_taser then
                cfg = WICON.taser
            elseif gkind then
                cfg = WICON.util
            elseif is_knife then
                cfg = WICON.knife
            elseif is_smg then
                cfg = WICON.smg
            elseif is_sniper then
                cfg = WICON.sniper
            elseif is_pistol then
                cfg = WICON.pistol
            else
                cfg = WICON.other
            end
            local isc, idx, idy = cfg[1], cfg[2], cfg[3]
            local icon_s = 18 * wsc * isc
            local ix = px + box_w - icon_s - 6 * wsc + idx * wsc
            local iy = py - 2 * wsc + idy * wsc
            if wpn then
                -- 收集尽可能多的名称变体供图标查找
                local wnames = {}
                local function add_name(n)
                    if n and n ~= '' then
                        local ln = string.lower(tostring(n))
                        wnames[#wnames + 1] = ln
                        -- 去 weapon_ 前缀
                        local stripped = ln:gsub('^weapon_', '')
                        if stripped ~= ln then wnames[#wnames + 1] = stripped end
                        -- 加 weapon_ 前缀
                        wnames[#wnames + 1] = 'weapon_' .. stripped
                    end
                end
                if info and info.name and info.name ~= '' then add_name(info.name) end
                -- 用 class name 再试（C_WeaponGlock → glock，C_Flashbang → flashbang）
                add_name(WK.class_key(wpn))
                -- 手雷补上与道具面板相同的图标名候选，保证两边图标一致
                local gnames = WK.NAMES[gkind]
                if gnames then
                    for i = 1, #gnames do add_name(gnames[i]) end
                end
                local tex = game_icon(wnames, icon_s)
                if tex then
                    local iw, ih = icon_dims(tex, icon_s)
                    render.image(tex, ix, iy, iw, ih,
                        with_a(U.col_main:get(), a_main * fade))
                elseif WK.icon[gkind] then
                    -- 没有游戏图标时用矢量道具图标兜底
                    WK.icon[gkind](ix, iy + icon_s * 0.5, icon_s, with_a(U.col_main:get(), a_main * fade))
                end
            end

            render.text(px + 10 * wsc, py, f_dim, label, nil, 9 * wsc)
            if glow then
                render.text(px + 10 * wsc - 0.5, py + line_h * 0.75 - 0.5, with_a(U.col_main:get(), a_main * 0.15 * fade), tostring(clip), nil, 16 * wsc)
            end
            render.text(px + 10 * wsc, py + line_h * 0.75, f_main, tostring(clip), nil, 15 * wsc)
            local cxw = text_size(tostring(clip), nil, 15 * wsc)
            render.text(px + 10 * wsc + cxw + 4 * wsc, py + line_h * 0.95, f_dim, '/ ' .. tostring(reserve), nil, 10 * wsc)

            -- 弹药条（clip / max_clip）
            local bar_y = py + 26 * wsc
            local bar_w = box_w - 20 * wsc
            local bar_h = math.max(2, 2.5 * wsc)
            local ratio = (clip > 0 and max_clip > 0) and (clip / max_clip) or 0
            if ratio > 1 then ratio = 1 end
            render.rect_filled(px + 10 * wsc, bar_y, bar_w, bar_h, with_a(U.col_main:get(), a_main * 0.14 * fade), 1)
            if ratio > 0 then
                local fill_w = math.max(1, bar_w * ratio)
                local bar_col = (ratio < 0.25) and c_acc or with_a(U.col_main:get(), a_main * 0.9 * fade)
                render.rect_filled(px + 10 * wsc, bar_y, fill_w, bar_h, bar_col, 1)
            end

            if U.bracket_on:get() then
                brackets(px - 4 * wsc, py - 8 * wsc, box_w, 42 * wsc, 5 * wsc, with_a(U.col_main:get(), a_main * 0.14 * fade), math.max(1, wsc))
            end
            U.drag_rect('weapon', px - 6 * wsc, py - 10 * wsc, box_w + 12 * wsc, 52 * wsc)
        end

        -- 道具框
        if U.util_on:get() then
            local counts = { he = 0, flash = 0, smoke = 0, fire = 0, inc = 0, decoy = 0, zeus = 0 }
            local dbg = {}
            local list = pawn:weapons()
            if list then
                local cnt = 0
                local ok, c = pcall(function() return #list end)
                if ok and type(c) == 'number' then cnt = c end
                if cnt > 0 then
                    for i = 1, cnt do tally_weapon(counts, list[i], dbg, pawn) end
                else
                    for _, wp in pairs(list) do tally_weapon(counts, wp, dbg, pawn) end
                end
            end
            if U.util_debug then
                local line = 'WPN(' .. tostring(list and 'y' or 'nil') .. '): ' .. table.concat(dbg, ' | ')
                    .. ' sway=' .. string.format('%.1f/%.1f', sway_sx, sway_sy)
                    .. ' insp=' .. tostring(insp_on)
                render.text(24, 160, color(255, 200, 90), line, 's', 12)
                -- 每秒一次把完整信息（含 m_iAmmo）输出到控制台
                if t >= dbg_next_t then
                    dbg_next_t = t + 1.0
                    pcall(dump_debug, pawn)
                    pcall(dump_armor_icons)
                    pcall(function() print('[MC HUD DEBUG] sway=' .. string.format('%.2f/%.2f', sway_sx, sway_sy)
                        .. ' insp=' .. tostring(insp_on)
                        .. ' peak=' .. string.format('%.2f', dbg_peak)
                        .. ' inspSeen=' .. tostring(dbg_insp_seen)
                        .. ' key=' .. tostring(inspect_key)
                        .. ' down=' .. tostring(inspect_down())
                        .. ' wAn=' .. (anchor_px and string.format('%.0f/%.0f', anchor_px, anchor_py) or 'nil')) end)
                    dbg_peak, dbg_insp_seen = 0, false
                end
            end
            build_icon_set()
            local usc = sc * U.util_scale:get()
            local items = {
                { key = 'he',    icon = icon_he,    names = { 'weapon_hegrenade', 'hegrenade', 'he_grenade' } },
                { key = 'flash', icon = icon_flash, names = { 'weapon_flashbang', 'flashbang', 'flash_bang' } },
                { key = 'smoke', icon = icon_smoke, names = { 'weapon_smokegrenade', 'smokegrenade', 'smoke_grenade' } },
                { key = 'fire',  icon = icon_fire,  names = { 'weapon_molotov', 'molotov', 'molotovgrenade', 'weapon_molotovgrenade', 'molotov_grenade' } },
                { key = 'inc',   icon = icon_fire,  names = { 'weapon_incgrenade', 'incgrenade', 'weapon_incendiarygrenade', 'incendiarygrenade', 'incendiary' } },
                { key = 'decoy', icon = icon_decoy, names = { 'weapon_decoy', 'decoy', 'weapon_decoygrenade', 'decoygrenade', 'decoy_grenade' } },
                { key = 'zeus',  icon = icon_zeus,  names = { 'weapon_taser', 'taser', 'weapon_zeus', 'zeus' } },
            }
            local isz = 14 * usc
            local row_h = 15 * usc
            local bx = w - 16 * usc - 64 * usc + U.ed.ux
            local by = h * 0.5 + (U.util_y + U.ed.uy) * usc
                        + (U.bob_on:get() and math.sin(t * 1.6 + 0.8) * 1.2 * usc or 0)
            local shown = 0
            for i = 1, #items do
                local it = items[i]
                local n = counts[it.key] or 0
                if n > 0 or U.util_empty:get() then
                    local y = by + shown * row_h
                    -- 图标位置偏移（固定值，不影响数量文字）
                    local off = U.util_off[it.key] or { 0, 0 }
                    local ix = bx + off[1] * usc
                    local iy = y + off[2] * usc
                    local live = n > 0
                    local icol = live and c_dim or with_a(U.col_dim:get(), a_main * 0.25)
                    local tcol = live and c_main or with_a(U.col_main:get(), a_main * 0.25)
                    -- 优先用游戏内置图标，失败则回退矢量图标
                    local tex = game_icon(it.names, isz)
                    if tex then
                        local iw, ih = icon_dims(tex, isz)
                        render.image(tex, ix, iy - ih * 0.5 + isz * 0.5, iw, ih, icol)
                    else
                        it.icon(ix, iy + isz * 0.5, isz, icol)
                    end
                    -- 数量文字固定在原始 bx/y，不随图标偏移
                    render.text(bx + isz + 6 * usc, y, tcol, tostring(n), 'v', 12 * usc)
                    shown = shown + 1
                end
            end
            if shown > 0 then
                render.rect_filled(bx - 8 * usc, by - 8 * usc, math.max(1, usc), shown * row_h + 4 * usc,
                    with_a(U.col_main:get(), a_main * 0.18))
                if U.bracket_on:get() then
                    brackets(bx - 10 * usc, by - 10 * usc, 42 * usc, shown * row_h + 6 * usc, 4 * usc,
                        with_a(U.col_main:get(), a_main * 0.12), math.max(1, usc))
                end
                U.drag_rect('util', bx - 14 * usc, by - 12 * usc, 74 * usc, shown * row_h + 20 * usc)
            end
        end

        -- 数据簇
        if U.center_on:get() then
            local csc = sc * U.center_scale:get()
            local anchor = to_index(U.center_anchor:get(), { '屏幕', '武器' }, 1)
            local cx = w * 0.5
            local base = h * 0.5 + 44 * csc
            if anchor == 0 then
                -- 屏幕锚点（combo 下标 0 起：0=屏幕，1=武器）
                cx = cx + (U.cl_dx + U.ed.cx) * csc
                base = h * 0.5 + (U.cl_dy + U.ed.cy) * csc
                -- 武器位移跟随：仅在屏幕锚点下需要模拟跟随
                if U.sway_on:get() then
                    local sx, sy = weapon_sway(pawn, csc, t)
                    cx = cx + sx
                    base = base + sy
                end
            else
                -- 武器锚点：真正以枪（视图模型）在屏幕上的位置为基准
                local ax_, ay_ = weapon_anchor(pawn)
                if ax_ ~= nil then
                    cx = ax_ + (U.cl_dx + U.ed.cx) * csc
                    base = ay_ + (U.cl_dy + U.ed.cy) * csc
                else
                    cx = cx + (U.cl_dx + U.ed.cx) * csc
                    base = h * 0.5 + (U.cl_dy + U.ed.cy) * csc
                end
            end
            local by = base + (U.bob_on:get() and math.sin(t * 1.9 + 0.6) * 1.6 * csc or 0)
            local half = 34 * csc
            U.drag_rect('cluster', cx - half - 18 * csc, by - 14 * csc, (half + 18 * csc) * 2, 70 * csc)
            render.rect_filled(cx - half - 14 * csc, by - 12 * csc, 14 * csc, math.max(1, csc), with_a(U.col_main:get(), a_main * 0.25))
            render.rect_filled(cx + half, by - 12 * csc, 14 * csc, math.max(1, csc), with_a(U.col_main:get(), a_main * 0.25))
            local wpn = pawn:weapon()
            local info = wpn and wpn:weapon_info() or nil
            local cclip = info and info.clip or 0
            local cres = info and info.reserve or 0
            local ckind = WK.KIND[WK.class_key(wpn) or '']
            if ckind then
                local gc = WK.gcount(pawn, ckind)
                if gc ~= nil and gc > 0 then cclip = gc; cres = 0 end
            end
            local clip_s = tostring(cclip)
            local res_s = '/ ' .. tostring(cres)
            local big = 23 * csc
            local small = 9.5 * csc
            local wbig = text_size(clip_s, nil, big)
            local wres = text_size(res_s, nil, small)
            local ax = cx - (wbig + 5 * csc + wres) * 0.5
            if glow then
                render.text(ax - 0.5, by - 0.5, with_a(U.col_main:get(), a_main * 0.14), clip_s, 'v', big + 1.5)
            end
            render.text(ax, by, c_main, clip_s, 'v', big)
            render.text(ax + wbig + 5 * csc, by + 3 * csc, c_dim, res_s, 'v', small)
            local ry = by + 22 * csc
            local hs = tostring(hp)
            local as = tostring(ap)
            local ts2 = 11 * csc
            -- HP 用文字，护甲用护甲图标（检测是否有头盔）
            local has_hel = (ap > 0) and pawn_has_helmet(pawn)
            local hp_lbl = 'HP'
            local iw_hp = text_size(hp_lbl, nil, ts2)
            local iw_am = 14 * csc
            local hiw = text_size(hs, nil, ts2)
            local aiw = text_size(as, nil, ts2)
            local mid = 26 * csc
            local total2 = iw_hp + 4 * csc + hiw + mid + iw_am + 4 * csc + aiw
            local rx = cx - total2 * 0.5
            -- HP 标签
            render.text(rx, ry, c_acc, hp_lbl, 'v', ts2)
            render.text(rx + iw_hp + 4 * csc, ry, c_main, hs, 'v', ts2)
            rx = rx + iw_hp + 4 * csc + hiw + mid
            -- 护甲图标（有头盔显示头甲图标，否则单护甲图标）
            -- 尺寸与位置偏移只作用于图标本身，不影响 HP/护甲文字布局
            local am_s = iw_am * U.armor_scale
            local am_x = rx + U.armor_dx * csc
            local am_y = ry + ts2 * 0.5 + U.armor_dy * csc
            draw_armor_icon(am_x, am_y, am_s, with_a(U.col_main:get(), a_main * 0.9), has_hel)
            -- 护甲数值文字固定在原始 iw_am 布局位置
            render.text(rx + iw_am + 4 * csc, ry, c_dim, as, 'v', ts2)
            local ky = by + 44 * csc
            local ks = 9 * csc
            local function key_glyph(kx, kyy, vk, label)
                local down = input.key_down(vk)
                render.text(kx, kyy, down and c_acc or c_dim, label, 'cv', ks)
            end
            key_glyph(cx, ky, 0x57, 'W')
            key_glyph(cx - 11 * csc, ky + 12 * csc, 0x41, 'A')
            key_glyph(cx, ky + 12 * csc, 0x53, 'S')
            key_glyph(cx + 11 * csc, ky + 12 * csc, 0x44, 'D')
            local spd = math.floor(pawn:velocity():length2d() + 0.5)
            render.text(cx + 42 * csc, ky + 14 * csc, c_dim, spd .. ' u/s', 'cv', 10 * csc)
            if U.bracket_on:get() then
                brackets(cx - 52 * csc, by - 18 * csc, 104 * csc, 74 * csc, 6 * csc, with_a(U.col_main:get(), a_main * 0.13), math.max(1, csc))
            end
        end
    end

    return {
        draw = draw_apho,
        update = update_game_hud,
        get_status = function() return hud_status end,
        set_hidden = set_hud_hidden,
        apply_scale = apply_hud_scale,
        is_hidden = function() return hud_hidden end,
        set_hidden_flag = function(v) hud_hidden = v end,
        reset_tick = function() hud_tick = 0 end,
    }
end)(U)

-- ════════════════════════════════════════════════════════════════
-- MC HUD 子系统（工厂函数）
-- ════════════════════════════════════════════════════════════════
local MC_SYS = (function(ctrl)
    local sw_keys, mc_hide, cp_pressed, sl_ks, sl_ka =
        ctrl.sw_keys, ctrl.mc_hide, ctrl.cp_pressed, ctrl.sl_ks, ctrl.sl_ka
    local sw_weap, sl_ws, sl_wa = ctrl.sw_weap, ctrl.sl_ws, ctrl.sl_wa
    local cp_shadow, cp_overlay, sw_blur, cp_wicon, cp_wtext =
        ctrl.cp_shadow, ctrl.cp_overlay, ctrl.sw_blur, ctrl.cp_wicon, ctrl.cp_wtext

    local POS_KEYS = "mc_hud_keys_pos"
    local POS_WEAP = "mc_hud_weap_pos"
    local KEY_W = 87
    local KEY_A = 65
    local KEY_S = 83
    local KEY_D = 68
    local KEY_SPACE = 32
    local ROLL_TIME = 0.18
    local PRESS_IN = 0.07
    local PRESS_OUT = 0.13
    local KEY_LATCH = 0.08
    local KEYF = { "Bahnschrift", "Verdana", "Tahoma", "Segoe UI", "Arial" }
    local NAMES = { "Microsoft YaHei", "Bahnschrift", "Verdana", "Tahoma", "Segoe UI", "Arial" }
    local MONO = { "Consolas", "Lucida Console", "Courier New", "DejaVu Sans Mono", "Arial" }

    local function num(v, def)
        local n = tonumber(v)
        if n == nil then return def end
        return n
    end

    local function clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local UI = { keys = false, weap = false, r = 255, g = 205, b = 253, a = 255,
                 k_move = false, k_jump = false, k_mouse = false, k_cps = false,
                 ks = 1, ka = 1, ws = 1, wa = 1 }

    local STYLE = { sr = 0, sg = 0, sb = 0, sa = 90,
                    or_ = 46, og_ = 52, ob_ = 46, oa_ = 46,
                    blur = true,
                    wir = 255, wig = 255, wib = 255,
                    wtr = 252, wtg = 254, wtb = 252 }

    local font_cache = {}

    local function load_font(list, size)
        for i = 1, #list do
            local ok, f = pcall(render.font, list[i], size)
            if ok and f ~= nil then return f end
        end
        return nil
    end

    local function text_w(font, size, txt, fallback)
        if txt == nil or txt == "" then return 0 end
        local ok, w = pcall(render.text_size, txt, nil, size, font)
        if ok and tonumber(w) ~= nil and w > 0 then return w end
        return #txt * fallback
    end

    local function fonts(scale)
        local tag = string.format("%.2f", math.floor(scale * 20 + 0.5) / 20)
        local b = font_cache[tag]
        if b ~= nil then return b end
        local key_size = math.floor(18 * scale + 0.5)
        local name_size = math.floor(15 * scale + 0.5)
        local mono_size = math.floor(13 * scale + 0.5)
        local cps_size = math.floor(15 * scale + 0.5)
        local key = load_font(KEYF, key_size)
        local name = load_font(NAMES, name_size)
        local mono = load_font(MONO, mono_size)
        local cps = load_font(MONO, cps_size)
        local function mh(fo, size, sample)
            local h = math.floor(size * 1.2 + 0.5)
            if fo ~= nil then
                local ok, _, hh = pcall(render.text_size, sample, nil, size, fo)
                if ok and tonumber(hh) ~= nil and hh > h then h = math.floor(hh + 0.5) end
            end
            return h
        end
        local adv = math.floor(7 * scale + 0.5)
        if mono ~= nil then
            local ok, w = pcall(render.text_size, "0", nil, mono_size, mono)
            if ok and tonumber(w) ~= nil and w > 0 then adv = w end
        end
        b = {
            tag = tag, key = key, name = name, mono = mono, cps = cps, adv = adv,
            key_h = mh(key, key_size, "W"), name_h = mh(name, name_size, "AK-47"),
            mono_h = mh(mono, mono_size, "0"), cps_h = mh(cps, cps_size, "0"),
            key_size = key_size, name_size = name_size, mono_size = mono_size, cps_size = cps_size,
        }
        font_cache[tag] = b
        return b
    end

    local scale_value = 1
    local scale_at = -1

    local function scale_now(now)
        if now - scale_at < 1 then return scale_value end
        scale_at = now
        local ok, s = pcall(render.scale)
        if ok and tonumber(s) ~= nil and s > 0 then
            scale_value = clamp(s, 0.7, 2.2)
        end
        return scale_value
    end

    local function soft_edge(x, y, w, h, rounding, scale, steps, r, g, b, a_max)
        local step = math.max(1, math.floor(1.1 * scale + 0.5))
        for k = steps, 1, -1 do
            local d = k * step
            local t = 1 - (k - 1) / steps
            local al = math.floor(a_max * t * t)
            if al > 0 then
                render.rect_filled(x - d, y - d, w + d * 2, h + d * 2, color(r, g, b, al), rounding + d)
            end
        end
    end

    local pos_cache = {}

    local function read_pos(path)
        local hit = pos_cache[path]
        if hit ~= nil then return hit.x, hit.y end
        local x, y = nil, nil
        local ok, data = pcall(db.load, path, nil)
        if ok and type(data) == "table" then
            x = num(data.x, nil)
            y = num(data.y, nil)
        end
        pos_cache[path] = { x = x, y = y }
        return x, y
    end

    local function write_pos(path, x, y)
        local hit = pos_cache[path]
        if hit == nil then
            hit = {}
            pos_cache[path] = hit
        end
        hit.x = x
        hit.y = y
        pcall(db.save, path, { x = x, y = y })
    end

    local drag_keys = { on = false, dx = 0, dy = 0 }
    local drag_weap = { on = false, dx = 0, dy = 0 }
    local INPUT = { mx = 0, my = 0, down = false, menu = false, t = -1 }

    local function over_menu(mx, my)
        local ok1, ps = pcall(function() return ui.position() end)
        local ok2, sz = pcall(function() return ui.size() end)
        if not ok1 or not ok2 or ps == nil or sz == nil then return false end
        local px, py = num(ps.x, 0), num(ps.y, 0)
        local pw, ph = num(sz.x, 0), num(sz.y, 0)
        return mx >= px and mx <= px + pw and my >= py and my <= py + ph
    end

    local function resolve_drag(st, path, sw_, sh_, w, h, def_x, def_y)
        local x, y = read_pos(path)
        if x == nil or y == nil then
            x = def_x
            y = def_y
        end
        x = clamp(x, 0, sw_ - w)
        y = clamp(y, 0, sh_ - h)
        if INPUT.menu and INPUT.down then
            if st.on then
                x = clamp(INPUT.mx - st.dx, 0, sw_ - w)
                y = clamp(INPUT.my - st.dy, 0, sh_ - h)
                st.x = x
                st.y = y
            elseif INPUT.mx >= x and INPUT.mx <= x + w and INPUT.my >= y and INPUT.my <= y + h then
                if not over_menu(INPUT.mx, INPUT.my) then
                    st.on = true
                    st.dx = INPUT.mx - x
                    st.dy = INPUT.my - y
                    st.x = x
                    st.y = y
                end
            end
        elseif st.on then
            st.on = false
            if st.x ~= nil and st.y ~= nil then
                x = st.x
                y = st.y
            end
            write_pos(path, x, y)
        end
        if st.on and st.x ~= nil and st.y ~= nil then
            x = st.x
            y = st.y
        end
        return x, y
    end

    local function input_poll(now)
        if now - INPUT.t < 0.008 then return end
        INPUT.t = now
        local ok, cx, cy = pcall(input.cursor)
        if ok and cx ~= nil then
            INPUT.mx = num(cx, 0)
            INPUT.my = num(cy, 0)
        end
        INPUT.down = input.key_down(1)
        local ok2, alpha = pcall(ui.alpha)
        if ok2 then
            INPUT.menu = num(alpha, 0) > 0.01
        else
            INPUT.menu = false
        end
    end

    local key_p = { 0, 0, 0, 0, 0 }
    local mouse_p = { 0, 0 }
    local down_buf = { false, false, false, false, false, false, false }
    local key_latch = { 0, 0, 0, 0, 0, 0, 0 }

    local function draw_key(x, y, w, h, legend, p, is_space, scale, f, cr, cg, cb, ca, am)
        local rounding = math.floor(11 * scale + 0.5)
        soft_edge(x, y, w, h, rounding, scale, 4, STYLE.sr, STYLE.sg, STYLE.sb, math.floor(STYLE.sa * am))
        if STYLE.blur then
            render.blur(x, y, w, h, math.max(1, math.floor(4 * scale + 0.5)))
        end
        render.rect_filled(x, y, w, h, color(STYLE.or_, STYLE.og_, STYLE.ob_, math.floor(STYLE.oa_ * am)), rounding)
        if p > 0.002 then
            local e = 1 - (1 - p) * (1 - p)
            local cx = x + w * 0.5
            local cy = y + h * 0.5
            local hw = w * 0.5 * e
            local hh = h * 0.5 * e
            if hw > 0.5 and hh > 0.5 then
                local rd2 = math.max(2, math.floor(rounding * e + 0.5))
                render.rect_filled(cx - hw, cy - hh, hw * 2, hh * 2, color(cr, cg, cb, math.floor(ca * (0.32 + 0.58 * e) * am)), rd2)
            end
        end
        if is_space then
            local lw = w * 0.58
            local th = math.max(2, math.floor(2 * scale + 0.5))
            local ly = y + h * 0.5 - th * 0.5
            render.rect_filled(x + (w - lw) * 0.5, ly, lw, th, color(255, 255, 255, math.floor(232 * am)), 1)
        elseif legend ~= "" then
            local tw = text_w(f.key, f.key_size, legend, f.key_size * 0.6)
            local tx = x + (w - tw) * 0.5
            local ty = y + (h - f.key_h) * 0.5
            render.text(math.floor(tx + 0.5), math.floor(ty + 0.5), color(255, 255, 255, math.floor(244 * am)), legend, nil, f.key_size, f.key)
        end
    end

    local function draw_mouse(x, y, w, h, legend, p, scale, f, cr, cg, cb, ca, am)
        local rounding = math.floor(11 * scale + 0.5)
        soft_edge(x, y, w, h, rounding, scale, 4, STYLE.sr, STYLE.sg, STYLE.sb, math.floor(STYLE.sa * am))
        if STYLE.blur then
            render.blur(x, y, w, h, math.max(1, math.floor(4 * scale + 0.5)))
        end
        render.rect_filled(x, y, w, h, color(STYLE.or_, STYLE.og_, STYLE.ob_, math.floor(STYLE.oa_ * am)), rounding)
        if p > 0.002 then
            render.rect_filled(x, y, w, h, color(cr, cg, cb, math.floor(ca * p * 0.92 * am)), rounding)
        end
        local tw = text_w(f.key, f.key_size, legend, f.key_size * 0.6)
        local ty = y + (h - f.key_h) * 0.5
        render.text(math.floor(x + (w - tw) * 0.5 + 0.5), math.floor(ty + 0.5), color(255, 255, 255, math.floor(244 * am)), legend, nil, f.key_size, f.key)
    end

    local cps_prev = { false, false }
    local cps_hist = { {}, {} }
    local cps_val = { 0, 0 }

    local function cps_track(now, idx, down)
        local h = cps_hist[idx]
        if down and not cps_prev[idx] then
            h[#h + 1] = now
        end
        cps_prev[idx] = down
        local cut = now - 1.0
        local k = 0
        local w = 0
        for i = 1, #h do
            local t = h[i]
            if t >= cut then
                k = k + 1
                w = w + 1
                h[w] = t
            end
        end
        while #h > w do
            h[#h] = nil
        end
        cps_val[idx] = k
    end

    local function draw_cps_num(val, font, size, cx, y, clr, hw)
        local txt = tostring(val)
        local tw = text_w(font, size, txt, hw)
        render.text(math.floor(cx - tw * 0.5 + 0.5), y, clr, txt, nil, size, font)
    end

    local function draw_cps(x, y, w, h, scale, f, lv, rv, am)
        local rounding = math.floor(11 * scale + 0.5)
        soft_edge(x, y, w, h, rounding, scale, 4, STYLE.sr, STYLE.sg, STYLE.sb, math.floor(STYLE.sa * am))
        if STYLE.blur then
            render.blur(x, y, w, h, math.max(1, math.floor(4 * scale + 0.5)))
        end
        render.rect_filled(x, y, w, h, color(STYLE.or_, STYLE.og_, STYLE.ob_, math.floor(STYLE.oa_ * am)), rounding)
        local cx = x + w * 0.5
        local hh = math.floor(h * 0.56 + 0.5)
        local top = y + math.floor((h - hh) * 0.5 + 0.5)
        local fl = math.max(2, math.floor(4 * scale + 0.5))
        if fl * 2 > hh - 2 then
            fl = math.max(1, math.floor((hh - 2) * 0.5))
        end
        local dw = math.max(1, math.floor(scale + 0.5))
        local mid = hh - fl * 2
        render.rect_filled(cx, top + fl, dw, mid, color(238, 242, 238, math.floor(150 * am)), 0)
        for i = 1, fl do
            local al = math.floor(150 * am * (i / (fl + 1)))
            render.rect_filled(cx, top + i - 1, dw, 1, color(238, 242, 238, al), 0)
            render.rect_filled(cx, top + hh - i, dw, 1, color(238, 242, 238, al), 0)
        end
        local clr = color(240, 244, 240, math.floor(236 * am))
        local ty = y + math.floor((h - f.cps_h) * 0.5 + 0.5)
        draw_cps_num(lv, f.cps, f.cps_size, x + w * 0.25, ty, clr, f.cps_h)
        draw_cps_num(rv, f.cps, f.cps_size, x + w * 0.75, ty, clr, f.cps_h)
    end

    local function draw_keystrokes(dt, scale, f, sw_, sh_, down, am)
        local ks = math.floor(40 * scale + 0.5)
        local gap = math.floor(6 * scale + 0.5)
        local w = ks * 3 + gap * 2
        local h_move = ks * 2 + gap
        local mv = not UI.k_move
        local jp = not UI.k_jump
        local ms = not UI.k_mouse
        local cp = not UI.k_cps
        local blocks = 0
        if mv then blocks = blocks + 1 end
        if jp then blocks = blocks + 1 end
        if ms then blocks = blocks + 1 end
        if cp then blocks = blocks + 1 end
        if blocks <= 0 then return end
        local h = 0
        if mv then h = h + h_move end
        if jp then h = h + ks end
        if ms then h = h + ks end
        if cp then h = h + ks end
        h = h + gap * (blocks - 1)
        local x, y = resolve_drag(drag_keys, POS_KEYS, sw_, sh_, w, h, 40, sh_ - h - 130)
        for i = 1, 5 do
            local target = down[i] and 1 or 0
            local p = key_p[i]
            if target > p then
                p = p + dt / PRESS_IN
            elseif target < p then
                p = p - dt / PRESS_OUT
            end
            if p > 1 then p = 1 elseif p < 0 then p = 0 end
            key_p[i] = p
        end
        for i = 1, 2 do
            local target = down[5 + i] and 1 or 0
            local p = mouse_p[i]
            if target > p then
                p = p + dt / 0.05
            elseif target < p then
                p = p - dt / 0.10
            end
            if p > 1 then p = 1 elseif p < 0 then p = 0 end
            mouse_p[i] = p
        end
        local r, g, b, a = UI.r, UI.g, UI.b, UI.a
        local cy = y
        if mv then
            draw_key(x + math.floor((w - ks) * 0.5), cy, ks, ks, "W", key_p[1], false, scale, f, r, g, b, a, am)
            draw_key(x, cy + ks + gap, ks, ks, "A", key_p[2], false, scale, f, r, g, b, a, am)
            draw_key(x + ks + gap, cy + ks + gap, ks, ks, "S", key_p[3], false, scale, f, r, g, b, a, am)
            draw_key(x + (ks + gap) * 2, cy + ks + gap, ks, ks, "D", key_p[4], false, scale, f, r, g, b, a, am)
            cy = cy + h_move + gap
        end
        if jp then
            draw_key(x, cy, w, ks, "", key_p[5], true, scale, f, r, g, b, a, am)
            cy = cy + ks + gap
        end
        if ms then
            local bw = math.floor((w - gap) * 0.5)
            draw_mouse(x, cy, bw, ks, "LMB", mouse_p[1], scale, f, r, g, b, a, am)
            draw_mouse(x + bw + gap, cy, bw, ks, "RMB", mouse_p[2], scale, f, r, g, b, a, am)
            cy = cy + ks + gap
        end
        if cp then
            draw_cps(x, cy, w, ks, scale, f, cps_val[1], cps_val[2], am)
        end
    end

    local icon_set = nil
    local icon_cache = {}
    local HAS_ICONS = false

    local function build_icon_set()
        if icon_set ~= nil then return end
        icon_set = {}
        local ok, list = pcall(render.icons)
        if ok and type(list) == "table" then
            for i = 1, #list do
                local nm = tostring(list[i])
                icon_set[string.lower(nm)] = nm
            end
        end
        for _, probe in ipairs({
            "weapon_ak47", "ak47", "weapon_knife", "knife",
            "weapon_hegrenade", "hegrenade", "weapon_flashbang", "flashbang",
            "weapon_smokegrenade", "smokegrenade", "weapon_molotov", "molotov",
            "weapon_taser", "taser", "item_kevlar",
        }) do
            if icon_set[probe] ~= nil then
                HAS_ICONS = true
                break
            end
        end
    end

    local function weapon_icon(names, size)
        if not HAS_ICONS then return nil end
        for i = 1, #names do
            local real = icon_set[string.lower(names[i])]
            if real ~= nil then
                local key = real .. "|" .. tostring(size)
                local hit = icon_cache[key]
                if hit == nil then
                    local ok, t = pcall(render.icon, real, size)
                    hit = (ok and t) or false
                    icon_cache[key] = hit
                end
                if hit then return hit end
            end
        end
        return nil
    end

    local function icon_dims(tex, s)
        local w, h = s, s
        local ok, tw_, th_ = pcall(function() return tex:size() end)
        if ok and tonumber(tw_) ~= nil and tonumber(th_) ~= nil and tw_ > 0 and th_ > 0 then
            if tw_ >= th_ then
                w = s
                h = s * th_ / tw_
            else
                h = s
                w = s * tw_ / th_
            end
        end
        return w, h
    end

    local function W(name, rank, short, pord) return { name, rank, short or name, pord } end
    local WEAPONS = {
        ak47 = W("AK-47", 1), aug = W("AUG", 1), famas = W("法玛斯", 1),
        galilar = W("加利尔 AR", 1), m4a1 = W("M4A4", 1), sg556 = W("SG 553", 1),
        m4a1_silencer = W("M4A1 消音型", 1), m4a1silencer = W("M4A1 消音型", 1),
        awp = W("AWP", 1), g3sg1 = W("G3SG1", 1), scar20 = W("SCAR-20", 1), ssg08 = W("SSG 08", 1),
        mac10 = W("MAC-10", 1), mp5sd = W("MP5-SD", 1), mp7 = W("MP7", 1), mp9 = W("MP9", 1),
        bizon = W("PP-野牛", 1), p90 = W("P90", 1), ump45 = W("UMP-45", 1),
        m249 = W("M249", 1), negev = W("内格夫", 1), nova = W("新星", 1),
        sawedoff = W("截短霰弹枪", 1), xm1014 = W("XM1014", 1), mag7 = W("MAG-7", 1),
        deagle = W("沙漠之鹰", 2), elite = W("双持贝瑞塔", 2), fiveseven = W("FN57", 2),
        glock = W("格洛克 18 型", 2), p250 = W("P250", 2), tec9 = W("Tec-9", 2),
        usp_silencer = W("USP 消音型", 2), uspsilencer = W("USP 消音型", 2),
        cz75a = W("CZ75", 2), revolver = W("R8 左轮手枪", 2), hkp2000 = W("P2000", 2),
        hegrenade = W("手雷", 9, "手雷", 4), flashbang = W("闪光弹", 9, "闪光", 3),
        smokegrenade = W("烟雾弹", 9, "烟雾", 1), decoygrenade = W("诱饵弹", 9, "诱饵", 2),
        decoy = W("诱饵弹", 9, "诱饵", 2),
        molotovgrenade = W("燃烧瓶", 9, "火瓶", 0), molotov = W("燃烧瓶", 9, "火瓶", 0),
        incgrenade = W("燃烧弹", 9, "燃烧", 0), incendiarygrenade = W("燃烧弹", 9, "燃烧", 0),
        tagrenade = W("探测手雷", 9, "探测", 6), snowball = W("雪球", 9, "雪球", 7),
        c4 = W("C4", 9, "C4", 8),
        taser = W("电击枪", 3), zeusx27 = W("电击枪", 3), zeus = W("电击枪", 3),
        defuser = W("拆弹钳", 9, "钳子", 9), defusekit = W("拆弹钳", 9, "钳子", 9),
        knife = W("匕首", 3), knife_t = W("T 匕首", 3), knife_ct = W("CT 匕首", 3),
        bayonet = W("刺刀", 3),
        knife_karambit = W("爪子刀", 3), knife_m9_bayonet = W("M9 刺刀", 3),
        knife_flip = W("折刀", 3), knife_gut = W("穿肠刀", 3),
        knife_butterfly = W("蝴蝶刀", 3), knife_falchion = W("弯刀", 3),
        knife_huntsman = W("猎杀者匕首", 3), knife_navaja = W("折叠刀", 3),
        knife_stiletto = W("短剑", 3), knife_talon = W("鹰爪刀", 3),
        knife_ursus = W("熊刀", 3), knife_skeleton = W("骷髅匕首", 3),
        knife_classic = W("经典匕首", 3), knife_paracord = W("伞绳匕首", 3),
        knife_survival = W("求生匕首", 3), knife_canis = W("犬齿匕首", 3),
        knife_voss = W("沃斯匕首", 3), knife_kukri = W("廓尔喀刀", 3),
        knife_cord = W("绳索匕首", 3), knife_outdoor = W("户外匕首", 3),
        knife_trench = W("战壕刀", 3), knife_push = W("推匕首", 3),
        knife_gypsy = W("吉普赛匕首", 3), knife_skinfix = W("匕首", 3),
        knife_default = W("匕首", 3),
    }

    local ICON_ALIAS = {
        molotovgrenade = { "molotov", "weapon_molotov", "molotov_grenade", "fire" },
        molotov = { "molotov", "weapon_molotov", "molotov_grenade", "fire" },
        incgrenade = { "incendiarygrenade", "incgrenade", "weapon_incendiarygrenade", "incendiary" },
        incendiarygrenade = { "incendiarygrenade", "incgrenade", "weapon_incendiarygrenade", "incendiary" },
        hegrenade = { "hegrenade", "he_grenade" },
        flashbang = { "flashbang", "flash_bang" },
        smokegrenade = { "smokegrenade", "smoke_grenade" },
        decoygrenade = { "decoygrenade", "decoy" },
        decoy = { "decoygrenade", "decoy" },
        defuser = { "defuser", "weapon_defuser", "defusekit", "kit_defuser" },
        defusekit = { "defuser", "weapon_defuser", "defusekit", "kit_defuser" },
        taser = { "taser", "zeus", "weapon_taser", "zeus_x27" },
        zeusx27 = { "taser", "zeus", "weapon_taser", "zeus_x27" },
        zeus = { "taser", "zeus", "weapon_taser", "zeus_x27" },
        knife = { "knife", "weapon_knife", "knife_default" },
        knife_t = { "knife", "weapon_knife", "knife_default" },
        knife_ct = { "knife", "weapon_knife", "knife_default" },
        knife_karambit = { "weapon_knife_karambit", "knife_karambit", "knife", "weapon_knife" },
        knife_m9_bayonet = { "weapon_knife_m9_bayonet", "knife_m9_bayonet", "knife", "weapon_knife" },
        knife_bayonet = { "weapon_knife_bayonet", "knife_bayonet", "knife", "weapon_knife" },
        knife_flip = { "weapon_knife_flip", "knife_flip", "knife", "weapon_knife" },
        knife_gut = { "weapon_knife_gut", "knife_gut", "knife", "weapon_knife" },
        knife_butterfly = { "weapon_knife_butterfly", "knife_butterfly", "knife", "weapon_knife" },
        knife_falchion = { "weapon_knife_falchion", "knife_falchion", "knife", "weapon_knife" },
        knife_huntsman = { "weapon_knife_huntsman", "knife_huntsman", "knife", "weapon_knife" },
        knife_navaja = { "weapon_knife_navaja", "knife_navaja", "knife", "weapon_knife" },
        knife_stiletto = { "weapon_knife_stiletto", "knife_stiletto", "knife", "weapon_knife" },
        knife_talon = { "weapon_knife_talon", "knife_talon", "knife", "weapon_knife" },
        knife_ursus = { "weapon_knife_ursus", "knife_ursus", "knife", "weapon_knife" },
        knife_skeleton = { "weapon_knife_skeleton", "knife_skeleton", "knife", "weapon_knife" },
        knife_classic = { "weapon_knife_classic", "knife_classic", "knife", "weapon_knife" },
        knife_paracord = { "weapon_knife_paracord", "knife_paracord", "knife", "weapon_knife" },
        knife_survival = { "weapon_knife_survival", "knife_survival", "knife", "weapon_knife" },
        knife_canis = { "weapon_knife_canis", "knife_canis", "knife", "weapon_knife" },
        knife_voss = { "weapon_knife_voss", "knife_voss", "knife", "weapon_knife" },
        knife_kukri = { "weapon_knife_kukri", "knife_kukri", "knife", "weapon_knife" },
        knife_cord = { "weapon_knife_cord", "knife_cord", "knife", "weapon_knife" },
        knife_outdoor = { "weapon_knife_outdoor", "knife_outdoor", "knife", "weapon_knife" },
        knife_trench = { "weapon_knife_trench", "knife_trench", "knife", "weapon_knife" },
        knife_push = { "weapon_knife_push", "knife_push", "knife", "weapon_knife" },
        knife_gypsy = { "weapon_knife_gypsy", "knife_gypsy", "knife", "weapon_knife" },
        knife_skinfix = { "weapon_knife_skinfix", "knife_skinfix", "knife", "weapon_knife" },
        knife_default = { "knife", "weapon_knife", "knife_default" },
        c4 = { "c4", "weapon_c4", "c4_explosive" },
    }

    local function norm_cls(cls)
        local s = string.lower(tostring(cls or ""))
        s = s:gsub("^c_?", "")
        s = s:gsub("^weapon_?", "")
        return s
    end

    local function weapon_meta(s)
        local w = WEAPONS[s]
        if w ~= nil then return w[1], w[2], w[3], w[4] end
        if string.find(s, "molotov", 1, true) ~= nil or string.find(s, "incendiary", 1, true) ~= nil then
            return "燃烧瓶", 9, "火瓶", 0
        end
        if string.find(s, "hegrenade", 1, true) ~= nil then return "手雷", 9, "手雷", 4 end
        if string.find(s, "flash", 1, true) ~= nil then return "闪光弹", 9, "闪光", 3 end
        if string.find(s, "smoke", 1, true) ~= nil then return "烟雾弹", 9, "烟雾", 1 end
        if string.find(s, "decoy", 1, true) ~= nil then return "诱饵弹", 9, "诱饵", 2 end
        if string.find(s, "tagrenade", 1, true) ~= nil or string.find(s, "sonar", 1, true) ~= nil then
            return "探测手雷", 9, "探测", 6
        end
        if string.find(s, "snowball", 1, true) ~= nil then return "雪球", 9, "雪球", 7 end
        if string.find(s, "defus", 1, true) ~= nil then return "拆弹钳", 9, "钳子", 9 end
        if string.find(s, "knife", 1, true) ~= nil or string.find(s, "bayonet", 1, true) ~= nil then
            -- 尝试从字符串中提取具体刀型：匹配 knife_xxx 或 xxx_bayonet
            local kn = string.match(s, "knife[_%-]?([%w]+)")
            if kn and kn ~= "" then
                local candidate = "knife_" .. kn
                if WEAPONS[candidate] then
                    local cw = WEAPONS[candidate]
                    return cw[1], cw[2], cw[3], cw[4]
                end
            end
            local by = string.match(s, "([%w]+)[_%-]?bayonet")
            if by and by ~= "" then
                local candidate = by .. "_bayonet"
                if WEAPONS[candidate] then
                    local cw = WEAPONS[candidate]
                    return cw[1], cw[2], cw[3], cw[4]
                end
            end
            return "匕首", 3, "匕首"
        end
        if string.find(s, "taser", 1, true) ~= nil or string.find(s, "zeus", 1, true) ~= nil then
            return "电击枪", 3, "电击枪"
        end
        return string.upper(s), 4, string.upper(s)
    end

    local function wclassify(w, cls_short)
        local ok, info = pcall(function() return w:weapon_info() end)
        if ok and type(info) == "table" then
            local nm = string.lower(tostring(info.name or ""))
            nm = nm:gsub("^weapon_?", "")
            if nm ~= "" and nm ~= "unknown" and nm:find("%s") == nil and nm:match("^%d+$") == nil then
                return nm
            end
        end
        return cls_short
    end

    local function get_ammo(w)
        local ok, info = pcall(function() return w:weapon_info() end)
        if ok and type(info) == "table" then
            return num(info.clip, -1), num(info.reserve, -1)
        end
        local clip = -1
        local okc, c = pcall(function() return w:get("CBasePlayerWeapon", "m_iClip1", "int") end)
        if okc then clip = num(c, -1) end
        local res = -1
        local okr, r = pcall(function() return w:get("CBasePlayerWeapon", "m_iPrimaryReserveAmmoCount", "int") end)
        if okr then res = num(r, -1) end
        return clip, res
    end

    local rolls = {}

    local function split_ammo(txt)
        local p = string.find(txt, "/", 1, true)
        if p == nil then return txt, "" end
        return txt:sub(1, p - 1), txt:sub(p + 1)
    end

    local function roll(key, text)
        local cc, cr = split_ammo(text or "")
        local s = rolls[key]
        if s == nil then
            s = { pc = cc, pr = cr, cc = cc, cr = cr, t = 1 }
            rolls[key] = s
            return s
        end
        if cc ~= s.cc or cr ~= s.cr then
            s.pc = s.cc
            s.pr = s.cr
            s.t = 0
        end
        s.cc = cc
        s.cr = cr
        return s
    end

    local function roll_step(s, dt)
        if s.t < 1 then
            s.t = s.t + dt / ROLL_TIME
            if s.t > 1 then s.t = 1 end
        end
    end

    local function cols_right(font, size, cur, prev, right, y, clr, line_h, top, bottom, t)
        local nc = #cur
        local np = #prev
        local lim = nc
        if np > lim then lim = np end
        local fb = line_h * 0.5
        local edge = right
        for k = 1, lim do
            local c = cur:sub(nc - k + 1, nc - k + 1)
            local p = prev:sub(np - k + 1, np - k + 1)
            local cw = text_w(font, size, c, fb)
            local pw = text_w(font, size, p, fb)
            local cell = cw
            if pw > cell then cell = pw end
            local px = edge - cell
            if c == p or c == "/" then
                if c ~= "" then
                    render.text(px, y, clr, c, nil, size, font)
                end
            else
                render.clip_push(px - 1, top, cell + 3, bottom - top)
                if p ~= "" then
                    render.text(px, y - line_h * t, clr, p, nil, size, font)
                end
                if c ~= "" then
                    render.text(px, y + line_h * (1 - t), clr, c, nil, size, font)
                end
                render.clip_pop()
            end
            edge = edge - cell
        end
    end

    local function cols_left(font, size, cur, prev, x, y, clr, line_h, top, bottom, t)
        local nc = #cur
        local np = #prev
        local lim = nc
        if np > lim then lim = np end
        local fb = line_h * 0.5
        local px = x
        for k = 1, lim do
            local c = cur:sub(k, k)
            local p = prev:sub(k, k)
            local cw = text_w(font, size, c, fb)
            local pw = text_w(font, size, p, fb)
            local cell = cw
            if pw > cell then cell = pw end
            if c == p or c == "/" then
                if c ~= "" then
                    render.text(px, y, clr, c, nil, size, font)
                end
            else
                render.clip_push(px - 1, top, cell + 3, bottom - top)
                if p ~= "" then
                    render.text(px, y - line_h * t, clr, p, nil, size, font)
                end
                if c ~= "" then
                    render.text(px, y + line_h * (1 - t), clr, c, nil, size, font)
                end
                render.clip_pop()
            end
            px = px + cell
        end
    end

    local function draw_ammo(s, font, size, x, y, clr, line_h, height)
        local cc = s.cc or ""
        local cr = s.cr or ""
        local pc = s.pc or cc
        local pr = s.pr or cr
        local fb = line_h * 0.5
        local wcc = text_w(font, size, cc, fb)
        local sw = text_w(font, size, "/", fb)
        local top = y - 1
        local bottom = y + height + 1
        local t = s.t
        if t >= 1 or (cc == pc and cr == pr) then
            render.text(x, y, clr, cc .. "/" .. cr, nil, size, font)
            return
        end
        local wpc = text_w(font, size, pc, fb)
        local cwid = wpc + (wcc - wpc) * t
        cols_right(font, size, cc, pc, x + cwid, y, clr, line_h, top, bottom, t)
        render.text(x + cwid, y, clr, "/", nil, size, font)
        cols_left(font, size, cr, pr, x + cwid + sw, y, clr, line_h, top, bottom, t)
    end

    local row_map = {}
    local rows = {}
    local row_state = { inner = 0, nrow = 0, nprop = 0 }
    local name_w_cache = {}
    local wgen = ""
    local panim = { w = 0, h = 0, on = false }

    local function collect_weapons(me, f, dt)
        if wgen ~= f.tag then
            wgen = f.tag
            name_w_cache = {}
            for _, r in pairs(row_map) do r.aw = 0 end
        end
        local items = {}
        local list = me:weapons()
        if type(list) == "table" then
            if #list > 0 then
                for i = 1, #list do items[i] = list[i] end
            else
                for _, v in pairs(list) do items[#items + 1] = v end
            end
        end
        for _, row in pairs(row_map) do row.seen = false end
        for i = 1, #items do
            local w = items[i]
            if type(w) == "number" then
                local oke, e = pcall(entity.from_handle, w)
                if oke then w = e else w = nil end
            end
            if w ~= nil then
                local ok, raw_cls = pcall(function() return w:class_name() end)
                if ok and type(raw_cls) == "string" and raw_cls ~= "" then
                    local s = wclassify(w, norm_cls(raw_cls))
                    local row = row_map[s]
                    if row == nil then
                        local nm, rank, short, pord = weapon_meta(s)
                        local is_knife = string.find(s, "knife", 1, true) ~= nil
                            or string.find(s, "bayonet", 1, true) ~= nil
                        local is_taser = string.find(s, "taser", 1, true) ~= nil
                            or string.find(s, "zeus", 1, true) ~= nil
                        local names_base = { "weapon_" .. s, s, "weapon" .. s, "item_" .. s, raw_cls }
                        -- raw_cls 去 C / CWeapon / weapon_ 前缀的变体
                        local raw_stripped = string.lower(tostring(raw_cls or ''))
                            :gsub('^cweapon', ''):gsub('^c', ''):gsub('^weapon_', '')
                        if raw_stripped ~= '' then
                            names_base[#names_base + 1] = raw_stripped
                            names_base[#names_base + 1] = 'weapon_' .. raw_stripped
                        end
                        row = { sid = s, pres = 0, miss = 0, slot = i - 1, pslot = 0, selp = 0,
                                ammo = "", aw = 0, clip = -1, reserve = -1,
                                name = nm, short = short, rank = rank, strip = rank == 9,
                                knife = is_knife, taser = is_taser,
                                icon_names = names_base }
                        local al = ICON_ALIAS[s]
                        if al ~= nil then
                            for k = 1, #al do row.icon_names[#row.icon_names + 1] = al[k] end
                        end
                        row.show = (rank >= 1 and rank <= 3)
                        row.pord = pord or i
                        local nw = name_w_cache[row.name]
                        if nw == nil then
                            nw = text_w(f.name, f.name_size, row.name, 60)
                            name_w_cache[row.name] = nw
                        end
                        row.name_w = nw
                        row.key = s .. "#ammo"
                        row_map[s] = row
                    end
                    row.seen = true
                    row.ent = w
                end
            end
        end
        local act_s = nil
        local oka, act = pcall(function() return me:weapon() end)
        if oka and act ~= nil then
            local okc, ac = pcall(function() return act:class_name() end)
            if okc and type(ac) == "string" and ac ~= "" then act_s = wclassify(act, norm_cls(ac)) end
        end
        local dead = nil
        local kin = dt / 0.10
        local kout = dt / 0.12
        for s, row in pairs(row_map) do
            local tgt = 1
            if not row.seen then
                row.miss = (row.miss or 0) + dt
                if row.miss > 0.12 then tgt = 0 end
            else
                row.miss = 0
            end
            if tgt > row.pres then
                row.pres = row.pres + kin
                if row.pres > 1 then row.pres = 1 end
            elseif tgt < row.pres then
                row.pres = row.pres - kout
                if row.pres < 0 then row.pres = 0 end
            end
            if row.pres <= 0.004 and not row.seen then
                if dead == nil then dead = {} end
                dead[#dead + 1] = s
            end
        end
        if dead ~= nil then
            for i = 1, #dead do
                row_map[dead[i]] = nil
            end
        end
        local tmp = {}
        local n = 0
        for _, row in pairs(row_map) do
            n = n + 1
            tmp[n] = row
        end
        table.sort(tmp, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.rank == 9 and a.pord ~= b.pord then return a.pord < b.pord end
            return a.name < b.name
        end)
        for i = 1, n do
            rows[i] = tmp[i]
            tmp[i] = nil
        end
        while #rows > n do
            rows[#rows] = nil
        end
        local k_idx = nil
        local t_idx = nil
        for i = 1, n do
            local row = rows[i]
            if row ~= nil then
                if row.knife and k_idx == nil then k_idx = i end
                if row.taser and t_idx == nil then t_idx = i end
            end
        end
        if k_idx ~= nil and t_idx ~= nil and t_idx ~= k_idx + 1 then
            local tr = rows[t_idx]
            table.remove(rows, t_idx)
            if t_idx < k_idx then k_idx = k_idx - 1 end
            table.insert(rows, k_idx + 1, tr)
        end
        local nrow, nprop = 0, 0
        local widest = 0
        local move = dt / 0.08
        if move > 1 then move = 1 end
        local ammo_w = 0
        for i = 1, n do
            local row = rows[i]
            if row.strip then
                nprop = nprop + 1
                local tgt = nprop - 1
                if row.pslot == nil then
                    row.pslot = tgt
                else
                    row.pslot = row.pslot + (tgt - row.pslot) * move
                    if math.abs(tgt - row.pslot) < 0.01 then row.pslot = tgt end
                end
            elseif row.show then
                nrow = nrow + 1
                local tgt = nrow - 1
                row.visible_idx = tgt
                if row.slot == nil then
                    row.slot = tgt
                else
                    row.slot = row.slot + (tgt - row.slot) * move
                    if math.abs(tgt - row.slot) < 0.01 then row.slot = tgt end
                end
            end
            row.sel = act_s ~= nil and row.sid == act_s
            if row.seen and row.show then
                local c, rv = get_ammo(row.ent)
                c = num(c, -1)
                rv = num(rv, -1)
                if c >= 0 then
                    row.clip = math.floor(c)
                    if rv < 0 then rv = 0 end
                    row.reserve = math.floor(rv)
                    if row.fc ~= row.clip or row.fr ~= row.reserve then
                        row.fc = row.clip
                        row.fr = row.reserve
                        local old_txt = row.ammo
                        row.ammo = string.format("%d/%d", row.clip, row.reserve)
                        local w1 = text_w(f.mono, f.mono_size, row.ammo, f.adv)
                        local w2 = text_w(f.mono, f.mono_size, old_txt, f.adv)
                        if w2 > w1 then w1 = w2 end
                        if w1 > (row.aw or 0) then row.aw = w1 end
                    end
                end
            end
            local rw = row.name_w or 0
            if rw > widest then widest = rw end
            local aw = row.aw or 0
            if aw > ammo_w then ammo_w = aw end
        end
        local inner = widest
        if ammo_w > inner then inner = ammo_w end
        row_state.inner = inner
        row_state.nrow = nrow
        row_state.nprop = nprop
    end

    local function draw_weapons(dt, scale, f, sw_, sh_, am)
        build_icon_set()
        local me = entity.local_pawn()
        if me == nil then return end
        collect_weapons(me, f, dt)
        local nws = row_state.nrow or 0
        local nprop = row_state.nprop or 0
        local nrow = nws
        if nrow > 8 then nrow = 8 end
        if nrow + nprop <= 0 then return end
        local lgap = math.floor(scale + 0.5)
        local row_h = math.floor(f.name_h + f.mono_h + lgap + 9 * scale + 0.5)
        local pad = math.floor(9 * scale + 0.5)
        local gap = math.floor(6 * scale + 0.5)
        local slot_w = math.floor(34 * scale + 0.5)
        local slot_gap = math.floor(6 * scale + 0.5)
        local strip_h = math.floor(row_h * 0.90 + 0.5)
        local strip_top = math.floor(4 * scale + 0.5)
        local icon_s = math.floor(row_h * 0.62 + 0.5)
        local icon_gap = math.floor(6 * scale + 0.5)
        local icon_w = HAS_ICONS and (icon_s + icon_gap) or 0
        local inner = math.floor(row_state.inner * 1.05 + 6) + icon_w
        local strip_w = 0
        if nprop > 0 then
            strip_w = nprop * slot_w + (nprop - 1) * slot_gap
            if strip_w > inner then inner = strip_w end
        end
        local w = pad * 2 + inner
        local h = pad * 2 + row_h * nrow
        if nprop > 0 then
            h = h + strip_h
            if nrow > 0 then h = h + strip_top end
        end
        if not panim.on or w > panim.w + 0.5 or h > panim.h + 0.5 or math.abs(w - panim.w) > 260 or math.abs(h - panim.h) > 260 then
            panim.w = w
            panim.h = h
            panim.on = true
        else
            local kk = dt / 0.08
            if kk > 1 then kk = 1 end
            panim.w = panim.w + (w - panim.w) * kk
            panim.h = panim.h + (h - panim.h) * kk
        end
        w = math.floor(panim.w + 0.5)
        h = math.floor(panim.h + 0.5)
        local x, y = resolve_drag(drag_weap, POS_WEAP, sw_, sh_, w, h, sw_ - w - 90, sh_ - h - 90)
        local rounding = math.floor(11 * scale + 0.5)
        soft_edge(x, y, w, h, rounding, scale, 5, STYLE.sr, STYLE.sg, STYLE.sb, math.floor(STYLE.sa * am))
        if STYLE.blur then
            render.blur(x, y, w, h, math.max(1, math.floor(4 * scale + 0.5)))
        end
        render.rect_filled(x, y, w, h, color(STYLE.or_, STYLE.og_, STYLE.ob_, math.floor(STYLE.oa_ * am)), rounding)
        local hl_r = math.max(2, math.floor(7 * scale + 0.5))
        local hl_ix = math.floor(pad * 0.4)
        local visible = {}
        local props = {}
        for i = 1, #rows do
            local row = rows[i]
            if row ~= nil then
                if row.show then visible[#visible + 1] = row end
                if row.strip then props[#props + 1] = row end
            end
        end
        for i = 1, #visible do
            local row = visible[i]
            local ry = math.floor(y + pad + (row.slot or 0) * row_h)
            local pa = (row.pres or 1) * am
            local sp = row.selp or 0
            if row.sel then
                sp = sp + dt / PRESS_IN
            else
                sp = sp - dt / PRESS_OUT
            end
            if sp > 1 then sp = 1 elseif sp < 0 then sp = 0 end
            row.selp = sp
            if sp > 0.004 then
                local e = 1 - (1 - sp) * (1 - sp)
                local cx = x + w * 0.5
                local cyr = ry + row_h * 0.5
                local hw = (w * 0.5 - hl_ix) * e
                local hh = row_h * 0.5 * e
                local rd2 = math.max(2, math.floor(hl_r * e + 0.5))
                render.rect_filled(cx - hw, cyr - hh, hw * 2, hh * 2, color(232, 240, 232, math.floor(34 * e * pa)), rd2)
            end
            if HAS_ICONS then
                local tex = weapon_icon(row.icon_names, icon_s)
                if tex ~= nil then
                    local iw, ih = icon_dims(tex, icon_s)
                    local iy = ry + math.floor((row_h - ih) * 0.5)
                    render.image(tex, x + pad + math.floor((icon_s - iw) * 0.5), iy, iw, ih,
                        color(STYLE.wir, STYLE.wig, STYLE.wib, math.floor(240 * pa)))
                end
            end
            local tx = x + pad + icon_w
            local ty
            if row.ammo ~= "" then
                ty = ry + math.floor((row_h - f.name_h - f.mono_h - lgap) * 0.5)
            else
                ty = ry + math.floor((row_h - f.name_h) * 0.5)
            end
            render.clip_push(tx, ry, w - pad * 2 - icon_w, row_h)
            render.text(tx, ty, color(STYLE.wtr, STYLE.wtg, STYLE.wtb, math.floor(242 * pa)), row.name, nil, f.name_size, f.name)
            render.clip_pop()
            if row.ammo ~= "" then
                local s = roll(row.key, row.ammo)
                roll_step(s, dt)
                local mono_y = ty + f.name_h + lgap
                draw_ammo(s, f.mono, f.mono_size, tx, mono_y, color(STYLE.wtr, STYLE.wtg, STYLE.wtb, math.floor(220 * pa)), f.mono_h, f.mono_h)
            end
        end
        if nprop > 0 then
            local throw_s = (UI.throw_s or 1)
            local throw_dx = (UI.throw_dx or 0) * scale
            local throw_dy = (UI.throw_dy or 0) * scale
            local strip_y = y + pad + row_h * nrow + throw_dy
            if nrow > 0 then strip_y = strip_y + strip_top end
            local sx0 = x + pad + math.floor((w - pad * 2 - strip_w) * 0.5) + throw_dx
            local cy = strip_y + strip_h * 0.5
            local box_h = math.floor(strip_h * 0.68 * throw_s)
            local prop_icon = math.floor(slot_w * 0.6 * throw_s + 0.5)
            local t_slot_w = math.floor(slot_w * throw_s + 0.5)
            local t_slot_gap = math.floor(slot_gap * throw_s + 0.5)
            for i = 1, #props do
                local row = props[i]
                local sx = sx0 + (row.pslot or 0) * (t_slot_w + t_slot_gap)
                    local pa = (row.pres or 1) * am
                    local sp = row.selp or 0
                    if row.sel then
                        sp = sp + dt / PRESS_IN
                    else
                        sp = sp - dt / PRESS_OUT
                    end
                    if sp > 1 then sp = 1 elseif sp < 0 then sp = 0 end
                    row.selp = sp
                    if sp > 0.004 then
                        local e = 1 - (1 - sp) * (1 - sp)
                        local cxs = sx + t_slot_w * 0.5
                        local hw = (t_slot_w * 0.5 + math.floor(2 * scale)) * e
                        local hh = box_h * 0.78 * e
                        local rd2 = math.max(2, math.floor(hl_r * e + 0.5))
                        render.rect_filled(cxs - hw, cy - hh, hw * 2, hh * 2, color(232, 240, 232, math.floor(34 * e * pa)), rd2)
                    end
                    local tex = HAS_ICONS and weapon_icon(row.icon_names, prop_icon) or nil
                    if tex ~= nil then
                        local iw, ih = icon_dims(tex, prop_icon)
                        render.image(tex, math.floor(sx + (t_slot_w - iw) * 0.5), math.floor(cy - ih * 0.5), iw, ih,
                            color(STYLE.wir, STYLE.wig, STYLE.wib, math.floor((row.sel and 250 or 198) * pa)))
                    else
                        local short = row.short or row.name
                        local fs_name = f.name_size * throw_s
                        local tw = text_w(f.name, fs_name, short, t_slot_w * 0.3)
                        local tcol = row.sel and color(STYLE.wtr, STYLE.wtg, STYLE.wtb, math.floor(250 * pa))
                            or color(STYLE.wtr, STYLE.wtr, STYLE.wtb, math.floor(198 * pa))
                        render.text(math.floor(sx + (t_slot_w - tw) * 0.5 + 0.5), math.floor(cy - f.mono_h * 0.5 + 0.5), tcol, short, nil, fs_name, f.name)
                    end
                    -- 投掷物中文名称（图标下方，小字体）
                    local pname = row.name
                    local shown = (tex == nil) and (row.short or row.name) or nil
                    if pname and pname ~= '' and pname ~= shown then
                        local pn_col = row.sel and color(STYLE.wtr, STYLE.wtg, STYLE.wtb, math.floor(220 * pa))
                            or color(STYLE.wtr, STYLE.wtg, STYLE.wtb, math.floor(170 * pa))
                        local pn_size = math.max(8, math.floor(9 * scale * throw_s + 0.5))
                        local pn_h = math.floor(pn_size * 1.1 + 0.5)
                        local pn_y = cy + box_h * 0.5 + 2 * scale * throw_s
                        local pn_w = text_w(f.name, pn_size, pname, t_slot_w * 0.95)
                        render.text(math.floor(sx + (t_slot_w - pn_w) * 0.5), math.floor(pn_y), pn_col, pname, nil, pn_size, f.name)
                    end
            end
        end
    end

    local DIM = { v = 0 }

    -- MC 主绘制帧（游戏 HUD 由统一 update_game_hud 处理）
    local function frame()
        local now = num(globals.realtime(), 0)
        local dt = num(globals.frametime(), 0.007)
        if dt <= 0 or dt > 0.5 then dt = 0.007 end
        UI.keys = sw_keys:get()
        UI.weap = sw_weap:get()
        local c = cp_pressed:get()
        if c ~= nil then
            UI.r = num(c.r, 255)
            UI.g = num(c.g, 205)
            UI.b = num(c.b, 253)
            UI.a = num(c.a, 255)
        end
        local hide = mc_hide:get()
        if type(hide) ~= "table" then hide = {} end
        UI.k_move = hide["移动"] == true
        UI.k_jump = hide["跳跃"] == true
        UI.k_mouse = hide["鼠标"] == true
        UI.k_cps = hide["CPS"] == true
        UI.ks = clamp(num(sl_ks:get(), 1), 0.5, 2.0)
        UI.ka = clamp(num(sl_ka:get(), 100), 20, 100) / 100
        UI.ws = clamp(num(sl_ws:get(), 1), 0.5, 2.0)
        UI.wa = clamp(num(sl_wa:get(), 100), 20, 100) / 100
        UI.throw_s = clamp(num(sl_throw_scale:get(), 1), 0.5, 3.0)
        UI.throw_dx = num(sl_throw_dx:get(), 0)
        UI.throw_dy = num(sl_throw_dy:get(), 0)
        local cs = cp_shadow:get()
        if cs ~= nil then
            STYLE.sr = num(cs.r, 0); STYLE.sg = num(cs.g, 0)
            STYLE.sb = num(cs.b, 0); STYLE.sa = num(cs.a, 90)
        end
        local co = cp_overlay:get()
        if co ~= nil then
            STYLE.or_ = num(co.r, 46); STYLE.og_ = num(co.g, 52)
            STYLE.ob_ = num(co.b, 46); STYLE.oa_ = num(co.a, 46)
        end
        STYLE.blur = sw_blur:get() ~= false
        local ci = cp_wicon:get()
        if ci ~= nil then
            STYLE.wir = num(ci.r, 255); STYLE.wig = num(ci.g, 255); STYLE.wib = num(ci.b, 255)
        end
        local ct = cp_wtext:get()
        if ct ~= nil then
            STYLE.wtr = num(ct.r, 252); STYLE.wtg = num(ct.g, 254); STYLE.wtb = num(ct.b, 252)
        end
        if not UI.keys and not UI.weap then return end
        local sw_, sh_ = render.screen_size()
        sw_ = num(sw_, 0)
        sh_ = num(sh_, 0)
        if sw_ <= 0 or sh_ <= 0 then return end
        input_poll(now)
        local dim_to = 1
        if not (drag_keys.on or drag_weap.on) then dim_to = 0 end
        DIM.v = DIM.v + (dim_to - DIM.v) * math.min(1, dt / 0.16)
        if DIM.v > 0.01 then
            render.rect_filled(0, 0, sw_, sh_, color(0, 0, 0, math.floor(132 * DIM.v)), 0)
        end
        local scale = scale_now(now)
        if UI.keys then
            down_buf[1] = input.key_down(KEY_W)
            down_buf[2] = input.key_down(KEY_A)
            down_buf[3] = input.key_down(KEY_S)
            down_buf[4] = input.key_down(KEY_D)
            down_buf[5] = input.key_down(KEY_SPACE)
            down_buf[6] = input.key_down(1)
            down_buf[7] = input.key_down(2)
            for i = 1, 7 do
                if down_buf[i] then
                    key_latch[i] = now + KEY_LATCH
                elseif now < key_latch[i] then
                    down_buf[i] = true
                end
            end
            cps_track(now, 1, down_buf[6])
            cps_track(now, 2, down_buf[7])
            local kq = math.floor(scale * UI.ks * 20 + 0.5) / 20
            draw_keystrokes(dt, kq, fonts(kq), sw_, sh_, down_buf, UI.ka)
        end
        if UI.weap then
            local wq = math.floor(scale * UI.ws * 20 + 0.5) / 20
            draw_weapons(dt, wq, fonts(wq), sw_, sh_, UI.wa)
        end
    end

    local last_err = 0
    local mc_err = nil

    local function guard_frame()
        local ok, err = pcall(frame)
        if not ok then
            local now = num(globals.realtime(), 0)
            if now - last_err > 5 then
                last_err = now
                mc_err = tostring(err)
                pcall(print, "[MC HUD] " .. tostring(err))
            end
        end
    end

    return {
        draw = guard_frame,
        get_err = function() return mc_err end,
    }
end)({
    sw_keys = sw_keys, mc_hide = mc_hide, cp_pressed = cp_pressed,
    sl_ks = sl_ks, sl_ka = sl_ka, sw_weap = sw_weap, sl_ws = sl_ws, sl_wa = sl_wa,
    sl_throw_scale = sl_throw_scale, sl_throw_dx = sl_throw_dx, sl_throw_dy = sl_throw_dy,
    cp_shadow = cp_shadow, cp_overlay = cp_overlay, sw_blur = sw_blur,
    cp_wicon = cp_wicon, cp_wtext = cp_wtext,
})

-- ════════════════════════════════════════════════════════════════
-- 统一 paint：始终跑游戏 HUD 控制；按总控件选择跑对应绘制
-- ════════════════════════════════════════════════════════════════
local paint_err = nil

-- 读取上次拖动保存的面板偏移
layout_load(U.ed, U.layout_store)

local function main_paint()
    local ok_hud, err_hud = pcall(HUD_SYS.update)
    if not ok_hud then
        paint_err = "HUD控制: " .. tostring(err_hud)
    end

    local apho = hud_selected("全境封锁HUD", 1)
    local mc   = hud_selected("MC HUD", 2)

    if apho then
        local ok, err = pcall(HUD_SYS.draw)
        if not ok then
            paint_err = "全境封锁HUD: " .. tostring(err)
        else
            paint_err = nil
        end
    end

    if mc then
        MC_SYS.draw()
    end

    if paint_err then
        render.text(24, 64, color(255, 80, 80), 'HUD 错误: ' .. tostring(paint_err), 's', 13)
    end
    local mc_err = MC_SYS.get_err()
    if mc_err then
        render.text(24, 82, color(255, 160, 80), 'MC HUD 错误: ' .. tostring(mc_err), 's', 13)
    end
end

events.on("paint", main_paint)

events.on("level_init", function()
    HUD_SYS.reset_tick()
    if HUD_SYS.is_hidden() then
        pcall(function() HUD_SYS.set_hidden(true) end)
    end
    pcall(function() HUD_SYS.apply_scale(U.hud_scale:get()) end)
end)

events.on("unload", function()
    if HUD_SYS.is_hidden() then
        pcall(function() HUD_SYS.set_hidden(false) end)
        HUD_SYS.set_hidden_flag(false)
    end
    pcall(function() HUD_SYS.apply_scale(1) end)
end)

print("[HUD Misc] 由Awa Subaru移植 (合并 APHRODITE 全息 HUD)")
print("[HUD Misc] 闲鱼：我是学生你懂我意思吧")
