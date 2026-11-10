-- @author vitma
-- @uid 1
-- =========================================================================
--     手雷助手（Aimware helper.lua 移植版） for Neverwin CS2
--     点位数据默认读取 C:\neverwin\scripts\data\helper_data.txt（需开启 insecure）
-- =========================================================================

local DATA_FILE = "helper_data.txt"
local DEFAULT_DATA = "return {\n}\n"

local MOVE_SCALE = 1
local IN_ATTACK, IN_JUMP, IN_DUCK = 1, 2, 4
local IN_FORWARD, IN_BACK = 8, 16
local IN_USE = 32
local IN_MOVELEFT, IN_MOVERIGHT = 512, 1024
local IN_ATTACK2 = 2048
local IN_SPEED = 65536

local BTN_ORDER = {
    "in_attack", "in_jump", "in_duck", "in_forward", "in_moveleft",
    "in_moveright", "in_back", "in_use", "in_attack2", "in_speed"
}
local BTN_CHARS = {
    in_attack = "A", in_jump = "J", in_duck = "D",
    in_forward = "F", in_moveleft = "L", in_moveright = "R",
    in_back = "B", in_use = "U", in_attack2 = "Z", in_speed = "S"
}
local BTN_CHARS_INV = {
    A = "in_attack", J = "in_jump", D = "in_duck",
    F = "in_forward", L = "in_moveleft", R = "in_moveright",
    B = "in_back", U = "in_use", Z = "in_attack2", S = "in_speed"
}

-- 手雷物品定义编号 -> 内部名称（兼容不同版本 weapon_info 字段差异）
local GRENADE_DEF = {
    [43] = "flashbang",
    [44] = "hegrenade",
    [45] = "smokegrenade",
    [46] = "molotov",
    [47] = "decoy",
    [48] = "incgrenade",
    [49] = "firebomb",
}

-- ---------------------------------------------------------------------------
ui.sidebar("道具助手", "gear")
print("Awa Subaru制作")
print("闲鱼:我是学生你懂我意思吧")

-- 界面（独立标签页：左列 回放中心/手动创建点位/录制，右列 显示效果/点位管理/状态）
-- ---------------------------------------------------------------------------
local main_tab = ui.tab("道具助手")

-- 回放中心组（左列，第 1 组）
local pb_group = main_tab:group("回放中心")
local enabled = pb_group:checkbox("启用", true)
local execute_key = pb_group:keybind("执行按键（默认鼠标左键）", 1)
local smooth = pb_group:slider_float("瞄准平滑度", 1, 50, 8, "%.0f")
local position_radius = pb_group:slider_float("点位半径", 2, 40, 8, "%.0f")
local show_distance = pb_group:slider_float("显示距离", 100, 5000, 1200, "%.0f")
local rec_fov = pb_group:slider_float("FOV", 1, 180, 5, "%.0f")
local auto_path = pb_group:checkbox("自动走到最近点位", true)
local path_range = pb_group:slider_float("自动寻路范围", 50, 1500, 50, "%.0f")
local path_center = pb_group:slider_float("路径中心", 0.1, 4, 0.1, "%.1f")
local path_settle = pb_group:slider_float("路径稳定延迟", 0.1, 2.0, 1.0, "%.1f")

-- 显示效果组（右列，第 2 组）
local disp_group = main_tab:group("显示效果")
local show_points = disp_group:checkbox("显示世界标签", true)
local show_spot_ring = disp_group:checkbox("显示点位圆环", true)
local show_fov = disp_group:checkbox("显示视场圆环", false)
local show_status = disp_group:checkbox("显示回放状态", false)
local bg_color = disp_group:color("标签背景", color(18, 20, 28, 195), true)
local glow_color = disp_group:color("标签光晕", color(255, 120, 70, 200), true)
local red = disp_group:color("瞄准点（待机）", color(245, 70, 70, 255))
local green = disp_group:color("瞄准点（就绪/播放中）", color(80, 230, 120, 255))

-- 录制/手动点位控件：前向声明（控件创建在逻辑函数之后，逻辑函数以 upvalue 引用）
local rec_name, rec_jump, rec_walk, rec_walk_ticks, rec_walk_dir, rec_crouch, rec_throw
local rec_recording, rec_save_macro, rec_save, del_save
local rec_prev = { save = false, macro = false, del = false }

-- ---------------------------------------------------------------------------
-- 通用工具
-- ---------------------------------------------------------------------------
local function normalize_yaw(yaw)
    while yaw > 180 do yaw = yaw - 360 end
    while yaw < -180 do yaw = yaw + 360 end
    return yaw
end

-- FOV 统一由菜单滑块控制，对所有点位（含旧数据）生效
local function point_lock_deg(point)
    local value = tonumber(rec_fov:get()) or 5
    return math.max(1, value)
end

local function angle_delta_to_point(view, point)
    local tp = math.max(-89, math.min(89, point.ang.pitch))
    local ty = normalize_yaw(point.ang.yaw)
    local vp = math.max(-89, math.min(89, view.pitch))
    local vy = normalize_yaw(view.yaw)
    local dp = tp - vp
    local dy = normalize_yaw(ty - vy)
    while dp > 180 do dp = dp - 360 end
    while dp < -180 do dp = dp + 360 end
    return dp, dy
end

local function is_view_in_point_fov(view, point)
    local lock = point_lock_deg(point)
    local pitch_delta, yaw_delta = angle_delta_to_point(view, point)
    return math.abs(pitch_delta) < lock and math.abs(yaw_delta) < lock
end

