-- ============================================================================
-- XFL Misc（Neverwin 移植版）
-- 移植自 Neverlose CSGO 脚本 XFL.Misc V4.7.4
-- 包含功能：天使光环 / 移动拖尾 / 挂机防踢
-- 移植者: Awa Subaru / 闲鱼:我是学生你懂我意思吧
-- ============================================================================

print("由Awa Subaru移植")
print("闲鱼:我是学生你懂我意思吧")

-- ----------------------------------------------------------------------------
-- 共享工具
-- ----------------------------------------------------------------------------
local PI2 = math.pi * 2
local m_sin, m_cos = math.sin, math.cos
local m_floor, m_sqrt = math.floor, math.sqrt
local m_random = math.random

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function fade(c, scale)
    local a = m_floor(c.a * scale + 0.5)
    if a < 0 then a = 0 elseif a > 255 then a = 255 end
    return color(c.r, c.g, c.b, a)
end

-- render.world_to_screen 包装：Neverwin 返回 x, y | nil，统一成 {x, y} 点表
local function w2s(v)
    local x, y = render.world_to_screen(v)
    if x == nil then return nil end
    return { x = x, y = y }
end

local function line2(p, q, col, thick)
    render.line(p.x, p.y, q.x, q.y, col, thick or 1)
end

local function circle2(p, col, rad)
    render.circle_filled(p.x, p.y, rad, col, 16)
end

local function utf8_chars(str)
    local t, n = {}, 0
    for ch in string.gmatch(str, ".[\128-\191]*") do
        n = n + 1
        t[n] = ch
    end
    return t, n
end

-- combo:get() 兼容（索引或字符串）
local function combo_idx(ctrl, items)
    local v = ctrl:get()
    if type(v) == "number" then
        if v < 1 then return 1 end
        if v > #items then return #items end
        return v
    end
    for i = 1, #items do
        if items[i] == v then return i end
    end
    return 1
end

-- dt 计算（对齐原版 state.xfl_dt）
local function xfl_dt(last, max)
    local now = globals.realtime()
    local dt = last ~= nil and now - last or 0.016
    if dt <= 0 or dt > max then dt = 0.016 end
    return now, dt
end

-- 相机位置捕获（Neverwin 无 render.camera_position，用 override_view 拿真实相机原点）
local cam_pos = vector(0, 0, 0)
local has_cam = false
events.on("override_view", function(view)
    local o = view:origin()
    if o ~= nil then
        cam_pos = o
        has_cam = true
    end
end)

-- ----------------------------------------------------------------------------
-- UI
-- ----------------------------------------------------------------------------
ui.sidebar("Angel Misc", "image")
local main_tab = ui.tab("Angel Misc")
local g_halo = main_tab:group("天使光环")
local g_trail = main_tab:group("移动拖尾")
local g_afk = main_tab:group("挂机防踢")
local g_status = main_tab:group("状态")

