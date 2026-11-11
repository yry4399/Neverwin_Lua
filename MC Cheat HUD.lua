-- MC Cheat HUD (Neverwin 移植版)
-- 原作: XFL.MC HUD (Neverlose CSGO)
-- 移植: Awa Subaru

ui.sidebar("MC Cheat HUD", "keyboard")

local tab = ui.tab("HUD")
local g_keys = tab:group("按键显示")
local g_weap = tab:group("武器状态")
local g_hud = tab:group("游戏 HUD")
local g_about = tab:group("关于")

local sw_keys = g_keys:checkbox("按键显示", false)
local mc_hide = g_keys:multi_combo("隐藏项目", { "移动", "跳跃", "鼠标", "CPS" })
local cp_pressed = g_keys:color("按下颜色", color(255, 205, 253, 255))
local sl_ks = g_keys:slider_float("按键缩放", 0.5, 2.0, 1.0, "%.2f")
local sl_ka = g_keys:slider_int("按键不透明度", 20, 100, 100)

local sw_weap = g_weap:checkbox("武器状态", false)
local sl_ws = g_weap:slider_float("面板缩放", 0.5, 2.0, 1.0, "%.2f")
local sl_wa = g_weap:slider_int("面板不透明度", 20, 100, 100)

local sw_hidew = g_hud:checkbox("隐藏原版武器栏", false)
local sw_hides = g_hud:checkbox("隐藏底部状态条", false)

local g_style = tab:group("外观")
local cp_shadow = g_style:color("投影颜色", color(0, 0, 0, 90))
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
g_about:label("由Awa Subaru移植")
g_about:label("鸣谢:小凤梨1337")

-- 系统浏览器打开链接（ffi ShellExecuteA → Shell32 → Steam 覆盖层兜底）
local shexec = nil
local function init_shexec()
    if shexec ~= nil then return end
    local ok_ffi, ffi = pcall(function() return rawget(_G, "ffi") end)
    if not ok_ffi or ffi == nil then
        shexec = false
        return
    end
    pcall(ffi.cdef, [[
        void * __stdcall ShellExecuteA(void *hwnd, const char *op, const char *file,
                                       const char *params, const char *dir, int show);
    ]])
    local fn
    pcall(function() fn = ffi.C.ShellExecuteA end)
    if not fn then
        local ns
        pcall(function() ns = ffi.load("Shell32") end)
        if ns then pcall(function() fn = ns.ShellExecuteA end) end
    end
    shexec = fn or false
end

local function open_url(url)
    init_shexec()
    if shexec then
        local ok, err = pcall(function() return shexec(nil, "open", url, nil, nil, 1) end)
        if ok then return end
        print("[MC Cheat HUD] ShellExecuteA 调用失败: " .. tostring(err))
    elseif shexec == false then
        print("[MC Cheat HUD] ffi 不可用，走 Steam 覆盖层回退")
    end
    local ok2, err2 = pcall(function() panorama.SteamOverlayAPI.OpenExternalBrowserURL(url) end)
    if not ok2 then
        print("[MC Cheat HUD] Steam 覆盖层打开也失败: " .. tostring(err2))
    end
end

g_about:button("闲鱼：我是学生你懂我意思吧", function()
    open_url("https://m.tb.cn/h.jS7Zhk2?tk=ZYFI6cX5T4D")
end)

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

-- 外观缓存：每帧从 cp_shadow / cp_overlay / cp_wicon / cp_wtext 读取，供所有 draw_* 共用
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

-- 柔和投影：从外到内逐层画实心圆角矩形（互相重叠），杜绝描边圆环与填充之间的缝隙
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

-- ── 游戏原版 HUD 隐藏（CS2 Panorama 面板 id，取自 HUD.lua 实测结果）─────────
local HUD_ID_WEAP = "HudBottomRight"              -- 右下武器栏
local HUD_ID_STATUS = "jsHudHealthArmorAmmoMore"  -- 底部血量/护甲/弹药状态条
local hud_hide = { on = false, last = -10, sig = "" }

local function pano_vis(ids, vis)
    local q = {}
    for i = 1, #ids do q[i] = '"' .. ids[i] .. '"' end
    local js = "(function(){var root=$.GetContextPanel();if(!root)return;var ids=["
        .. table.concat(q, ",") .. "];"
        .. "for(var i=0;i<ids.length;i++){var p=root.FindChildTraverse(ids[i]);"
        .. "if(p){p.style.visibility='" .. vis .. "';}}})();"
    pcall(panorama.run, js)
end

