-- ============================================================================
-- Solace Legit（Neverwin 移植版）· DEBUG 版
-- 每次加载会在控制台打印 1 次启动信息 + createmove 每 0.5s 打印状态
-- 方便定位问题后再裁掉
-- ============================================================================

print("[Solace Legit] 由Awa Subaru移植")
print("[Solace Legit] 闲鱼:我是学生你懂我意思吧")

-- ----------------------------------------------------------------------------
-- 调试辅助
-- ----------------------------------------------------------------------------
local DBG = { last_log = 0 }
local function log(...)
    print("[Solace Legit] " .. table.concat({ ... }, " | "))
end
local function log_rate(interval, ...)
    local now = globals.realtime and globals.realtime() or 0
    if now - DBG.last_log >= interval then
        DBG.last_log = now
        log(...)
    end
end

-- ----------------------------------------------------------------------------
-- 共享工具
-- ----------------------------------------------------------------------------
local m_sqrt = math.sqrt
local m_sin, m_cos, m_pi = math.sin, math.cos, math.pi
local m_random = math.random
local m_rad = math.rad
local m_abs = math.abs
local m_tan = math.tan

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function nrand() return m_random() * 2 - 1 end

local function bind_active(kb)
    local ok0, v = pcall(function() return kb:get() end)
    if ok0 then
        if type(v) == "number" then
            if v <= 0 then return true end
            return input.key_down(v)
        end
        if type(v) == "boolean" then return v end
    end
    local ok, act = pcall(function() return kb:active() end)
    if ok and type(act) == "boolean" then return act end
    return false
end

local function bind_held(kb)
    local ok0, v = pcall(function() return kb:get() end)
    if ok0 then
        if type(v) == "number" then
            if v <= 0 then return false end
            return input.key_down(v)
        end
        if type(v) == "boolean" then return v end
    end
    local ok, act = pcall(function() return kb:active() end)
    return ok and act == true
end

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

local function hit_chance(info, dist, radius)
    if info == nil then return 1 end
    local inacc = (tonumber(info.inaccuracy) or 0) + (tonumber(info.spread) or 0)
    if inacc <= 0 then return 1 end
    local spread_r = m_tan(inacc) * dist
    if spread_r <= 0.01 then return 1 end
    return clamp(radius / spread_r, 0, 1)
end

local function wname(info) return tostring(info and info.name or ""):lower() end

local function is_sniper(info)
    local n = wname(info)
    return n:find("awp") or n:find("ssg08") or n:find("scar20") or n:find("g3sg1")
end
local function is_knife(info)
    local n = wname(info)
    return n:find("knife") or n:find("bayonet")
end
local function is_revolver(info) return wname(info):find("revolver") end
local function is_zeus(info) return wname(info):find("taser") end

-- ----------------------------------------------------------------------------
-- 共享状态
-- ----------------------------------------------------------------------------
local S = {
    cam_fov = 90,
    react = {}, react_gc_t = 0,
    arc_total = 1, arc_prev = 0, arc_mag = 0, speed_jit = 1,
    cur_target = nil, aim_pos = nil,
    old_punch_x = 0, old_punch_y = 0, rcs_rand = 1, prev_attack = false,
    trig_t0 = nil,
    qp = { active = false, phase = "", ox = 0, oy = 0, oz = 0, df = 0, ds = 1, t0 = 0, fired = false },
}

events.on("override_view", function(view)
    local ok, f = pcall(function() return view:fov() end)
    if ok and type(f) == "number" and f > 1 then S.cam_fov = f end
end)

-- ----------------------------------------------------------------------------
-- UI
-- ----------------------------------------------------------------------------
ui.sidebar("Solace Legit", "misc")
local main_tab = ui.tab("Solace Legit")
local C = {}