-- ============================================================================
-- 天使光环
-- ============================================================================
do
    local HALO_STYLE = { "华丽", "简约", "文字" }

    local halo_enable = g_halo:checkbox("启用天使光环", false)
    local halo_style = g_halo:combo("样式", HALO_STYLE, 1)
    local lbl_base = g_halo:label("──────── 基础 ────────")
    local halo_color = g_halo:color("颜色", color(255, 174, 232, 255), true)
    local halo_alpha = g_halo:slider_int("透明度", 0, 255, 175)
    local halo_radius = g_halo:slider_int("半径", 5, 50, 14)
    local halo_height = g_halo:slider_int("高度偏移", -30, 30, 8)
    local halo_gradient = g_halo:checkbox("渐变", false)
    local halo_speed = g_halo:slider_int("渐变速度", 1, 50, 10)
    local halo_smooth = g_halo:checkbox("平滑", true)
    local halo_smooth_w = g_halo:slider_int("平滑量", 1, 20, 6)
    local lbl_pro = g_halo:label("──────── 华丽 ────────")
    local halo_glow = g_halo:slider_int("光环强度", 0, 100, 70)
    local halo_pulse = g_halo:checkbox("呼吸脉冲", true)
    local halo_twin = g_halo:checkbox("双环", false)
    local halo_ringspin = g_halo:slider_int("旋转速度", 0, 100, 40)
    local halo_star = g_halo:checkbox("流动星光", true)
    local halo_motes = g_halo:checkbox("圣光粒子", true)
    local lbl_text = g_halo:label("──────── 文字 ────────")
    local halo_txt = g_halo:text("文字内容", "XFL.Misc")
    local halo_tgap = g_halo:slider_int("文字间隔", 0, 60, 20)
    local halo_tsize = g_halo:slider_int("文字大小", 3, 20, 7)
    local halo_tspin = g_halo:slider_int("文字旋转速度", 0, 20, 5)
    local halo_thide = g_halo:checkbox("背面遮挡", true)

    local base_vis = { lbl_base, halo_color, halo_alpha, halo_radius, halo_height,
        halo_gradient, halo_speed, halo_smooth, halo_smooth_w }
    local pro_vis = { lbl_pro, halo_glow, halo_pulse, halo_twin, halo_ringspin,
        halo_star, halo_motes }
    local text_vis = { lbl_text, halo_txt, halo_tgap, halo_tsize, halo_tspin, halo_thide }

    local function halo_refresh()
        local on = halo_enable:get()
        local st = combo_idx(halo_style, HALO_STYLE)
        halo_style:visible(on)
        for i = 1, #base_vis do base_vis[i]:visible(on) end
        for i = 1, #pro_vis do pro_vis[i]:visible(on and st == 1) end
        for i = 1, #text_vis do text_vis[i]:visible(on and st == 3) end
    end
    halo_enable:callback(halo_refresh)
    halo_style:callback(halo_refresh)
    halo_refresh()

    -- 光环绘制辅助
    local FX_BX = vector(1, 0, 0)
    local FX_BY = vector(0, 1, 0)
    local GLOW_K = { 1.00, 1.11, 1.26 }
    local GLOW_A = { 1.00, 0.32, 0.14 }

    local function glow_poly(pts, cols, n, closed, glow)
        local cx, cy, cnt = 0, 0, 0
        for i = 1, n do
            local p = pts[i]
            if p ~= nil then
                cx = cx + p.x
                cy = cy + p.y
                cnt = cnt + 1
            end
        end
        if cnt == 0 then return end
        cx, cy = cx / cnt, cy / cnt
        local last = closed and n or (n - 1)
        if glow > 0.02 then
            for layer = 3, 2, -1 do
                local k = GLOW_K[layer]
                local a = GLOW_A[layer] * glow
                for i = 1, last do
                    local p, q = pts[i], pts[(i % n) + 1]
                    if p ~= nil and q ~= nil then
                        line2({ x = cx + (p.x - cx) * k, y = cy + (p.y - cy) * k },
                            { x = cx + (q.x - cx) * k, y = cy + (q.y - cy) * k },
                            fade(cols[i], a))
                    end
                end
            end
        end
        for i = 1, last do
            local p, q = pts[i], pts[(i % n) + 1]
            if p ~= nil and q ~= nil then line2(p, q, cols[i]) end
        end
    end

    local function ring(center, radius, base_col, opt)
        local segs = opt.segs or 40
        local wave = opt.wave or 0
        local phase = opt.phase or 0
        local cam = opt.cam
        local depth = opt.depth or 0.55
        local glow = opt.glow or 0
        local scale = opt.scale or 1
        local color_at = opt.color_at
        local pts, cols = {}, {}
        local dep, near_d, far_d = {}, nil, nil
        for i = 1, segs do
            local a = PI2 * (i - 1) / segs
            local r = radius
            if wave ~= 0 then r = radius * (1 + wave * m_sin(a * 3 + phase)) end
            local p = center + FX_BX * (m_cos(a) * r) + FX_BY * (m_sin(a) * r)
            pts[i] = w2s(p)
            if cam ~= nil then
                local d = (p - cam):length()
                dep[i] = d
                if near_d == nil or d < near_d then near_d = d end
                if far_d == nil or d > far_d then far_d = d end
            end
        end
        local span = (near_d ~= nil) and (far_d - near_d) or 0
        for i = 1, segs do
            local f = scale
            if span > 0.5 then f = f * (1 - depth * ((dep[i] - near_d) / span)) end
            if color_at ~= nil then
                cols[i] = color_at(PI2 * (i - 1) / segs, f)
            else
                cols[i] = fade(base_col, f)
            end
        end
        glow_poly(pts, cols, segs, true, glow)
    end

    local function ring_plain(center, radius, col, segs)
        segs = segs or 48
        local last = nil
        for i = 0, segs do
            local a = PI2 * i / segs
            local p = w2s(center + FX_BX * (m_cos(a) * radius) + FX_BY * (m_sin(a) * radius))
            if last ~= nil and p ~= nil then line2(last, p, col) end
            last = p
        end
    end

    local function mote_spawn(pool, maxn, x, y, z, radius, vlo, vhi)
        if #pool >= maxn then return end
        local a = m_random() * PI2
        local rr = radius * (0.45 + m_random() * 0.75)
        pool[#pool + 1] = {
            x = x + m_cos(a) * rr,
            y = y + m_sin(a) * rr,
            z = z + (m_random() - 0.5) * 6,
            vz = vlo + m_random() * (vhi - vlo),
            life = 0,
            max = 0.9 + m_random() * 1.2,
            size = 0.9 + m_random() * 1.1,
            ph = m_random() * PI2,
        }
    end

    local function mote_draw(pool, dt, col)
        for i = #pool, 1, -1 do
            local m = pool[i]
            m.life = m.life + dt
            if m.life >= m.max then
                table.remove(pool, i)
            else
                m.z = m.z + m.vz * dt
                local p = w2s(vector(m.x, m.y, m.z))
                if p ~= nil then
                    local k = m.life / m.max
                    local f = (1 - k) * (1 - k) * (0.55 + 0.45 * m_sin(m.life * 9 + m.ph))
                    if f > 0.03 then
                        local rad = m.size * (1 - k * 0.5)
                        if rad < 1 then rad = 1 end
                        circle2(p, fade(col, f * 0.12), rad * 3.0)
                        circle2(p, fade(col, f * 0.32), rad * 1.9)
                        circle2(p, fade(col, f), rad)
                    end
                end
            end
        end
    end

    -- 文字模式辅助
    local LADDER = { 6, 8, 10, 12, 14, 16, 19, 22, 26, 30, 32, 36, 44, 52, 64 }
    local function snap_px(px)
        local best, bestd = LADDER[1], math.abs(px - LADDER[1])
        for i = 2, #LADDER do
            local d = math.abs(px - LADDER[i])
            if d < bestd then
                best, bestd = LADDER[i], d
            end
        end
        return best
    end

    local glyph_cache = {}
    local function glyph_width(ch)
        local w = glyph_cache[ch]
        if w == nil then
            w = 16
            local ok, tw = pcall(render.text_size, ch, nil, 32)
            if ok and type(tw) == "number" and tw > 0 then w = tw end
            glyph_cache[ch] = w
        end
        return w
    end

    local function draw_char(cx, cy, col, ch, px)
        local w, h = render.text_size(ch, nil, px)
        w = w or px * 0.5
        h = h or px
        render.text(cx - w / 2, cy - h / 2, col, ch, nil, px)
    end

    -- 头部位置（优先头部 hitbox，失败退回眼睛位置）
    local head_idx = nil
    local function get_head_pos(pawn)
        if head_idx ~= nil then
            local ok, p = pcall(pawn.hitbox, pawn, head_idx)
            if ok and p ~= nil then return p end
            head_idx = nil
        end
        local ok, hbs = pcall(pawn.hitboxes, pawn)
        if ok and hbs ~= nil then
            for i = 1, #hbs do
                local hb = hbs[i]
                if hb.group_name == "head" and hb.center ~= nil then
                    head_idx = hb.index
                    return hb.center
                end
            end
        end
        return pawn:eye_position()
    end

    -- 状态
    local pool, pool_acc = {}, 0
    local pos_smooth, last_raw = nil, nil
    local ppu_smooth = nil
    local last_t = nil
    local txt_src, txt_chars, txt_n = nil, nil, 0
    local txt_gw = {}
    local ti_pool = {}
    local b1, b2, b3 = {}, {}, {}

    local function ti_get(i)
        local t = ti_pool[i]
        if t == nil then
            t = { sx = 0, sy = 0, ch = "", ang = 0, k = 0 }
            ti_pool[i] = t
        end
        return t
    end

    events.on("paint", function()
        if not halo_enable:get() then
            if #pool > 0 then pool = {} end
            pos_smooth, ppu_smooth = nil, nil
            return
        end
        if not has_cam or not engine.in_game() then return end
        local me = entity.local_pawn()
        if me == nil or not me:alive() then return end
        local eye = me:eye_position()
        if eye == nil then return end
        if (cam_pos - eye):length() < 16 then return end -- 第一人称不显示

        local head = get_head_pos(me)
        if head == nil then return end
        head = head:clone()

        local now, dt = xfl_dt(last_t, 0.25)
        last_t = now

        if halo_smooth:get() then
            local sw = 1 - halo_smooth_w:get() * 0.025
            local sa = 1 - (1 - sw) ^ (dt * 60)
            if pos_smooth == nil or (last_raw ~= nil and (head - last_raw):length() > 160) then
                pos_smooth = head:clone()
            else
                pos_smooth = pos_smooth:lerp(head, sa)
            end
            last_raw = head:clone()
            head = pos_smooth:clone()
        else
            pos_smooth, last_raw = nil, nil
        end

        head.z = head.z + halo_height:get()

        local base_alpha = halo_alpha:get()
        local radius = halo_radius:get()
        local bc = halo_color:get()
        local base_col = color(bc.r, bc.g, bc.b, base_alpha)
        local grad = halo_gradient:get()
        local style = combo_idx(halo_style, HALO_STYLE)

        -- ======================== 文字模式 ========================
        if style == 3 then
            if #pool > 0 then pool = {} end
            local raw = halo_txt:get()
            if type(raw) ~= "string" or raw == "" then raw = "XFL.Misc" end
            if raw ~= txt_src then
                local s = raw:gsub("^%s+", ""):gsub("%s+$", "")
                txt_src = raw
                txt_chars, txt_n = utf8_chars(s)
                if txt_n < 1 then
                    txt_chars, txt_n = nil, 0
                end
            end
            local chars, n = txt_chars, txt_n
            if n < 1 then return end

            local scrw, scrh = render.screen_size()
            local center = w2s(head)
            if center == nil then return end
            if center.x < -320 or center.y < -320 or center.x > scrw + 320 or center.y > scrh + 320 then return end

            local bxp = w2s(head + FX_BX * radius)
            local bxm = w2s(head - FX_BX * radius)
            local byp = w2s(head + FX_BY * radius)
            local bym = w2s(head - FX_BY * radius)
            if bxp == nil or bxm == nil or byp == nil or bym == nil then return end

            local abx = (bxp.x - bxm.x) * 0.5
            local aby = (bxp.y - bxm.y) * 0.5
            local acx = (byp.x - bym.x) * 0.5
            local acy = (byp.y - bym.y) * 0.5
            local cr = abx * acy - aby * acx
            local sm = abx * abx + aby * aby + acx * acx + acy * acy
            local disc = sm * sm - 4 * cr * cr
            if disc < 0 then disc = 0 end
            local a2 = (sm + m_sqrt(disc)) * 0.5
            if a2 < 1 then return end
            local span_px = m_sqrt(a2)

            local ppu_now = span_px / radius
            if ppu_smooth == nil then
                ppu_smooth = ppu_now
            else
                ppu_smooth = ppu_smooth + (ppu_now - ppu_smooth) * 0.30
            end
            local ppu = ppu_smooth

            local world_h = halo_tsize:get() * 0.32
            local px = world_h * ppu
            if px < 3 then return end
            px = snap_px(px)

            local gscale = world_h / 32
            local wtot = 0
            for i = 1, n do
                local w = glyph_width(chars[i]) * gscale
                txt_gw[i] = w
                wtot = wtot + w
            end

            local span_s = wtot / radius
            local gap_req = halo_tgap:get() * (PI2 / 360)
            local period = span_s + gap_req
            local budget = 84
            local blocks = 1
            if period > 0.0001 then blocks = m_floor(PI2 / period + 0.0001) end
            if blocks > 8 then blocks = 8 end
            if n * blocks > budget then
                blocks = m_floor(budget / n)
                if blocks < 1 then blocks = 1 end
            end
            if span_s > 0.0001 then
                local fit = m_floor(PI2 / (span_s * 1.03))
                if fit < 1 then fit = 1 end
                if blocks > fit then blocks = fit end
            end
            local step = PI2 / blocks

            local flow = now * halo_speed:get() * 0.004
            local spin = now * halo_tspin:get() * 0.2
            local hide = halo_thide:get()
            local cam = cam_pos
            local lim_x = scrw + 140
            local lim_y = scrh + 140

            local sux, suy = 0, 0
            local flat = true
            local dcx = cam.x - head.x
            local dcy = cam.y - head.y
            local dcz = cam.z - head.z
            local dcl = m_sqrt(dcx * dcx + dcy * dcy + dcz * dcz)
            if dcl > 0.001 then
                local bx = (dcx * FX_BX.x + dcy * FX_BX.y + dcz * FX_BX.z) / dcl
                local by = (dcx * FX_BY.x + dcy * FX_BY.y + dcz * FX_BY.z) / dcl
                local pl = m_sqrt(bx * bx + by * by)
                if pl > 0.05 then
                    sux = bx / pl
                    suy = by / pl
                    flat = false
                end
            end

            local cnt = 0
            local bn1, bn2, bn3 = 0, 0, 0
            for b = 0, blocks - 1 do
                local start = spin + b * step
                local acc = 0
                for i = 1, n do
                    local w = txt_gw[i]
                    local ang = start + (acc + w * 0.5) / radius
                    acc = acc + w
                    local ca = m_cos(ang)
                    local cb = m_sin(ang)
                    local spx = center.x + ca * abx + cb * acx
                    local spy = center.y + ca * aby + cb * acy
                    if spx > -140 and spy > -140 and spx < lim_x and spy < lim_y then
                        cnt = cnt + 1
                        local it = ti_get(cnt)
                        it.sx = spx
                        it.sy = spy
                        it.ch = chars[i]
                        it.ang = ang
                        local k = 0
                        if not flat then
                            k = 0.5 - 0.5 * (ca * sux + cb * suy)
                            if k < 0 then k = 0 end
                            if k > 1 then k = 1 end
                        end
                        it.k = k
                        if k >= 0.66 then
                            bn1 = bn1 + 1
                            b1[bn1] = it
                        elseif k >= 0.33 then
                            bn2 = bn2 + 1
                            b2[bn2] = it
                        else
                            bn3 = bn3 + 1
                            b3[bn3] = it
                        end
                    end
                end
            end
            if cnt < 1 then return end

            for pass = 1, 3 do
                local arr, nb
                if pass == 1 then
                    arr, nb = b1, bn1
                elseif pass == 2 then
                    arr, nb = b2, bn2
                else
                    arr, nb = b3, bn3
                end
                for j = 1, nb do
                    local it = arr[j]
                    local k = it.k
                    local f = 1 - 0.5 * k
                    if hide then
                        local hf = 1 - clamp((k - 0.34) / 0.66, 0, 1)
                        hf = hf * hf * (3 - 2 * hf)
                        f = f * hf
                    end
                    if f > 0.02 then
                        local col = base_col
                        if grad then
                            col = color_hsv((it.ang / PI2 + flow) % 1, 0.68, 1, base_alpha)
                        end
                        draw_char(it.sx, it.sy, fade(col, f), it.ch, px)
                    end
                end
            end
            return
        end

        -- ======================== 简约模式 ========================
        if style == 2 then
            if #pool > 0 then pool = {} end
            local col = base_col
            if grad then
                col = color_hsv((now * halo_speed:get() * 10) % 360 / 360, 1, 1, base_alpha)
            end
            ring_plain(head, radius, col, 48)
            return
        end

        -- ======================== 华丽模式 ========================
        local glow = halo_glow:get() * 0.01
        local spin = halo_ringspin:get() * 0.01
        local cam = cam_pos
        local flow = now * halo_speed:get() * 0.004

        local function color_at(ang, f)
            if not grad then return fade(base_col, f) end
            return fade(color_hsv((ang / PI2 + flow) % 1, 0.68, 1, base_alpha), f)
        end
        local function color_at_twin(ang, f)
            if not grad then return fade(base_col, f) end
            return fade(color_hsv((ang / PI2 - flow + 0.5) % 1, 0.68, 1, base_alpha), f)
        end

        local breathe, bright = 1, 1
        if halo_pulse:get() then
            breathe = 1 + 0.055 * m_sin(now * 2.1)
            bright = 0.88 + 0.12 * m_sin(now * 1.7 + 0.6)
        end
        local r_main = radius * breathe

        ring(head, r_main, base_col, {
            segs = 40, glow = glow, depth = 0.50, cam = cam,
            scale = bright, color_at = color_at,
        })

        if halo_twin:get() then
            ring(head, r_main * 0.64, base_col, {
                segs = 28, glow = glow * 0.65, depth = 0.50, cam = cam,
                wave = 0.09, phase = -now * (0.7 + spin * 3.5),
                scale = bright * 0.62, color_at = color_at_twin,
            })
        end

        if halo_star:get() then
            local sa0 = now * (0.55 + spin * 4.5)
            local tail = 13
            for k = 0, tail do
                local a = sa0 - k * 0.052
                local p = w2s(head + FX_BX * (m_cos(a) * r_main) + FX_BY * (m_sin(a) * r_main))
                if p ~= nil then
                    local f = 1 - k / (tail + 1)
                    f = f * f * bright
                    local rad = 1 + 2.6 * f
                    circle2(p, fade(base_col, f * 0.08 * (0.4 + glow)), rad * 3.2)
                    circle2(p, fade(base_col, f * 0.34), rad * 1.8)
                    circle2(p, fade(base_col, f), rad)
                end
            end
        end

        if halo_motes:get() then
            pool_acc = pool_acc + dt * 18
            while pool_acc >= 1 do
                pool_acc = pool_acc - 1
                mote_spawn(pool, 26, head.x, head.y, head.z, radius, 16, 40)
            end
        end
        if #pool > 0 then mote_draw(pool, dt, base_col) end
    end)

    events.on("unload", function()
        pool = {}
    end)