local function sync_hud_hide(now)
    local hw = sw_hidew:get()
    local hs = sw_hides:get()
    if not hw and not hs then
        if hud_hide.on then
            hud_hide.on = false
            hud_hide.sig = ""
            pano_vis({ HUD_ID_WEAP, HUD_ID_STATUS }, "visible")
        end
        return
    end
    local sig = (hw and "1" or "0") .. (hs and "1" or "0")
    local ids = {}
    if hw then ids[#ids + 1] = HUD_ID_WEAP end
    if hs then ids[#ids + 1] = HUD_ID_STATUS end
    if sig ~= hud_hide.sig then
        pano_vis({ HUD_ID_WEAP, HUD_ID_STATUS }, "visible")
        pano_vis(ids, "collapse")
        hud_hide.sig = sig
        hud_hide.on = true
        hud_hide.last = now
    elseif now - hud_hide.last > 1.0 then
        pano_vis(ids, "collapse")
        hud_hide.last = now
    end
end

-- ── 游戏内置图标（render.icons 表懒加载，paint 外不可用）────────────────────
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
    for _, probe in ipairs({ "weapon_ak47", "ak47", "weapon_knife", "knife" }) do
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

-- ── 武器分类表（key = 归一化短名）────────────────────────────────────────────
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
    knife = W("匕首", 3), knife_t = W("匕首", 3), bayonet = W("刺刀", 3),
}

-- 图标名别名：游戏内置图标名 ≠ 类名（如燃烧瓶图标叫 molotov 不叫 molotovgrenade）
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
    c4 = { "c4", "weapon_c4", "c4_explosive" },
}

-- class_name() 返回的是 schema 类名（CWeaponAK47 / CMolotovGrenade），
-- 也兼容 designer 名（weapon_ak47）：统一归一化成短名
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
        return "匕首", 3, "匕首"
    end
    if string.find(s, "taser", 1, true) ~= nil or string.find(s, "zeus", 1, true) ~= nil then
        return "电击枪", 3, "电击枪"
    end
    return string.upper(s), 4, string.upper(s)
end

-- 归一化 sid：优先用 weapon_info().name（能区分共用类名的武器，
-- 如 USP-S 与 P2000 都可能是 C_WeaponHKP2000），失败再用 class_name 归一化
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
                    row = { sid = s, pres = 0, miss = 0, slot = i - 1, pslot = 0, selp = 0,
                            ammo = "", aw = 0, clip = -1, reserve = -1,
                            name = nm, short = short, rank = rank, strip = rank == 9,
                            knife = is_knife, taser = is_taser,
                            icon_names = { "weapon_" .. s, s, "weapon" .. s, raw_cls } }
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
        local strip_y = y + pad + row_h * nrow
        if nrow > 0 then strip_y = strip_y + strip_top end
        local sx0 = x + pad + math.floor((w - pad * 2 - strip_w) * 0.5)
        local cy = strip_y + strip_h * 0.5
        local box_h = math.floor(strip_h * 0.68)
        local prop_icon = math.floor(slot_w * 0.6 + 0.5)
        for i = 1, #props do
            local row = props[i]
            local sx = sx0 + (row.pslot or 0) * (slot_w + slot_gap)
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
                    local cxs = sx + slot_w * 0.5
                    local hw = (slot_w * 0.5 + math.floor(2 * scale)) * e
                    local hh = box_h * 0.78 * e
                    local rd2 = math.max(2, math.floor(hl_r * e + 0.5))
                    render.rect_filled(cxs - hw, cy - hh, hw * 2, hh * 2, color(232, 240, 232, math.floor(34 * e * pa)), rd2)
                end
                local tex = HAS_ICONS and weapon_icon(row.icon_names, prop_icon) or nil
                if tex ~= nil then
                    local iw, ih = icon_dims(tex, prop_icon)
                    render.image(tex, math.floor(sx + (slot_w - iw) * 0.5), math.floor(cy - ih * 0.5), iw, ih,
                        color(STYLE.wir, STYLE.wig, STYLE.wib, math.floor((row.sel and 250 or 198) * pa)))
                else
                    local short = row.short or row.name
                    local tw = text_w(f.name, f.mono_size, short, slot_w * 0.3)
                    local tcol = row.sel and color(STYLE.wtr, STYLE.wtg, STYLE.wtb, math.floor(250 * pa))
                        or color(STYLE.wtr, STYLE.wtg, STYLE.wtb, math.floor(198 * pa))
                    render.text(math.floor(sx + (slot_w - tw) * 0.5 + 0.5), math.floor(cy - f.mono_h * 0.5 + 0.5), tcol, short, nil, f.mono_size, f.name)
                end
        end
    end
end

local DIM = { v = 0 }

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
    sync_hud_hide(now)
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
        -- 采样防抖：观察到按下后锁存 80ms，消除高频闪烁
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

local function guard_frame()
    local ok, err = pcall(frame)
    if not ok then
        local now = num(globals.realtime(), 0)
        if now - last_err > 5 then
            last_err = now
            pcall(print, "[MC HUD] " .. tostring(err))
        end
    end
end

events.on("paint", guard_frame)

events.on("level_init", function()
    hud_hide.last = -10
end)

events.on("unload", function()
    if hud_hide.on then
        pano_vis({ HUD_ID_WEAP, HUD_ID_STATUS }, "visible")
        hud_hide.on = false
    end
end)

print("[MC Cheat HUD] 由Awa Subaru移植")
print("[MC Cheat HUD] 闲鱼：我是学生你懂我意思吧")