local function distance_xy(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function point_position(point)
    return vector(point.pos.x, point.pos.y, point.pos.z)
end

local function map_name()
    local name = game.map() or ""
    local short = name:match("maps/(.+)%.vpk")
    if short then name = short end
    name = name:gsub("%.vpk$", "")
    return name
end

-- 当前镜头视角（pitch/yaw 表）
local function camera_view()
    local ok, v = pcall(engine.view_angles)
    if ok and v then
        return { pitch = tonumber(v.x) or 0, yaw = tonumber(v.y) or 0 }
    end
    return { pitch = 0, yaw = 0 }
end

local function is_fire_grenade(name)
    return name == "molotov" or name == "incgrenade" or name == "firebomb"
end

local function weapon_matches(point_weapon, held_weapon)
    if point_weapon == nil then return true end
    if point_weapon == held_weapon then return true end
    return is_fire_grenade(point_weapon) and is_fire_grenade(held_weapon)
end

local function get_player()
    local pawn = entity.local_pawn()
    if pawn == nil then return nil end
    local ok, alive = pcall(function() return pawn:alive() end)
    if not ok or not alive then return nil end
    return pawn
end

-- 手持手雷名称（非手雷返回 nil）
local function get_grenade(pawn)
    local ok, weapon = pcall(function() return pawn:weapon() end)
    if not ok or weapon == nil then return nil end

    local ok2, info = pcall(function() return weapon:weapon_info() end)
    if not ok2 or info == nil then return nil end

    local def = tonumber(info.def)
    if def and GRENADE_DEF[def] then return GRENADE_DEF[def] end

    local raw = tostring(info.name or "")
    raw = raw:lower():gsub("^weapon_", "")
    if GRENADE_DEF[43] == raw or is_fire_grenade(raw) then return raw end
    if raw == "flashbang" or raw == "hegrenade" or raw == "smokegrenade" or raw == "decoy" then
        return raw
    end
    return nil
end

local function bind_down(kb)
    local v = kb:get()
    if type(v) == "boolean" then return v end
    if type(v) == "number" and v > 0 then
        return input.key_down(v)
    end
    local ok, active = pcall(function() return kb:active() end)
    if ok and type(active) == "boolean" then return active end
    return false
end

local function is_execute_down()
    return bind_down(execute_key)
end

-- ---------------------------------------------------------------------------
-- 数据存取（优先 insecure 文件，失败时退回 db）
-- ---------------------------------------------------------------------------
local function read_raw_data()
    local ok, raw = pcall(function() return file.read(DATA_FILE) end)
    if ok and type(raw) == "string" and raw ~= "" then return raw end
    if db and type(db.load) == "function" then
        local ok2, stored = pcall(db.load, "grenade_helper_data", nil)
        if ok2 and type(stored) == "string" and stored ~= "" then return stored end
    end
    return nil
end

local function write_raw_data(text)
    local ok, res = pcall(function() return file.write(DATA_FILE, text) end)
    if ok and res ~= false then return true end
    if db and type(db.save) == "function" then
        local ok2 = pcall(db.save, "grenade_helper_data", text)
        if ok2 then return true end
    end
    return false
end

local function load_lineups()
    local raw = read_raw_data()
    if raw == nil then
        write_raw_data(DEFAULT_DATA)
        return {}
    end
    local load_ok, fn = pcall(load, raw)
    if not load_ok or type(fn) ~= "function" then
        print("[手雷助手] 解析 " .. DATA_FILE .. " 失败")
        return {}
    end
    local success, data = pcall(fn)
    if not success or type(data) ~= "table" then
        print("[手雷助手] " .. DATA_FILE .. " 必须返回一个表")
        return {}
    end
    return data
end

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
local lineups = load_lineups()
if next(lineups) == nil then
    print("[手雷助手] 未读取到点位：请开启 insecure，并把 helper_data.txt 放到 C:\\neverwin\\scripts\\data")
end
local loaded_map = ""
local label_alphas = {}

local state = "idle"
local active = nil
local candidate = nil
local aim_pitch = 0
local aim_yaw = 0
local stable_ticks = 0
local playback_tick = 0
local await_key_release = false
local path_phase = "none"
local path_settle_ticks = 0
local path_stuck_ticks = 0
local path_last_nd = 1e9
local macro_diag = nil  -- 临时诊断：宏播放帧移动量统计

local rec_on_prev = false
local rec_key_prev = false   -- 绑键上一帧物理按下状态
local rec_on_latch = false   -- 录制开关锁存（按一下开、再按一下关）
local rec_waiting = false
local rec_active = false
local rec_buf = {}
local rec_meta = nil
local rec_ready_frames = nil
local rec_ready_meta = nil

local function valid_point(point)
    if type(point) ~= "table" then return false end
    local p, a = point.pos, point.ang
    return type(p) == "table" and type(a) == "table" and
        type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number" and
        type(a.pitch) == "number" and type(a.yaw) == "number"
end

local function reset_playback()
    state = "idle"
    active = nil
    stable_ticks = 0
    playback_tick = 0
end

local function point_has_macro(point)
    return type(point) == "table"
        and type(point.movement) == "table"
        and type(point.movement.frames) == "table"
end

local function calc_move(btn1, btn2)
    if btn1 then return MOVE_SCALE end
    if btn2 then return -MOVE_SCALE end
    return 0
end

local function parse_buttons_str(str)
    local down, up = {}, {}
    if type(str) ~= "string" then return down, up end
    for i = 1, #str do
        local c = str:sub(i, i)
        local lower = c:lower()
        if c == lower then
            table.insert(up, BTN_CHARS_INV[c:upper()])
        else
            table.insert(down, BTN_CHARS_INV[c])
        end
    end
    return down, up
end

local function compress_usercmds(usercmds)
    if type(usercmds) ~= "table" or #usercmds == 0 then return {} end
    local frames = {}
    local current = {
        viewangles = { pitch = usercmds[1].pitch, yaw = usercmds[1].yaw },
        buttons = {}
    }
    for _, key in ipairs(BTN_ORDER) do
        current.buttons[key] = false
    end
    local empty_count = 0
    for _, cmd in ipairs(usercmds) do
        local buttons = ""
        for _, btn in ipairs(BTN_ORDER) do
            local value_prev = current.buttons[btn]
            if cmd[btn] and not value_prev then
                buttons = buttons .. BTN_CHARS[btn]
            elseif not cmd[btn] and value_prev then
                buttons = buttons .. string.lower(BTN_CHARS[btn])
            end
            current.buttons[btn] = cmd[btn] and true or false
        end
        local frame = {
            cmd.pitch - current.viewangles.pitch,
            cmd.yaw - current.viewangles.yaw,
            buttons,
            cmd.forwardmove,
            cmd.sidemove
        }
        current.viewangles = { pitch = cmd.pitch, yaw = cmd.yaw }
        if frame[#frame] == calc_move(cmd.in_moveright, cmd.in_moveleft) then
            frame[#frame] = nil
            if frame[#frame] == calc_move(cmd.in_forward, cmd.in_back) then
                frame[#frame] = nil
                if frame[#frame] == "" then
                    frame[#frame] = nil
                    if frame[#frame] == 0 then
                        frame[#frame] = nil
                        if frame[#frame] == 0 then
                            frame[#frame] = nil
                        end
                    end
                end
            end
        end
        if #frame > 0 then
            if empty_count > 0 then
                table.insert(frames, empty_count)
                empty_count = 0
            end
            table.insert(frames, frame)
        else
            empty_count = empty_count + 1
        end
    end
    if empty_count > 0 then
        table.insert(frames, empty_count)
    end
    return frames
end

local function decompress_frames(raw_frames, base_ang)
    if type(raw_frames) ~= "table" then return nil end
    local frames = {}
    for _, frame in ipairs(raw_frames) do
        if type(frame) == "number" then
            if frame <= 0 then return nil end
            for _ = 1, frame do
                table.insert(frames, {})
            end
        elseif type(frame) == "table" then
            table.insert(frames, frame)
        else
            return nil
        end
    end
    local current = {
        viewangles = {
            pitch = (base_ang and base_ang.pitch) or 0,
            yaw = (base_ang and base_ang.yaw) or 0
        },
        buttons = {},
        forwardmove = 0,
        sidemove = 0
    }
    for _, key in ipairs(BTN_ORDER) do
        current.buttons[key] = false
    end
    local out = {}
    for i, value in ipairs(frames) do
        local pitch = value[1]
        local yaw = value[2]
        local buttons = value[3]
        local forwardmove = value[4]
        local sidemove = value[5]
        current.viewangles.pitch = current.viewangles.pitch + (pitch or 0)
        current.viewangles.yaw = current.viewangles.yaw + (yaw or 0)
        if type(buttons) == "string" then
            local buttons_down, buttons_up = parse_buttons_str(buttons)
            for _, btn in ipairs(buttons_down) do
                if btn then current.buttons[btn] = true end
            end
            for _, btn in ipairs(buttons_up) do
                if btn then current.buttons[btn] = false end
            end
        end
        if type(forwardmove) == "number" then
            current.forwardmove = forwardmove
        else
            current.forwardmove = calc_move(current.buttons.in_forward, current.buttons.in_back)
        end
        if type(sidemove) == "number" then
            current.sidemove = sidemove
        else
            current.sidemove = calc_move(current.buttons.in_moveright, current.buttons.in_moveleft)
        end
        local row = {
            pitch = current.viewangles.pitch,
            yaw = current.viewangles.yaw,
            forwardmove = current.forwardmove,
            sidemove = current.sidemove
        }
        for btn, pressed in pairs(current.buttons) do
            row[btn] = pressed
        end
        out[i] = row
    end
    return out
end

local function ensure_macro_cmds(point)
    if point._macro_cmds then return point._macro_cmds end
    local ok, cmds = pcall(decompress_frames, point.movement.frames, point.ang)
    if not ok or type(cmds) ~= "table" or #cmds == 0 then return nil end
    point._macro_cmds = cmds
    return cmds
end

local function escape_lua_string(value)
    return tostring(value):gsub("\\", "\\\\"):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\"", "\\\"")
end

local function serialize_frames(frames)
    local parts = {}
    for i, f in ipairs(frames) do
        if type(f) == "number" then
            parts[i] = tostring(math.floor(f + 0.5))
        else
            local cells = {}
            for j = 1, #f do
                local x = f[j]
                if type(x) == "string" then
                    cells[j] = "\"" .. escape_lua_string(x) .. "\""
                elseif type(x) == "number" then
                    if x == math.floor(x) then
                        cells[j] = string.format("%d", x)
                    else
                        cells[j] = string.format("%.4f", x)
                    end
                else
                    cells[j] = "0"
                end
            end
            parts[i] = "{" .. table.concat(cells, ", ") .. "}"
        end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function read_data_file()
    return read_raw_data() or DEFAULT_DATA
end

local function write_data_file(text)
    return write_raw_data(text)
end

local function build_manual_entry(ctx, name)
    return "        {\n" ..
        "            name   = \"" .. escape_lua_string(name) .. "\",\n" ..
        "            pos    = {x=" .. string.format("%.1f", ctx.pos.x) ..
        ", y=" .. string.format("%.1f", ctx.pos.y) ..
        ",  z=" .. string.format("%.1f", ctx.pos.z) .. "},\n" ..
        "            ang    = {pitch=" .. string.format("%.2f", ctx.ang.pitch) ..
        ", yaw=" .. string.format("%.2f", ctx.ang.yaw) .. "},\n" ..
        "            jump   = " .. tostring(rec_jump:get()) .. ",\n" ..
        "            crouch = " .. tostring(rec_crouch:get()) .. ",\n" ..
        "            walk   = " .. tostring(rec_walk:get()) .. ",\n" ..
        "            walk_ticks = " .. tostring(math.floor(rec_walk_ticks:get())) .. ",\n" ..
        "            walk_dir = " .. tostring(rec_walk_dir:get()) .. ",\n" ..
        "            throw_mode = " .. tostring(rec_throw:get()) .. ",\n" ..
        "            weapon = \"" .. escape_lua_string(ctx.weapon) .. "\",\n" ..
        "            range  = " .. tostring(math.floor(rec_fov:get())) .. ",\n" ..
        "        },\n"
end

local function build_macro_entry(ctx, name, frames)
    return "        {\n" ..
        "            name   = \"" .. escape_lua_string(name) .. "\",\n" ..
        "            pos    = {x=" .. string.format("%.1f", ctx.pos.x) ..
        ", y=" .. string.format("%.1f", ctx.pos.y) ..
        ",  z=" .. string.format("%.1f", ctx.pos.z) .. "},\n" ..
        "            ang    = {pitch=" .. string.format("%.2f", ctx.ang.pitch) ..
        ", yaw=" .. string.format("%.2f", ctx.ang.yaw) .. "},\n" ..
        "            weapon = \"" .. escape_lua_string(ctx.weapon) .. "\",\n" ..
        "            range  = " .. tostring(math.floor(rec_fov:get())) .. ",\n" ..
        "            movement = { frames = " .. serialize_frames(frames) .. " },\n" ..
        "        },\n"
end

local function insert_point_entry(text, map, entry)
    local map_key = '    ["' .. map .. '"] = {'
    local mpos = text:find(map_key, 1, true)
    if mpos then
        local block_start = mpos + #map_key
        local depth = 1
        local ci = block_start
        while ci <= #text and depth > 0 do
            local ch = text:sub(ci, ci)
            if ch == "{" then depth = depth + 1
            elseif ch == "}" then depth = depth - 1 end
            if depth > 0 then ci = ci + 1 end
        end
        return text:sub(1, ci - 1) .. "\n" .. entry .. "    " .. text:sub(ci)
    end
    local new_map = '    ["' .. map .. '"] = {\n' .. entry .. "    },\n"
    return text:gsub("return%s*%{", "return {\n" .. new_map, 1)
end

local function find_entry_bounds(text, point)
    local px_str = string.format("%.1f", point.pos.x)
    local py_str = string.format("%.1f", point.pos.y)
    local pitch_str = string.format("%.2f", point.ang.pitch)
    local yaw_str = string.format("%.2f", point.ang.yaw)
    local search_from = 1
    local found_at = nil
    while true do
        local pos_x = text:find("x=" .. px_str, search_from, true)
        if not pos_x then break end
        local line_end = text:find("\n", pos_x, true) or #text
        local line_str = text:sub(pos_x, line_end)
        if line_str:find("y=" .. py_str, 1, true) then
            local ang_pos = text:find("ang    = {pitch=", pos_x, true)
            if ang_pos and ang_pos < pos_x + 180 then
                local ang_end = text:find("}", ang_pos, true) or ang_pos
                local ang_str = text:sub(ang_pos, ang_end)
                if ang_str:find("pitch=" .. pitch_str, 1, true) and ang_str:find("yaw=" .. yaw_str, 1, true) then
                    found_at = pos_x
                    break
                end
            end
        end
        search_from = pos_x + 1
    end
    if not found_at then return nil, nil end

    local entry_start = found_at
    while entry_start > 1 do
        entry_start = entry_start - 1
        if text:sub(entry_start, entry_start + 8) == "        {" then break end
    end

    local depth = 0
    local ci = entry_start
    local entry_end = nil
    while ci <= #text do
        local ch = text:sub(ci, ci)
        if ch == "{" then depth = depth + 1
        elseif ch == "}" then
            depth = depth - 1
            if depth == 0 then
                entry_end = ci + 1
                if text:sub(entry_end, entry_end) == "," then entry_end = entry_end + 1 end
                if text:sub(entry_end, entry_end) == "\n" then entry_end = entry_end + 1 end
                break
            end
        end
        ci = ci + 1
    end
    return entry_start, entry_end
end

local function reload_lineups()
    lineups = load_lineups()
    label_alphas = {}
end

local function player_speed_2d(pawn)
    local ok, v = pcall(function() return pawn:velocity() end)
    if not ok or v == nil then return 0 end
    local vx, vy = tonumber(v.x) or 0, tonumber(v.y) or 0
    return math.sqrt(vx * vx + vy * vy)
end

local function flag_down(buttons, flag)
    return bit.band(buttons, flag) ~= 0
end

-- ---------------------------------------------------------------------------
-- cmd 读写封装（Neverwin wl.cmd）
-- ---------------------------------------------------------------------------
local function cmd_buttons(cmd)
    local ok, b = pcall(function() return cmd:buttons() end)
    if ok and type(b) == "number" then return math.floor(b) end
    return 0
end

local function cmd_set_buttons(cmd, mask)
    pcall(function() cmd:set_buttons(math.floor(mask)) end)
end

local function cmd_view(cmd)
    local ok, v = pcall(function() return cmd:view_angles() end)
    if ok and v then
        return tonumber(v.x) or 0, tonumber(v.y) or 0
    end
    local view = camera_view()
    return view.pitch, view.yaw
end

local function cmd_move(cmd)
    local ok, f, s = pcall(function() return cmd:move() end)
    if ok then
        return tonumber(f) or 0, tonumber(s) or 0
    end
    return 0, 0
end

local function capture_cmd_frame(cmd)
    local buttons = cmd_buttons(cmd)
    local pitch, yaw = cmd_view(cmd)
    local fwd, side = cmd_move(cmd)
    return {
        pitch = pitch,
        yaw = yaw,
        forwardmove = fwd,
        sidemove = side,
        in_attack = flag_down(buttons, IN_ATTACK),
        in_attack2 = flag_down(buttons, IN_ATTACK2),
        in_jump = flag_down(buttons, IN_JUMP),
        in_duck = flag_down(buttons, IN_DUCK),
        in_forward = flag_down(buttons, IN_FORWARD),
        in_back = flag_down(buttons, IN_BACK),
        in_moveleft = flag_down(buttons, IN_MOVELEFT),
        in_moveright = flag_down(buttons, IN_MOVERIGHT),
        in_use = flag_down(buttons, IN_USE),
        in_speed = flag_down(buttons, IN_SPEED)
    }
end

local function commit_recording_buffer()
    if #rec_buf > 0 and rec_meta then
        local ok, frames = pcall(compress_usercmds, rec_buf)
        if ok and type(frames) == "table" and #frames > 0 then
            rec_ready_frames = frames
            rec_ready_meta = rec_meta
            print(string.format("[手雷助手] 已录制 %d tick（压缩后 %d）", #rec_buf, #frames))
        else
            print("[手雷助手] 录制压缩失败")
        end
    else
        print("[手雷助手] 录制已取消（为空）")
    end
    rec_active = false
    rec_waiting = false
    rec_buf = {}
    rec_meta = nil
end

local function update_recording(cmd, pawn)
    -- 绑键统一当"按一下切换"处理：只在按下瞬间翻转锁存，
    -- 绑定无论设为按住(hold)还是切换(toggle)模式，行为一致
    local down = false
    pcall(function() down = rec_recording:active() end)  -- keybind 状态用 :active()（:get() 返回键码）
    if down and not rec_key_prev then
        rec_on_latch = not rec_on_latch
    end
    rec_key_prev = down

    local on = rec_on_latch
    if on and not rec_on_prev then
        rec_waiting = true
        rec_active = false
        rec_buf = {}
        rec_meta = nil
        print("[手雷助手] 录制已就绪：手持道具并保持静止")
    elseif (not on) and rec_on_prev then
        commit_recording_buffer()
    end
    rec_on_prev = on
    if not on or pawn == nil then return end

    if rec_waiting and not rec_active then
        if player_speed_2d(pawn) >= 2 then return end
        local weapon = get_grenade(pawn)
        if weapon == nil then return end
        local view = camera_view()
        local origin = pawn:origin()
        rec_meta = {
            pos = { x = origin.x, y = origin.y, z = origin.z },
            ang = { pitch = view.pitch, yaw = view.yaw },
            weapon = weapon,
            map = map_name()
        }
        rec_buf = {}
        rec_active = true
        rec_waiting = false
        table.insert(rec_buf, capture_cmd_frame(cmd))
        print("[手雷助手] 录制开始")
        return
    end

    if not rec_active then return end
    table.insert(rec_buf, capture_cmd_frame(cmd))
end

local function get_live_record_context()
    local pawn = get_player()
    if pawn == nil then return nil end
    local weapon = get_grenade(pawn)
    if weapon == nil then return nil end
    local origin = pawn:origin()
    local view = camera_view()
    return {
        pos = origin,
        ang = view,
        map = map_name(),
        weapon = weapon
    }
end

local function get_macro_record_context()
    if rec_ready_meta then
        return {
            pos = rec_ready_meta.pos,
            ang = rec_ready_meta.ang,
            map = rec_ready_meta.map,
            weapon = rec_ready_meta.weapon
        }
    end
    return nil
end

local function frame_time()
    local ok, ft = pcall(globals.frametime)
    if ok and type(ft) == "number" and ft > 0 then return ft end
    return 0.016
end

local function point_key(point)
    return string.format("%d,%d,%d", math.floor(point.pos.x + 0.5), math.floor(point.pos.y + 0.5), math.floor(point.pos.z + 0.5))
end

local function same_spot_pos(a, b)
    if not a or not b or not a.pos or not b.pos then return false end
    if distance_xy(a.pos, b.pos) > 2.5 then return false end
    return math.abs(a.pos.z - b.pos.z) <= 10
end

local function group_key(point)
    return string.format("%d,%d,%d",
        math.floor(point.pos.x / 2 + 0.5) * 2,
        math.floor(point.pos.y / 2 + 0.5) * 2,
        math.floor(point.pos.z / 8 + 0.5) * 8)
end

local function point_label_key(point)
    return point_key(point) .. "|" .. tostring(point.ang.pitch) .. "|" .. tostring(point.ang.yaw)
end

local function update_label_alpha(key, distance, fade_start, fade_end, ft)
    if label_alphas[key] == nil then label_alphas[key] = 0 end
    local target = 255
    if distance <= fade_start then
        target = 255
    elseif distance >= fade_end then
        target = 0
    else
        local t = (distance - fade_start) / (fade_end - fade_start)
        t = math.min(1, math.max(0, t))
        target = math.floor(255 * (1 - t) * (1 - t) * (1 - t))
    end
    local speed = target > label_alphas[key] and (255 / 0.18) or (255 / 0.30)
    local delta = target - label_alphas[key]
    local max_d = speed * ft
    if delta > max_d then delta = max_d elseif delta < -max_d then delta = -max_d end
    label_alphas[key] = label_alphas[key] + delta
    return math.floor(math.max(0, math.min(255, label_alphas[key])))
end

local function find_candidate(pawn, map, weapon, view)
    local points = lineups[map]
    if type(points) ~= "table" then return nil end
    local origin = pawn:origin()
    local best, best_angle = nil, math.huge
    for _, point in ipairs(points) do
        if valid_point(point) and weapon_matches(point.weapon, weapon) then
            local target = point_position(point)
            if distance_xy(origin, target) <= position_radius:get() and math.abs(origin.z - target.z) <= 12 then
                if is_view_in_point_fov(view, point) then
                    local pitch_delta, yaw_delta = angle_delta_to_point(view, point)
                    local angle_distance = math.abs(pitch_delta) + math.abs(yaw_delta)
                    if angle_distance < best_angle then
                        best = point
                        best_angle = angle_distance
                    end
                end
            end
        end
    end
    return best
end

local function pawn_speed(pawn)
    local ok, vel = pcall(function() return pawn:velocity() end)
    if not ok or type(vel) ~= "table" then return 0 end
    local x = tonumber(vel.x) or 0
    local y = tonumber(vel.y) or 0
    local z = tonumber(vel.z) or 0
    return math.sqrt(x * x + y * y + z * z)
end

local function find_nearest(pawn, map, weapon, max_dist, skip_key)
    local points = lineups[map]
    if type(points) ~= "table" then return nil, 1e9 end
    local origin = pawn:origin()
    local limit = max_dist or 1e9
    local best, best_d, best_score = nil, 1e9, 1e9
    for _, point in ipairs(points) do
        if valid_point(point) and weapon_matches(point.weapon, weapon) then
            if skip_key == nil or point_label_key(point) ~= skip_key then
                local target = point_position(point)
                local d = distance_xy(origin, target)
                -- 高度差加权：避免选到楼上/楼下看似更近的点
                local score = d + math.abs(origin.z - target.z) * 0.8
                if d <= limit and score < best_score then
                    best = point
                    best_d = d
                    best_score = score
                end
            end
        end
    end
    return best, best_d
end

local function clear_controlled_buttons(buttons)
    buttons = bit.band(buttons, bit.bnot(IN_ATTACK))
    buttons = bit.band(buttons, bit.bnot(IN_ATTACK2))
    buttons = bit.band(buttons, bit.bnot(IN_JUMP))
    buttons = bit.band(buttons, bit.bnot(IN_DUCK))
    buttons = bit.band(buttons, bit.bnot(IN_FORWARD))
    buttons = bit.band(buttons, bit.bnot(IN_BACK))
    buttons = bit.band(buttons, bit.bnot(IN_MOVELEFT))
    buttons = bit.band(buttons, bit.bnot(IN_MOVERIGHT))
    return buttons
end

local function throw_buttons(point, base)
    local mode = point.throw_mode or 0
    if mode == 0 then base = bit.bor(base, IN_ATTACK) end
    if mode == 1 then base = bit.bor(base, bit.bor(IN_ATTACK, IN_ATTACK2)) end
    if mode == 2 then base = bit.bor(base, IN_ATTACK2) end
    return base
end

local function charge_ticks_for(point)
    local weapon = point.weapon
    if weapon == "flashbang" then return 4 end
    if weapon == "hegrenade" then return 14 end
    return 8
end

local function weapon_label(weapon)
    if weapon == "flashbang" then return "闪光" end
    if weapon == "hegrenade" then return "高爆" end
    if weapon == "smokegrenade" then return "烟雾" end
    if is_fire_grenade(weapon) then return "燃烧" end
    return "手雷"
end

local function apply_view(cmd, pitch, yaw)
    pitch = math.max(-89, math.min(89, pitch))
    yaw = normalize_yaw(yaw)
    local ang = vector(pitch, yaw, 0)
    pcall(function() cmd:set_view_angles(ang) end)
    pcall(function() cmd:lock_angles() end)
    pcall(function() engine.set_view_angles(ang) end)
    return pitch, yaw
end

local function write_aim(cmd)
    aim_pitch, aim_yaw = apply_view(cmd, aim_pitch, aim_yaw)
    pcall(function() cmd:set_move(0, 0) end)
    pcall(function() cmd:set_upmove(0) end)
    cmd_set_buttons(cmd, clear_controlled_buttons(cmd_buttons(cmd)))
end

local function write_charge(cmd, point)
    aim_pitch, aim_yaw = apply_view(cmd, aim_pitch, aim_yaw)
    pcall(function() cmd:set_move(0, 0) end)
    pcall(function() cmd:set_upmove(0) end)
    local buttons = throw_buttons(point, clear_controlled_buttons(cmd_buttons(cmd)))
    if point.crouch then buttons = bit.bor(buttons, IN_DUCK) end
    cmd_set_buttons(cmd, buttons)
end

local function write_walk(cmd, point)
    aim_pitch = point.ang.pitch
    aim_yaw = normalize_yaw(point.ang.yaw)
    aim_pitch, aim_yaw = apply_view(cmd, aim_pitch, aim_yaw)
    local dir = tonumber(point.walk_dir) or 0
    local spd = MOVE_SCALE
    local fwd, side = 0, 0
    local buttons = throw_buttons(point, clear_controlled_buttons(cmd_buttons(cmd)))
    if dir == 0 then
        fwd = spd
        buttons = bit.bor(buttons, IN_FORWARD)
    elseif dir == 1 then
        fwd = -spd
        buttons = bit.bor(buttons, IN_BACK)
    elseif dir == 2 then
        side = spd
        buttons = bit.bor(buttons, IN_MOVELEFT)
    else
        side = spd
        buttons = bit.bor(buttons, IN_MOVERIGHT)
    end
    pcall(function() cmd:set_move(fwd, side) end)
    pcall(function() cmd:set_upmove(0) end)
    if point.crouch then buttons = bit.bor(buttons, IN_DUCK) end
    cmd_set_buttons(cmd, buttons)
end

local function write_release(cmd, point, jumping)
    aim_pitch, aim_yaw = apply_view(cmd, aim_pitch, aim_yaw)
    pcall(function() cmd:set_move(0, 0) end)
    pcall(function() cmd:set_upmove(0) end)
    local buttons = clear_controlled_buttons(cmd_buttons(cmd))
    if point.crouch and not jumping then buttons = bit.bor(buttons, IN_DUCK) end
    if jumping then buttons = bit.bor(buttons, IN_JUMP) end
    cmd_set_buttons(cmd, buttons)
end

local function write_approach(cmd, pawn, point, snap)
    local origin = pawn:origin()
    local dx = point.pos.x - origin.x
    local dy = point.pos.y - origin.y
    local dist = math.sqrt(dx * dx + dy * dy)
    snap = tonumber(snap) or 0.5
    if dist <= snap then
        pcall(function() cmd:set_move(0, 0) end)
        pcall(function() cmd:set_upmove(0) end)
        cmd_set_buttons(cmd, clear_controlled_buttons(cmd_buttons(cmd)))
        return true
    end
    local view = camera_view()
    local wish = math.deg(math.atan2(dy, dx))
    local yd = normalize_yaw(wish - view.yaw) * math.pi / 180
    local scale = 1
    if dist < 8 then
        scale = math.max(0.15, dist / 8)
    end
    pcall(function() cmd:set_move(math.cos(yd) * scale, math.sin(yd) * scale) end)
    pcall(function() cmd:set_upmove(0) end)
    local buttons = clear_controlled_buttons(cmd_buttons(cmd))
    buttons = bit.bor(buttons, IN_FORWARD)
    cmd_set_buttons(cmd, buttons)
    return false
end

local function write_macro(cmd)
    if active == nil then return end
    local cmds = active._macro_cmds
    if type(cmds) ~= "table" then return end
    local frame = cmds[playback_tick]
    if frame == nil then return end
    apply_view(cmd, frame.pitch, frame.yaw)
    pcall(function() cmd:set_move(frame.forwardmove or 0, frame.sidemove or 0) end)
    -- 临时诊断：统计宏帧移动量，定位“点按式慢走”
    if macro_diag then
        local m = math.abs(frame.forwardmove or 0) + math.abs(frame.sidemove or 0)
        if m < 0.05 then macro_diag.zeros = macro_diag.zeros + 1 end
        if m > macro_diag.max then macro_diag.max = m end
        macro_diag.sum = macro_diag.sum + m
        macro_diag.n = macro_diag.n + 1
    end
    pcall(function() cmd:set_upmove(0) end)
    local buttons = clear_controlled_buttons(cmd_buttons(cmd))
    buttons = bit.band(buttons, bit.bnot(IN_USE))
    buttons = bit.band(buttons, bit.bnot(IN_SPEED))
    if frame.in_attack then buttons = bit.bor(buttons, IN_ATTACK) end
    if frame.in_attack2 then buttons = bit.bor(buttons, IN_ATTACK2) end
    if frame.in_jump then buttons = bit.bor(buttons, IN_JUMP) end
    if frame.in_duck then buttons = bit.bor(buttons, IN_DUCK) end
    if frame.in_forward then buttons = bit.bor(buttons, IN_FORWARD) end
    if frame.in_back then buttons = bit.bor(buttons, IN_BACK) end
    if frame.in_moveleft then buttons = bit.bor(buttons, IN_MOVELEFT) end
    if frame.in_moveright then buttons = bit.bor(buttons, IN_MOVERIGHT) end
    if frame.in_use then buttons = bit.bor(buttons, IN_USE) end
    if frame.in_speed then buttons = bit.bor(buttons, IN_SPEED) end
    cmd_set_buttons(cmd, buttons)
end

local function write_current_command(cmd)
    if active == nil then return end
    if state == "macro" then write_macro(cmd) end
    if state == "aim" then write_aim(cmd) end
    if state == "charge" then write_charge(cmd, active) end
    if state == "walk" then write_walk(cmd, active) end
    if state == "release" then write_release(cmd, active, false) end
    if state == "jump" then write_release(cmd, active, true) end
end

local function start_aim(cmd, point)
    active = point
    state = "aim"
    stable_ticks = 0
    playback_tick = 0
    local view = camera_view()
    aim_pitch = view.pitch
    aim_yaw = normalize_yaw(view.yaw)
    if point_has_macro(point) then
        ensure_macro_cmds(point)
    end
end

local function start_macro(point)
    local cmds = ensure_macro_cmds(point)
    if cmds == nil then return false end
    active = point
    state = "macro"
    stable_ticks = 0
    -- 跳过录制前导的静止瞄准段：aim 阶段已完成对准，
    -- 从第一个有动作（攻击/移动/跳跃/明显转视角）的帧开始播放，
    -- 否则回放会把录制时站立瞄准的一两秒也完整重放（表现为慢/卡顿）
    local start_i = 1
    local p0, y0 = cmds[1].pitch or 0, cmds[1].yaw or 0
    for i = 1, math.max(#cmds - 1, 1) do
        local f = cmds[i]
        local moving = math.abs(f.forwardmove or 0) > 0.05 or math.abs(f.sidemove or 0) > 0.05
        local turning = math.abs((f.pitch or p0) - p0) + math.abs(normalize_yaw((f.yaw or y0) - y0)) > 0.5
        if f.in_attack or f.in_attack2 or f.in_jump or moving or turning then
            start_i = i
            break
        end
    end
    playback_tick = start_i - 1  -- 播放循环每 tick 先 +1，减 1 使首帧落在 start_i
    macro_diag = { zeros = 0, max = 0, sum = 0, n = 0 }  -- 临时诊断
    return true
end

local function aim_target_angles(point)
    if point_has_macro(point) then
        local cmds = point._macro_cmds or ensure_macro_cmds(point)
        if type(cmds) == "table" and cmds[1] then
            return cmds[1].pitch, cmds[1].yaw
        end
    end
    return point.ang.pitch, point.ang.yaw
end

local function update_playback(cmd, pawn, map, weapon)
    if map ~= loaded_map then
        lineups = load_lineups()
        loaded_map = map
        reset_playback()
        candidate = nil
        await_key_release = false
        path_phase = "none"
        path_settle_ticks = 0
        path_stuck_ticks = 0
        path_last_nd = 1e9
        label_alphas = {}
    end

    if await_key_release then
        if not is_execute_down() then await_key_release = false end
        return
    end

    local view = camera_view()
    candidate = find_candidate(pawn, map, weapon, view)
    if state == "idle" then
        local settle_need = 8
        pcall(function()
            local ti = globals.interval() or (1 / 64)
            if type(ti) ~= "number" or ti <= 0 then ti = 1 / 64 end
            settle_need = math.max(1, math.floor(path_settle:get() / ti + 0.5))
        end)
        local rad = position_radius:get()

        if candidate and is_execute_down() then
            path_phase = "none"
            path_settle_ticks = 0
            path_stuck_ticks = 0
            start_aim(cmd, candidate)
            return
        end

        if auto_path:get() and is_execute_down() then
            local snap = tonumber(path_center:get()) or 0.5
            local leave = math.max(snap + 3, rad + 2)

            local near, nd = find_nearest(pawn, map, weapon, path_range:get())

            if not near then
                path_phase = "none"
                path_settle_ticks = 0
                path_stuck_ticks = 0
            elseif path_phase == "ready" then
                -- 对齐原版：停稳后立即对寻路目标执行，不等待视角 FOV 对准；
                -- 不在点位半径内则退出寻路状态，下帧重新走判定
                if nd <= rad then
                    path_phase = "none"
                    start_aim(cmd, near)
                    return
                end
                path_phase = "none"
            elseif path_phase == "settle" then
                if nd > leave then
                    path_phase = "walk"
                    path_settle_ticks = 0
                    path_stuck_ticks = 0
                    path_last_nd = nd
                else
                    path_settle_ticks = path_settle_ticks + 1
                    pcall(function() cmd:set_move(0, 0) end)
                    pcall(function() cmd:set_upmove(0) end)
                    cmd_set_buttons(cmd, clear_controlled_buttons(cmd_buttons(cmd)))
                    if path_settle_ticks < settle_need then
                        return
                    end
                    path_phase = "ready"
                    path_settle_ticks = 0
                    return
                end
            else
                local close_enough = nd <= snap
                if path_phase == "walk" then
                    if nd < path_last_nd - 0.15 then
                        path_stuck_ticks = 0
                        path_last_nd = nd
                    else
                        path_stuck_ticks = path_stuck_ticks + 1
                    end
                    if nd <= rad and path_stuck_ticks > 24 then
                        close_enough = true
                    end
                end

                if not close_enough and nd > snap then
                    path_phase = "walk"
                    if path_last_nd > nd + 50 then path_last_nd = nd end
                    write_approach(cmd, pawn, near, snap)
                    return
                elseif path_phase == "walk" and close_enough then
                    path_phase = "settle"
                    path_settle_ticks = 0
                    path_stuck_ticks = 0
                    pcall(function() cmd:set_move(0, 0) end)
                    pcall(function() cmd:set_upmove(0) end)
                    cmd_set_buttons(cmd, clear_controlled_buttons(cmd_buttons(cmd)))
                    return
                elseif nd <= snap and path_phase ~= "walk" then
                    path_phase = "none"
                end
            end
        else
            path_phase = "none"
            path_settle_ticks = 0
            path_stuck_ticks = 0
        end
        return
    end

    if not is_execute_down() or active == nil or not weapon_matches(active.weapon, weapon) then
        reset_playback()
        return
    end

    if state == "macro" then
        playback_tick = playback_tick + 1
        local cmds = active._macro_cmds
        if type(cmds) ~= "table" or playback_tick > #cmds then
            if macro_diag and macro_diag.n > 0 then
                print(string.format("[道具助手] 宏诊断: 播放%d帧 零移动帧=%d 最大移动量=%.2f 平均=%.2f",
                    macro_diag.n, macro_diag.zeros, macro_diag.max, macro_diag.sum / macro_diag.n))
            end
            macro_diag = nil
            reset_playback()
            await_key_release = true
        end
        return
    end

    if state == "aim" then
        local tp, ty = aim_target_angles(active)
        local target_pitch = math.max(-89, math.min(89, tp))
        local target_yaw = normalize_yaw(ty)
        local pitch_delta = target_pitch - aim_pitch
        local yaw_delta = normalize_yaw(target_yaw - aim_yaw)
        local total = math.abs(pitch_delta) + math.abs(yaw_delta)

        local s = math.max(2, smooth:get())
        local max_step = math.min(6, math.max(0.35, 32 / s))
        local step_p = pitch_delta / s
        local step_y = yaw_delta / s

        if math.abs(step_p) > max_step then
            step_p = max_step * (pitch_delta > 0 and 1 or -1)
        end
        if math.abs(step_y) > max_step then
            step_y = max_step * (yaw_delta > 0 and 1 or -1)
        end
        if total > 0.3 then
            if math.abs(step_p) >= math.abs(pitch_delta) then step_p = pitch_delta * 0.5 end
            if math.abs(step_y) >= math.abs(yaw_delta) then step_y = yaw_delta * 0.5 end
        else
            if math.abs(step_p) > math.abs(pitch_delta) then step_p = pitch_delta end
            if math.abs(step_y) > math.abs(yaw_delta) then step_y = yaw_delta end
        end

        aim_pitch = math.max(-89, math.min(89, aim_pitch + step_p))
        aim_yaw = normalize_yaw(aim_yaw + step_y)

        if math.abs(pitch_delta) < 0.15 and math.abs(yaw_delta) < 0.15 then
            stable_ticks = stable_ticks + 1
            if stable_ticks >= 4 then
                aim_pitch = target_pitch
                aim_yaw = target_yaw
                if point_has_macro(active) then
                    if start_macro(active) then return end
                end
                state = "charge"
                playback_tick = 0
            end
        else
            stable_ticks = 0
        end
        return
    end

    if state == "charge" then
        playback_tick = playback_tick + 1
        if playback_tick > charge_ticks_for(active) then
            playback_tick = 0
            if active.walk then
                state = "walk"
            else
                state = "release"
            end
        end
    elseif state == "walk" then
        playback_tick = playback_tick + 1
        local need = tonumber(active.walk_ticks) or 30
        if active.crouch then need = need * 3 end
        if playback_tick >= need then
            playback_tick = 0
            state = "release"
        end
    elseif state == "release" then
        playback_tick = playback_tick + 1
        if playback_tick > 1 then
            if active.jump then state = "jump"; playback_tick = 0
            else reset_playback(); await_key_release = true end
        end
    elseif state == "jump" then
        playback_tick = playback_tick + 1
        if playback_tick > 5 then reset_playback(); await_key_release = true end
    end
end

local function should_block_early_pin(pawn, weapon)
    if state == "aim" then return true end
    if candidate then return true end
    if path_phase ~= "none" then return true end
    if not auto_path:get() then return false end
    local near, nd = find_nearest(pawn, map_name(), weapon, path_range:get())
    return near ~= nil and nd <= path_range:get()
end

local function is_lmb_execute()
    local k = execute_key:get()
    if type(k) == "number" then return k == 1 end
    return true
end

local function block_early_pin(cmd)
    if not enabled:get() then return end
    if not is_lmb_execute() then return end
    if not is_execute_down() then return end
    local pawn = get_player()
    if pawn == nil then return end
    local weapon = get_grenade(pawn)
    if weapon == nil then return end
    if state == "charge" or state == "walk" or state == "release" or state == "jump" or state == "macro" then
        return
    end
    if not should_block_early_pin(pawn, weapon) then return end
    local buttons = cmd_buttons(cmd)
    buttons = bit.band(buttons, bit.bnot(IN_ATTACK))
    buttons = bit.band(buttons, bit.bnot(IN_ATTACK2))
    cmd_set_buttons(cmd, buttons)
end

-- ---------------------------------------------------------------------------
-- 绘制
-- ---------------------------------------------------------------------------
local function draw_ring(point, radius, r, g, b, a)
    local last_x, last_y = nil, nil
    for i = 0, 48 do
        local angle = i / 48 * math.pi * 2
        local world = vector(point.pos.x + math.cos(angle) * radius, point.pos.y + math.sin(angle) * radius, point.pos.z + 5)
        local x, y = render.world_to_screen(world)
        if x and y and last_x and last_y then
            render.line(last_x, last_y, x, y, color(r, g, b, a), 1)
        end
        last_x, last_y = x, y
    end
end

local function draw_ui_panel(x1, y1, x2, y2, alpha, accent_r, accent_g, accent_b)
    local round = 7
    local w = x2 - x1
    local h = y2 - y1
    local scale = alpha / 255
    local gc = glow_color:get()
    local bc = bg_color:get()

    render.shadow(x1, y1, w, h, color(gc.r, gc.g, gc.b, math.floor((gc.a or 255) * scale * 0.45)), 6, round)
    render.rect_filled(x1, y1, w, h, color(bc.r, bc.g, bc.b, math.floor((bc.a or 255) * scale * 0.88)), round)
    render.rect(x1, y1, w, h, color(accent_r, accent_g, accent_b, math.floor(210 * scale)), round, 1)
end

local function measure_label(title, subtitle)
    local tw1, th1 = render.text_size(title)
    local tw2, th2 = 0, 0
    if subtitle ~= "" then tw2, th2 = render.text_size(subtitle) end
    local pad_x, pad_y = 11, 7
    local w = math.max(tw1, tw2) + pad_x * 2
    local h = th1 + pad_y * 2
    if subtitle ~= "" then h = h + th2 + 3 end
    return w, h, pad_x, pad_y, th1
end

local function draw_world_label(cx, cy, title, subtitle, alpha, accent_r, accent_g, accent_b)
    local w, h, pad_x, pad_y, th1 = measure_label(title, subtitle)
    local x1 = math.floor(cx - w / 2)
    local y1 = math.floor(cy - h / 2)
    local x2 = x1 + w
    local y2 = y1 + h
    draw_ui_panel(x1, y1, x2, y2, alpha, accent_r, accent_g, accent_b)
    render.text(x1 + pad_x, y1 + pad_y, color(255, 255, 255, alpha), title)
    if subtitle ~= "" then
        render.text(x1 + pad_x, y1 + pad_y + th1 + 3, color(190, 196, 210, math.floor(alpha * 0.88)), subtitle)
    end
    return h
end

local function draw_fov_ring(point, in_range, alpha)
    if not show_fov:get() then return end
    local sw, sh = render.screen_size()
    local cx = math.floor(sw / 2)
    local cy = math.floor(sh / 2)
    local lock = point_lock_deg(point)
    local scale = (sw / 2) / 45
    local rpx = math.floor(lock * scale)
    local c
    if in_range then
        local g = green:get()
        c = color(g.r, g.g, g.b, math.min(g.a or 255, math.floor(150 * alpha / 255)))
    else
        local r = red:get()
        c = color(r.r, r.g, r.b, math.min(r.a or 255, math.floor(95 * alpha / 255)))
    end
    local prev_x, prev_y = nil, nil
    for i = 0, 64 do
        local angle = i / 64 * math.pi * 2
        local px = cx + math.floor(math.cos(angle) * rpx)
        local py = cy + math.floor(math.sin(angle) * rpx)
        if prev_x and prev_y then
            render.line(prev_x, prev_y, px, py, c, 1)
        end
        prev_x, prev_y = px, py
    end
end

local function lineup_dot_screen_xy(pawn, point, view)
    local origin = pawn:origin()
    local pitch_rad = math.rad(point.ang.pitch)
    local yaw_rad = math.rad(point.ang.yaw)
    local lx = math.cos(pitch_rad) * math.cos(yaw_rad)
    local ly = math.cos(pitch_rad) * math.sin(yaw_rad)
    local lz = -math.sin(pitch_rad)
    local eye_z = origin.z + 64

    for _, dist in ipairs({ 500, 350, 800, 200 }) do
        local tip = vector(origin.x + lx * dist, origin.y + ly * dist, eye_z + lz * dist)
        local tx, ty = render.world_to_screen(tip)
        if tx and ty then return tx, ty end
    end

    local sw, sh = render.screen_size()
    local cx = math.floor(sw / 2)
    local cy = math.floor(sh / 2)
    local dpitch, dyaw = angle_delta_to_point(view, point)
    local scale = (sw / 2) / 45
    local tx = cx - math.floor(dyaw * scale)
    local ty = cy + math.floor(dpitch * scale)
    tx = math.max(12, math.min(sw - 12, tx))
    ty = math.max(12, math.min(sh - 12, ty))
    return tx, ty
end

local function draw_aim_glow(x, y, r, g, b, alpha)
    local dot_r = 3
    local layers = {
        { r = dot_r + 4, a = 0.05 },
        { r = dot_r + 3, a = 0.12 },
        { r = dot_r + 2, a = 0.28 },
        { r = dot_r + 1, a = 0.55 },
        { r = dot_r,     a = 1.00 },
    }
    for _, layer in ipairs(layers) do
        render.circle_filled(x, y, layer.r, color(r, g, b, math.floor(alpha * layer.a)))
    end
end

local function draw_aim_target(pawn, point, is_playing, in_fov, alpha, view)
    local x, y = lineup_dot_screen_xy(pawn, point, view)

    local ac = red:get()
    if is_playing or in_fov then ac = green:get() end
    local ar, ag, ab = ac.r, ac.g, ac.b

    local title = point.name or "点位"
    local _, label_h = measure_label(title, "")
    local label_cy = y - 10 - math.floor(label_h / 2)
    draw_world_label(x, label_cy, title, "", alpha, ar, ag, ab)

    draw_aim_glow(x, y, ar, ag, ab, alpha)
    render.circle_filled(x, y, 4, color(0, 0, 0, math.floor(140 * alpha / 255)))
    render.circle(x, y, 4, color(ar, ag, ab, alpha), 16, 1)
    render.circle_filled(x, y, 2, color(ar, ag, ab, alpha))
end

local function spot_name()
    local name = rec_name:get()
    if name == nil or name == "" then return "新点位" end
    return name
end

local function save_manual_spot()
    local ctx = get_live_record_context()
    if ctx == nil then
        print("[手雷助手] 保存失败：保存前需手持道具")
        rec_save:set(false)
        rec_prev.save = false
        return
    end
    local name = spot_name()
    local entry = build_manual_entry(ctx, name)
    local text = insert_point_entry(read_data_file(), ctx.map, entry)
    if not write_data_file(text) then
        print("[手雷助手] 写入失败：请开启 insecure 权限")
    end
    reload_lineups()
    print(string.format("[手雷助手] 已保存点位 \"%s\" 在 %s", name, ctx.map))
    if rec_walk:get() then
        print(string.format("[手雷助手] 走投: tick=%d 方向=%d", math.floor(rec_walk_ticks:get()), rec_walk_dir:get()))
    end
end

local function save_macro_spot()
    if rec_active or rec_waiting then
        commit_recording_buffer()
        rec_on_prev = false
        rec_on_latch = false
    end
    if type(rec_ready_frames) ~= "table" or #rec_ready_frames == 0 or rec_ready_meta == nil then
        print("[手雷助手] 保存录制失败：请先开启录制并投掷后再保存")
        return
    end
    local ctx = get_macro_record_context()
    if ctx == nil then
        print("[手雷助手] 保存录制失败：缺少录制数据")
        return
    end
    local name = spot_name()
    local ok, entry = pcall(build_macro_entry, ctx, name, rec_ready_frames)
    if not ok or type(entry) ~= "string" then
        print("[手雷助手] 保存录制失败: " .. tostring(entry))
        return
    end
    local text = insert_point_entry(read_data_file(), ctx.map, entry)
    if not write_data_file(text) then
        print("[手雷助手] 写入失败：请开启 insecure 权限")
    end
    reload_lineups()
    print(string.format("[手雷助手] 已保存录制 \"%s\" 在 %s（%d 帧）", name, ctx.map, #rec_ready_frames))
    rec_ready_frames = nil
    rec_ready_meta = nil
end

local function delete_nearest_spot()
    local pawn = get_player()
    if pawn == nil then return end
    local weapon = get_grenade(pawn)
    if weapon == nil then
        print("[手雷助手] 删除失败：请先手持对应道具")
        return
    end
    local map = map_name()
    local list = lineups[map]
    if type(list) ~= "table" or #list == 0 then
        print("[手雷助手] 删除失败：此地图无点位")
        return
    end
    local origin = pawn:origin()
    local view = camera_view()
    local delete_radius = 8
    local target = nil
    local target_d = nil
    local best_angle = math.huge
    for _, point in ipairs(list) do
        if valid_point(point) and weapon_matches(point.weapon, weapon) then
            local pos = point_position(point)
            local d = distance_xy(origin, pos)
            if d <= delete_radius and math.abs(origin.z - pos.z) <= 12 and is_view_in_point_fov(view, point) then
                local pitch_delta, yaw_delta = angle_delta_to_point(view, point)
                local angle_distance = math.abs(pitch_delta) + math.abs(yaw_delta)
                if angle_distance < best_angle then
                    target = point
                    target_d = d
                    best_angle = angle_distance
                end
            end
        end
    end
    if target == nil then
        print("[手雷助手] 删除失败：站在 8 单位内并瞄准点位（绿色）")
        return
    end
    local text = read_data_file()
    local entry_start, entry_end = find_entry_bounds(text, target)
    if entry_start == nil or entry_end == nil then
        print("[手雷助手] 删除失败：无法在文件中定位点位")
        return
    end
    if not write_data_file(text:sub(1, entry_start - 1) .. text:sub(entry_end)) then
        print("[手雷助手] 写入失败：请开启 insecure 权限")
    end
    if active == target then reset_playback() end
    reload_lineups()
    print(string.format("[手雷助手] 已删除点位 \"%s\"（%.1f 单位）", target.name or "点位", target_d))
end

-- ---------------------------------------------------------------------------
-- 管理面板：当前地图全部点位（所有道具）+ 行内改名 / 删除
-- ---------------------------------------------------------------------------
local MANAGE_ROW_H = 34
local MANAGE_HEADER_H = 28
local MANAGE_FOOTER_H = 18

local manage_scroll = 0
local manage_selected_key = nil
local manage_map_loaded = ""
local manage_error_printed = false
local manage_name = nil
local manage_filter = nil
local manage_map = nil
local manage_search = nil
local manage_last_filter = 0
local manage_last_map = ""
local manage_last_search = ""
local manage_scroll_dragging = false

local MANAGE_FILTERS = { "全部道具", "烟雾弹", "闪光弹", "高爆手雷", "燃烧弹", "诱饵弹" }
local MANAGE_MAP_AUTO = "当前地图"
local manage_map_items = { MANAGE_MAP_AUTO }

local function refresh_manage_map_items()
    local keys = {}
    for key in pairs(lineups) do
        if type(key) == "string" and key ~= "" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local list = { MANAGE_MAP_AUTO }
    for _, key in ipairs(keys) do list[#list + 1] = key end
    local same = #list == #manage_map_items
    if same then
        for i = 1, #list do
            if list[i] ~= manage_map_items[i] then same = false; break end
        end
    end
    if same then return end
    manage_map_items = list
    if manage_map ~= nil then
        pcall(function() manage_map:items(manage_map_items) end)
    end
end

local function manage_selected_map()
    local sel = 0
    if manage_map ~= nil then
        local ok, value = pcall(function() return manage_map:get() end)
        if ok and type(value) == "number" then sel = value end
    end
    local picked = manage_map_items[sel + 1]
    if sel > 0 and picked ~= nil then return picked end
    local map = map_name()
    if map == "" then map = loaded_map end
    return map
end

local function manage_filter_index()
    if manage_filter == nil then return 0 end
    local ok, value = pcall(function() return manage_filter:get() end)
    if ok and type(value) == "number" then return value end
    return 0
end

local function point_matches_filter(point, filter)
    local weapon = tostring(point.weapon or "")
    if filter == 1 then return weapon == "smokegrenade" end
    if filter == 2 then return weapon == "flashbang" end
    if filter == 3 then return weapon == "hegrenade" end
    if filter == 4 then return is_fire_grenade(weapon) end
    if filter == 5 then return weapon == "decoy" end
    return true
end

local function manage_search_text()
    if manage_search == nil then return "" end
    local ok, value = pcall(function() return manage_search:get() end)
    if ok and type(value) == "string" then return value end
    return ""
end

-- 名称包含搜索词即命中（不区分大小写，纯文本匹配）
local function point_matches_search(point, query)
    if query == nil or query == "" then return true end
    local name = tostring(point.name or ""):lower()
    return name:find(query:lower(), 1, true) ~= nil
end

local function collect_manage_points()
    local map = manage_selected_map()
    if map == "" then return {}, "", 0 end
    if lineups[map] == nil and manage_map_loaded ~= map then
        manage_map_loaded = map
        lineups = load_lineups()
    end
    local list = lineups[map]
    local filter = manage_filter_index()
    local query = manage_search_text()
    local out = {}
    local total = 0
    if type(list) == "table" then
        for _, point in ipairs(list) do
            if valid_point(point) then
                total = total + 1
                if point_matches_filter(point, filter) and point_matches_search(point, query) then
                    table.insert(out, point)
                end
            end
        end
    end
    return out, map, total
end

local function manage_notify(text)
    pcall(client.notify, text, "手雷助手")
    print("[手雷助手] " .. text)
end

local function trim_utf8_tail(s)
    while #s > 0 do
        local b = s:byte(#s)
        if b < 0x80 or b >= 0xC0 then break end
        s = s:sub(1, #s - 1)
    end
    return s
end

local function fit_text(text, max_w, size)
    text = tostring(text or "")
    local tw = render.text_size(text, nil, size)
    if tw <= max_w then return text end
    local out = text
    while #out > 1 do
        out = trim_utf8_tail(out:sub(1, #out - 1))
        if #out == 0 then break end
        if render.text_size(out .. "…", nil, size) <= max_w then
            return out .. "…"
        end
    end
    return "…"
end

local function rename_point_entry(point, new_name)
    if new_name == nil or new_name == "" then return false, "名称不能为空" end
    local text = read_data_file()
    local entry_start, entry_end = find_entry_bounds(text, point)
    if entry_start == nil or entry_end == nil then
        return false, "无法在 helper_data.txt 中定位该点位"
    end
    local block = text:sub(entry_start, entry_end)
    local escaped = escape_lua_string(new_name)
    local replaced, count = block:gsub('name%s*=%s*"[^"]*"', function()
        return 'name   = "' .. escaped .. '"'
    end, 1)
    if count == 0 then return false, "该点位缺少 name 字段" end
    if not write_data_file(text:sub(1, entry_start - 1) .. replaced .. text:sub(entry_end + 1)) then
        return false, "写入失败：请开启 insecure 权限"
    end
    reload_lineups()
    return true
end

local function remove_point_entry(point)
    local text = read_data_file()
    local entry_start, entry_end = find_entry_bounds(text, point)
    if entry_start == nil or entry_end == nil then
        return false, "无法在 helper_data.txt 中定位该点位"
    end
    if not write_data_file(text:sub(1, entry_start - 1) .. text:sub(entry_end + 1)) then
        return false, "写入失败：请开启 insecure 权限"
    end
    if active ~= nil and point_label_key(active) == point_label_key(point) then
        reset_playback()
    end
    reload_lineups()
    return true
end

local function draw_manage_button(bx, by, bw, bh, label, hover, normal_fill, hover_fill)
    render.rect_filled(bx, by, bw, bh, hover and hover_fill or normal_fill, 4)
    local tw = render.text_size(label, nil, 11)
    render.text(bx + math.floor((bw - tw) / 2), by + math.floor((bh - 12) / 2),
        color(235, 238, 246, 255), label, nil, 11)
end

local function draw_manage_widget(x, y, w, h, input)
    input = input or {}
    refresh_manage_map_items()
    local points, map, total = collect_manage_points()

    local filter = manage_filter_index()
    if filter ~= manage_last_filter then
        manage_last_filter = filter
        manage_scroll = 0
        manage_scroll_dragging = false
    end
    if map ~= manage_last_map then
        manage_last_map = map
        manage_scroll = 0
        manage_scroll_dragging = false
        manage_selected_key = nil
    end
    local query = manage_search_text()
    if query ~= manage_last_search then
        manage_last_search = query
        manage_scroll = 0
        manage_scroll_dragging = false
    end

    local list_y = y + MANAGE_HEADER_H
    local list_h = h - MANAGE_HEADER_H - MANAGE_FOOTER_H
    local rows = math.max(1, math.floor(list_h / MANAGE_ROW_H))
    local max_scroll = math.max(0, #points - rows)

    if manage_scroll < 0 then manage_scroll = 0 end
    if manage_scroll > max_scroll then manage_scroll = max_scroll end

    local mx = tonumber(input.mx) or 0
    local my = tonumber(input.my) or 0
    -- 统一换算成控件内局部坐标（兼容绝对/相对两种约定）
    if not (mx >= 0 and mx <= w and my >= 0 and my <= h) then
        mx, my = mx - x, my - y
    end
    local clicked = input.click or input.clicked
    local wheel = tonumber(input.wheel) or 0
    local hover = input.hover
    local mouse_down = input.down or input.dragging or input.active

    if hover and wheel ~= 0 then
        manage_scroll = math.max(0, math.min(max_scroll, manage_scroll - (wheel > 0 and 1 or -1)))
    end

    -- 面板背景
    render.rect_filled(x, y, w, h, color(16, 18, 24, 240), 6)
    render.rect(x, y, w, h, color(58, 64, 78, 200), 6, 1)

    local filter_name = MANAGE_FILTERS[filter + 1] or MANAGE_FILTERS[1]
    local title
    if query ~= "" then
        title = string.format("%s · %s · 搜索\"%s\" · %d / %d",
            (map ~= "" and map or "未知地图"), filter_name, query, #points, total)
    else
        title = string.format("%s · %s · %d / %d 个点位",
            (map ~= "" and map or "未知地图"), filter_name, #points, total)
    end
    render.text(x + 8, y + 7, color(224, 228, 238, 255),
        fit_text(title, w - 16, 12), nil, 12)

    -- 滚动条几何
    local bar_w = 5
    local bar_x = w - 3 - bar_w
    local bar_top = MANAGE_HEADER_H + 2
    local bar_h = list_h - 4
    local show_bar = max_scroll > 0 and #points > 0
    local thumb_h = 0
    local thumb_y = bar_top
    if show_bar then
        thumb_h = math.max(26, math.floor(bar_h * rows / #points))
        local range = math.max(1, bar_h - thumb_h)
        thumb_y = bar_top + math.floor(manage_scroll / max_scroll * range)
    end

    local in_bar_x = mx >= bar_x - 2 and mx <= bar_x + bar_w + 2
    local in_bar = show_bar and in_bar_x and my >= bar_top and my <= bar_top + bar_h
    local in_thumb = show_bar and in_bar_x and my >= thumb_y and my <= thumb_y + thumb_h
    local thumb_drag_span = math.max(1, bar_h - thumb_h)

    if clicked and in_bar then
        manage_scroll_dragging = true
        local pct = (my - bar_top - thumb_h / 2) / thumb_drag_span
        pct = math.max(0, math.min(1, pct))
        manage_scroll = math.floor(pct * max_scroll + 0.5)
    elseif manage_scroll_dragging and mouse_down then
        local pct = (my - bar_top - thumb_h / 2) / thumb_drag_span
        pct = math.max(0, math.min(1, pct))
        manage_scroll = math.floor(pct * max_scroll + 0.5)
    elseif not mouse_down then
        manage_scroll_dragging = false
    end

    if show_bar then
        render.rect_filled(x + bar_x, y + bar_top, bar_w, bar_h, color(34, 38, 48, 235), 3)
        local thumb_color = (in_thumb or manage_scroll_dragging) and color(126, 150, 190, 255) or color(88, 98, 120, 235)
        render.rect_filled(x + bar_x, y + thumb_y, bar_w, thumb_h, thumb_color, 3)
    end

    if #points == 0 then
        local empty_text = "该地图暂无点位，可切换地图"
        if query ~= "" then
            empty_text = string.format("没有匹配 \"%s\" 的点位", query)
        elseif total > 0 then
            empty_text = "此分类下暂无点位，可切换到“全部道具”"
        end
        render.text(x + 8, list_y + 8, color(140, 146, 160, 255), empty_text, nil, 12)
        local footer_empty = string.format("滚轮/拖动滚动条 · 0 / %d", total)
        render.text(x + 8, y + h - MANAGE_FOOTER_H + 2, color(128, 134, 148, 255), footer_empty, nil, 11)
        return
    end

    local size_name, size_sub = 12, 11
    local btn_w, btn_h, btn_gap, right_pad = 42, 16, 4, 16
    local rel_btn_y = 9
    local row_max_x = show_bar and (bar_x - 3) or (w - 4)

    for r = 1, rows do
        local index = manage_scroll + r
        local point = points[index]
        if point == nil then break end

        local ry = list_y + (r - 1) * MANAGE_ROW_H
        local rel_y = ry - y
        local row_hover = mx >= 4 and mx <= row_max_x and my >= rel_y and my <= rel_y + MANAGE_ROW_H
        local key = point_label_key(point)
        local selected = manage_selected_key == key

        if selected then
            render.rect_filled(x + 4, ry, w - 8, MANAGE_ROW_H - 2, color(50, 62, 84, 235), 4)
        elseif row_hover then
            render.rect_filled(x + 4, ry, w - 8, MANAGE_ROW_H - 2, color(32, 36, 46, 235), 4)
        end

        local name_w = w - 16 - (btn_w * 2 + btn_gap * 2) - btn_gap
        local label = string.format("%d. %s", index, point.name or "点位")
        local name_color = selected and color(255, 255, 255, 255) or color(208, 213, 225, 255)
        render.text(x + 8, ry + 2, name_color,
            fit_text(label, name_w, size_name), nil, size_name)

        local tags = weapon_label(point.weapon)
        if point_has_macro(point) then tags = tags .. " · 宏"
        elseif point.walk then tags = tags .. " · 走投" end
        local sub = string.format("%s  |  %.1f, %.1f, %.1f", tags, point.pos.x, point.pos.y, point.pos.z)
        render.text(x + 8, ry + 18, color(132, 138, 152, 255),
            fit_text(sub, name_w + 8, size_sub), nil, size_sub)

        local del_x = x + w - right_pad - btn_w
        local ren_x = del_x - btn_gap - btn_w
        local rel_del_x = w - right_pad - btn_w
        local rel_ren_x = rel_del_x - btn_gap - btn_w
        local rel_ry = rel_y + rel_btn_y

        local ren_hover = mx >= rel_ren_x and mx <= rel_ren_x + btn_w and my >= rel_ry and my <= rel_ry + btn_h
        local del_hover = mx >= rel_del_x and mx <= rel_del_x + btn_w and my >= rel_ry and my <= rel_ry + btn_h

        draw_manage_button(ren_x, ry + rel_btn_y, btn_w, btn_h, "改名", ren_hover,
            color(46, 92, 132, 235), color(64, 128, 184, 255))
        draw_manage_button(del_x, ry + rel_btn_y, btn_w, btn_h, "删除", del_hover,
            color(134, 54, 54, 235), color(182, 74, 74, 255))

        if clicked then
            if ren_hover then
                local new_name = manage_name:get()
                if new_name == nil or new_name == "" then
                    manage_notify("请先在上方“新名称”输入框填写名称")
                else
                    local ok, err = rename_point_entry(point, new_name)
                    if ok then
                        manage_notify(string.format("已重命名为 \"%s\"（%s）", new_name, map))
                    else
                        manage_notify(err)
                    end
                    points = collect_manage_points()
                end
            elseif del_hover then
                local ok, err = remove_point_entry(point)
                if ok then
                    manage_notify(string.format("已删除点位 \"%s\"（%s）", point.name or "点位", map))
                    if manage_selected_key == key then manage_selected_key = nil end
                else
                    manage_notify(err)
                end
                points = collect_manage_points()
            elseif row_hover then
                manage_selected_key = key
                manage_name:set(point.name or "")
            end
        end
    end

    local first = manage_scroll + 1
    local last = math.min(#points, manage_scroll + rows)
    local footer = string.format("滚轮/拖动滚动条 · 显示 %d-%d / %d", first, last, #points)
    render.text(x + 8, y + h - MANAGE_FOOTER_H + 2, color(128, 134, 148, 255), footer, nil, 11)
end

-- 手动创建点位组（左列，第 3 组）：保存当前点位 + 投掷方式（变量已在文件头前向声明）
local manual_group = main_tab:group("手动创建点位")
rec_jump = manual_group:checkbox("跳投", false)
rec_walk = manual_group:checkbox("走投", true)
rec_walk_ticks = manual_group:slider_float("走投时长（tick）", 1, 250, 30, "%.0f")
rec_walk_dir = manual_group:combo("走投方向", { "前", "后", "左", "右" })
rec_crouch = manual_group:checkbox("下蹲", false)
rec_throw = manual_group:combo("投掷模式", { "左键", "双键", "右键" })
rec_save = manual_group:button("在当前位置创建点位", function() save_manual_spot() end)

-- 点位管理组（右列，第 4 组）
local manage_group = main_tab:group("点位管理")
refresh_manage_map_items()
manage_map = manage_group:combo("地图选择", manage_map_items)
manage_filter = manage_group:combo("道具分类", MANAGE_FILTERS)
manage_search = manage_group:text("搜索点位名称")
manage_name = manage_group:text("新名称")
manage_group:custom("点位列表（滚轮翻页 / 行内改名与删除）", 430, function(x, y, w, h, input)
    local ok, err = pcall(draw_manage_widget, x, y, w, h, input)
    if not ok and not manage_error_printed then
        manage_error_printed = true
        print("[手雷助手] 管理列表绘制失败: " .. tostring(err))
    end
end)

-- 录制组（左列，第 5 组）：宏录制
local rec_group = main_tab:group("录制")
rec_name = rec_group:text("点位名称")
rec_recording = rec_group:keybind("开启录制")
rec_save_macro = rec_group:button("保存点位", function() save_macro_spot() end)
del_save = rec_group:button("删除瞄准的点位", function() delete_nearest_spot() end)

-- 状态组（右列，点位管理组下方）：insecure 状态 + 一键重载 + 作者信息
-- 用 loadstring 独立 chunk 构建：主函数 local 已达 200 编译上限，不能新增 local
if type(loadstring) == "function" then
    if not pcall(loadstring([==[
local main_tab = ...
-- 状态组：insecure 状态 + 一键重载 + 作者信息 + 闲鱼链接
local g_status = main_tab:group("状态")
local insecure_chk = g_status:checkbox("Allow Insecure（允许不安全模式）", client.insecure())
g_status:label("当前 Allow Insecure：" .. (client.insecure() and "已开启" or "未开启"))
g_status:button("应用并立即重载脚本", function()
    pcall(function() config.set("lua.allow_insecure", insecure_chk:get()) end)
    pcall(function() client.reload() end)
end)
g_status:label("Awa Subaru制作")
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
        print("[道具助手] ShellExecuteA 调用失败: " .. tostring(err))
    elseif shexec == false then
        print("[道具助手] ffi 不可用（需开启 Allow Insecure），走 Steam 覆盖层回退")
    end
    local ok2, err2 = pcall(function() panorama.SteamOverlayAPI.OpenExternalBrowserURL(url) end)
    if not ok2 then
        print("[道具助手] Steam 覆盖层打开也失败: " .. tostring(err2))
    end
end
g_status:button("闲鱼:我是学生你懂我意思吧", function()
    open_url("https://m.tb.cn/h.jS7Zhk2?tk=ZYFI6cX5T4D")
end)
]==]), main_tab) then
        print("[手雷助手] 状态组构建失败")
    end
else
    print("[手雷助手] loadstring 不可用，状态组跳过")
end

-- ---------------------------------------------------------------------------
-- 回调
-- ---------------------------------------------------------------------------
events.on("createmove", function(cmd)
    local pawn = get_player()
    update_recording(cmd, pawn)
    if rec_active or rec_waiting then return end
    if not enabled:get() then reset_playback(); return end
    if pawn == nil then reset_playback(); return end
    local weapon = get_grenade(pawn)
    if weapon == nil then
        reset_playback()
        return
    end
    block_early_pin(cmd)
    update_playback(cmd, pawn, map_name(), weapon)
    write_current_command(cmd)
    block_early_pin(cmd)
end)

events.on("paint", function()
    if rec_active or rec_waiting then
        local msg = "录制中：保持静止..."
        if rec_active then
            local ti = 1 / 64
            pcall(function()
                local t = globals.interval()
                if type(t) == "number" and t > 0 then ti = t end
            end)
            msg = string.format("录制中 %.2fs / %d tick", #rec_buf * ti, #rec_buf)
        end
        render.text(12, 12, color(255, 200, 80, 255), msg)
    end

    if not enabled:get() then return end
    local pawn = get_player()
    if pawn == nil then return end
    local weapon = get_grenade(pawn)
    if weapon == nil then return end
    local map = map_name()
    local points = lineups[map]
    if type(points) ~= "table" then return end

    local origin = pawn:origin()
    local view = camera_view()
    local rc = red:get()
    local gc = green:get()
    local rr, rg, rb = rc.r, rc.g, rc.b
    local gr, gg, gb = gc.r, gc.g, gc.b
    local show_limit = show_distance:get()
    local fade_start = show_limit * 0.82
    local fade_end = show_limit * 1.06
    local radius = position_radius:get()
    local ft = frame_time()

    local path_near = nil
    if auto_path:get() then
        local near, nd = find_nearest(pawn, map, weapon, path_range:get())
        if near and nd <= path_range:get() then
            path_near = near
        end
    end

    local draw_list = {}
    for _, point in ipairs(points) do
        if valid_point(point) and weapon_matches(point.weapon, weapon) then
            local distance = distance_xy(origin, point_position(point))
            local is_path = path_near ~= nil and same_spot_pos(point, path_near)
            if distance <= fade_end + 50 or is_path then
                local on_spot = distance <= radius and math.abs(origin.z - point.pos.z) <= 12
                local alpha = 255
                if not on_spot and not is_path then
                    alpha = update_label_alpha(point_label_key(point), distance, fade_start, fade_end, ft)
                end
                if alpha >= 4 or on_spot or is_path then
                    table.insert(draw_list, {
                        point = point,
                        distance = distance,
                        alpha = (on_spot or is_path) and math.max(alpha, 220) or alpha,
                        on_spot = on_spot,
                        is_path = is_path,
                        is_active = active == point,
                    })
                end
            end
        end
    end

    local standing_pt = nil
    local standing_best = math.huge
    for _, item in ipairs(draw_list) do
        if item.on_spot and item.distance < standing_best then
            standing_best = item.distance
            standing_pt = item.point
        end
    end
    if standing_pt then
        local filtered = {}
        for _, item in ipairs(draw_list) do
            if same_spot_pos(item.point, standing_pt) or item.is_path then
                table.insert(filtered, item)
            end
        end
        draw_list = filtered
    end

    local stack_groups = {}
    for _, item in ipairs(draw_list) do
        local pk = group_key(item.point)
        if not stack_groups[pk] then stack_groups[pk] = {} end
        table.insert(stack_groups[pk], item)
    end

    for _, items in pairs(stack_groups) do
        local point0 = items[1].point
        table.sort(items, function(a, b)
            return (a.point.name or "") < (b.point.name or "")
        end)

        local accent_r, accent_g, accent_b = rr, rg, rb
        for _, item in ipairs(items) do
            if item.is_active or item.is_path then accent_r, accent_g, accent_b = gr, gg, gb; break end
        end

        local any_on_spot = false
        local any_path = false
        for _, item in ipairs(items) do
            if item.on_spot then any_on_spot = true end
            if item.is_path then any_path = true end
        end

        if show_spot_ring:get() and (any_on_spot or any_path) then
            local ring_alpha = 255
            for _, item in ipairs(items) do
                if item.on_spot or item.is_path then ring_alpha = math.max(ring_alpha, item.alpha) end
            end
            draw_ring(point0, radius, accent_r, accent_g, accent_b, math.floor(170 * ring_alpha / 255))
        end

        if any_on_spot or any_path then
            local fov_item = nil
            local best_ang = math.huge
            for _, item in ipairs(items) do
                if item.on_spot or item.is_path then
                    local in_fov = is_view_in_point_fov(view, item.point)
                    if item.is_active then
                        fov_item = item
                        best_ang = -1
                    elseif best_ang >= 0 and in_fov then
                        local dp, dy = angle_delta_to_point(view, item.point)
                        local ad = math.abs(dp) + math.abs(dy)
                        if ad < best_ang then
                            best_ang = ad
                            fov_item = item
                        end
                    elseif fov_item == nil then
                        fov_item = item
                    end
                    local spot_alpha = math.max(item.alpha, 220)
                    local ready = in_fov or item.is_path
                    local playing = item.is_active and is_execute_down() and state ~= "aim"
                    draw_aim_target(pawn, item.point, playing, ready, spot_alpha, view)
                end
            end
            if fov_item then
                local ready = is_view_in_point_fov(view, fov_item.point) or fov_item.is_path
                draw_fov_ring(fov_item.point, ready, math.max(fov_item.alpha, 220))
            end
        end

        local sx, sy = render.world_to_screen(vector(point0.pos.x, point0.pos.y, point0.pos.z + 14))
        if sx and sy and show_points:get() then
            local heights, total_h = {}, 0
            for i, item in ipairs(items) do
                local tag = ""
                if point_has_macro(item.point) then tag = " · 宏"
                elseif item.point.walk then tag = " · 走投" end
                local subtitle = string.format("%.0f u · %s%s", item.distance, weapon_label(item.point.weapon), tag)
                local _, h = measure_label(item.point.name or "点位", subtitle)
                heights[i] = h
                total_h = total_h + h + (i < #items and 5 or 0)
            end

            local cur_y = sy - math.floor(total_h / 2)
            for i, item in ipairs(items) do
                local point = item.point
                local item_r, item_g, item_b = rr, rg, rb
                if item.is_active or item.is_path then item_r, item_g, item_b = gr, gg, gb end
                local tag = ""
                if point_has_macro(point) then tag = " · 宏"
                elseif point.walk then tag = " · 走投" end
                local subtitle = string.format("%.0f u · %s%s", item.distance, weapon_label(point.weapon), tag)
                local cy = cur_y + math.floor(heights[i] / 2)
                draw_world_label(sx, cy, point.name or "点位", subtitle,
                    item.alpha, item_r, item_g, item_b)
                cur_y = cur_y + heights[i] + 5
            end
        end
    end

    if show_status:get() and not rec_active and not rec_waiting then
        render.text(12, 12, color(255, 255, 255, 255), "手雷助手: " .. state)
        if candidate then
            render.text(12, 28, color(255, 255, 255, 255), "点位: " .. (candidate.name or "点位"))
        elseif path_near then
            render.text(12, 28, color(255, 255, 255, 255), "路径: " .. (path_near.name or "点位"))
        end
        if path_phase ~= "none" then
            render.text(12, 44, color(255, 255, 255, 255), "路径阶段: " .. path_phase)
        end
    end
end)