end

-- ============================================================================
-- 移动拖尾
-- ============================================================================
do
    local TRAIL_STYLE = { "线条", "星光" }

    local trail_enable = g_trail:checkbox("启用移动拖尾", false)
    local trail_style = g_trail:combo("样式", TRAIL_STYLE, 1)
    local lbl_base = g_trail:label("──────── 基础 ────────")
    local trail_color = g_trail:color("颜色", color(214, 176, 255, 255), true)
    local trail_fade = g_trail:slider_float("消散时间", 0.2, 5.0, 1.0, "%.1f")
    local trail_ground = g_trail:checkbox("贴合地形", true)
    local lbl_line = g_trail:label("──────── 线条 ────────")
    local trail_width = g_trail:slider_int("线条粗细", 2, 24, 8)
    local trail_taper = g_trail:slider_int("尾部收窄", 0, 100, 65)
    local trail_rainbow = g_trail:checkbox("流动渐变", true)
    local trail_inner = g_trail:checkbox("白色内核", true)
    local trail_pulse = g_trail:checkbox("能量脉冲", true)
    local lbl_star = g_trail:label("──────── 星光 ────────")
    local trail_ssize = g_trail:slider_int("星光大小", 2, 20, 8)
    local trail_star = g_trail:slider_int("星光数量", 1, 10, 5)
    local trail_sfade = g_trail:slider_float("淡入时间", 0, 1.0, 0.10, "%.2f")
    local trail_streak = g_trail:checkbox("星星拖尾", true)

    local base_vis = { lbl_base, trail_color, trail_fade, trail_ground }
    local line_vis = { lbl_line, trail_width, trail_taper, trail_rainbow, trail_inner, trail_pulse }
    local star_vis = { lbl_star, trail_ssize, trail_star, trail_sfade, trail_streak }

    local function trail_refresh()
        local on = trail_enable:get()
        local st = combo_idx(trail_style, TRAIL_STYLE)
        trail_style:visible(on)
        for i = 1, #base_vis do base_vis[i]:visible(on) end
        for i = 1, #line_vis do line_vis[i]:visible(on and st == 1) end
        for i = 1, #star_vis do star_vis[i]:visible(on and st == 2) end
    end
    trail_enable:callback(trail_refresh)
    trail_style:callback(trail_refresh)
    trail_refresh()

    local TGV = {
        STEP = 0.010, MAX = 260, GAP = 48, HEAD = 0.11, RED = 0.16,
        LOWZ = 3, MOVE = 18, HUESPD = 0.055, STAR = 0.55, DOT = 3.4,
        STARMAX = 300,
        STAR_LV = { 10, 16, 25, 38, 55, 80, 120, 180, 270, 400 },
        DRAWMAX = 170,
        GLOW_K = { 2.85, 1.80 },
        GLOW_A = { 0.055, 0.130 },
        SINK = 0.90, PULSE_W = 3.0, PULSE_S = 2.4,
        SNAP_UP = 32, SNAP_DN = 80, SNAP_LIFT = 2.2,
        STAR_CULL = 0.22, STAR_HARD = 420, STAR_HUE = 0.09,
        STAR_WHITE = 0.14, STAR_MIX = 0.55,
        seq = 0,
    }

    local trail_pts, trail_w, trail_acc = {}, {}, 0
    local trail_stars, trail_star_acc = {}, 0
    local trail_hue = 0
    local trail_last = nil
    local cm_last = nil

    local function tg_erase(n)
        for i = 1, n do
            trail_pts[i] = nil
            trail_w[i] = nil
        end
    end
    local function tg_drop(k)
        local n = #trail_pts
        if k <= 0 or n == 0 then return end
        if k > n then k = n end
        for i = 1, n - k do
            trail_pts[i] = trail_pts[i + k]
            trail_w[i] = trail_w[i + k]
        end
        for i = n - k + 1, n do
            trail_pts[i] = nil
            trail_w[i] = nil
        end
    end
    local function tg_clear()
        tg_erase(#trail_pts)
        trail_acc = 0
    end

    local function tg_tint(c, hue, sat, f)
        local h = hue % 1
        if h < 0 then h = h + 1 end
        local tc = color_hsv(h, sat, 1, c.a)
        return color(
            m_floor(c.r * (1 - f) + tc.r * f + 0.5),
            m_floor(c.g * (1 - f) + tc.g * f + 0.5),
            m_floor(c.b * (1 - f) + tc.b * f + 0.5),
            c.a)
    end

    local function tg_mix(c1, c2, f)
        return color(
            c1.r + (c2.r - c1.r) * f,
            c1.g + (c2.g - c1.g) * f,
            c1.b + (c2.b - c1.b) * f,
            c1.a + (c2.a - c1.a) * f)
    end

    -- 贴地探测（只能在 createmove 里 trace）
    local function tg_ground_z(pawn, x, y, z)
        local ok, tr = pcall(trace.line,
            vector(x, y, z + TGV.SNAP_UP), vector(x, y, z - TGV.SNAP_DN), pawn)
        if not ok or tr == nil then return z end
        if tr.start_solid or tr.fraction == nil or tr.fraction >= 1 then return z end
        if tr.position == nil then return z end
        return tr.position.z + TGV.SNAP_LIFT
    end

    local function tg_star_add(px, py, pz, t)
        local cnt = #trail_stars
        if cnt >= TGV.STAR_HARD then return end
        if cnt >= TGV.STARMAX then
            for k = 1, cnt do
                local old = trail_stars[k]
                if old.cull == nil then
                    old.cull = t
                    break
                end
            end
        end
        TGV.seq = TGV.seq + 1
        local az = m_random() * PI2
        local rad = 0.8 + m_random() * 1.7
        local sz = 0.75 + m_random() * 1.05
        local h0, s0, v0 = trail_color:get():hsv()
        local hh = (h0 + (m_random() - 0.5) * TGV.STAR_HUE) % 1
        local ss = s0 * (0.86 + m_random() * 0.28)
        if ss > 1 then ss = 1 end
        local vv = v0 * (0.86 + m_random() * 0.32)
        if vv > 1 then vv = 1 end
        trail_stars[cnt + 1] = {
            x = px + m_cos(az) * rad,
            y = py + m_sin(az) * rad,
            z = pz + (m_random() - 0.5) * 2.2,
            a = az,
            spin = (m_random() < 0.5 and 1 or -1) * (0.9 + m_random() * 2.0),
            o0 = 0.20 + m_random() * 0.45,
            o1 = 1.00 + m_random() * 1.50,
            t = t,
            ph = m_random() * PI2,
            tws = 1.8 + m_random() * 2.6,
            sz = sz,
            gain = 0.85 + 0.55 * sz,
            hh = hh, ss = ss, vv = vv,
            wh = m_random() < TGV.STAR_WHITE,
            rot = m_random() * PI2,
            rots = (m_random() < 0.5 and 1 or -1) * (0.35 + m_random() * 0.75),
            sk = (TGV.seq % 4 == 0),
        }
    end

    local function tg_stars_clear()
        for i = #trail_stars, 1, -1 do trail_stars[i] = nil end
        trail_star_acc = 0
    end

    local function tg_stars_draw(maxage, now, dt, base, unit, in_t, trail)
        local list = trail_stars
        local dense = #list > 110
        local white = color(255, 255, 255, base.a)
        local i = 1
        while i <= #list do
            local st = list[i]
            local age = now - st.t
            local k = age / maxage
            local die = 0
            if st.cull ~= nil then die = (now - st.cull) / TGV.STAR_CULL end
            if k >= 1 or die >= 1 then
                table.remove(list, i)
            else
                if k < 0 then k = 0 end
                local cull = 1 - die
                st.a = st.a + st.spin * dt
                st.rot = st.rot + st.rots * dt
                st.rad = st.o0 + (st.o1 - st.o0) * k
                local sa, ca = m_sin(st.a), m_cos(st.a)
                local px = st.x + sa * st.rad
                local py = st.y + ca * st.rad
                local sc = w2s(vector(px, py, st.z + k * 0.8))
                if sc ~= nil then
                    local fade_k = (1 - k) ^ 0.7
                    local ain = in_t > 0 and (age / in_t) or 1
                    if ain > 1 then ain = 1 end
                    local tw = 0.72 + 0.28 * m_sin(now * st.tws + st.ph)
                    local f = fade_k * ain * tw * st.gain * cull
                    if f > 0.03 then
                        local col = color_hsv(st.hh, st.ss, st.vv, base.a)
                        if st.wh then col = tg_mix(col, white, TGV.STAR_MIX) end
                        local rad = st.sz * unit * (0.60 + 0.40 * fade_k)
                        if not dense then
                            circle2(sc, fade(col, 0.10 * f), rad * 3.6)
                        end
                        circle2(sc, fade(col, 0.32 * f), rad * 2.0)
                        circle2(sc, fade(col, 0.95 * f), rad)
                        circle2(sc, color(255, 255, 255, m_floor(base.a * 0.80 * f)), rad * 0.42)
                        if (not dense) and f > 0.35 then
                            local L = rad * 3.4 * f
                            local cr, sr = m_cos(st.rot), m_sin(st.rot)
                            local gc = fade(col, 0.34 * f)
                            line2({ x = sc.x - cr * L, y = sc.y - sr * L },
                                { x = sc.x + cr * L, y = sc.y + sr * L }, gc)
                            line2({ x = sc.x + sr * L, y = sc.y - cr * L },
                                { x = sc.x - sr * L, y = sc.y + cr * L }, gc)
                        end
                        if trail and (not dense) and st.sk and f > 0.42 then
                            local tl = st.rad - (rad * 4.0 + 2.2)
                            if tl < 0 then tl = 0 end
                            if tl < st.rad then
                                local tp = w2s(vector(st.x + sa * tl, st.y + ca * tl, st.z + k * 0.8))
                                if tp ~= nil then
                                    line2(tp, sc, fade(col, 0.22 * f))
                                end
                            end
                        end
                    end
                end
                i = i + 1
            end
        end
    end

    local function tg_pick(n)
        if n < 2 then
            local p = trail_pts[n]
            return p[1], p[2], p[3]
        end
        local i = math.random(n - 1)
        local a, b = trail_pts[i], trail_pts[i + 1]
        local f = math.random()
        return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
    end

    -- 采样（createmove 内，允许 trace 贴地）
    events.on("createmove", function(cmd)
        if not trail_enable:get() then return end
        if not engine.in_game() then return end
        local me = entity.local_pawn()
        if me == nil or not me:alive() then return end
        local vel = me:velocity()
        local spd = 0
        if vel ~= nil then
            spd = m_sqrt(vel.x * vel.x + vel.y * vel.y)
        end
        local sampling = spd >= TGV.MOVE or (not me:on_ground())
        local now = globals.realtime()
        local dt = cm_last ~= nil and now - cm_last or 0.016
        cm_last = now
        if dt <= 0 or dt > 0.25 then dt = 0.016 end
        local maxage = trail_fade:get()
        if maxage < 0.1 then maxage = 0.1 end
        local step = maxage / TGV.MAX
        if step < TGV.STEP then step = TGV.STEP end
        trail_acc = trail_acc + dt
        if sampling and trail_acc >= step - 0.000001 then
            local o = me:origin()
            if o ~= nil then
                trail_acc = trail_acc - step
                local px, py, pz = o.x, o.y, o.z - TGV.LOWZ
                if trail_ground:get() then pz = tg_ground_z(me, px, py, pz) end
                local n = #trail_pts
                if n == 0 then
                    trail_pts[1] = { px, py, pz, now }
                    trail_w[1] = 0
                elseif ((px - trail_pts[n][1]) ^ 2 + (py - trail_pts[n][2]) ^ 2) > (TGV.GAP * TGV.GAP) then
                    tg_erase(n)
                    trail_pts[1] = { px, py, pz, now }
                    trail_w[1] = 0
                else
                    if n >= TGV.MAX then
                        tg_drop(1)
                        n = n - 1
                    end
                    n = n + 1
                    trail_pts[n] = { px, py, pz, now }
                    trail_w[n] = 0
                end
            end
        end
    end)

    -- 绘制（paint 内）
    events.on("paint", function()
        local now, dt = xfl_dt(trail_last, 0.25)
        trail_last = now

        if not trail_enable:get() then
            if #trail_pts > 0 then tg_clear() end
            if #trail_stars > 0 or trail_star_acc > 0 then tg_stars_clear() end
            return
        end

        local maxage = trail_fade:get()
        if maxage < 0.1 then maxage = 0.1 end
        local starlight = combo_idx(trail_style, TRAIL_STYLE) == 2
        local me = entity.local_pawn()
        local alive = me ~= nil and me:alive()
        local moving, spd = false, 0
        if alive then
            local vel = me:velocity()
            if vel ~= nil then
                spd = m_sqrt(vel.x * vel.x + vel.y * vel.y)
                moving = spd >= TGV.MOVE
            end
        end
        local sampling = moving or (alive and not me:on_ground())

        local n = #trail_pts
        if n == 0 then return end

        for i = 1, n do
            local rate = sampling and (dt / TGV.HEAD) or (dt / TGV.RED)
            if rate > 1 then rate = 1 end
            local target = sampling and 1 or 0
            trail_w[i] = trail_w[i] + (target - trail_w[i]) * rate
        end

        local kill = 0
        for i = 1, n do
            if (now - trail_pts[i][4]) > maxage then
                kill = i
            else
                break
            end
        end
        if kill > 0 then
            tg_drop(kill)
            n = n - kill
        end
        if n == 0 then return end

        local c = trail_color:get()
        local base = color(c.r, c.g, c.b, c.a)
        local rainbow = trail_rainbow:get()
        if rainbow then trail_hue = (trail_hue + dt * TGV.HUESPD) % 1 end
        local hue = trail_hue
        local hw = trail_width:get()

        if n < 2 then
            if starlight then
                trail_star_acc = 0
                tg_stars_clear()
                return
            end
            local p = trail_pts[1]
            if trail_w[1] > 0.06 then
                local sp = w2s(vector(p[1], p[2], p[3]))
                if sp ~= nil then
                    local ha = base
                    if rainbow then ha = color_hsv(hue % 1, 0.50, 1, base.a) end
                    local rr = TGV.DOT
                    circle2(sp, fade(ha, 0.14 * trail_w[1]), rr * 2.2)
                    circle2(sp, fade(ha, 0.45 * trail_w[1]), rr * 1.1)
                    circle2(sp, fade(ha, 0.90 * trail_w[1]), rr * 0.6)
                end
            end
            return
        end

        if starlight then
            local lv = m_floor(trail_star:get() + 0.5)
            if lv < 1 then
                lv = 1
            elseif lv > #TGV.STAR_LV then
                lv = #TGV.STAR_LV
            end
            local spawn = TGV.STAR_LV[lv] * dt * (sampling and 1 or 0)
            local safety = 0
            while trail_star_acc >= 1 and safety < 40 do
                trail_star_acc = trail_star_acc - 1
                safety = safety + 1
                local px, py, pz = tg_pick(n)
                tg_star_add(px, py, pz, now)
            end
            trail_star_acc = math.min(trail_star_acc + spawn, 2.0)
            if #trail_stars > 0 then
                local unit = TGV.STAR * (trail_ssize:get() * 0.125)
                local in_t = trail_sfade:get()
                local in_max = maxage * 0.25
                if in_t > in_max then in_t = in_max end
                tg_stars_draw(maxage, now, dt, base, unit, in_t, trail_streak:get())
            end
            return
        end

        local inner_ok = trail_inner:get()
        local pulse_ok = trail_pulse:get()
        local taper = trail_taper:get() * 0.01
        if taper > 1 then taper = 1 end
        local rr_head = TGV.DOT * (1 + 0.35 * clamp(spd / 260, 0, 1))

        local stride = 1
        if n - 1 > TGV.DRAWMAX then stride = m_floor((n - 2) / TGV.DRAWMAX) + 1 end

        local dot = 0
        local i = 1
        while i < n do
            local j = i + stride
            if j > n then j = n end
            local a, b = trail_pts[i], trail_pts[j]
            local ka = (now - a[4]) / maxage
            local kb = (now - b[4]) / maxage
            if ka < 0 then ka = 0 end
            if kb < 0 then kb = 0 end
            if ka < 0.995 or kb < 0.995 then
                local life = 1 - (ka + kb) * 0.5
                local f = life * (0.62 + 0.38 * life * life)
                local wline = (trail_w[i] * (1 - ka * 0.30) + trail_w[j] * (1 - kb * 0.30)) * 0.5
                local u = (i - 1) / (n - 1)
                local pm = 1
                if pulse_ok then
                    local pw = 0.5 + 0.5 * m_sin(u * TGV.PULSE_W * PI2 - now * TGV.PULSE_S)
                    pm = 0.40 + 0.60 * pw
                end
                local thick = hw * wline * (1 - taper * (1 - life))
                if thick > 0.05 then
                    local ca = base
                    if rainbow then ca = color_hsv((hue - u * 0.55) % 1, 0.55, 1, base.a) end
                    local dz = (1 - life) * TGV.SINK
                    local e1 = w2s(vector(a[1], a[2], a[3] - dz))
                    local e2 = w2s(vector(b[1], b[2], b[3] - dz))
                    if e1 ~= nil and e2 ~= nil then
                        local q1, q2 = e1, e2
                        local dx, dy = e2.x - e1.x, e2.y - e1.y
                        local sl = m_sqrt(dx * dx + dy * dy)
                        if sl > 0.01 then
                            local ex = thick * TGV.GLOW_K[1] * 0.5
                            if ex > sl * 0.5 then ex = sl * 0.5 end
                            local ux, uy = dx / sl * ex, dy / sl * ex
                            q1 = { x = e1.x - ux, y = e1.y - uy }
                            q2 = { x = e2.x + ux, y = e2.y + uy }
                        end
                        line2(q1, q2, fade(ca, TGV.GLOW_A[1] * f * pm), thick * TGV.GLOW_K[1])
                        line2(q1, q2, fade(ca, TGV.GLOW_A[2] * f * pm), thick * TGV.GLOW_K[2])
                        line2(q1, q2, fade(ca, 0.92 * f * (0.90 + 0.10 * pm)), thick)
                        if inner_ok then
                            local ic = tg_tint(ca, hue + 0.50, 0.30, 0.72)
                            line2(q1, q2, fade(ic, 0.60 * f * f), thick * 0.42)
                        end
                    end
                end
                if j == n then dot = f * (0.90 + 0.10 * pm) * trail_w[n] end
            end
            i = j
        end

        if dot > 0.05 then
            local p = trail_pts[n]
            local sp = w2s(vector(p[1], p[2], p[3] + 0.4))
            if sp ~= nil then
                local ha = base
                if rainbow then ha = color_hsv(hue % 1, 0.45, 1, base.a) end
                local rr = rr_head
                circle2(sp, fade(ha, 0.13 * dot), rr * 2.4)
                circle2(sp, fade(ha, 0.40 * dot), rr * 1.20)
                circle2(sp, fade(ha, 0.90 * dot), rr * 0.62)
                if inner_ok then
                    circle2(sp, color(255, 255, 255, m_floor(base.a * 0.55 * dot)), rr * 0.26)
                end
            end
        end
    end)

    events.on("unload", function()
        tg_erase(#trail_pts)
        trail_w = {}
        tg_stars_clear()
        trail_hue = 0
    end)
end

-- ============================================================================
-- 挂机防踢（AFK）
-- ============================================================================
do
    local AFK_HOLD = { 0.05, 0.10, 0.20, 0.35, 0.50 }
    local AFK_HOLD_ITEMS = { "0.05秒", "0.10秒", "0.20秒", "0.35秒", "0.50秒" }
    local AFK_DIR_ITEMS = { "随机", "前后", "左右" }

    local afk_enable = g_afk:checkbox("启用 AFK", false)
    local afk_interval = g_afk:slider_int("间隔(秒)", 1, 30, 5)
    local afk_hold = g_afk:combo("移动时长", AFK_HOLD_ITEMS, 3)
    local afk_dir = g_afk:combo("移动方向", AFK_DIR_ITEMS, 1)
    local afk_random = g_afk:checkbox("随机化", true)

    local afk_move_f, afk_move_s = 0, 0
    local afk_move_until = 0
    local afk_next = 0

    local function afk_stop()
        afk_move_f, afk_move_s = 0, 0
    end

    local function afk_roll(v)
        if not afk_random:get() then return v end
        return v * (0.7 + m_random() * 0.6)
    end

    local function afk_push()
        local mode = combo_idx(afk_dir, AFK_DIR_ITEMS)
        local pick
        if mode == 2 then
            pick = math.random(2)
        elseif mode == 3 then
            pick = 2 + math.random(2)
        else
            pick = math.random(4)
        end
        if pick == 1 then
            afk_move_f, afk_move_s = 1, 0
        elseif pick == 2 then
            afk_move_f, afk_move_s = -1, 0
        elseif pick == 3 then
            afk_move_f, afk_move_s = 0, -1
        else
            afk_move_f, afk_move_s = 0, 1
        end
        local hold = AFK_HOLD[combo_idx(afk_hold, AFK_HOLD_ITEMS)] or AFK_HOLD[3]
        afk_move_until = globals.realtime() + hold * afk_roll(1)
    end

    events.on("createmove", function(cmd)
        if not afk_enable:get() then
            afk_stop()
            return
        end
        if not engine.in_game() then
            afk_stop()
            return
        end
        local pawn = entity.local_pawn()
        if pawn == nil or not pawn:alive() then
            afk_stop()
            return
        end

        -- 玩家手动移动时停止 AFK（cmd 初始移动量反映用户输入）
        local f, s = cmd:move()
        if f ~= 0 or s ~= 0 then
            afk_stop()
            return
        end

        local now = globals.realtime()

        -- AFK 移动中
        if afk_move_f ~= 0 or afk_move_s ~= 0 then
            if now >= afk_move_until then
                afk_stop()
                return
            end
            pcall(function() cmd:set_move(afk_move_f, afk_move_s) end)
            if afk_move_f > 0 then
                pcall(function() cmd:press(8) end) -- forward
            elseif afk_move_f < 0 then
                pcall(function() cmd:press(16) end) -- back
            end
            if afk_move_s > 0 then
                pcall(function() cmd:press(1024) end) -- right
            elseif afk_move_s < 0 then
                pcall(function() cmd:press(512) end) -- left
            end
            return
        end

        -- 静止时才触发下一次 AFK 移动
        local vel = pawn:velocity()
        local spd = 0
        if vel ~= nil then
            spd = m_sqrt(vel.x * vel.x + vel.y * vel.y)
        end
        if spd > 10 then return end
        if not pawn:on_ground() then return end
        if now < afk_next then return end

        afk_push()
        afk_next = now + afk_interval:get() * afk_roll(1)
    end)
end

-- ============================================================================
-- 状态组
-- ============================================================================
do
    local insecure_chk = g_status:checkbox("Allow Insecure（允许不安全模式）", client.insecure())
    g_status:label("当前 Allow Insecure：" .. (client.insecure() and "已开启" or "未开启"))
    g_status:button("应用并立即重载脚本", function()
        pcall(function() config.set("lua.allow_insecure", insecure_chk:get()) end)
        pcall(function() client.reload() end)
    end)
    g_status:label("由Awa Subaru移植")
    g_status:label("鸣谢：小凤梨1337")

    -- 系统浏览器打开 URL（全局 ffi → ffi.C → ffi.load 兜底链）
    local shexec
    local function init_shexec()
        if shexec ~= nil then return end
        if type(ffi) ~= "table" or type(ffi.cdef) ~= "function" then
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
            print("[XFL Misc] ShellExecuteA 调用失败: " .. tostring(err))
        end
        local ok2, err2 = pcall(function() panorama.SteamOverlayAPI.OpenExternalBrowserURL(url) end)
        if not ok2 then
            print("[XFL Misc] Steam 覆盖层打开失败: " .. tostring(err2))
        end
    end
    g_status:button("闲鱼:我是学生你懂我意思吧", function()
        open_url("https://m.tb.cn/h.jS7Zhk2?tk=ZYFI6cX5T4D")
    end)
end