do
    local g = main_tab:group("自瞄")
    C.aim_on = g:checkbox("启用自瞄", false)
    C.aim_key_on = g:checkbox("启用自瞄按键", false)
    C.aim_key = g:keybind("自瞄按键（需开启上方开关）", 0)
    C.aim_fov = g:slider_float("自瞄 FOV", 0.5, 30, 10, "%.1f")
    C.aim_smooth = g:slider_float("平滑", 1, 100, 12, "%.0f")
    C.aim_dist_adj = g:checkbox("按距离调节平滑", true)
    C.aim_head = g:checkbox("头部", true)
    C.aim_chest = g:checkbox("胸部", true)
    C.aim_stomach = g:checkbox("腹部", false)
    C.aim_arms = g:checkbox("手臂", false)
    C.aim_legs = g:checkbox("腿部", false)
    C.aim_react_min = g:slider_int("反应时间·最小 (ms)", 0, 500, 80)
    C.aim_react_max = g:slider_int("反应时间·最大 (ms)", 0, 500, 150)
    C.aim_min_dmg = g:slider_int("最小伤害（可视）", 0, 120, 0)
    C.aim_min_dmg_aw = g:slider_int("最小伤害（穿墙）", 0, 120, 15)
    C.aim_autofire = g:checkbox("自动开火", false)
    C.aim_hc = g:slider_int("开火命中率 (%)", 0, 100, 0)
    C.aim_ground = g:checkbox("仅站立时开火", true)
    C.aim_smoke = g:checkbox("烟雾检查", true)
    C.aim_vis_fov = g:checkbox("显示 FOV 圈", false)
    C.aim_fov_col = g:color("FOV 圈颜色", color(120, 170, 255, 170), true)
    C.aim_vis_tar = g:checkbox("显示锁定目标", true)
end

do
    local g = main_tab:group("人性化瞄准")
    C.hum_on = g:checkbox("启用人性化", true)
    C.hum_amount = g:slider_int("人性化强度", 0, 100, 50)
    C.hum_curve = g:slider_int("弧线强度", 0, 100, 35)
    C.hum_curve_rand = g:slider_int("弧线随机化", 0, 100, 40)
    C.hum_yaw = g:slider_int("水平抖动", 0, 100, 25)
    C.hum_pitch = g:slider_int("垂直抖动", 0, 100, 15)
    C.hum_speed = g:slider_int("速度变化", 0, 100, 30)
    C.hum_noise = g:slider_int("轴速度噪声", 0, 100, 20)
end

do
    local g = main_tab:group("后坐力控制")
    C.rcs_on = g:checkbox("启用压枪", false)
    C.rcs_strength = g:slider_int("强度 (%)", 0, 100, 70)
    C.rcs_min = g:slider_int("随机最小 (%)", 0, 150, 85)
    C.rcs_max = g:slider_int("随机最大 (%)", 0, 150, 115)
    C.rcs_standalone = g:checkbox("独立模式（无需锁定）", false)
    C.rcs_auto_only = g:checkbox("仅全自动武器", true)
end

do
    local g = main_tab:group("自动扳机")
    C.trig_on = g:checkbox("启用扳机", false)
    C.trig_key_on = g:checkbox("启用扳机按键", false)
    C.trig_key = g:keybind("扳机按键（需开启上方开关）", 0)
    C.trig_delay = g:slider_int("开火延迟 (ms)", 0, 500, 80)
    C.trig_hc = g:slider_int("命中率门槛 (%)", 0, 100, 40)
    C.trig_head = g:checkbox("仅爆头", false)
    C.trig_min_dmg = g:slider_int("最小伤害（可视）", 0, 120, 0)
    C.trig_min_dmg_aw = g:slider_int("最小伤害（穿墙）", 0, 120, 0)
    C.trig_smoke = g:checkbox("烟雾检查", true)
    C.trig_flash = g:checkbox("闪光检查", true)
    C.trig_stop = g:checkbox("开火前急停", false)
end

do
    local g = main_tab:group("自动急停")
    C.stop_on = g:checkbox("启用急停", false)
    C.stop_mode = g:combo("模式", { "开火前", "瞄准时", "始终" }, 1)
    C.stop_early = g:checkbox("提前急停（锁定即减速）", false)
end

do
    local g = main_tab:group("特殊武器")
    C.scope_on = g:checkbox("狙击自动开镜", false)
    C.revolver_on = g:checkbox("R8 自动击发", false)
    C.zeus_on = g:checkbox("Zeus 自动开火", false)
    C.knife_on = g:checkbox("自动刀（背刺）", false)
end

do
    local g = main_tab:group("快速探头")
    C.qp_on = g:checkbox("启用快速探头", false)
    C.qp_key = g:keybind("探头按键（需绑定）", 0)
    C.qp_mode = g:combo("回撤模式", { "松开回撤", "开火后回撤" }, 1)
    C.qp_color = g:color("起点标记颜色", color(255, 190, 90, 200), true)
    C.qp_div = g:label("──────── 探头辅助 ────────")
    C.pa_on = g:checkbox("启用探头辅助", false)
    C.pa_key = g:keybind("辅助按键（按住生效）", 0)
    C.pa_smooth = g:slider_float("辅助平滑", 1, 100, 20, "%.0f")
end

-- 状态组
local g_status = main_tab:group("状态")

-- ----------------------------------------------------------------------------
-- 目标筛选（修复版：先用角度筛候选，再 trace 验证）
-- ----------------------------------------------------------------------------
-- CS2 hitbox index 映射（最通用的一组，实测后可微调）
local PART_INDICES = {
    head    = { [0]  = true },
    chest   = { [1] = true, [2] = true },     -- neck + chest
    stomach = { [3] = true, [4] = true },     -- stomach + pelvis
    arms    = { [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true, [12] = true },
    legs    = { [13] = true, [14] = true, [15] = true, [16] = true, [17] = true, [18] = true },
}

local function part_enabled(part_name)
    if part_name == "head" and C.aim_head:get() then return true end
    if part_name == "chest" and C.aim_chest:get() then return true end
    if part_name == "stomach" and C.aim_stomach:get() then return true end
    if part_name == "arms" and C.aim_arms:get() then return true end
    if part_name == "legs" and C.aim_legs:get() then return true end
    return false
end

local function hb_in_part(hb)
    local idx = tonumber(hb and hb.index) or -1
    local grp = tonumber(hb and hb.group) or -1
    for part_name, indices in pairs(PART_INDICES) do
        if part_enabled(part_name) then
            if indices[idx] or indices[grp] then return true end
        end
    end
    return false
end

-- 最原始版：任何 hitbox 在 FOV 内就取第一个可用
local function find_best(eye, view, fov, min_dmg, min_dmg_aw, smoke_chk)
    local best = nil
    local players = entity.players()
    for i = 1, #players do
        local tp = players[i].pawn
        if tp ~= nil then
            local ok_a, alive = pcall(function() return tp:alive() end)
            local ok_e, enemy = pcall(function() return tp:is_enemy() end)
            if ok_a and alive and ok_e and enemy then
                local ok_h, hbs = pcall(function() return tp:hitboxes() end)
                if ok_h and type(hbs) == "table" then
                    for h = 1, #hbs do
                        local hb = hbs[h]
                        if hb.center ~= nil and hb_in_part(hb) then
                            local ang = math.calc_angle(eye, hb.center)
                            local dy = math.normalize_angle(ang.y - view.y)
                            local dp = math.normalize_angle(ang.x - view.x)
                            local score = m_sqrt(dy * dy + dp * dp)
                            if score <= fov then
                                local blocked = false
                                if smoke_chk then
                                    local s_ok, s_hit = pcall(trace.smoke, eye, hb.center)
                                    if s_ok and s_hit == true then blocked = true end
                                end
                                if not blocked then
                                    -- 原生弹道 trace 验证伤害
                                    local ok_t, res = pcall(trace.bullet, eye, hb.center, tp)
                                    if ok_t and type(res) == "table" and res.target_hit == true then
                                        local dmg = tonumber(res.target_damage) or 0
                                        local pen = res.penetrated == true
                                        local need = pen and min_dmg_aw or min_dmg
                                        if dmg >= need then
                                            if best == nil or score < best.score then
                                                best = { pawn = tp, pos = hb.center,
                                                    dmg = dmg, pen = pen, score = score,
                                                    radius = tonumber(hb.radius) or 4 }
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function reaction_ok(addr)
    local now = globals.realtime()
    local e = S.react[addr]
    if e == nil then
        local lo = C.aim_react_min:get()
        local hi = C.aim_react_max:get()
        if hi < lo then hi = lo end
        S.react[addr] = { t = now, need = (lo + m_random() * (hi - lo)) / 1000, seen = now }
        e = S.react[addr]
    end
    e.seen = now
    return now - e.t >= e.need
end

local function react_gc()
    local now = globals.realtime()
    if now - S.react_gc_t < 1 then return end
    S.react_gc_t = now
    for k, v in pairs(S.react) do
        if now - (v.seen or 0) > 3 then S.react[k] = nil end
    end
end

-- ----------------------------------------------------------------------------
-- 人性化弧线瞄准
-- ----------------------------------------------------------------------------
local function hum_scale()
    if not C.hum_on:get() then return 0 end
    return clamp(C.hum_amount:get() / 100, 0, 1)
end

local function reset_arc(eye, view, pos)
    local ang = math.calc_angle(eye, pos)
    local dp = math.normalize_angle(ang.x - view.x)
    local dy = math.normalize_angle(ang.y - view.y)
    S.arc_total = math.max(0.4, m_sqrt(dp * dp + dy * dy))
    S.arc_prev = 0
    local hs = hum_scale()
    local curve = C.hum_curve:get() / 100
    local crand = C.hum_curve_rand:get() / 100
    local dir = m_random() < 0.5 and -1 or 1
    S.arc_mag = hs * curve * S.arc_total * 0.45 * math.max(0, 1 + nrand() * crand) * dir
    local svar = C.hum_speed:get() / 100
    S.speed_jit = math.max(0.1, 1 + nrand() * svar * hs)
end

local function aim_at(cmd, view, eye, pos, smooth, dist_adj, hs)
    local ang = math.calc_angle(eye, pos)
    local dp = math.normalize_angle(ang.x - view.x)
    local dy = math.normalize_angle(ang.y - view.y)
    local dist_deg = m_sqrt(dp * dp + dy * dy)
    if dist_deg < 0.02 then return 0 end

    local step = math.remap(clamp(smooth, 1, 100), 1, 100, 25, 0.35)
    if dist_adj then
        local dist = eye:dist(pos)
        step = step / clamp(dist / 900, 0.45, 1.7)
    end
    step = step * S.speed_jit
    if step > dist_deg then step = dist_deg end

    local dir_p, dir_y = dp / dist_deg, dy / dist_deg
    local pp, py = -dir_y, dir_p

    local prog = 1 - clamp(dist_deg / S.arc_total, 0, 1)
    local arc_now = m_sin(prog * m_pi) * S.arc_mag
    local arc_delta = arc_now - S.arc_prev
    S.arc_prev = arc_now

    local step_p, step_y = step, step
    local noise_p, noise_y = 0, 0
    if hs > 0 then
        local noise_amt = C.hum_noise:get() / 100
        step_p = step * (1 + nrand() * noise_amt * hs)
        step_y = step * (1 + nrand() * noise_amt * hs)
        noise_p = nrand() * (C.hum_pitch:get() / 100) * hs * 0.25
        noise_y = nrand() * (C.hum_yaw:get() / 100) * hs * 0.25
    end

    local np = view.x + dir_p * step_p + pp * arc_delta + noise_p
    local ny = view.y + dir_y * step_y + py * arc_delta + noise_y
    np = clamp(np, -89, 89)
    ny = math.normalize_angle(ny)
    cmd:set_view_angles(vector(np, ny, 0))
    return dist_deg - step
end

-- ----------------------------------------------------------------------------
-- 自动急停
-- ----------------------------------------------------------------------------
local function release_move_keys(cmd)
    cmd:release(8) cmd:release(16) cmd:release(512) cmd:release(1024)
end

local function do_autostop(cmd, pawn)
    local ok, vel = pcall(function() return pawn:velocity() end)
    if not ok or vel == nil then return true end
    local speed = vel:length2d()
    local ok2, ms = pcall(engine.max_speed)
    local threshold = ((ok2 and tonumber(ms)) or 250) * 0.3
    if speed < threshold or speed < 12 then
        cmd:set_move(0, 0)
        release_move_keys(cmd)
        return true
    end
    local view = cmd:view_angles()
    local fwd, right = view:angle_vectors()
    local f = -(vel.x * fwd.x + vel.y * fwd.y)
    local s = -(vel.x * right.x + vel.y * right.y)
    f = clamp(f / 250, -1, 1)
    s = clamp(s / 250, -1, 1)
    cmd:set_move(f, s)
    release_move_keys(cmd)
    return false
end

local STOP_MODES = { "开火前", "瞄准时", "始终" }

local function fire_weapon(cmd, pawn, info)
    if C.stop_on:get() and combo_idx(C.stop_mode, STOP_MODES) == 1 then
        if not do_autostop(cmd, pawn) then return false end
    end
    cmd:press(1)
    return true
end

-- ----------------------------------------------------------------------------
-- 后坐力控制
-- ----------------------------------------------------------------------------
local function apply_rcs(cmd, pawn)
    local ok, punch = pcall(function() return pawn:aim_punch() end)
    if not ok or punch == nil then return end
    if punch.x == 0 and punch.y == 0 then
        S.old_punch_x, S.old_punch_y = 0, 0
        return
    end
    local k = clamp(C.rcs_strength:get() / 100 * S.rcs_rand, 0, 3)
    local dp = (punch.x - S.old_punch_x) * 2 * k
    local dy = (punch.y - S.old_punch_y) * 2 * k
    S.old_punch_x, S.old_punch_y = punch.x, punch.y
    if dp == 0 and dy == 0 then return end
    local v = cmd:view_angles()
    cmd:set_view_angles(vector(clamp(v.x - dp, -89, 89), math.normalize_angle(v.y - dy), 0))
end

-- ----------------------------------------------------------------------------
-- 自动扳机
-- ----------------------------------------------------------------------------
local function triggerbot(cmd, pawn, info, eye, view, now)
    if not C.trig_on:get() then S.trig_t0 = nil return end
    if C.trig_key_on:get() and not bind_active(C.trig_key) then S.trig_t0 = nil return end
    if info == nil or info.can_shoot == false then S.trig_t0 = nil return end

    local fwd = view:forward()
    local to = eye + fwd * 8192
    local ok, res = pcall(trace.bullet, eye, to)
    if not ok or type(res) ~= "table" or res.entity == nil then S.trig_t0 = nil return end
    local t = res.entity
    local ok2, enemy = pcall(function() return t:is_enemy() end)
    local ok3, alive = pcall(function() return t:alive() end)
    if not (ok2 and enemy and ok3 and alive) then S.trig_t0 = nil return end

    local hit_pos = res.position
    if hit_pos == nil then S.trig_t0 = nil return end

    if C.trig_head:get() then
        local ok4, head = pcall(function() return t:hitbox(0) end)
        if not ok4 or head == nil or hit_pos:dist(head) > 15 then
            S.trig_t0 = nil; return
        end
    end

    local dmg = tonumber(res.damage) or 0
    local pen = res.penetrated == true
    local ok5, res2 = pcall(trace.bullet, eye, hit_pos, t)
    if ok5 and type(res2) == "table" then
        if res2.target_damage ~= nil then dmg = tonumber(res2.target_damage) or dmg end
        pen = res2.penetrated == true
    end
    local need = pen and C.trig_min_dmg_aw:get() or C.trig_min_dmg:get()
    if dmg < need then S.trig_t0 = nil return end

    if C.trig_smoke:get() then
        local s_ok, s_hit = pcall(trace.smoke, eye, hit_pos)
        if s_ok and s_hit == true then S.trig_t0 = nil return end
    end
    if C.trig_flash:get() then
        local f_ok, fd = pcall(function() return pawn:get("C_CSPlayerPawn", "m_flFlashDuration", "float") end)
        if f_ok and type(fd) == "number" and fd > 0.3 then S.trig_t0 = nil return end
    end

    local dist = eye:dist(hit_pos)
    if hit_chance(info, dist, 10) * 100 < C.trig_hc:get() then S.trig_t0 = nil return end

    if S.trig_t0 == nil then S.trig_t0 = now end
    if now - S.trig_t0 < C.trig_delay:get() / 1000 then return end

    fire_weapon(cmd, pawn, info)
end

-- ----------------------------------------------------------------------------
-- 快速探头
-- ----------------------------------------------------------------------------
local function press_move_buttons(cmd, f, s)
    if f > 0.15 then cmd:press(8) elseif f < -0.15 then cmd:press(16) end
    if s > 0.15 then cmd:press(1024) elseif s < -0.15 then cmd:press(512) end
end

local function move_world_dir(cmd, dir)
    local view = cmd:view_angles()
    local fwd, right = view:angle_vectors()
    local f = dir.x * fwd.x + dir.y * fwd.y
    local s = dir.x * right.x + dir.y * right.y
    local len = m_sqrt(f * f + s * s)
    if len > 0.001 then f, s = f / len, s / len end
    cmd:set_move(f, s)
    press_move_buttons(cmd, f, s)
end

local QP_MODES = { "松开回撤", "开火后回撤" }

local function quick_peek_move(cmd, pawn, now)
    if not C.qp_on:get() then S.qp.active = false return end
    local held = bind_held(C.qp_key)
    local mode = combo_idx(C.qp_mode, QP_MODES)
    if not S.qp.active then
        if held then
            local ok, o = pcall(function() return pawn:origin() end)
            if not ok or o == nil then return end
            S.qp.active = true; S.qp.phase = "out"
            S.qp.ox, S.qp.oy, S.qp.oz = o.x, o.y, o.z
            local f, s = cmd:move()
            if f == 0 and s == 0 then s = 1 end
            S.qp.df, S.qp.ds = f, s
            S.qp.t0 = now; S.qp.fired = false
        end
        return
    end
    if S.qp.phase == "out" then
        cmd:set_move(S.qp.df, S.qp.ds)
        press_move_buttons(cmd, S.qp.df, S.qp.ds)
        if not held then S.qp.phase = "back"
        elseif mode == 2 and S.qp.fired then S.qp.phase = "back"
        elseif now - S.qp.t0 > 2.0 then S.qp.phase = "back" end
    elseif S.qp.phase == "back" then
        local ok, o = pcall(function() return pawn:origin() end)
        if not ok or o == nil then S.qp.active = false return end
        local dx, dy = S.qp.ox - o.x, S.qp.oy - o.y
        local d = m_sqrt(dx * dx + dy * dy)
        if d < 24 then
            S.qp.active = false; S.qp.phase = ""
            cmd:set_move(0, 0); release_move_keys(cmd)
        else
            move_world_dir(cmd, vector(dx, dy, 0))
        end
    end
end

-- ----------------------------------------------------------------------------
-- 主循环
-- ----------------------------------------------------------------------------
events.on("createmove", function(cmd)
    if not engine.in_game() then return end
    local pawn = entity.local_pawn()
    if pawn == nil then
        log_rate(2, "pawn is nil")
        return
    end
    local ok_alive, alive = pcall(function() return pawn:alive() end)
    if not ok_alive or not alive then
        S.cur_target = nil; S.aim_pos = nil
        return
    end

    local weapon, info = nil, nil
    local ok_w, w = pcall(function() return pawn:weapon() end)
    if ok_w and w ~= nil then
        weapon = w
        local ok_i, wi = pcall(function() return w:weapon_info() end)
        if ok_i then info = wi end
    end

    local ok_e, eye = pcall(function() return pawn:eye_position() end)
    if not ok_e or eye == nil then return end
    local view = cmd:view_angles()
    if view == nil then return end

    local now = globals.realtime()

    log_rate(2, "createmove OK",
        "weapon=" .. tostring(info and info.name or "nil"),
        "aim_on=" .. tostring(C.aim_on:get()),
        "aim_key_on=" .. tostring(C.aim_key_on:get()),
        "view=(" .. string.format("%.1f", view.x) .. "," .. string.format("%.1f", view.y) .. ")")

    -- RCS 随机系数
    local attacking = cmd:has(1)
    if attacking and not S.prev_attack then
        local lo, hi = C.rcs_min:get(), C.rcs_max:get()
        if hi < lo then hi = lo end
        S.rcs_rand = (lo + m_random() * (hi - lo)) / 100
    end
    S.prev_attack = attacking

    -- 1. 快速探头
    quick_peek_move(cmd, pawn, now)

    -- 2. 自瞄（checkbox 常开 + keybind 可选附加开关，刀/Zeus 跳过）
    local locked = nil
    local aim_allowed = C.aim_on:get()
        and (not C.aim_key_on:get() or bind_active(C.aim_key))
        and info ~= nil and not is_knife(info) and not is_zeus(info)
    if aim_allowed then
        locked = find_best(eye, view, C.aim_fov:get(),
            C.aim_min_dmg:get(), C.aim_min_dmg_aw:get(), C.aim_smoke:get())

        if locked ~= nil then
            local addr = locked.pawn:address()
            log_rate(2, "锁定目标 addr=" .. tostring(addr),
                "dmg=" .. tostring(locked.dmg),
                "pen=" .. tostring(locked.pen),
                "score=" .. string.format("%.2f", locked.score))

            if reaction_ok(addr) then
                if S.cur_target ~= addr then
                    reset_arc(eye, view, locked.pos)
                end
                local remaining = aim_at(cmd, view, eye, locked.pos,
                    C.aim_smooth:get(), C.aim_dist_adj:get(), hum_scale())
                view = cmd:view_angles()
                S.aim_pos = locked.pos

                local want_fire = C.aim_autofire:get() or (S.qp.active and S.qp.phase == "out")
                if want_fire and remaining < 1.0 then
                    local can_fire = true
                    if S.qp.active and S.qp.phase == "out" then
                        can_fire = do_autostop(cmd, pawn)
                    end
                    if can_fire then
                        local dist = eye:dist(locked.pos)
                        local hc_ok = hit_chance(info, dist, locked.radius) * 100 >= C.aim_hc:get()
                        local ground_ok = (not C.aim_ground:get()) or pawn:on_ground()
                        if hc_ok and ground_ok then
                            fire_weapon(cmd, pawn, info)
                        end
                    end
                end
            else
                S.aim_pos = nil
            end
        else
            S.cur_target = nil; S.aim_pos = nil
            log_rate(2, "find_best 未找到目标")
        end
    else
        S.cur_target = nil; S.aim_pos = nil
    end

    -- 3. 探头辅助
    if locked == nil and C.pa_on:get() and bind_held(C.pa_key) and info ~= nil then
        local t = find_best(eye, view, 25, 0, 0, C.aim_smoke:get())
        if t ~= nil then
            aim_at(cmd, view, eye, t.pos, C.pa_smooth:get(), true, hum_scale())
            view = cmd:view_angles()
        end
    end

    -- 4. RCS
    if C.rcs_on:get() and info ~= nil then
        local auto_ok = (not C.rcs_auto_only:get()) or info.full_auto == true
        local engaged = C.rcs_standalone:get() or locked ~= nil or attacking
        if auto_ok and engaged then
            apply_rcs(cmd, pawn)
            view = cmd:view_angles()
        end
    end

    -- 5. 自动急停
    if C.stop_on:get() then
        local mode = combo_idx(C.stop_mode, STOP_MODES)
        if mode == 3 then do_autostop(cmd, pawn)
        elseif mode == 2 and locked ~= nil then do_autostop(cmd, pawn) end
    end
    if C.stop_early:get() and locked ~= nil then do_autostop(cmd, pawn) end

    -- 6. 扳机
    triggerbot(cmd, pawn, info, eye, view, now)

    -- 7. 特殊武器
    if info ~= nil then
        if C.scope_on:get() and locked ~= nil and is_sniper(info) then
            local ok_s, scoped = pcall(function() return pawn:scoped() end)
            if ok_s and not scoped then cmd:press(2048) end
        end
        if C.revolver_on:get() and is_revolver(info) and locked ~= nil then
            if S.qp.fired or attacking or C.aim_autofire:get() then
                if S.fire_toggle then cmd:press(1) else cmd:release(1) end
                S.fire_toggle = not S.fire_toggle
            end
        end
        if C.zeus_on:get() and is_zeus(info) and info.can_shoot ~= false then
            local players = entity.players()
            for i = 1, #players do
                local tp = players[i].pawn
                if tp ~= nil then
                    local ok_a, al = pcall(function() return tp:alive() end)
                    local ok_e2, en = pcall(function() return tp:is_enemy() end)
                    if ok_a and al and ok_e2 and en then
                        local ok_h, hbs = pcall(function() return tp:hitboxes() end)
                        if ok_h and type(hbs) == "table" then
                            for h = 1, #hbs do
                                local hb = hbs[h]
                                if hb.index == 2 and hb.center ~= nil then
                                    if eye:dist(hb.center) < 185 then
                                        local ok_t, res = pcall(trace.bullet, eye, hb.center, tp)
                                        if ok_t and type(res) == "table" and res.target_hit and (tonumber(res.target_damage) or 0) >= 50 then
                                            local ang = math.calc_angle(eye, hb.center)
                                            cmd:set_view_angles(vector(ang.x, ang.y, 0))
                                            cmd:press(1)
                                        end
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if C.knife_on:get() and is_knife(info) then
            local players = entity.players()
            for i = 1, #players do
                local tp = players[i].pawn
                if tp ~= nil then
                    local ok_a, al = pcall(function() return tp:alive() end)
                    local ok_e2, en = pcall(function() return tp:is_enemy() end)
                    if ok_a and al and ok_e2 and en then
                        local ok_o, to = pcall(function() return tp:origin() end)
                        if ok_o and to ~= nil and eye:dist(to) < 78 then
                            local chest = to + vector(0, 0, 48)
                            local ok_t, res = pcall(trace.bullet, eye, chest, tp)
                            if ok_t and type(res) == "table" and res.target_hit then
                                local ok_ta, ta = pcall(function() return tp:eye_angles() end)
                                local backstab = false
                                if ok_ta and ta ~= nil then
                                    local tfwd = ta:forward()
                                    local to_me = (eye - chest):normalized()
                                    backstab = tfwd:dot(to_me) > 0.3
                                end
                                local ang = math.calc_angle(eye, chest)
                                cmd:set_view_angles(vector(ang.x, ang.y, 0))
                                if backstab then cmd:press(2048) else cmd:press(1) end
                            end
                        end
                    end
                end
            end
        end
    end

    if S.qp.active and S.qp.phase == "out" and cmd:has(1) then S.qp.fired = true end

    react_gc()
end)

-- ----------------------------------------------------------------------------
-- 可视化
-- ----------------------------------------------------------------------------
events.on("paint", function()
    if not engine.in_game() then return end
    local sw, sh = render.screen_size()
    if C.aim_on:get() and C.aim_vis_fov:get() then
        local fov = C.aim_fov:get()
        local cam = S.cam_fov
        if cam > 1 and fov > 0 then
            local rad = m_tan(m_rad(fov)) / m_tan(m_rad(cam) / 2) * (sh / 2)
            if rad > 2 and rad < sh then
                render.circle(sw / 2, sh / 2, rad, C.aim_fov_col:get(), 64, 1)
            end
        end
    end
    if C.aim_vis_tar:get() and S.aim_pos ~= nil then
        local x, y = render.world_to_screen(S.aim_pos)
        if x ~= nil then
            render.circle(x, y, 7, color(255, 80, 80, 220), 24, 1.5)
            render.circle_filled(x, y, 2, color(255, 255, 255, 230), 12)
        end
    end
    if S.qp.active then
        local x, y = render.world_to_screen(vector(S.qp.ox, S.qp.oy, S.qp.oz))
        if x ~= nil then
            render.circle(x, y, 6, C.qp_color:get(), 20, 1.5)
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 状态组
-- ----------------------------------------------------------------------------
do
    local insecure_chk = g_status:checkbox("Allow Insecure（允许不安全模式）", client.insecure())
    g_status:label("当前 Allow Insecure：" .. (client.insecure() and "已开启" or "未开启"))
    g_status:button("应用并立即重载脚本", function()
        pcall(function() config.set("lua.allow_insecure", insecure_chk:get()) end)
        pcall(function() client.reload() end)
    end)
    g_status:label("由Awa Subaru移植")

    local shexec
    local function init_shexec()
        if shexec ~= nil then return end
        if type(ffi) ~= "table" or type(ffi.cdef) ~= "function" then shexec = false; return end
        pcall(ffi.cdef, [[
            void * __stdcall ShellExecuteA(void *hwnd, const char *op, const char *file,
                                           const char *params, const char *dir, int show);
        ]])
        local fn
        pcall(function() fn = ffi.C.ShellExecuteA end)
        if not fn then
            local ns; pcall(function() ns = ffi.load("Shell32") end)
            if ns then pcall(function() fn = ns.ShellExecuteA end) end
        end
        shexec = fn or false
    end
    local function open_url(url)
        init_shexec()
        if shexec then
            local ok, err = pcall(function() return shexec(nil, "open", url, nil, nil, 1) end)
            if ok then return end
            log("ShellExecuteA 失败", tostring(err))
        end
        local ok2, err2 = pcall(function() panorama.SteamOverlayAPI.OpenExternalBrowserURL(url) end)
        if not ok2 then log("Steam 覆盖层打开失败", tostring(err2)) end
    end
    g_status:button("闲鱼:我是学生你懂我意思吧", function()
        open_url("https://m.tb.cn/h.jS7Zhk2?tk=ZYFI6cX5T4D")
    end)
end
