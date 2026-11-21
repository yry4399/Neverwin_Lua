-- @author gera289
-- @uid 1
-- ============================================================
--  Eagle × Spotify  |  Neverlose Lua API (CS2)
--  Версия: spotify-2.2 (marquee text + no pulse + fix table overflow)
-- ============================================================

local VERSION = "cloud village-lky0112"
local NL_UI = ui

-- ============================================================
--  NETEASE MUSIC CENTER: isolated source + virtual UI controls
-- ============================================================
local NLC_UI = {
    controls = {},
    panel = { x = 0, y = 0, w = 0, h = 0, inside = false },
    text_focus = nil,
    key_capture = nil,
}
local nlc_db_key = "media_center_nlc_controls_v1"
local nlc_controls_by_key, nlc_controls_by_label = {}, {}
local nlc_saved_controls = {}
local nlc_dirty, nlc_dirty_since = false, 0

if type(db) == "table" and type(db.load) == "function" then
    local ok, saved = pcall(db.load, nlc_db_key, {})
    if ok and type(saved) == "table" then nlc_saved_controls = saved end
end

local function nlc_now()
    local value
    if type(globals) == "table" then
        local ok, result = pcall(function()
            local realtime = globals.realtime
            if type(realtime) == "function" then return realtime() end
            return realtime
        end)
        if ok then value = tonumber(result) end
    end
    return value or os.clock()
end

local function nlc_report_error(where, err)
    pcall(function() log.console("[NLC UI] " .. where .. ": " .. tostring(err)) end)
end

local function nlc_rgba(value)
    local r, g, b, a
    if value ~= nil then
        local ok, ur, ug, ub, ua = pcall(function() return value:unpack() end)
        if ok then r, g, b, a = ur, ug, ub, ua end
        if r == nil and type(value) == "table" then
            r, g, b, a = value.r, value.g, value.b, value.a
        end
    end
    local function channel(v, fallback)
        return math.max(0, math.min(255, math.floor(tonumber(v) or fallback)))
    end
    return channel(r, 255), channel(g, 255), channel(b, 255), channel(a, 255)
end

local function nlc_normalize(control, value)
    local kind = control.kind
    if kind == "color" then
        return color(nlc_rgba(value))
    elseif kind == "checkbox" then
        return value == true
    elseif kind == "text" or kind == "label" then
        return tostring(value or "")
    elseif kind == "slider_int" or kind == "slider_float" then
        local number = tonumber(value) or tonumber(control.value) or control.min or 0
        if kind == "slider_int" then
            if number >= 0 then
                number = math.floor(number + 0.5)
            else
                number = math.ceil(number - 0.5)
            end
        end
        return math.max(control.min, math.min(control.max, number))
    elseif kind == "listbox" or kind == "combo" or kind == "keybind" then
        return math.max(0, math.floor(tonumber(value) or 0))
    end
    return value
end

local function nlc_same_value(control, a, b)
    if control.kind ~= "color" then return a == b end
    local ar, ag, ab, aa = nlc_rgba(a)
    local br, bg, bb, ba = nlc_rgba(b)
    return ar == br and ag == bg and ab == bb and aa == ba
end

local function nlc_mark_dirty()
    nlc_dirty = true
    nlc_dirty_since = nlc_now()
end

local nlc_control_methods = {}
nlc_control_methods.__index = nlc_control_methods

function nlc_control_methods:get()
    return self.value
end

function nlc_control_methods:set(value)
    value = nlc_normalize(self, value)
    if not nlc_same_value(self, self.value, value) then
        self.value = value
        if self.kind ~= "button" and self.kind ~= "label" then nlc_mark_dirty() end
    end
    return self
end

function nlc_control_methods:change(value)
    self:set(value)
    if self._callback then
        local ok, err = pcall(self._callback, self.value, self)
        if not ok then nlc_report_error("change " .. self.label, err) end
    end
    return self
end

function nlc_control_methods:callback(fn)
    if type(fn) == "function" then self._callback = fn end
    return self
end

function nlc_control_methods:activate()
    if self.kind ~= "button" or not self._callback then return false end
    local ok, err = pcall(self._callback)
    if not ok then nlc_report_error("click " .. self.label, err) end
    return ok
end

function nlc_control_methods:items(list)
    if list == nil then return self.item_values end
    if type(list) ~= "table" then return self end
    local copied = {}
    for i = 1, #list do copied[i] = list[i] end
    self.item_values = copied
    local selection = self.value or 0
    if #copied == 0 then
        selection = 0
    elseif selection >= #copied then
        selection = #copied - 1
    end
    self:set(selection)
    return self
end

nlc_control_methods.set_items = nlc_control_methods.items

function nlc_control_methods:depends(other, value)
    self.dependencies[#self.dependencies + 1] = { control = other, value = value }
    return self
end

function nlc_control_methods:inactive(state, reason)
    self.inactive_state = state == true
    self.inactive_reason = reason
    return self
end

local function nlc_new_control(group, kind, label, default, min, max, extra)
    label = tostring(label or "")
    local control = setmetatable({
        group = group,
        label = label,
        kind = kind,
        key = group .. "\030" .. label .. "\030" .. kind,
        min = min,
        max = max,
        height = extra,
        value = default,
        item_values = {},
        dependencies = {},
        inactive_state = false,
    }, nlc_control_methods)

    if kind == "listbox" or kind == "combo" then
        local source = min or {}
        control.min = nil
        for i = 1, #source do control.item_values[i] = source[i] end
    elseif kind == "button" then
        control._callback = min
        control.value = nil
    end

    control.value = nlc_normalize(control, control.value)
    local saved = nlc_saved_controls[control.key]
    if saved ~= nil and kind ~= "button" and kind ~= "label" then
        control.value = nlc_normalize(control, saved)
    end

    NLC_UI.controls[#NLC_UI.controls + 1] = control
    nlc_controls_by_key[control.key] = control
    if nlc_controls_by_label[label] == nil then nlc_controls_by_label[label] = control end
    return control
end

local function nlc_find_control(label, group)
    if group ~= nil then
        for i = 1, #NLC_UI.controls do
            local control = NLC_UI.controls[i]
            if control.group == group and control.label == label then return control end
        end
        return nil
    end
    return nlc_controls_by_key[label] or nlc_controls_by_label[label]
end

function NLC_UI.get(label, group)
    local control = nlc_find_control(label, group)
    if control then return control.value, control end
    return nil
end

function NLC_UI.click(label, group)
    local control = nlc_find_control(label, group)
    if control then return control:activate() end
    return false
end

function NLC_UI.save()
    if not nlc_dirty then return true end
    local data = {}
    for i = 1, #NLC_UI.controls do
        local control = NLC_UI.controls[i]
        if control.kind ~= "button" and control.kind ~= "label" then
            if control.kind == "color" then
                local r, g, b, a = nlc_rgba(control.value)
                data[control.key] = { r = r, g = g, b = b, a = a }
            else
                data[control.key] = control.value
            end
        end
    end
    local ok, result = pcall(db.save, nlc_db_key, data)
    if ok and result ~= false then
        nlc_dirty = false
        return true
    end
    return false, result
end

function NLC_UI.tick()
    if nlc_dirty and nlc_now() - nlc_dirty_since >= 0.45 then return NLC_UI.save() end
end

local function nlc_input_blocked()
    return NLC_UI.text_focus ~= nil or NLC_UI.key_capture ~= nil
end

local function nlc_pointer_over_panel()
    return NLC_UI.panel.inside == true
end

local function nlc_new_group(tab_name, group_name)
    local group = { tab = tab_name, name = group_name }
    function group.text(label, default)
        return nlc_new_control(group_name, "text", label, default)
    end
    function group.listbox(label, items, height)
        return nlc_new_control(group_name, "listbox", label, 0, items, nil, height)
    end
    function group.button(label, fn)
        return nlc_new_control(group_name, "button", label, nil, fn)
    end
    function group.checkbox(label, default)
        return nlc_new_control(group_name, "checkbox", label, default)
    end
    function group.slider_int(label, min, max, default)
        return nlc_new_control(group_name, "slider_int", label, default, min, max)
    end
    function group.slider_float(label, min, max, default)
        return nlc_new_control(group_name, "slider_float", label, default, min, max)
    end
    function group.combo(label, items, default)
        return nlc_new_control(group_name, "combo", label, default, items)
    end
    function group.color(label, default)
        return nlc_new_control(group_name, "color", label, default)
    end
    function group.keybind(label, default)
        return nlc_new_control(group_name, "keybind", label, default)
    end
    function group.label(text)
        return nlc_new_control(group_name, "label", text, text)
    end
    return group
end

local nlc_virtual_ui = {}
function nlc_virtual_ui.sidebar() end
function nlc_virtual_ui.tab(name)
    local tab = { name = name, groups = {} }
    function tab:group(group_name)
        local group = nlc_new_group(name, group_name)
        self.groups[#self.groups + 1] = group
        return group
    end
    return tab
end

local function nlc_bootstrap()
-- @author 1star
-- @uid 1

--[[
    netease_lyric_fade.lua  ——  Starlose (lua.nlcrack.cc) 移植版 v10
    网易云在线播放 + 唱片 HUD（封面 / 歌名 / 作者 / 歌词）

    ── 与原版（Starline / GD 风格 API）的对照 ──────────────────────────
    cheat.FindExport        -> memory.export
    cheat.GetScreenSize     -> render.screen_size
    cheat.LogScreen         -> log.console / client.notify
    cheat.GetClipboard      -> utils.clipboard_get
    renderer.CreateFont     -> render.font(name, size)   （scripts/fonts）
    renderer.MeasureText    -> render.text_size
    renderer.Text           -> render.text(x, y, col, text, flags, size, font)
    renderer.Circle/Filled  -> render.circle / render.circle_filled
    renderer.Line           -> render.line
    renderer.Image          -> render.image(texture, x, y, w, h, tint, rounding)
    renderer.CreateTextureFromMemory -> render.load_image / render.texture
    renderer.PushClip       -> render.clip_push / render.clip_pop
    renderer.WorldToScreen  -> render.world_to_screen(vector)
    globals.GetRealTime     -> globals.realtime
    engine.GetLocalEyePos   -> entity.local_pawn():eye_position()
    engine.GetViewAngles    -> engine.camera_angles() / engine.view_angles()
    math.AngleVectors       -> vector:angle_vectors()
    
    entity.GetLocalPlayer   -> entity.local_pawn()
    http.Get / json.Decode  -> http.get / json.decode
    file.Read/Write/Append  -> file.read/file.write/file.append（根目录 scripts/data）
    events.On               -> events.on
    ui.Tab/Group/TextInput  -> ui.tab/ui.group/ui.text
    ListBox/SliderInt/...   -> ui.listbox/ui.slider_int/...
    :Get() / :SetItems()    -> :get() / :items()

    ── 使用前提 ────────────────────────────────────────────────────────
    1. 必须开启 insecure 模式（DirectShow 播放要 ffi，网络/文件要 http/file）。
    2. 字体放 C:\starlose\scripts\fonts\ ：msyh.ttc（中文）、malgun.ttf（韩文）
       不放也能跑，只是韩文会缺字形 / 回退默认字体。
    3. Cookie 放 C:\starlose\scripts\data\music\cookie.txt（VIP 歌必需）。
    4. 封面图可选：C:\starlose\scripts\images\netease\<歌曲id>.jpg
       （脚本也会把下载到的封面写到 data\music\cover_<id>.jpg 备查）

    数据源（全部走网易云自己的接口）：
      搜索 /api/cloudsearch/pc?s=          支持拼音
      直链 /api/song/enhance/player/url    免费歌有 url，VIP 返回 -110
      兜底 代理 (meting) 与 song/media/outer/url，直接交给 DirectShow 跟随 302
      歌词 /api/song/lyric?id=
      详情 /api/song/detail/?ids=[..]
      歌单 /api/user/playlist + v6/playlist/detail 的 trackIds
]]

-- ================================================================ 环境
HAS_FILE = (type(file) == "table")
HAS_HTTP = (type(http) == "table")
HAS_FFI  = (type(ffi) == "table")
HAS_MEM  = (type(memory) == "table")

NE_BASE     = "https://music.163.com"
MUSIC       = "music"
DBG         = "music/debug.log"
COOKIE_FILE = "music/cookie.txt"
cookie      = ""

local function say(msg)
    pcall(function() log.console("[音乐] " .. tostring(msg)) end)
end

local function notify(msg)
    pcall(function() client.notify(tostring(msg), "网易云") end)
end

-- 这个构建里 globals.realtime 是【函数】（文档写成字段），两种都兼容
local function raw_time()
    local v = nil
    pcall(function()
        local g = globals.realtime
        if type(g) == "function" then v = g() else v = g end
    end)
    v = tonumber(v)
    if not v then
        pcall(function()
            local g = globals.curtime
            if type(g) == "function" then v = tonumber(g()) else v = tonumber(g) end
        end)
    end
    return v or 0
end

-- 有的构建只有 file.write 没有 file.append，而且 append 可能"返回成功但没写"，
-- 所以这里 append 之后回读校验，没长就退回 读-拼接-写
dbg_size = -1
local function dbg(msg)
    if not HAS_FILE then return end
    local text = tostring(msg)
    local ok = pcall(function()
        local line = string.format("[%8.2f] %s\n", raw_time(), text)

        local appended = false
        if type(file.append) == "function" then
            local okc, r = pcall(file.append, DBG, line)
            appended = okc and (r ~= false)
        end

        if appended then
            local chk = nil
            pcall(function() chk = file.read(DBG) end)
            local sz = (type(chk) == "string") and #chk or -1
            if sz <= dbg_size then appended = false else dbg_size = sz end
        end

        if not appended then
            local old = nil
            pcall(function() old = file.read(DBG) end)
            if type(old) ~= "string" then old = "" end
            if #old > 65536 then old = old:sub(-32768) end
            local merged = old .. line
            pcall(file.write, DBG, merged)
            dbg_size = #merged
        end
    end)
    if not ok then
        pcall(file.append, DBG, "[dbg-fallback] " .. text .. "\n")
    end
end

if HAS_FILE then
    pcall(file.write, DBG, "=== netease_lyric_fade v10 (starlose) ===\n")
    -- 记下初始长度，第一行 append 的回读校验才有基准
    pcall(function()
        local t = file.read(DBG)
        if type(t) == "string" then dbg_size = #t end
    end)
end
dbg(string.format("boot: ffi=%s http=%s file=%s mem=%s g=%s",
        tostring(HAS_FFI), tostring(HAS_HTTP), tostring(HAS_FILE), tostring(HAS_MEM),
        tostring(type(globals) == "table")))
-- ── 自动开启 insecure（参考 unsafe.lua：写配置键后重载自身即可生效）──────────
-- ffi/http/file 是【加载时】注入的，所以流程是：写配置 → 重载脚本 → 再加载就齐了。
-- 只在"配置里还没打开"时重载一次，避免反复重载成死循环。
local insecure_need = not (HAS_HTTP and HAS_FFI and HAS_FILE)
local insecure_optout, insecure_cfg = false, nil
pcall(function()
    if config then
        insecure_optout = (config.get("lua.nlc_insecure_optout") == true)
        insecure_cfg = config.get("lua.allow_insecure")
    end
end)

if insecure_need and not insecure_optout and config then
    if insecure_cfg ~= true then
        local set_ok = false
        pcall(function()
            config.set("lua.allow_insecure", true)
            set_ok = (config.get("lua.allow_insecure") == true)
        end)
        dbg("自动开启 insecure：set=" .. tostring(set_ok))
        if set_ok then
            notify("正在开启 Allow Insecure 并重载脚本…")
            pcall(function()
                if type(client.delay) == "function" then
                    client.delay(0.4, function() pcall(function() client.reload() end) end)
                elseif type(client.reload) == "function" then
                    client.reload()
                end
            end)
        else
            notify("自动开启 Allow Insecure 失败，请手动勾选或在菜单里允许")
        end
    else
        dbg("配置 lua.allow_insecure=true 但本次仍无 ffi/http：可能需菜单允许或重启客户端")
        notify("insecure 已配置但未生效：请重启客户端一次")
    end
end

-- ================================================================ Win32 / DirectShow
export_cache = {}
local function export_addr(mod, name)
    if not HAS_MEM then return nil end
    local key = mod .. "!" .. name
    local hit = export_cache[key]
    if hit ~= nil then return hit or nil end
    local ok, a = pcall(memory.export, mod, name)
    if ok and type(a) == "number" and a > 0 then
        export_cache[key] = a
        return a
    end
    export_cache[key] = false
    return nil
end

ds = {
    ready = false, inited = false,
    graph = nil, control = nil, seek = nil, audio = nil,
    has_seek = false, has_audio = false, dur_ms = 0,
    vol_put = 7, vol_get = 8,
}

local ds_stop, ds_play, ds_pos_ms, ds_run, ds_pause, set_music_volume

if HAS_FFI then
  local __ds_ok, __ds_err = pcall(function()
    local libs, p_load, p_gpa = {}, nil, nil

    local function init_kernel()
        if p_load and p_gpa then return end
        -- 先拿 kernel32 两个导出地址（memory.export 最稳，kernel32 必在）
        local a = export_addr("kernel32.dll", "LoadLibraryA")
        local b = export_addr("kernel32.dll", "GetProcAddress")
        if a then p_load = ffi.cast("void* (__stdcall *)(const char *)", a) end
        if b then p_gpa  = ffi.cast("void* (__stdcall *)(void *, const char *)", b) end

        -- 兜底 1：ffi.C 默认命名空间
        if not (p_load and p_gpa) then
            pcall(ffi.cdef, [[
                void * __stdcall LoadLibraryA(const char *);
                void * __stdcall GetProcAddress(void *, const char *);
            ]])
            if not p_load then pcall(function() p_load = ffi.C.LoadLibraryA end) end
            if not p_gpa  then pcall(function() p_gpa  = ffi.C.GetProcAddress end) end
        end

        -- 兜底 2：ffi.load
        if not (p_load and p_gpa) then
            local ns = nil
            pcall(function() ns = ffi.load("kernel32") end)
            if ns then
                pcall(function() p_load = ns.LoadLibraryA end)
                pcall(function() p_gpa  = ns.GetProcAddress end)
            end
        end
    end

    local function load_lib(name)
        if libs[name] ~= nil then return libs[name] or nil end
        init_kernel()
        local h = nil
        if p_load then
            local ok, r = pcall(function() return p_load(name) end)
            if ok then h = r end
        end
        libs[name] = h or false
        return h or nil
    end

    local function proc(lib, sym)
        local a = export_addr(lib, sym)
        if a then return a end
        init_kernel()
        local h = load_lib(lib)
        if h and p_gpa then
            local ok, p = pcall(function() return p_gpa(h, sym) end)
            if ok and p then return p end
        end
        return nil
    end

    pcall(ffi.cdef, [[
        typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; unsigned char Data4[8]; } SL_GUID;
    ]])

    local function guid(d1, d2, d3, b)
        local g = ffi.new("SL_GUID")
        g.Data1, g.Data2, g.Data3 = d1, d2, d3
        for i = 1, 8 do g.Data4[i - 1] = b[i] end
        return g
    end

    ds.CLSID_FilterGraph = guid(0xe436ebb3, 0x524f, 0x11ce, { 0x9f, 0x53, 0x00, 0x20, 0xaf, 0x0b, 0xa7, 0x70 })
    ds.IID_IGraphBuilder = guid(0x56a868a9, 0x0ad4, 0x11ce, { 0xb0, 0x3a, 0x00, 0x20, 0xaf, 0x0b, 0xa7, 0x70 })
    ds.IID_IMediaControl = guid(0x56a868b1, 0x0ad4, 0x11ce, { 0xb0, 0x3a, 0x00, 0x20, 0xaf, 0x0b, 0xa7, 0x70 })
    ds.IID_IMediaSeeking = guid(0x36b73880, 0xc2c8, 0x11cf, { 0x8b, 0x46, 0x00, 0x80, 0x5f, 0x6c, 0xef, 0x60 })
    ds.IID_IBasicAudio  = guid(0x56a868b3, 0x0ad4, 0x11ce, { 0xb0, 0x3a, 0x00, 0x20, 0xaf, 0x0b, 0xa7, 0x70 })

    local ci = proc("ole32.dll", "CoInitializeEx")
    local cc = proc("ole32.dll", "CoCreateInstance")
    local mw = proc("kernel32.dll", "MultiByteToWideChar")
    ds.co_init   = ci and ffi.cast("int (__stdcall *)(void *, unsigned long)", ci) or nil
    ds.co_create = cc and ffi.cast("int (__stdcall *)(const SL_GUID *, void *, unsigned long, const SL_GUID *, void **)", cc) or nil
    ds.mb2wc     = mw and ffi.cast("int (__stdcall *)(unsigned, unsigned long, const char *, int, uint16_t *, int)", mw) or nil
    ds.ready = (ds.co_init ~= nil and ds.co_create ~= nil and ds.mb2wc ~= nil)

    local function vcall(obj, index, sig, ...)
        if not obj then return nil end
        local vt = ffi.cast("void**", ffi.cast("void**", obj)[0])
        local fp = vt[index]
        if fp == nil then return nil end
        local fn = ffi.cast(sig, fp)
        local args, n = { ... }, select("#", ...)
        local ok, r = pcall(function() return fn(obj, unpack(args, 1, n)) end)
        if not ok then
            dbg("vcall[" .. index .. "] 异常: " .. tostring(r))
            return nil
        end
        return tonumber(r)
    end

    local function ds_wide(s)
        if not ds.mb2wc then return nil end
        local need = ds.mb2wc(65001, 0, s, -1, nil, 0)
        if not need or need <= 0 then return nil end
        local buf = ffi.new("uint16_t[?]", need)
        ds.mb2wc(65001, 0, s, -1, buf, need)
        return buf
    end

    function ds_stop()
        local function rel(obj)
            if obj then vcall(obj, 2, "unsigned long (__stdcall *)(void *)") end
        end
        if ds.control then vcall(ds.control, 9, "int (__stdcall *)(void *)") end
        rel(ds.seek); rel(ds.audio); rel(ds.control); rel(ds.graph)
        ds.control, ds.seek, ds.audio = nil, nil, nil
        ds.has_seek, ds.has_audio, ds.graph, ds.dur_ms = false, false, nil, 0
    end

    function ds_run()   if ds.control then return vcall(ds.control, 7, "int (__stdcall *)(void *)") end end
    function ds_pause() if ds.control then return vcall(ds.control, 8, "int (__stdcall *)(void *)") end end

    local function ds_query(iid)
        local out = ffi.new("void*[1]")
        local hr = vcall(ds.graph, 0, "int (__stdcall *)(void *, const SL_GUID *, void **)", iid, out)
        if hr == 0 and out[0] then return out[0] end
        return nil
    end

    function ds_play(url)
        if not ds.ready then return false, "依赖缺失(ole32/kernel32)" end
        if not ds.inited then pcall(function() ds.co_init(nil, 2) end) ds.inited = true end
        ds_stop()

        local out = ffi.new("void*[1]")
        local hr = ds.co_create(ds.CLSID_FilterGraph, nil, 1, ds.IID_IGraphBuilder, out)
        if hr ~= 0 or not out[0] then
            hr = ds.co_create(ds.CLSID_FilterGraph, nil, 23, ds.IID_IGraphBuilder, out)
        end
        if not out[0] then return false, "建图失败 " .. tostring(hr) end
        ds.graph = out[0]

        local wide = ds_wide(url)
        if not wide then return false, "宽字符失败" end
        local r = vcall(ds.graph, 13, "int (__stdcall *)(void *, const uint16_t *, const uint16_t *)", wide, nil)
        if r ~= 0 and r ~= 1 then return false, "RenderFile=" .. tostring(r) end

        ds.control = ds_query(ds.IID_IMediaControl)
        if not ds.control then return false, "无 IMediaControl" end
        local rh = ds_run()

        ds.seek = ds_query(ds.IID_IMediaSeeking)
        if ds.seek then
            -- GetDuration vtable 索引 = 10
            local d = ffi.new("int64_t[1]")
            local dhr = vcall(ds.seek, 10, "int (__stdcall *)(void *, int64_t *)", d)
            local dur = tonumber(d[0]) or 0
            if dhr == 0 and dur > 0 then
                ds.dur_ms = dur / 10000
                ds.has_seek = true
            end
        end

        ds.audio = ds_query(ds.IID_IBasicAudio)
        if ds.audio then
            -- put_Volume=7, get_Volume=8：写进去再读回来验证
            local cb = -1500
            local ph = vcall(ds.audio, 7, "int (__stdcall *)(void *, int)", cb)
            local back = ffi.new("int32_t[1]")
            local gh = vcall(ds.audio, 8, "int (__stdcall *)(void *, int32_t *)", back)
            local v = tonumber(back[0])
            if ph == 0 and gh == 0 and v and math.abs(v - cb) <= 3 then
                ds.has_audio = true
                dbg("图内音量可用 put=7 get=8 读回=" .. tostring(v))
            else
                ph = vcall(ds.audio, 8, "int (__stdcall *)(void *, int)", cb)
                local back2 = ffi.new("int32_t[1]")
                gh = vcall(ds.audio, 7, "int (__stdcall *)(void *, int32_t *)", back2)
                local v2 = tonumber(back2[0])
                if ph == 0 and gh == 0 and v2 and math.abs(v2 - cb) <= 3 then
                    ds.vol_put, ds.vol_get, ds.has_audio = 8, 7, true
                    dbg("图内音量可用 put=8 get=7")
                else
                    dbg("音量接口验证失败 ph=" .. tostring(ph) .. " gh=" .. tostring(gh) ..
                        " v=" .. tostring(v) .. " v2=" .. tostring(v2))
                end
            end
        else
            dbg("拿不到 IBasicAudio")
        end

        return (rh == 0 or rh == 1), "Run=" .. tostring(rh)
    end

    function ds_pos_ms()
        if not (ds.seek and ds.has_seek) then return nil end
        local out = ffi.new("int64_t[1]")
        -- GetCurrentPosition vtable 索引 = 12
        if vcall(ds.seek, 12, "int (__stdcall *)(void *, int64_t *)", out) ~= 0 then return nil end
        local v = tonumber(out[0]) or 0
        if v < 0 then return nil end
        return v / 10000
    end

    -- 跳转到指定毫秒位置（真正驱动 DirectShow 跳转）。返回 true 表示调用成功。
    function ds_seek_ms(target_ms)
        if not (ds.seek and ds.has_seek) then return false end
        if target_ms < 0 then target_ms = 0 end
        local pos = ffi.new("int64_t[1]", math.floor(target_ms * 10000))
        local stop = ffi.new("int64_t[1]", 0)
        -- SetPositions vtable 索引 = 14
        local hr = vcall(ds.seek, 14,
            "int (__stdcall *)(void *, int64_t *, uint32_t, int64_t *, uint32_t)",
            pos, 0x4, stop, 0)
        if hr == 0 then
            -- 跳转成功：同步虚拟时间轴，并延后下一次轮询，
            -- 避免 DS 跳转生效前轮询读到旧位置把 start_t 拉回
            local nowt = raw_time()
            start_t = nowt - target_ms / 1000
            pos_ms = target_ms
            last_poll = nowt
            last_seek_t = nowt
            pos_bad = 0
            return true
        end
        return false
    end

    -- 只改这首曲子的音量（图内音量），centibel：0=原音量，-10000=静音
    -- 用等响曲线：0..1 当振幅再转 dB（20*log10），这样 0-100 每一档都能听出差别
    function set_music_volume(v01)
        if not (ds.audio and ds.has_audio) then return false end
        local cb
        if v01 <= 0.002 then
            cb = -10000
        else
            if v01 > 1 then v01 = 1 end
            cb = math.floor(2000 * math.log(v01) / math.log(10))
        end
        if cb > 0 then cb = 0 end
        if cb < -10000 then cb = -10000 end
        local hr = vcall(ds.audio, ds.vol_put, "int (__stdcall *)(void *, int)", cb)
        dbg("图内音量 " .. math.floor(v01 * 100 + 0.5) .. "% cb=" .. cb .. " hr=" .. tostring(hr))
        return hr == 0
    end
  end)
  if not __ds_ok then
    dbg("boot: ffi 块异常: " .. tostring(__ds_err))
    ds.ready = false
    ds_stop = ds_stop or function() end
    ds_play = ds_play or function() return false, "DS 初始化失败" end
    ds_pos_ms = ds_pos_ms or function() return nil end
    ds_run = ds_run or function() end
    ds_pause = ds_pause or function() end
    set_music_volume = set_music_volume or function() return false end
  end
else
    ds.ready = false
    ds_stop = function() end
    ds_run = function() end
    ds_pause = function() end
    ds_play = function() return false, "无 ffi（需开启 insecure 模式）" end
    ds_pos_ms = function() return nil end
    set_music_volume = function() return false end
end

-- ================================================================ 字体
-- 从这里到文件末尾整体兜一层：任何初始化异常都写进 debug.log，而不是让脚本静默卸载
__body_ok, __body_err = pcall(function()

SIZES = { 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56 }

-- render.font 从 scripts/fonts 读取；同时把常见绝对路径当兜底候选
CJK_CANDIDATES = {
    "msyh.ttc", "msyhbd.ttc", "msyhl.ttc", "Deng.ttf", "simhei.ttf", "simsun.ttc",
    "C:/Windows/Fonts/msyh.ttc",
}
KR_CANDIDATES = {
    "malgun.ttf", "malgunbd.ttf", "malgunsl.ttf", "NanumGothic.ttf",
    "NotoSansKR-Regular.otf", "gulim.ttc",
    "C:/Windows/Fonts/malgun.ttf",
}
UNI_CANDIDATES = {
    "ArialUnicodeMS.ttf", "arialuni.ttf", "unifont.ttf",
    "C:/Windows/Fonts/ArialUnicodeMS.ttf",
}

font_cache = {}
local function get_font(path, size)
    local key = tostring(path) .. "|" .. tostring(size)
    local hit = font_cache[key]
    if hit ~= nil then return hit or nil end
    local f = nil
    local ok, obj = pcall(function() return render.font(path, size) end)
    if ok and obj then
        local loaded = true
        pcall(function() loaded = obj:loaded() ~= false end)
        if loaded then f = obj end
    end
    font_cache[key] = f or false
    return f
end

fonts, fonts_kr, fonts_uni = {}, {}, {}

local function build_font_set(candidates, tbl, label)
    if tbl.built then return tbl end
    tbl.built = true
    for _, path in ipairs(candidates) do
        local made = 0
        for i = 1, #SIZES do
            local f = get_font(path, SIZES[i])
            if f then
                tbl[i] = f
                made = made + 1
            end
        end
        dbg(string.format("[字体] %s 候选 %s 建成=%d/%d", label, tostring(path), made, #SIZES))
        if made > 0 then
            dbg(string.format("[字体] %s 采用 %s", label, tostring(path)))
            return tbl
        end
    end
    dbg("[字体] " .. label .. " 全部候选失败，回退默认字体")
    return nil
end

build_font_set(CJK_CANDIDATES, fonts, "中文")

-- 选最接近的字号档位（字体对象是按档位预建的）
local function pick_size(px)
    local best, bi = 1e9, 4
    for i = 1, #SIZES do
        local d = math.abs(SIZES[i] - px)
        if d < best then best, bi = d, i end
    end
    return bi, SIZES[bi]
end

local function ensure_kr_fonts() return build_font_set(KR_CANDIDATES, fonts_kr, "韩文") end
local function ensure_uni_fonts() return build_font_set(UNI_CANDIDATES, fonts_uni, "中韩混排") end

-- 按 UTF-8 完整字符步进，判断每个字符属于哪套字体，绝不在多字节字符中间切开
local function char_kind(s, i)
    local b = string.byte(s, i)
    if not b then return nil, 1 end
    local n = 1
    if b >= 0xF0 then n = 4
    elseif b >= 0xE0 then n = 3
    elseif b >= 0xC0 then n = 2 end

    local kind = "latin"
    if b >= 0xEA and b <= 0xED then
        kind = "kr"                       -- U+A800–U+D7FF，含韩文音节
    elseif b >= 0xE4 and b <= 0xE9 then
        kind = "cjk"                      -- U+4E00–U+9FFF 汉字
    elseif b == 0xE1 then
        local b2 = string.byte(s, i + 1)
        if b2 and b2 >= 0x84 and b2 <= 0x87 then kind = "kr" end   -- 韩文字母
    elseif b >= 0xE0 and b <= 0xE3 then
        kind = "cjk"                      -- 日文假名等，用中文字体
    end
    return kind, n
end

local function utf8_len(s)
    local i, n = 1, 0
    while i <= #s do
        local _, step = char_kind(s, i)
        i = i + (step or 1)
        n = n + 1
    end
    return n
end

local function scan_script(s)
    if type(s) ~= "string" then return false, false end
    local hangul, cjk = false, false
    local i = 1
    while i <= #s do
        local kind, step = char_kind(s, i)
        if kind == "kr" then hangul = true
        elseif kind == "cjk" then cjk = true end
        i = i + step
    end
    return hangul, cjk
end

local function split_runs(s)
    local runs = {}
    local i = 1
    local cur, curkind = "", nil
    while i <= #s do
        local kind, step = char_kind(s, i)
        local ch = string.sub(s, i, i + step - 1)
        if kind ~= curkind then
            if cur ~= "" then runs[#runs + 1] = { text = cur, kind = curkind } end
            cur, curkind = ch, kind
        else
            cur = cur .. ch
        end
        i = i + step
    end
    if cur ~= "" then runs[#runs + 1] = { text = cur, kind = curkind } end
    return runs
end

-- 文字宽度缓存：text_size 每帧调用很费
measure_cache = {}
local function measure(font, text, size)
    local key = size .. "|" .. tostring(text)
    local v = measure_cache[key]
    if v then return v end

    local w = nil
    local ok, r = pcall(function()
        if font then return render.text_size(text, "", size, font) end
        return render.text_size(text, "", size)
    end)
    if ok and type(r) == "number" and r > 0 then
        w = r
    else
        -- 测量失败时按字符数估算（按字节算会把韩文/中文算成 3 倍宽）
        w = math.floor(utf8_len(text) * size * 0.62 + 0.5)
        if w <= 0 then w = size end
    end

    if #measure_cache > 400 then measure_cache = {} end
    measure_cache[key] = w
    return w
end

-- ================================================================ 韩文兜底
-- 有些构建的字体图集只包含拉丁/中文，韩文音节（U+AC00–D7A3）会画成空白。
-- 这里先测字宽判断字形是否存在；不存在就把韩文转成罗马音再画，至少不是一片空白。
HANGUL_L = { "g","kk","n","d","tt","r","m","b","pp","s","ss","","j","jj","ch","k","t","p","h" }
HANGUL_V = { "a","ae","ya","yae","eo","e","yeo","ye","o","wa","wae","oe","yo","u","wo","we","wi","yu","eu","ui","i" }
HANGUL_T = { "","k","k","ks","n","nj","nh","t","l","lk","lm","lb","ls","lt","lp","lh","m","p","ps","t","t","ng","t","t","k","t","p","h" }

local function utf8_cp(s, i, step)
    local b1 = string.byte(s, i)
    if step == 3 then
        local b2, b3 = string.byte(s, i + 1), string.byte(s, i + 2)
        if b1 and b2 and b3 then
            return (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
        end
    end
    return nil
end

local function hangul_roman(s)
    local out = {}
    local i = 1
    while i <= #s do
        local kind, step = char_kind(s, i)
        local ch = string.sub(s, i, i + step - 1)
        local cp = (kind == "kr" and step == 3) and utf8_cp(s, i, step) or nil
        if cp and cp >= 0xAC00 and cp <= 0xD7A3 then
            local idx = cp - 0xAC00
            local L = math.floor(idx / 588) + 1
            local V = math.floor((idx % 588) / 28) + 1
            local T = (idx % 28) + 1
            out[#out + 1] = (HANGUL_L[L] or "") .. (HANGUL_V[V] or "") .. (HANGUL_T[T] or "")
        else
            out[#out + 1] = ch
        end
        i = i + step
    end
    return table.concat(out)
end

local function raw_text_w(font, text, size)
    local ok, w = pcall(function()
        if font then return render.text_size(text, "", size, font) end
        return render.text_size(text, "", size)
    end)
    if ok and type(w) == "number" then return w end
    return -1
end

kr_ok_cache = nil
local function kr_ok()
    if kr_ok_cache ~= nil then return kr_ok_cache end

    ensure_kr_fonts()
    ensure_uni_fonts()
    local i = pick_size(24)
    local f = fonts_kr[i] or fonts_uni[i]
    if not f then
        kr_ok_cache = false
        dbg("韩文：没有可用的韩文字体对象 → 用罗马音显示")
        return false
    end

    local w_kr = raw_text_w(f, "안녕하세요", 24)
    local w_la = raw_text_w(f, "aaaaa", 24)
    -- 韩文是全角，正常应明显宽于等长度的拉丁字母；相等说明命中缺字回退
    kr_ok_cache = (w_kr > 0 and w_la > 0 and w_kr > w_la * 1.35)
    dbg(string.format("韩文字形检测：韩=%s 拉丁=%s → %s",
            tostring(w_kr), tostring(w_la), kr_ok_cache and "正常" or "缺字形（改用罗马音）"))
    return kr_ok_cache
end

local function maybe_romanize(text)
    if type(text) ~= "string" then return text end
    local hangul = scan_script(text)
    if not hangul then return text end
    if kr_ok() then return text end
    if kr_fallback_cb and kr_fallback_cb:get() == false then return text end
    return hangul_roman(text)
end
local function font_by_kind(kind, px)
    local i = pick_size(px)
    if kind == "kr" then
        ensure_kr_fonts()
        if fonts_kr[i] then return fonts_kr[i] end
        ensure_uni_fonts()
        if fonts_uni[i] then return fonts_uni[i] end
        return fonts[i]
    end
    return fonts[i]
end

-- 纯韩/韩英 → Malgun；中韩混排 → 统一字体（没有就分段绘制）
local function font_lookup(text, px)
    local hangul, cjk = scan_script(text)
    local i = pick_size(px)
    if not hangul then return fonts[i] end
    if cjk then
        ensure_uni_fonts()
        if fonts_uni[i] then return fonts_uni[i] end
    end
    return font_by_kind("kr", px)
end

-- 一行文字的宽度（混排且没有统一字体时按语种分段累加）
local function width_of(text, px)
    text = maybe_romanize(text)
    local hangul, cjk = scan_script(text)
    if hangul and cjk then
        ensure_uni_fonts()
        local i = pick_size(px)
        if not fonts_uni[i] then
            local total = 0
            for _, run in ipairs(split_runs(text)) do
                total = total + measure(font_by_kind(run.kind, px), run.text, px)
            end
            return total
        end
    end
    return measure(font_lookup(text, px), text, px)
end

local function draw_raw(font, text, x, y, col, size)
    if font then
        render.text(x, y, col, text, "", size, font)
    else
        render.text(x, y, col, text, "", size)
    end
end

-- 画一行文字，自动处理中韩混排；glow_d 为 0 表示不发光。返回实际绘制宽度
-- 柔和光晕：三层同心环 × 8 方向 + 一层底色，近似高斯衰减。
-- 相比原来"4 方向 × 2 层"的硬偏移，这样不会出现四个鬼影，圆润干净。
-- 开销：每段文字最多 1 + 3×8 = 25 次绘制，alpha 过低的那层直接跳过。
-- 四层同心环（alpha 0.50/0.34/0.18/0.08 近似高斯），核心向白色偏移 45%
GLOW_RINGS = { { 0.30, 0.50 }, { 0.65, 0.34 }, { 1.05, 0.18 }, { 1.50, 0.08 } }

-- 色板取出来的颜色可能是 0..1 也可能是 0..255，统一成 0..255
local function col255(c, dr, dg, db, da)
    if not c then return color(dr or 255, dg or 255, db or 255, da or 255) end
    local r, g, b, a = 255, 255, 255, 255
    pcall(function() r, g, b, a = c:unpack() end)
    if r <= 1.01 and g <= 1.01 and b <= 1.01 and (a or 1) <= 1.01 then
        r, g, b, a = r * 255, g * 255, b * 255, (a or 1) * 255
    end
    return color(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5),
                 math.floor((a or 255) + 0.5))
end
local function mix_white(r, g, b, k)
    return math.floor(r + (255 - r) * k),
           math.floor(g + (255 - g) * k),
           math.floor(b + (255 - b) * k)
end

local function paint_glow(font, seg, sx, y, px, glow_col, glow_alpha, d)
    if not glow_col or (glow_alpha or 0) < 6 or (d or 0) <= 0 then return end
    local gr, gg, gb = glow_col:unpack()

    local cr, cg, cb = mix_white(gr, gg, gb, 0.45)
    draw_raw(font, seg, sx, y, color(cr, cg, cb, math.floor(glow_alpha * 0.24)), px)

    local dirs = (px >= 34) and 12 or 8
    local ring_count = (px >= 22) and #GLOW_RINGS or 2
    for i = 1, ring_count do
        local ring = GLOW_RINGS[i]
        local a = math.floor(glow_alpha * ring[2])
        if a >= 6 then
            local rr = d * ring[1]
            local c = color(gr, gg, gb, a)
            for k = 0, dirs - 1 do
                local ang = k * (2 * math.pi / dirs)
                draw_raw(font, seg, sx + math.cos(ang) * rr, y + math.sin(ang) * rr, c, px)
            end
        end
    end
end
local function draw_text_line(text, x, y, px, col, glow_col, glow_alpha, glow_d)
    text = maybe_romanize(text)
    local hangul, cjk = scan_script(text)
    local need_runs = false
    if hangul and cjk then
        ensure_uni_fonts()
        local i = pick_size(px)
        need_runs = (fonts_uni[i] == nil)
    end

    local d = tonumber(glow_d) or 0
    local glow_on_here = (d > 0 and glow_col ~= nil and (glow_alpha or 0) > 0)

    local function paint(font, seg, sx)
        local w = measure(font, seg, px)
        if glow_on_here then
            paint_glow(font, seg, sx, y, px, glow_col, glow_alpha, d)
        end
        draw_raw(font, seg, sx, y, col, px)
        return w
    end

    local total = 0
    if need_runs then
        for _, run in ipairs(split_runs(text)) do
            total = total + paint(font_by_kind(run.kind, px), run.text, x + total)
        end
    else
        total = paint(font_lookup(text, px), text, x)
    end
    return total
end

-- ================================================================ UI
act = {}

pcall(function() ui.sidebar("网易云音乐", "globe") end)
tab = ui.tab("网易云")

-- 控件联动显示：有的构建没有 depends，出错就忽略（控件照常显示）
local function dep(el, other, val)
    pcall(function() el:depends(other, val) end)
end

-- ── 布局：搜索 + 播放 + 歌单合并成一组，从上到下就是使用顺序 ──────────────
g_main  = tab:group("搜索 / 歌单")
g_lrc   = tab:group("歌词")
g_world = tab:group("世界歌词")
g_info  = tab:group("状态")

-- ① 搜索
kw      = g_main.text("关键词或歌曲ID", "")
res_box = g_main.listbox("结果", { "(搜一下)" }, 7)
g_main.button("搜索", function() if act.search_box then act.search_box() end end)
res_box:callback(function() if act.pick_search then act.pick_search() end end)

-- ② 播放控制（显示"将播放"的是哪一边，避免点错）
sel_lbl = g_main.label("将播放：搜索结果（先搜索）")
g_main.button("播放选中", function() if act.play_selected then act.play_selected() end end)
g_main.button("暂停 / 继续", function() if act.toggle then act.toggle() end end)
g_main.button("停止", function() if act.stop then act.stop() end end)
vol_sl   = g_main.slider_int("音乐音量 (0-100)", 0, 100, 70)
time_lbl = g_main.label("00:00 / 00:00")
-- 回调参数在不同构建里可能是 (值) / (元素) / ()，所以拿不到数字就自己读元素
vol_sl:callback(function(v)
    local n = tonumber(v)
    if not n then
        pcall(function() n = tonumber(vol_sl:get()) end)
    end
    if n and act.vol then act.vol(n) end
end)

-- ③ 歌单
uid_input = g_main.text("UID", "")
pl_box    = g_main.listbox("歌单", { "(先拉取)" }, 6)
track_box = g_main.listbox("曲目", { "(先载入)" }, 8)
track_box:callback(function() if act.pick_track then act.pick_track() end end)
g_main.button("拉取歌单", function() if act.uid_fetch then act.uid_fetch() end end)
g_main.button("载入曲目", function() if act.uid_load then act.uid_load() end end)
g_main.button("整单播放", function() if act.track_play_all then act.track_play_all() end end)
g_main.button("收藏当前", function() if act.loc_add then act.loc_add() end end)
auto_next  = g_main.checkbox("自动下一首", true)
shuffle_on = g_main.checkbox("随机播放", false)
repeat_one = g_main.checkbox("单曲循环", false)
hk_toggle  = g_main.keybind("播放暂停键", 0)     -- 未设置
hk_prev    = g_main.keybind("上一首键", 0)
hk_next    = g_main.keybind("下一首键", 0)

-- ── 歌词 ─────────────────────────────────────────────────────────────────
lyr_on     = g_lrc.checkbox("屏幕中间大歌词", false)
size_items = { "16", "20", "24", "28", "32", "36", "40", "44", "48", "56" }
size_box   = g_lrc.combo("大歌词字号", size_items, 4)
px_sl      = g_lrc.slider_int("大歌词水平", 0, 100, 50)
py_sl      = g_lrc.slider_int("大歌词垂直", 10, 98, 82)
col_base     = g_lrc.color("歌词·文字色", color(255, 255, 255, 240))
col_hi       = g_lrc.color("高亮色", color(120, 220, 255, 255))
lyr_glow_on  = g_lrc.checkbox("歌词·发光", true)
lyr_glow_al  = g_lrc.slider_int("歌词·发光强度", 0, 255, 90)
lyr_glow_sp  = g_lrc.slider_float("歌词·发光扩散", 1, 10, 3)
lyr_glow_fol = g_lrc.checkbox("发光跟随文字色", true)
lyr_glow_col = g_lrc.color("发光色", color(120, 200, 255, 255))
lyr_off      = g_lrc.slider_int("偏移(ms)", -3000, 3000, 0)
kara_on      = g_lrc.checkbox("逐字高亮", true)
kr_fallback_cb     = g_lrc.checkbox("韩文缺字形时转罗马音", true)
dep(lyr_glow_al, lyr_glow_on, true)
dep(lyr_glow_sp, lyr_glow_on, true)
dep(lyr_glow_fol, lyr_glow_on, true)
dep(lyr_glow_col, lyr_glow_on, true)
dep(size_box, lyr_on, true)
dep(px_sl, lyr_on, true)
dep(py_sl, lyr_on, true)


-- ── 世界歌词（钉在空间某点，走动/转身时按透视移动）─────────────────────────
wl_on       = g_world.checkbox("启用世界歌词", false)
wl_screen   = g_world.checkbox("屏幕固定(不随视角移动)", false)
wl_follow   = g_world.checkbox("每句歌词随机换位", false)
wl_bounce   = g_world.checkbox("逐字出场（唱到哪字出哪字）", true)
wl_beat_on  = g_world.checkbox("跟随节拍跳动", false)
wl_bpm      = g_world.slider_int("节拍(BPM)", 60, 200, 110)
wl_bpm_auto = g_world.checkbox("自动测 BPM", false)
pcall(function()
    wl_bpm_auto:callback(function()
        pcall(function() wl_bpm:inactive(wl_bpm_auto:get() == true, "自动测 BPM 已开启，手动节拍失效") end)
    end)
end)
bpm_lbl     = g_world.label("当前 BPM：110（手动）")
wl_beat_amp = g_world.slider_int("跳动幅度(px)", 2, 40, 8)
wl_beat_scale = g_world.slider_int("节拍放大(%)", 0, 60, 18)
wl_beat_dur   = g_world.slider_int("跳动时长(ms)", 80, 600, 260)

wl_dist     = g_world.slider_int("距离", 100, 1200, 320)
wl_side     = g_world.slider_int("左右偏移", -400, 400, 0)
wl_height   = g_world.slider_int("世界·高度", -150, 150, 0)
wl_size     = g_world.slider_int("字号", 8, 64, 22)
wl_col_text = g_world.color("字体颜色", color(255, 255, 255, 255))
wl_glow_on  = g_world.checkbox("世界·发光", true)
wl_glow_al  = g_world.slider_int("世界·发光强度", 0, 255, 90)
wl_glow_sp  = g_world.slider_float("世界·发光扩散", 1, 10, 3)
wl_col_glow = g_world.color("发光颜色", color(120, 200, 255, 255))
wl_fade_in  = g_world.slider_int("淡入时间(ms)", 100, 3000, 550)
wl_fade_out = g_world.slider_int("淡出时间(ms)", 100, 3000, 650)
g_world.button("钉在面前（立即重算锚点）", function() if act.anchor_here then act.anchor_here() end end)
g_world.button("清除锚点", function() if act.anchor_clear then act.anchor_clear() end end)

dep(wl_bounce, wl_on, true)

dep(wl_dist, wl_on, true)
dep(wl_side, wl_on, true)
dep(wl_height, wl_on, true)
dep(wl_size, wl_on, true)
dep(wl_col_text, wl_on, true)
dep(wl_glow_al, wl_on, true)
dep(wl_glow_sp, wl_on, true)
dep(wl_col_glow, wl_on, true)
dep(wl_fade_in, wl_on, true)
dep(wl_fade_out, wl_on, true)
dep(wl_screen, wl_on, true)
dep(wl_follow, wl_on, true)

-- ── 状态 ─────────────────────────────────────────────────────────────────
-- ── Allow Insecure（联网 / 文件 / ffi 播放的总开关）──────────────────────────
-- 脚本在加载时探测 ffi/http/file/memory，所以勾选后要写配置键 lua.allow_insecure
-- 并重载脚本，这些全局表才会真的注入。
local insecure_ok, insecure_cur = pcall(function()
    if config == nil then return nil end
    return config.get("lua.allow_insecure")
end)

if insecure_cur == nil then
    pcall(function()
        if client and type(client.insecure) == "function" then
            insecure_cur = client.insecure()
        end
    end)
end

local insecure_init = (insecure_cur == true)
insecure_chk = g_info.checkbox("Allow Insecure（允许不安全模式）", insecure_init)

insecure_chk:callback(function(v)
    local on = v
    if type(on) ~= "boolean" then
        pcall(function() on = (insecure_chk:get() == true) end)
    end
    if config ~= nil then
        pcall(function()
            config.set("lua.allow_insecure", on)
            -- 手动关掉就记一笔，避免下次加载又被自动打开
            config.set("lua.nlc_insecure_optout", (on == false))
        end)
    end
    dbg("Allow Insecure -> " .. tostring(on))

    if on then
        notify("已开启 Allow Insecure，正在重载脚本以载入 ffi/http/file…")
        pcall(function()
            if type(client.delay) == "function" then
                client.delay(0.6, function() pcall(function() client.reload() end) end)
            elseif type(client.reload) == "function" then
                client.reload()
            end
        end)
    else
        notify("已关闭 Allow Insecure（联网 / 播放不可用，重载后生效）")
    end
end)

g_info.label("本脚本必须开启 Allow Insecure：联网搜索 / 读写 Cookie / DirectShow 播放")
g_info.label(string.format("当前子系统：ffi=%s  http=%s  file=%s  mem=%s",
        tostring(HAS_FFI), tostring(HAS_HTTP), tostring(HAS_FILE), tostring(HAS_MEM)))

g_info.button("应用并立即重载脚本", function()
    if config ~= nil then
        pcall(function()
            config.set("lua.allow_insecure", true)
            config.set("lua.nlc_insecure_optout", false)
        end)
    end
    pcall(function() insecure_chk:set(true) end)
    pcall(function() client.reload() end)
end)

info_lbl = g_info.label("初始化…")
g_info.label("QQ群 774802658")
cookie_lbl = g_info.label(cookie ~= "" and ("Cookie: 已加载 " .. #cookie .. " 字符")
        or "Cookie: 未加载（VIP 歌必需）")
g_info.button("重新读取 cookie.txt", function() if act.reload_cookie then act.reload_cookie() end end)
g_info.button("从剪贴板导入 Cookie", function() if act.cookie_clip then act.cookie_clip() end end)
g_info.button("韩文字体自检（日志）", function() if act.font_check then act.font_check() end end)
g_info.button("自检（网络 / 解码）", function() if act.selftest then act.selftest() end end)
g_info.label("Cookie 存到 data\\music\\cookie.txt")
dbg("boot: UI 建立完成")

-- ================================================================ 状态
results, cloud_tracks = {}, {}
cur, lyrics = nil, {}
pos_ms, len_ms = 0, 0
playing, paused = false, false
backend = "none"
start_t = 0
last_seek_t = 0
local_pl = "我的收藏"
pos_ok, pos_bad = true, 0
pending_vol = nil
last_list = "search"   -- 最后一次操作的列表：search / track
vol_retry = 0
vol_user_set = false   -- 用户是否真的动过音量滑条（没动过就别用 0 去静音）
hud = { tex = nil, tex_for = nil, angle = 0 }
drag = { on = false, ox = 0, oy = 0 }
world_anchor = nil
world_anchor_line = nil
world_anchor_song = nil
world_transition = nil
world_fade_start = 0
world_pending_line = nil
world_pending_song = nil
world_dir_x, world_dir_y = nil, nil
beat_bpm, bpm_shown = 0, -1     -- 自动测速结果（滑动平均）
beat_phase, beat_last, bpm_line = 0, -1, -1   -- 连续节拍相位（BPM 变了也不会跳拍）
beat_bpm_now = 110
world_hidden_since = nil
world_repin_done = false




-- ================================================================ 工具
local function fmt(ms)
    ms = math.max(0, math.floor(ms or 0))
    return string.format("%d:%02d", math.floor(ms / 60000), math.floor(ms % 60000 / 1000))
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function url_encode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c)
        return string.format("%%02X", string.byte(c))
    end))
end

-- URL 形态自适应：不同构建的 http 对 %XX 处理不同（原样发 / 解码一次 / 再编码一次），
-- 搜索和详情都按「编码式」「原始式」各试一遍，记住能用的那种。
local kr_fallback_cb     -- 前向声明：UI 里创建
url_style = 0        -- 0=未测, 1=百分号编码, 2=原始（空格转 +）
local ne                   -- 前向声明：http_json 之后才定义

local function enc_raw(s)
    return (tostring(s):gsub(" ", "+"))
end

local function url_encode_style(s, style)
    if style == 2 then return enc_raw(s) end
    return url_encode(s)
end

-- 依次尝试几种 URL 形态；accept(data) 返回 true,value 表示这种形态可用
local function try_styles(build, accept, done)
    local order
    -- 优先用上次成功的那种，但仍然保留另一种做单次兜底（不同接口可能脾气不一样）
    if url_style == 1 then order = { 1, 2 }
    elseif url_style == 2 then order = { 2, 1 }
    else order = { 1, 2 } end

    local i, errs = 1, {}
    local function step()
        if i > #order then
            done(nil, table.concat(errs, " / "))
            return
        end
        local st = order[i]
        i = i + 1
        ne(build(st), function(d, err)
            local okv, val, why = accept(d)
            if okv then
                if url_style ~= st then
                    url_style = st
                    dbg("URL 形态=" .. (st == 1 and "百分号编码" or "原始"))
                end
                done(val, nil, st)
            else
                errs[#errs + 1] = string.format("%s:%s",
                        st == 1 and "编码" or "原始", tostring(err or why))
                step()
            end
        end)
    end
    step()
end

local function now_s()
    return raw_time()
end

-- 登录用 Cookie：浏览器登录 music.163.com 后把 Cookie 存到 data\music\cookie.txt
local function load_cookie()
    if not HAS_FILE then cookie = "" return 0 end
    local ok, t = pcall(file.read, COOKIE_FILE)
    if ok and type(t) == "string" and #t > 8 then
        cookie = string.gsub(t, "[\r\n]+", " ")
        cookie = string.gsub(cookie, "^%s+", "")
        cookie = string.gsub(cookie, "%s+$", "")
    else
        cookie = ""
    end
    dbg("cookie 长度=" .. #cookie)
    return #cookie
end
load_cookie()

-- 请求头策略（硬性约束，写在代码里而不是靠纪律）：
--   * Cookie 只在 URL 精确匹配 https://music.163.com/ 时附加
--   * 任何第三方域名（Meting 代理、CDN）一律只带 User-Agent
local function headers_for(url)
    local h = { ["User-Agent"] = "Mozilla/5.0" }
    if type(url) == "string" and string.find(url, "^https://music%.163%.com/") then
        h["Referer"] = "https://music.163.com/"
        if cookie ~= "" then h["Cookie"] = cookie end
    end
    return h
end

local function proxy_headers()
    return { ["User-Agent"] = "Mozilla/5.0" }
end

-- 兼容不同实现的响应字段名（status/code、body/text/data）
local function res_status(res)
    return tonumber(res and (res.status or res.code)) or 0
end

local function res_body(res)
    local b = res and (res.body or res.text or res.data)
    if type(b) == "string" then return b end
    return ""
end

-- http.get 的签名在不同客户端上不完全一样：先按 (url, opts, cb)，抛错再退回 (url, cb)
local function http_get(url, opts, cb)
    if not HAS_HTTP then return false, "http 不可用（insecure 模式没开）" end
    local ok, a, b = pcall(http.get, url, opts, cb)
    if ok then
        if a == false then return false, tostring(b) end
        return true
    end
    local ok2, a2, b2 = pcall(http.get, url, cb)
    if ok2 then
        if a2 == false then return false, tostring(b2) end
        return true
    end
    return false, tostring(b)
end

local function http_json(url, headers, cb)
    if not HAS_HTTP then
        cb(nil, "http 不可用（insecure 模式没开）")
        return
    end
    local done = false
    local function finish(d, err)
        if done then return end
        done = true
        pcall(cb, d, err)
    end

    local started, err = http_get(url, { headers = headers or {}, timeout = 6 }, function(res)
        local status = res_status(res)
        local body = res_body(res)
        if status < 200 or status >= 300 then
            dbg("HTTP " .. tostring(status) .. " 长度 " .. #body .. " " .. tostring(url):sub(1, 90))
            finish(nil, string.format("HTTP %s（返回 %d 字节）", tostring(status), #body))
            return
        end
        local okj, data = pcall(json.decode, body)
        if not okj or data == nil then
            dbg("JSON 解析失败 " .. body:sub(1, 120))
            finish(nil, string.format("JSON 解析失败（%d 字节，开头: %s）",
                    #body, body:sub(1, 40):gsub("[\r\n]", " ")))
            return
        end
        finish(data)
    end)

    if not started then
        dbg("http.get 启动失败 " .. tostring(err) .. " " .. tostring(url):sub(1, 80))
        finish(nil, "请求发不出去：" .. tostring(err))
    end
end

-- 前向声明：下面 ne_search 要用
local artists_of

ne = function(path, cb)
    http_json(NE_BASE .. path, headers_for(NE_BASE .. path), cb)
end

-- 搜索：拼音 / 中文 / ID 都走这里（拼音与中文由服务端处理，URL 形态自适应）
local function ne_search(word, cb)
    local function accept(d)
        local songs = d and d.result and d.result.songs
        if type(songs) == "table" and #songs > 0 then return true, songs end
        return false, "空结果"
    end

    try_styles(function(st)
        return "/api/cloudsearch/pc?s=" .. url_encode_style(word, st) .. "&type=1&limit=30&offset=0"
    end, accept, function(songs, err)
        if not songs then
            cb(nil, err or "没有结果")
            return
        end
        local out = {}
        for i = 1, #songs do
            local s = songs[i]
            out[#out + 1] = {
                id = s.id, name = s.name or "?",
                artist = artists_of(s.ar),
                dur_ms = tonumber(s.dt) or 0,
                fee = s.fee,
                pic_url = s.al and s.al.picUrl or nil,
            }
        end
        dbg("搜索 " .. tostring(word) .. " -> " .. #out .. " 首")
        cb(out)
    end)
end

-- 批量详情（song/detail 一次可给几十上百个 id）
local function ne_details(ids, cb)
    local list = "[" .. table.concat(ids, ",") .. "]"

    local function accept(d)
        local songs = d and d.songs
        if type(songs) == "table" and #songs > 0 then return true, songs end
        return false, "空结果"
    end

    try_styles(function(st)
        return "/api/song/detail/?ids=" .. url_encode_style(list, st)
    end, accept, function(songs, err)
        if not songs then
            cb(nil, err or "详情没有返回")
            return
        end
        cb(songs)
    end)
end

artists_of = function(t)
    if type(t) ~= "table" or #t == 0 then return "未知" end
    local out = {}
    for i = 1, #t do
        if type(t[i]) == "table" then out[#out + 1] = tostring(t[i].name or "?")
        else out[#out + 1] = tostring(t[i]) end
    end
    return table.concat(out, "/")
end

-- 第三方代理（Meting 之类）：只有 UA，没有 Cookie / Referer / 任何账号信息
-- 注：v10 起不再自己解析 302，直接把 URL 交给 DirectShow 的 File Source 跟随，
--     避免把整首 mp3 拉进 Lua 字符串。顺序很重要：qijieya 给完整曲目，
--     injahow 对 VIP 只给 30 秒试听。
PROXIES = {
    { name = "qijieya", base = "https://api.qijieya.cn/meting/?type=url&id=" },
    { name = "injahow", base = "https://api.injahow.cn/meting/?type=url&id=" },
    { name = "meting-hk", base = "https://music-api.heheda.top/meting/?type=url&id=" },
}

NSTEP = 2 + #PROXIES + 1

-- 逐个音源解析：1/2 官方接口拿 JSON url，其余直接给可 302 的 URL
local function resolve_step(id, i, cb)
    if i > NSTEP then cb(nil) return end

    if i == 1 or i == 2 then
        local br = (i == 1) and 320000 or 128000
        local order = (url_style == 2) and { 2, 1 } or { 1, 2 }
        local k = 1
        local function attempt()
            local st = order[k]
            k = k + 1
            local q = url_encode_style("[" .. tostring(id) .. "]", st)
            ne("/api/song/enhance/player/url?ids=" .. q .. "&br=" .. br, function(d, err)
                local row = d and d.data and d.data[1]
                local u = row and row.url
                if type(u) == "string" and u ~= "" then
                    url_style = st
                    dbg(string.format("源 官方%d ok（形态 %d）", br / 1000, st))
                    cb(u, "官方" .. (br / 1000) .. "k")
                    return
                end
                dbg(string.format("源 官方%d 无 code=%s err=%s 形态=%d",
                        br / 1000, tostring(row and row.code), tostring(err), st))
                if k <= #order then attempt() else cb(nil) end
            end)
        end
        attempt()
        return
    end

    if i < NSTEP then
        local p = PROXIES[i - 2]
        dbg("源 " .. p.name .. " 直连（302 交给 DS）")
        cb(p.base .. tostring(id), p.name)
        return
    end

    dbg("源 outer 直连（302 交给 DS）")
    cb(NE_BASE .. "/song/media/outer/url?id=" .. tostring(id) .. ".mp3", "outer")
end

local function parse_lrc(text)
    local out = {}
    for line in string.gmatch(text, "[^\r\n]+") do
        local stamps = {}
        for mm, ss, frac in string.gmatch(line, "%[(%d+):(%d+)%.(%d+)%]") do
            stamps[#stamps + 1] = tonumber(mm) * 60 + tonumber(ss) + tonumber(frac) / (10 ^ #frac)
        end
        for mm, ss in string.gmatch(line, "%[(%d+):(%d+)%]") do
            stamps[#stamps + 1] = tonumber(mm) * 60 + tonumber(ss)
        end
        local body = string.gsub(line, "%[%d+:%d+%.?%d*%]", "")
        body = string.gsub(body, "^%s+", "")
        body = string.gsub(body, "%s+$", "")
        if #stamps > 0 and body ~= "" then
            for i = 1, #stamps do out[#out + 1] = { t = stamps[i], text = body } end
        end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- 列表控件的方法名各构建略有差异：items / set_items / setItems
local function list_items(el, list)
    if not el then return false end
    if type(el.items) == "function" then
        local ok = pcall(function() el:items(list) end)
        if ok then return true end
    end
    for _, n in ipairs({ "set_items", "setItems", "setlist", "update" }) do
        local f = el[n]
        if type(f) == "function" then
            local ok = pcall(function() f(el, list) end)
            if ok then return true end
        end
    end
    return false
end

local function set_info(text)
    pcall(function() info_lbl:set(tostring(text)) end)
end

local function set_cookie_label()    pcall(function()
        cookie_lbl:set(cookie ~= "" and ("Cookie: 已加载 " .. #cookie .. " 字符")
                or "Cookie: 未加载（VIP 歌必需）")
    end)
end

-- ================================================================ 时间轴
local function now_ms() return (now_s() - start_t) * 1000 end

local function timeline_ms()
    if paused then return pos_ms end
    return now_ms()
end

local function lyr_offset()
    local v = 0
    pcall(function() v = lyr_off:get() or 0 end)
    return v
end

local function cur_line_index()
    local t = (timeline_ms() + lyr_offset()) / 1000
    local idx = 0
    for i = 1, #lyrics do
        if lyrics[i].t <= t then idx = i else break end
    end
    return idx, t
end

-- ================================================================ 封面
-- Neverwin: render.load_image 接收图片字节（PNG/JPG/SVG），
-- render.load_image_from_file 接收路径。下载后先内存直解，再落盘重试。
cover_style = nil
cover_tried = {}       -- 每首歌只尝试下载一次

-- 这个构建的图片根目录是 scripts\images，子目录能不能扫不确定，所以
-- 子目录 / 根目录、jpg / png 都试；load_image 的两种调用形式也都试。
local function image_candidates(id)
    return {
        "music/covers/" .. id .. ".jpg",
        "C:/neverwin/scripts/music/covers/" .. id .. ".jpg",
        "C:\\neverwin\\scripts\\music\\covers\\" .. id .. ".jpg",
        "netease/" .. id .. ".jpg",
        id .. ".jpg",
        "images/" .. id .. ".jpg",
        "netease\\" .. id .. ".jpg",
        "C:/neverwin/scripts/images/netease/" .. id .. ".jpg",
        "C:\\neverwin\\scripts\\images\\netease\\" .. id .. ".jpg",
        "./" .. id .. ".jpg",
        "netease/" .. id .. ".png",
        id .. ".png",
        "netease/" .. id,
        id,
    }
end

local function v2_size(w, h)
    if type(vector2) == "function" then return vector2(w, h) end
    if type(vector2) == "table" and type(vector2.new) == "function" then return vector2.new(w, h) end
    return nil
end

-- 把图片字节解码成纹理（主路径，不依赖 scripts\images 目录映射）
-- 注意：image.size 在加载后是 0x0，画完第一帧才有真实尺寸，
-- 因此这里不能用尺寸判断成败，只能用返回值是否为 nil 判断。
local function make_texture(data)
    local sz = v2_size(192, 192)
    if sz then
        local ok, t = pcall(render.load_image, data, sz)
        if ok and t then return t end
    end
    local ok, t = pcall(render.load_image, data)
    if ok and t then return t end
    local ok2, t2 = pcall(render.load_image, data, 192, 192)
    if ok2 and t2 then return t2 end
    return nil
end

-- BMP（网易云图片服务支持 type=bmp）→ RGBA → 纹理。
-- 该环境没有 io、file 与 render 目录不同源、也不支持 JPEG，
-- 但 render.texture 可以直接吃原始 RGBA，所以用未压缩 BMP 绕开整条文件链路。
local function le16(s, i)
    return (s:byte(i) or 0) + (s:byte(i + 1) or 0) * 256
end

local function le32(s, i)
    local b1, b2, b3, b4 = s:byte(i, i + 3)
    return (b1 or 0) + (b2 or 0) * 256 + (b3 or 0) * 65536 + (b4 or 0) * 16777216
end

local function bmp_to_texture(data)
    if not data or #data < 54 or data:sub(1, 2) ~= "BM" then return nil end
    local off = le32(data, 11)
    local w = le32(data, 19)
    local h = le32(data, 23)
    local bpp = le16(data, 29)
    if (bpp ~= 24 and bpp ~= 32) or w <= 0 or h == 0 then return nil end
    local bottom_up = h > 0
    if h < 0 then h = -h end
    local bytes_pp = bpp / 8
    local stride = math.floor((w * bytes_pp + 3) / 4) * 4
    if off + stride * h > #data + 1 then return nil end
    local parts = {}
    for y = 0, h - 1 do
        local src_row = bottom_up and (h - 1 - y) or y
        local base = off + src_row * stride + 1
        for x = 0, w - 1 do
            local p = base + x * bytes_pp
            local b, g, r, a = data:byte(p, p + bytes_pp - 1)
            parts[#parts + 1] = string.char(r or 0, g or 0, b or 0, a or 255)
        end
    end
    local ok, tex = pcall(render.texture, table.concat(parts), w, h)
    if ok and tex then return tex end
    return nil
end

local function load_file_image(p)
    if type(render.load_image_from_file) == "function" then
        local ok, t = pcall(render.load_image_from_file, p)
        if ok and t then return t end
    end
    -- 本构建没有 load_image_from_file，只能靠 load_image(路径, w, h)。
    -- 先确认文件存在，避免把不存在的路径当数据解码出 0x0 空纹理冒充成功。
    if type(render.load_image) == "function" then
        local exists = true
        if HAS_FILE then
            exists = false
            pcall(function() exists = file.exists(p) == true end)
        end
        if exists then
            local ok, t = pcall(render.load_image, p, 192, 192)
            if ok and t then return t end
        end
    end
    if HAS_FILE then
        local ok, bytes = pcall(file.read, p)
        if ok and type(bytes) == "string" and #bytes > 2 then
            return make_texture(bytes)
        end
    end
    return nil
end

local function try_load_image(cands)
    for _, p in ipairs(cands) do
        local t = load_file_image(p)
        if t then return t, p, "file" end
    end
    return nil
end

local function load_cover(song)
    if not song or not song.pic_url or song.pic_url == "" then
        hud.tex, hud.tex_for = nil, nil
        return
    end
    -- 只有真的拿到纹理才认为这首歌处理过，否则下次还能重试
    if hud.tex_for == song.pic_url and hud.tex then return end
    if hud.tex_for ~= song.pic_url then
        hud.tex = nil            -- 换歌先清掉上一首的封面，否则盘心一直显示旧图
        hud.tex_for = song.pic_url
    end

    local sid = tostring(song.id)
    local cands = image_candidates(sid)
    print(string.format("[cover] 进入加载 id=%s pic=%s http=%s", sid, tostring(song.pic_url), tostring(HAS_HTTP)))

    local tex, which, form = try_load_image(cands)
    if tex then
        if hud.tex_for == song.pic_url then hud.tex = tex end
        cover_style = "images"
        dbg("封面=images（" .. tostring(which) .. " / " .. tostring(form) .. "）")
        return
    end

    if not HAS_HTTP then return end
    if cover_tried[sid] then
        dbg("封面：" .. sid .. " 本地没有图，已尝试过下载")
        return
    end
    cover_tried[sid] = true

    local url = song.pic_url
    if url:sub(1, 2) == "//" then url = "https:" .. url end
    url = url:gsub("^http://", "https://")
    -- 让网易云 CDN 直接输出未压缩 BMP：本环境没有 io、JPEG 解码器，
    -- BMP 可以在脚本内直接转 RGBA 交给 render.texture
    url = url .. (url:find("?", 1, true) and "&" or "?") .. "imageView&thumbnail=192y192&type=bmp"

    local started, herr = http_get(url, { headers = headers_for(url), timeout = 8 }, function(res)
        local st = res_status(res)
        local body = res_body(res)
        if type(res) == "string" then body, st = res, 200 end
        print(string.format("[cover] 响应 type=%s status=%s len=%d", type(res), tostring(st), #body))
        if st ~= 200 or #body < 128 then
            dbg("封面下载失败 status=" .. tostring(st) .. " 长度=" .. #body)
            return
        end

        if hud.tex_for ~= song.pic_url then return end

        -- 首选：BMP → RGBA → render.texture，完全绕开文件与图片解码器
        local tex_bmp = bmp_to_texture(body)
        print("[cover] BMP 解码=" .. tostring(tex_bmp ~= nil) .. " len=" .. #body)
        if tex_bmp then
            hud.tex = tex_bmp
            cover_style = "bmp"
            return
        end

        -- 先试内存解码；本平台 load_image 对原始字节支持不佳，失败属正常
        local tex_mem = make_texture(body)
        print("[cover] 内存解码=" .. tostring(tex_mem ~= nil))
        if tex_mem then
            hud.tex = tex_mem
            cover_style = "memory"
            if HAS_FILE then pcall(file.write, MUSIC .. "/covers/" .. sid .. ".jpg", body) end
            return
        end

        -- 写盘 + load_image(路径, 192, 192)：本构建唯一可用的文件加载方式。
        -- file 的写入基准与 load_image 的读取基准可能不同，所以把常见相对位置都写一份再逐一加载。
        if HAS_FILE then
            local fname = "cover_" .. sid .. ".png"
            for _, wpath in ipairs({ fname, "images/" .. fname, "../images/" .. fname, "scripts/images/" .. fname }) do
                pcall(file.write, wpath, body)
            end
            -- 用 io 库把文件从 data 目录复制到 images 目录（两个 API 的根目录不同）
            if type(io) == "table" and io.open then
                local okio, msg = pcall(function()
                    local src = io.open("C:/neverwin/scripts/data/" .. fname, "rb")
                    if not src then return "src nil" end
                    local data_all = src:read("*a")
                    src:close()
                    local dst = io.open("C:/neverwin/scripts/images/" .. fname, "wb")
                    if not dst then return "dst nil" end
                    dst:write(data_all)
                    dst:close()
                    return "ok"
                end)
                print("[cover] io 复制=" .. tostring(okio) .. " " .. tostring(msg))
            else
                print("[cover] io 不可用 type(io)=" .. type(io))
            end
            -- file 的基准是 scripts/data，render 的基准是 scripts/images，且 ../ 被拦截，
            -- 所以只能尝试用绝对路径等方式把 data 下的文件读出来
            local loads = {
                fname,
                "images/" .. fname,
                "data/" .. fname,
                "../data/" .. fname,
                "C:/neverwin/scripts/data/" .. fname,
                "C:\\neverwin\\scripts\\data\\" .. fname,
            }
            for _, lpath in ipairs(loads) do
                local ok, tt = pcall(render.load_image, lpath, 192, 192)
                print("[cover] 加载 " .. lpath .. " ok=" .. tostring(ok) .. " v=" .. tostring(tt))
                if ok and tt and hud.tex_for == song.pic_url then
                    hud.tex = tt
                    cover_style = "file"
                    print("[cover] 文件加载成功 " .. lpath)
                    return
                end
            end
        end

        cover_style = "none"
        print("[cover] 封面不可用")
    end)
    if started == false then print("[cover] 封面请求未发出：" .. tostring(herr)) end
end

-- ================================================================ 播放
-- 统计有多少行是韩文，方便排查“是没取到歌词还是字体画不出”
local function count_hangul_lines(list)
    local n = 0
    for i = 1, #list do
        local h = scan_script(list[i].text)
        if h then n = n + 1 end
    end
    return n
end

local function log_lyric_stats(tag)
    dbg(string.format("[歌词] %s 行数=%d 韩文行=%d", tostring(tag),
            #lyrics, count_hangul_lines(lyrics)))
end

local function load_lyric(song)
    lyrics = {}
    if not song then return end
    local cache = MUSIC .. "/" .. tostring(song.id) .. ".lrc"
    local text = nil
    if HAS_FILE then
        local okr, t = pcall(file.read, cache)
        if okr then text = t end
    end
    if type(text) == "string" then
        lyrics = parse_lrc(text)
        log_lyric_stats("缓存 " .. tostring(song.id))
        if count_hangul_lines(lyrics) > 0 then ensure_kr_fonts() end
        return
    end
    ne("/api/song/lyric?id=" .. tostring(song.id) .. "&lv=1&kv=1&tv=-1", function(d)
        local l = d and d.lrc and d.lrc.lyric
        if type(l) == "string" and l ~= "" then
            lyrics = parse_lrc(l)
            if HAS_FILE then pcall(file.write, cache, l) end
            log_lyric_stats("接口 " .. tostring(song.id))
            if count_hangul_lines(lyrics) > 0 then ensure_kr_fonts() end
        else
            dbg("[歌词] 接口没有返回歌词 id=" .. tostring(song.id))
        end
    end)
end

-- 逐个音源尝试；试听片段（明显短于歌曲时长）会被判掉换下一个源
local function try_play(song, i)
    if i > NSTEP then
        backend = "none"
        playing = false
        set_info("所有音源都失败：" .. tostring(song.name))
        say("所有音源都失败：" .. tostring(song.name))
        notify("所有音源都失败：" .. tostring(song.name))
        return
    end

    resolve_step(song.id, i, function(url, kind)
        if not url then
            try_play(song, i + 1)
            return
        end

        -- 音频流也优先走 https：直接把 http:// 换成 https://，开不了再回退
        local sec_url = url
        if string.sub(url, 1, 7) == "http://" then
            sec_url = "https://" .. string.sub(url, 8)
        end

        local ok, err = ds_play(sec_url)
        if not ok and sec_url ~= url then
            dbg("https 打不开，回退 http 重试")
            ok, err = ds_play(url)
        end
        if not ok then
            dbg("源 " .. tostring(kind) .. " 打不开: " .. tostring(err))
            try_play(song, i + 1)
            return
        end

        if song.dur_ms and song.dur_ms > 90000 and ds.dur_ms > 0
                and ds.dur_ms < song.dur_ms * 0.7 then
            dbg(string.format("源 %s 只有 %.0fs（歌曲 %.0fs），判定试听，换源",
                    tostring(kind), ds.dur_ms / 1000, song.dur_ms / 1000))
            ds_stop()
            try_play(song, i + 1)
            return
        end

        backend = "dshow"
        if ds.dur_ms > 0 then len_ms = ds.dur_ms elseif song.dur_ms then len_ms = song.dur_ms end
        -- 没动过滑条就用 70，避免滑条读到 0 把声音直接静音
        local v = 70
        if vol_user_set then
            local got = nil
            pcall(function() got = tonumber(vol_sl:get()) end)
            if got then v = got end
        end
        pending_vol = clamp(v, 0, 100)
        set_info("播放(" .. tostring(kind) .. ")：" .. tostring(song.name))
        say("播放源自：" .. tostring(kind))
    end)
end

local function play_song(song)
    if not song then return end
    cur = song
    pos_ms, len_ms, paused, pos_ok, pos_bad = 0, 0, false, true, 0
    playing = true
    start_t = now_s()
    set_info("解析中…")
    dbg("play_song " .. tostring(song.id) .. " " .. tostring(song.name))
    load_lyric(song)
    load_cover(song)
    dbg(string.format("切歌: %s %s | 封面=%s | 歌词=%d 行",
            tostring(song.id), tostring(song.name),
            (song.pic_url and song.pic_url ~= "") and "有" or "无", #lyrics))
    try_play(song, 1)
end

-- ================================================================ 动作
local function fail(where, err)
    local text = string.format("%s：%s", tostring(where), tostring(err))
    dbg(text)
    set_info(text)
    say(text)
    notify(text)
end

act.search_box = function()
    local s = tostring(kw:get() or "")
    local t = string.gsub(s, "^%s+", "")
    t = string.gsub(t, "%s+$", "")
    if t == "" then say("先输入关键词或 ID") return end
    if not HAS_HTTP then
        fail("搜索", "http 不可用，请先开启 insecure 模式")
        return
    end

    set_info("搜索中：" .. t)

    if string.match(t, "^%d+$") and #t >= 5 then
        ne_details({ t }, function(songs, err)
            if err then fail("按 ID 取详情失败", err) return end
            local so = songs and songs[1]
            if not so then
                fail("按 ID 取详情", "这个 ID 没有返回")
                return
            end
            local song = {
                id = so.id, name = so.name or "?", artist = artists_of(so.artists),
                dur_ms = tonumber(so.duration) or 0, fee = so.fee,
                pic_url = so.album and so.album.picUrl or nil,
            }
            results = { song }
            if not list_items(res_box, { song.name .. " - " .. song.artist }) then
                dbg("列表写入失败（items/set_items 都不可用）")
            end
            play_song(song)
        end)
        return
    end

    ne_search(t, function(list, err)
        if err then fail("搜索", err) return end
        if type(list) ~= "table" or #list == 0 then
            fail("搜索", "没搜到「" .. t .. "」")
            return
        end
        results = list
        local items = {}
        for i = 1, #list do
            items[i] = list[i].name .. " - " .. list[i].artist
        end
        local wrote = list_items(res_box, items)
        pcall(function() res_box:set(0) end)   -- 自动选中第一条
        if wrote then
            last_list = "search"
            if act.update_sel then act.update_sel() end
            set_info("搜到 " .. #list .. " 首，已选中第 1 首")
            say("搜到 " .. #list .. " 首（已选中第 1 首，按「播放 / 暂停」）")
            notify("搜到 " .. #list .. " 首，已选中第 1 首")
        else
            fail("列表写入失败", "items / set_items 都不可用")
        end
    end)
end

-- 「播放」放到哪一边：看最后操作的是哪个列表（last_list 在状态区声明）
local function sel_index(box, n)
    local i = 0
    pcall(function() i = box:get() or 0 end)
    if i < 0 then i = 0 end
    if i >= n and i > 0 then i = i - 1 end     -- 兼容 1 基实现
    return i
end

act.update_sel = function()
    local text
    if last_list == "track" then
        local ti = sel_index(track_box, #cloud_tracks)
        local tr = cloud_tracks[ti + 1]
        text = tr and string.format("将播放：歌单 #%d %s", ti + 1, tostring(tr.name))
                    or "将播放：歌单（先载入曲目）"
    else
        local ri = sel_index(res_box, #results)
        local s = results[ri + 1]
        text = s and string.format("将播放：搜索 #%d %s", ri + 1, tostring(s.name))
                   or "将播放：搜索结果（先搜索）"
    end
    pcall(function() sel_lbl:set(text) end)
end

act.pick_search = function()
    last_list = "search"
    act.update_sel()
end

act.pick_track = function()
    last_list = "track"
    act.update_sel()
end

-- 只播放选中项（不负责暂停），随时可以从任一列表切歌
act.play_selected = function()
    if last_list == "track" then
        local ti = sel_index(track_box, #cloud_tracks)
        local tr = cloud_tracks[ti + 1]
        if tr then
            dbg("播放歌单曲目 #" .. (ti + 1) .. " " .. tostring(tr.name))
            play_song(tr)
            act.update_sel()
            return
        end
        -- 歌单这边没东西：退回去看搜索
        last_list = "search"
    end

    local ri = sel_index(res_box, #results)
    local s = results[ri + 1]
    if s then
        dbg("播放搜索结果 #" .. (ri + 1) .. " " .. tostring(s.name))
        play_song(s)
        act.update_sel()
        return
    end

    dbg("没有可播的选中项: 结果=" .. #results .. " 曲目=" .. #cloud_tracks ..
        " 来源=" .. tostring(last_list))
    say("先在列表里选一首")
end

-- 暂停 / 继续
act.toggle = function()
    if not playing then
        act.play_selected()
        return
    end
    if paused then
        if backend == "dshow" then ds_run() end
        start_t = now_s() - pos_ms / 1000
        paused = false
    else
        pos_ms = now_ms()
        if backend == "dshow" then ds_pause() end
        paused = true
    end
end

-- 当前"作用列表 + 选中下标 + 对应列表控件"
local function list_state()
    if last_list == "track" then
        return cloud_tracks, sel_index(track_box, #cloud_tracks) + 1, track_box
    end
    return results, sel_index(res_box, #results) + 1, res_box
end

-- 当前正在播放的曲目在列表中的下标（播放后选中项不会自动跟着走，需要用这个）
local function cur_index(list)
    if not cur then return nil end
    for i = 1, #list do
        local s = list[i]
        if s and s == cur then return i end
        if s and s.id ~= nil and cur.id ~= nil and tostring(s.id) == tostring(cur.id) then return i end
    end
    return nil
end

act.next_track = function()
    local list, idx, box = list_state()
    if #list == 0 then return end
    -- 以当前播放曲目为准，避免连续切歌停留在同一首
    idx = cur_index(list) or idx
    local n
    if shuffle_on and shuffle_on:get() and #list > 1 then
        repeat n = math.random(#list) until n ~= idx
    else
        n = idx + 1
        if n > #list then n = 1 end
    end
    pcall(function() box:set(n - 1) end)
    play_song(list[n])
    act.update_sel()
end

act.prev_track = function()
    local list, idx, box = list_state()
    if #list == 0 then return end
    idx = cur_index(list) or idx
    local n = idx - 1
    if n < 1 then n = #list end
    pcall(function() box:set(n - 1) end)
    play_song(list[n])
    act.update_sel()
end
-- 兼容旧名字
act.primary = act.play_selected
local function clear_world_state()
    world_anchor, world_anchor_line, world_anchor_song = nil, nil, nil
    world_transition = nil
    world_pending_line, world_pending_song = nil, nil
    world_hidden_since, world_repin_done = nil, false
end

act.stop = function()
    ds_stop()
    backend = "none"
    playing, paused = false, false
    pos_ms, len_ms = 0, 0
    clear_world_state()
    pcall(function() time_lbl:set("00:00 / 00:00") end)
    set_info("已停止")
end

act.vol = function(v)
    local n = tonumber(v)
    if not n then return end
    vol_user_set = true
    pending_vol = clamp(n, 0, 100)
end

-- ---------------- 视角 / 世界坐标
local function local_pawn()
    local p = nil
    pcall(function() p = entity.local_pawn() end)
    return p
end

-- 不在对局里就不画（音乐照放，只是别把 HUD 糊到菜单上）
local function in_game()
    local v = nil
    local ok = pcall(function() v = engine.in_game() end)
    if not ok or v == nil then return true end     -- 接口缺失时不拦
    return v and true or false
end

local function local_eye()
    local p = local_pawn()
    if not p then return nil end
    local e = nil
    pcall(function() e = p:eye_position() end)
    return e
end

local function view_angles()
    local a = nil
    local ok = pcall(function() a = engine.camera_angles() end)
    if not ok or not a then pcall(function() a = engine.view_angles() end) end
    return a
end

local function world_to_screen(x, y, z)
    local sx, sy = nil, nil
    local ok = pcall(function()
        sx, sy = render.world_to_screen(vector(x, y, z))
    end)
    if ok and sx then return sx, sy end
    return nil
end

-- 把视角压平：只取水平朝向，俯仰角不参与定位。
-- 这样低头看地 / 抬头看天，歌词的水平位置和高度都保持一致。
local function flat_view(va)
    if not va then return nil end
    local fwd, right = nil, nil
    local ok = pcall(function()
        local f, r = va:angle_vectors()
        fwd, right = f, r
    end)
    if not ok or not fwd then
        pcall(function() fwd = va:forward() end)
    end
    if not fwd then return nil end

    local hx, hy = fwd.x, fwd.y
    local hlen = math.sqrt(hx * hx + hy * hy)
    if hlen < 0.08 then
        hx, hy = world_dir_x or 1, world_dir_y or 0
    else
        hx, hy = hx / hlen, hy / hlen
        world_dir_x, world_dir_y = hx, hy
    end

    local rx, ry = 0, 0
    if right then
        local rlen = math.sqrt(right.x * right.x + right.y * right.y)
        if rlen > 0.08 then rx, ry = right.x / rlen, right.y / rlen end
    end

    return hx, hy, rx, ry
end

-- 生成一个世界坐标：水平距离只看朝向，高度 = 眼位 + 高度偏移。
-- 前方有墙时把点收近到墙前；下方有地板时抬到地面上方，永不入地。
local function compute_anchor(eye, va, randomize)
    local hx, hy, rx, ry = flat_view(va)
    if not hx then return nil end

    local want_d = wl_dist:get()
    if want_d < 60 then want_d = 60 end

    local sd = wl_side:get()
    local ht = wl_height:get()
    if randomize then
        sd = sd + (math.random() * 2 - 1) * 120
        ht = ht + (math.random() * 2 - 1) * 55
    end

    local side_limit = want_d * 0.8
    if sd < -side_limit then sd = -side_limit end
    if sd > side_limit then sd = side_limit end

    local function place(d)
        return {
            x = eye.x + hx * d + rx * sd,
            y = eye.y + hy * d + ry * sd,
            z = eye.z + ht,
        }
    end

    -- 不做任何射线检测：直接按理想距离/偏移放置
    return place(want_d)
end

act.anchor_here = function()
    local eye = local_eye()
    if not eye then say("不在游戏里，钉不了") return end
    world_anchor = compute_anchor(eye, view_angles(), false)
    if not world_anchor then say("算不出锚点") return end
    local idx = cur_line_index()
    world_anchor_line = idx
    world_anchor_song = cur and cur.id or nil
    dbg(string.format("世界歌词锚点 x=%.1f y=%.1f z=%.1f d=%d side=%d h=%d",
            world_anchor.x, world_anchor.y, world_anchor.z,
            wl_dist:get(), wl_side:get(), wl_height:get()))
    say(string.format("歌词已钉在面前 %d 单位，左右 %d，高度 %d",
            wl_dist:get(), wl_side:get(), wl_height:get()))
end

act.anchor_clear = function()
    world_anchor = nil
    world_anchor_line = nil
    world_anchor_song = nil
    say("世界歌词锚点已清除")
end

-- 韩文字体自检：把每个候选的加载结果和实测宽度写进 debug.log
act.font_check = function()
    local sample = "안녕하세요"
    dbg("=== 韩文字体自检开始 ===")

    local function probe(name, tbl)
        local n = 0
        for i = 1, #SIZES do if tbl[i] then n = n + 1 end end
        local w = "nil"
        if tbl[4] then
            local ok, v = pcall(function() return render.text_size(sample, "", 24, tbl[4]) end)
            w = ok and tostring(v) or ("err:" .. tostring(v))
        end
        dbg(string.format("  %s: 字号=%d/%d 宽=%s", name, n, #SIZES, tostring(w)))
        return n
    end

    local cjk_n = probe("中文(msyh)", fonts)
    local kr_n = probe("韩文(Malgun)", fonts_kr)
    local uni_n = probe("混排(ArialUnicode)", fonts_uni)
    local ok_kr = kr_ok()
    dbg(string.format("=== 自检结束：中文=%d 韩文=%d 混排=%d 韩文渲染=%s ===",
            cjk_n, kr_n, uni_n, ok_kr and "字形正常" or "缺字形→罗马音"))
    dbg("韩文样例: 안녕하세요 → " .. hangul_roman("안녕하세요"))

    if ok_kr then
        say("韩文字体 OK（字形正常，详见 debug.log）")
    elseif kr_n > 0 then
        say("韩文字体已加载，但字形缺失 → 已自动改用罗马音显示")
    else
        say("韩文字体没加载成功，把 malgun.ttf 放到 scripts\\fonts")
    end
end

-- 自检：一条命令看清卡在哪（insecure / 网络 / 解码 / 列表）
act.selftest = function()
    if not HAS_HTTP then
        fail("自检", "http 不可用 → 菜单里打开 Lua/Allow Insecure 后重载脚本")
        return
    end
    set_info("自检中：请求 cloudsearch…")
    local url = NE_BASE .. "/api/cloudsearch/pc?s=" .. url_encode("test") .. "&type=1&limit=1&offset=0"
    local started, err = http_get(url, { headers = headers_for(url), timeout = 8 }, function(res)
        local st = res_status(res)
        local body = res_body(res)
        local okj, data = pcall(json.decode, body)
        local songs = okj and data and data.result and data.result.songs
        local n = type(songs) == "table" and #songs or -1
        local msg = string.format("自检：status=%s 字节=%d 解码=%s 命中=%d",
                tostring(st), #body, (okj and data ~= nil) and "ok" or "fail", n)
        if st ~= 200 or not okj then
            msg = msg .. " | 开头：" .. body:sub(1, 60):gsub("[\r\n]", " ")
        end
        set_info(msg)
        say(msg)
        dbg(msg)
    end)
    if not started then fail("自检", err) end
end

act.reload_cookie = function()
    local n = load_cookie()
    set_cookie_label()
    say(n > 0 and ("Cookie 已加载（" .. n .. " 字符）") or "没找到 cookie.txt")
end

-- 从剪贴板直接写入 cookie.txt，省掉手动建文件
act.cookie_clip = function()
    local t = nil
    pcall(function() t = utils.clipboard_get() end)
    if not t or #t < 10 then say("剪贴板是空的") return end
    t = string.gsub(t, "[\r\n]+", " ")
    t = string.gsub(t, "^%s+", "")
    t = string.gsub(t, "%s+$", "")
    if not string.find(string.lower(t), "music_u", 1, true) then
        say("剪贴板里没有 MUSIC_U，可能不是网易云 Cookie")
    end
    if not HAS_FILE then say("没有 file 权限（需 insecure）") return end
    local ok = file.write(COOKIE_FILE, t)
    if not ok then say("写 cookie.txt 失败") return end
    local n = load_cookie()
    set_cookie_label()
    say("Cookie 已导入（" .. n .. " 字符）")
    notify("Cookie 已导入（" .. n .. " 字符）")
end

local function apply_volume(v100)
    return set_music_volume(clamp(v100 / 100, 0, 1))
end

act.uid_fetch = function()
    local uid = tostring(uid_input:get() or "")
    if not string.match(uid, "^%d+$") then say("UID 要是数字") return end
    ne("/api/user/playlist/?offset=0&limit=200&uid=" .. uid, function(d)
        local list = d and d.playlist
        if type(list) ~= "table" then say("拉取失败（歌单没公开？）") return end
        local items = {}
        for i = 1, #list do
            items[#items + 1] = string.format("%s (%s)", tostring(list[i].name), tostring(list[i].trackCount or 0))
        end
        list_items(pl_box, (#items > 0) and items or { "(没有歌单)" })
        say("歌单 " .. #items .. " 个")
    end)
end

act.uid_load = function()
    local idx = 0
    pcall(function() idx = (pl_box:get() or 0) + 1 end)
    local uid = tostring(uid_input:get() or "")
    ne("/api/user/playlist/?offset=0&limit=200&uid=" .. uid, function(d)
        local p = d and d.playlist and d.playlist[idx]
        if not p then say("先拉取歌单") return end

        -- trackIds 可能是 {id=..} 也可能是纯数字；tracks 只给前几条
        local function ids_from(pl)
            local ids = {}
            if type(pl) ~= "table" then return ids end
            if type(pl.trackIds) == "table" then
                for i = 1, #pl.trackIds do
                    local row = pl.trackIds[i]
                    if type(row) == "table" and row.id then ids[#ids + 1] = row.id
                    elseif type(row) == "number" then ids[#ids + 1] = row end
                end
            end
            if #ids == 0 and type(pl.tracks) == "table" then
                for i = 1, #pl.tracks do
                    local tr = pl.tracks[i]
                    if type(tr) == "table" and tr.id then ids[#ids + 1] = tr.id end
                end
            end
            return ids
        end

        local function load_with(ids, pname)
            if #ids == 0 then
                if cookie == "" then
                    fail("载入歌单", "读不到曲目：没登录 Cookie（私人歌单必须登录）")
                else
                    fail("载入歌单", "这个歌单读不到曲目")
                end
                return
            end

            set_info("载入歌单 " .. tostring(pname) .. "（" .. #ids .. " 首）…")

            local map = {}
            local i, failed = 1, 0
            local function step()
                if i > #ids then
                    cloud_tracks = {}
                    local items = {}
                    for k = 1, #ids do
                        local so = map[ids[k]]
                        if so then
                            local song = {
                                id = so.id, name = so.name or "?",
                                artist = artists_of(so.artists),
                                dur_ms = tonumber(so.duration) or 0, fee = so.fee,
                                pic_url = so.album and so.album.picUrl or nil,
                            }
                            cloud_tracks[#cloud_tracks + 1] = song
                            items[#items + 1] = song.name .. " - " .. song.artist
                        end
                    end
                    list_items(track_box, items)
                    if #cloud_tracks == 0 then
                        fail("载入歌单", string.format("详情全部失败（%d 批），id 有 %d 个", failed, #ids))
                        return
                    end
                    last_list = "track"
                    if act.update_sel then act.update_sel() end
                    set_info("歌单 " .. tostring(pname) .. "：" .. #cloud_tracks .. " 首")
                    say("载入 " .. #cloud_tracks .. " 首")
                    notify("歌单已载入 " .. #cloud_tracks .. " 首")
                    return
                end
                local chunk = {}
                for j = i, math.min(i + 49, #ids) do chunk[#chunk + 1] = ids[j] end
                i = i + 50
                ne_details(chunk, function(songs, derr)
                    if songs then
                        for k = 1, #songs do map[songs[k].id] = songs[k] end
                    else
                        failed = failed + 1
                        dbg("详情批次失败: " .. tostring(derr))
                    end
                    step()
                end)
            end
            step()
        end

        ne("/api/v6/playlist/detail?id=" .. tostring(p.id), function(pd)
            local pl = pd and pd.playlist
            if type(pl) ~= "table" then
                fail("载入歌单", "v6 详情返回无效")
                return
            end
            local ids = ids_from(pl)
            if #ids > 0 then
                load_with(ids, p.name)
                return
            end
            -- 兜底：老接口（有的构建/无 Cookie 时 v6 的 trackIds 是空的）
            ne("/api/playlist/detail?id=" .. tostring(p.id), function(od)
                local opl = od and od.playlist
                load_with(ids_from(opl), p.name)
            end)
        end)
    end)
end

local function pl_path(name) return MUSIC .. "/" .. name .. ".txt" end

act.track_play_all = function()
    if #cloud_tracks == 0 then say("先载入曲目") return end
    local lines = {}
    for i = 1, #cloud_tracks do
        local t = cloud_tracks[i]
        lines[i] = string.format("%s|%s|%s", tostring(t.id), tostring(t.name), tostring(t.artist or ""))
    end
    if HAS_FILE then pcall(file.write, MUSIC .. "/当前歌单.txt", table.concat(lines, "\n")) end
    local_pl = "当前歌单"
    play_song(cloud_tracks[1])
end

act.loc_add = function()
    if not cur then say("先播放一首") return end
    local text = nil
    if HAS_FILE then
        local okr, t = pcall(file.read, pl_path(local_pl))
        if okr then text = t end
    end
    local lines, exists = {}, false
    if type(text) == "string" then
        for line in string.gmatch(text, "[^\r\n]+") do
            lines[#lines + 1] = line
            local id = string.match(line, "^(%d+)|")
            if id and tostring(id) == tostring(cur.id) then exists = true end
        end
    end
    if exists then say("已在歌单里") return end
    lines[#lines + 1] = string.format("%s|%s|%s", tostring(cur.id), tostring(cur.name), tostring(cur.artist or ""))
    if HAS_FILE then pcall(file.write, pl_path(local_pl), table.concat(lines, "\n")) end
    say("已收藏（" .. #lines .. " 首）")
end

-- ================================================================ 绘制
local function col_of(el, fallback)
    local c = fallback
    pcall(function() c = el:get() end)
    return c or fallback
end


-- 屏幕中间大歌词（可选）
local function draw_big_lyric()
    if not lyr_on:get() or not playing or not cur or #lyrics == 0 then return end
    local w, h = render.screen_size()
    local si = size_box:get() + 1
    local size = tonumber(size_items[si] or "") or SIZES[4]
    local idx, t = cur_line_index()
    if idx == 0 then return end

    local base = col_of(col_base, color(255, 255, 255, 240))
    local gcol = lyr_glow_fol:get() and base or col_of(lyr_glow_col, color(120, 200, 255, 255))
    local text = lyrics[idx].text
    local tw = width_of(text, size)
    local x = math.floor(w * (px_sl:get() / 100) - tw * 0.5)
    local y = math.floor(h * (py_sl:get() / 100))

    draw_text_line(text, x, y, size, base, gcol, lyr_glow_al:get(),
            lyr_glow_on:get() and math.max(1, lyr_glow_sp:get() * 0.85) or 0)

    if kara_on:get() then
        local nxt = lyrics[idx + 1] and lyrics[idx + 1].t or (lyrics[idx].t + 4)
        local span = nxt - lyrics[idx].t
        if span < 0.3 then span = 0.3 end
        local p = clamp((t - lyrics[idx].t) / span, 0, 1)
        if p > 0 then
            local hi = col_of(col_hi, color(120, 220, 255, 255))
            render.clip_push(x - 2, y - 3, math.floor(tw * p) + 2, size + 8)
            draw_text_line(text, x, y, size, hi, nil, 0)
            render.clip_pop()
        end
    end
end

-- 逐字跳动：只让"正在唱的那个字"往上弹，整句不动
-- 单字光晕：核心 + 两圈方向偏移，跟着字的位置走（逐字跳动时光会一起弹）
local function paint_glow_char(font, ch, x, y, px, glow_col, glow_alpha, d, dirs)
    if not glow_col or (glow_alpha or 0) < 6 or (d or 0) <= 0 then return end
    local gr, gg, gb = glow_col:unpack()
    local cr, cg, cb = mix_white(gr, gg, gb, 0.45)
    draw_raw(font, ch, x, y, color(cr, cg, cb, math.floor(glow_alpha * 0.24)), px)

    local layers = { { 0.40, 0.50 }, { 0.85, 0.26 }, { 1.40, 0.10 } }
    for li = 1, #layers do
        local a = math.floor(glow_alpha * layers[li][2])
        if a >= 6 then
            local rr = d * layers[li][1]
            for k = 0, dirs - 1 do
                local ang = k * (2 * math.pi / dirs)
                draw_raw(font, ch, x + math.cos(ang) * rr, y + math.sin(ang) * rr,
                        color(gr, gg, gb, a), px)
            end
        end
    end
end
-- 弹跳状态：记录"当前正在唱的字"是什么时候出现的，跳动按固定 0.3 秒走完，
-- 这样快歌也能看清弹一下，而不是被字的时长压扁
POP = { line = nil, idx = -1, t0 = 0 }
-- 逐字出场（卡拉OK式）：只画已经唱到的字，正在唱的那个字从下往上弹出来，
-- 还没唱到的字完全不出现。kara_p 为 nil 时（淡出的上一句）整行照画。
local function draw_text_chars(text, x, y, px, col, glow_col, glow_alpha, glow_d, kara_p, t)
    text = maybe_romanize(text)
    local total = utf8_len(text)
    if total <= 0 then return end

    local reveal = (kara_p ~= nil)
    local pos, full, frac = total, total, 1
    if reveal then
        local p = clamp(kara_p, 0, 1)
        pos = p * total
        full = math.floor(pos + 1e-6)
        frac = pos - full
    end

    local amp = math.max(4, px * 0.42)
    local d = tonumber(glow_d) or 0
    local glow_here = (d > 0 and glow_col ~= nil and (glow_alpha or 0) > 0)

    local i, n, cx = 1, 0, x
    while i <= #text do
        local kind, step = char_kind(text, i)
        local ch = string.sub(text, i, i + step - 1)
        local f = font_lookup(ch, px)
        local w = measure(f, ch, px)
        n = n + 1

        if not reveal or n <= full then
            -- 已经唱过：正常显示
            if glow_here then
                paint_glow_char(f, ch, cx, y, px, glow_col, glow_alpha, d, (#text <= 20) and 8 or 4)
            end
            draw_raw(f, ch, cx, y, col, px)
        elseif n == full + 1 and frac > 0 then
            -- 正在唱：弹跳出现（固定 0.3 秒、带过冲和回弹），不跟句速
            local nowt = now_s()
            if POP.line ~= text or POP.idx ~= n then
                POP.line, POP.idx, POP.t0 = text, n, nowt
            end
            local e = clamp((nowt - POP.t0) / 0.30, 0, 1)
            local bounce = math.sin(math.pi * e) * (1 + 0.35 * math.sin(3 * math.pi * e))
            local lift = -amp * bounce
            local a = clamp(e * 4, 0, 1)

            local r, g, b, ga = col:unpack()
            local c = color(r, g, b, math.floor((ga or 255) * a))
            if glow_here then
                paint_glow_char(f, ch, cx, y + lift, px, glow_col,
                        math.floor((glow_alpha or 0) * a), d * (0.7 + 0.3 * e),
                        (#text <= 20) and 8 or 4)
            end
            draw_raw(f, ch, cx, y + lift, c, px)
        end
        -- n > full + 1：还没唱到，一个字都不画

        cx = cx + w
        i = i + step
    end
end
-- 当前句的逐字进度 0..1（给逐字跳动用）
local function kara_progress(idx, t)
    local line = lyrics[idx]
    if not line then return nil end
    local nxt = lyrics[idx + 1] and lyrics[idx + 1].t or (line.t + 4)
    local span = nxt - line.t
    if span < 0.3 then span = 0.3 end
    return clamp((t - line.t) / span, 0, 1)
end
local function draw_world_lyric()
    if not wl_on:get() then return end
    if not playing then return end

    local eye = local_eye()
    if not eye then return end

    local idx, t = cur_line_index()
    local now = now_s()

    -- 自动测 BPM：用这句歌词的"字密度"反推节拍（字/秒 → 拍/分），折到 70..180 并做滑动平均
    if idx > 0 and lyrics[idx] and idx ~= bpm_line then
        bpm_line = idx
        local nxt = lyrics[idx + 1] and lyrics[idx + 1].t or (lyrics[idx].t + 4)
        local span = nxt - lyrics[idx].t
        local nch = utf8_len(lyrics[idx].text)
        if span > 0.25 and nch > 0 then
            local bpm = 60 / (span / nch)
            while bpm > 180 do bpm = bpm / 2 end
            while bpm < 70 do bpm = bpm * 2 end
            beat_bpm = (beat_bpm == 0) and bpm or (beat_bpm * 0.85 + bpm * 0.15)
            local rounded = math.floor(beat_bpm + 0.5)
            if rounded ~= bpm_shown then
                bpm_shown = rounded
                local auto = (wl_bpm_auto and wl_bpm_auto:get()) and "（自动）" or "（手动）"
                pcall(function() bpm_lbl:set(string.format("当前 BPM：%d%s", rounded, auto)) end)
            end
        end
    end
    local song_id = cur and cur.id or nil
    local va = view_angles()

    -- 连续节拍相位：按 dt 累加。BPM 中途变化不会让相位突然跳，因此不会"抽搐"
    do
        local nowt = timeline_ms() / 1000
        if beat_last < 0 then beat_last = nowt end
        local dt = nowt - beat_last
        if dt < 0 or dt > 1.0 then dt = 0 end
        beat_last = nowt

        local use_bpm = (wl_bpm and wl_bpm:get()) or 110
        if wl_bpm_auto and wl_bpm_auto:get() and beat_bpm > 0 then
            use_bpm = beat_bpm
        end
        beat_bpm_now = use_bpm

        if wl_beat_on and wl_beat_on:get() then
            beat_phase = (beat_phase + dt * (use_bpm / 60)) % 1000000
        end
    end
    -- 歌曲切换时清空旧状态，避免上一首的淡出文字残留。
    if world_anchor_song ~= nil and world_anchor_song ~= song_id then
        world_anchor, world_anchor_line = nil, nil
        world_transition = nil
        world_pending_line, world_pending_song = nil, nil
        world_hidden_since, world_repin_done = nil, false
    end

    -- 换句：只在“刚发现这句”的那一帧登记一次淡出，之后重试多少次都不再重置计时。
    if idx > 0 and world_anchor_line ~= idx then
        if world_pending_line ~= idx or world_pending_song ~= song_id then
            world_pending_line, world_pending_song = idx, song_id
            world_hidden_since, world_repin_done = nil, false
            if world_anchor and world_anchor_line and world_anchor_song == song_id
                    and lyrics[world_anchor_line] then
                world_transition = {
                    text = lyrics[world_anchor_line].text,
                    anchor = { x = world_anchor.x, y = world_anchor.y, z = world_anchor.z },
                    start = now,
                }
            else
                world_transition = nil
            end
            world_anchor = nil
        end

        -- 算不出来就下一帧继续试：不改行号、不动 transition.start，
        -- 旧句照常淡出，新句一算出来就淡入，不会出现两句都不显示。
        local next_anchor = compute_anchor(eye, va, wl_follow:get())
        if next_anchor then
            world_anchor = next_anchor
            world_anchor_line = idx
            world_anchor_song = song_id
            world_fade_start = now
            world_pending_line, world_pending_song = nil, nil
        end

        if lyrics[idx] then
            local hh = scan_script(lyrics[idx].text)
            if hh then
                dbg(string.format("[歌词] 第 %d 行含韩文，韩文字体=%s，混排字体=%s",
                        idx, fonts_kr[1] and "已加载" or "缺失",
                        fonts_uni[1] and "已加载" or "缺失"))
            end
        end

        -- 屏幕固定模式不需要世界锚点，直接推进行号和淡入计时
        if wl_screen:get() and world_anchor_line ~= idx then
            world_anchor_line = idx
            world_anchor_song = song_id
            world_fade_start = now
            world_pending_line, world_pending_song = nil, nil
        end
    end

    -- 遮挡判定分三种结果：无遮挡 / 被墙挡住 / 检测失败（失败不隐藏）
    local function project_visible(anchor)
        if not anchor then return nil end

        local sx, sy = world_to_screen(anchor.x, anchor.y, anchor.z)
        if not sx then return nil end          -- 只代表在相机后方/画面外
        local dx, dy, dz = anchor.x - eye.x, anchor.y - eye.y, anchor.z - eye.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        return sx, sy, clamp(400 / math.max(dist, 1), 0.35, 1.8)
    end

    local function draw_text_at(text, anchor, alpha, scale, current, fsx, fsy, kara_p)
        if not text or text == "" or alpha <= 0 then return end
        local sx, sy, projected_scale
        if fsx then
            sx, sy, projected_scale = fsx, fsy, 1.0     -- 屏幕固定：不投影、不遮挡检测
        else
            sx, sy, projected_scale = project_visible(anchor)
        end
        if not sx then return end
        scale = scale or projected_scale
        local sz0 = math.floor(wl_size:get() * scale * (current and 1.0 or 0.92) + 0.5)
        sz0 = clamp(sz0, 8, 96)

        -- 节拍：算出"这一次拍子有多重"
        local hop = 0
        if wl_beat_on and wl_beat_on:get() then
            local bpm = beat_bpm_now or 110
            if bpm < 30 then bpm = 110 end

            local bf = beat_phase % 1
            local since = bf * (60 / bpm)          -- 这一拍已经过去多少秒
            local dur = ((wl_beat_dur and wl_beat_dur:get()) or 260) / 1000
            if dur < 0.08 then dur = 0.08 end

            local atk = math.min(0.06, dur * 0.25)
            local kick
            if since < atk then
                kick = since / atk
            else
                kick = math.exp(-(since - atk) / (dur * 0.38))
            end
            if kick < 0.02 then kick = 0 end

            local ACCENT2 = { 1.0, 0.45, 0.82, 0.35 }
            local bi2 = math.floor(beat_phase) % 4
            hop = kick * ACCENT2[bi2 + 1]
        end

        -- 放大用"交叉淡入淡出"：小字淡出、大字淡入，看起来是连续长大，
        -- 不会像直接换字号那样一顿一跳。
        local pct = (wl_beat_scale and wl_beat_scale:get()) or 18
        local wmix = 0
        if current and hop > 0 and pct > 0 then
            wmix = clamp((hop - 0.2) / 0.6, 0, 1)
        end

        -- 连续插值：找到夹住 want 的两个相邻档位（只差 2px），按比例同时画，
        -- 2px 的差距肉眼看不出"两份"，但字号是连续变大的。
        local sz_a, sz_b, mix_b = sz0, sz0, 0
        if wmix > 0.02 then
            local want = sz0 * (1 + (pct / 100) * wmix)
            if want > SIZES[#SIZES] then want = SIZES[#SIZES] end
            for i = 1, #SIZES - 1 do
                if want <= SIZES[i + 1] then
                    sz_a, sz_b = SIZES[i], SIZES[i + 1]
                    mix_b = clamp((want - sz_a) / (sz_b - sz_a), 0, 1)
                    break
                end
            end
        end

        local base = col_of(wl_col_text, color(255, 255, 255, 255))
        local glow = col_of(wl_col_glow, color(120, 200, 255, 255))
        local r, g, b, _ = base:unpack()
        local glow_alpha = math.floor(wl_glow_al:get() * (alpha / 255))
        local gd = wl_glow_on:get() and math.max(1, wl_glow_sp:get() * 0.85) or 0

        local amp_px = (wl_beat_amp and wl_beat_amp:get()) or 8

        local function emit(px, mul)
            local a = math.floor(alpha * mul + 0.5)
            if a <= 3 then return end
            local tw = width_of(text, px)
            local xx = math.floor(sx - tw * 0.5)
            local yy = math.floor(sy - px * 0.5)
            if hop > 0 then
                yy = yy - math.floor(amp_px * hop * 0.45 + 0.5)
                xx = xx + math.floor(math.sin(math.pi * (beat_phase % 1)) * amp_px * 0.10 * hop + 0.5)
            end
            local ga = math.floor(glow_alpha * mul + 0.5)
            if current and wl_bounce:get() then
                draw_text_chars(text, xx, yy, px, color(r, g, b, a), glow, ga, gd, kara_p, t)
            else
                draw_text_line(text, xx, yy, px, color(r, g, b, a), glow, ga, gd)
            end
        end

        if mix_b > 0.02 and sz_b > sz_a then
            emit(sz_a, 1 - mix_b)
            emit(sz_b, mix_b)
        else
            emit(sz_a, 1)
        end
    end

    -- 屏幕固定模式：歌词钉死在屏幕上，走动、转身都不会动
    local fixed_sx, fixed_sy
    if wl_screen:get() then
        local sw, sh = render.screen_size()
        fixed_sx = math.floor(sw * 0.5 + wl_side:get())
        fixed_sy = math.floor(sh * 0.5 - wl_height:get())
    end

    -- 上一句独立淡出：留在原锚点上慢慢消散；idx==0 时也照画，不提前清除。
    local fade_out_s = math.max(0.1, wl_fade_out:get() / 1000)
    if world_transition then
        local elapsed = now - world_transition.start
        local fade = 1 - clamp(elapsed / fade_out_s, 0, 1)
        if fade > 0 then
            draw_text_at(world_transition.text, world_transition.anchor,
                    math.floor(255 * fade), nil, false, fixed_sx, fixed_sy)
        else
            world_transition = nil
        end
    end

    -- 当前句淡入：整句期间位置固定；只有整句都看不见超过 1.5 秒才重算一次
    local fade_in_s = math.max(0.1, wl_fade_in:get() / 1000)
    local anchor_ready = world_anchor and world_anchor_line == idx and world_anchor_song == song_id
    if idx > 0 and lyrics[idx] and (fixed_sx or anchor_ready) then
        local sx, sy, pscale
        if fixed_sx then
            sx, sy, pscale = fixed_sx, fixed_sy, 1.0
        else
            sx, sy, pscale = project_visible(world_anchor)
        end

        -- 看不见（被墙挡 / 出画面）持续 1.5 秒：允许重算一次锚点
        if not sx and not fixed_sx then
            if not world_hidden_since then
                world_hidden_since = now
            elseif (now - world_hidden_since) > 1.5 and not world_repin_done then
                local na = compute_anchor(eye, va, false)
                if na then
                    world_anchor = na
                    world_repin_done = true
                    world_hidden_since = nil
                    world_fade_start = now
                    dbg("世界歌词整句不可见，重算锚点一次")
                    sx, sy, pscale = project_visible(world_anchor)
                else
                    dbg("世界歌词重算锚点失败，保持原样")
                end
            end
        end

        if sx then
            world_hidden_since = nil
            local fade_in = clamp((now - world_fade_start) / fade_in_s, 0, 1)
            draw_text_at(lyrics[idx].text, world_anchor, math.floor(255 * fade_in),
                    pscale, true, sx, sy, kara_progress(idx, t))
        end
    end
end

-- ================================================================ 事件
last_poll = 0
err_count = 0
local function safe(tag, fn)
    local ok, err = pcall(fn)
    if not ok then
        err_count = err_count + 1
        if err_count == 1 or err_count % 600 == 0 then
            dbg("[" .. tag .. "] 出错: " .. tostring(err))
        end
    end
end

-- 切歌热键（按住键位触发一次）
local function key_hit(el)
    if not el then return false end
    local vk = 0
    pcall(function() vk = tonumber(el:get()) or 0 end)
    if vk <= 0 then return false end
    local down = false
    pcall(function() down = input.key_pressed(vk) == true end)
    return down
end

events.on("input", function(msg, wparam)
    if nlc_input_blocked() then return nil end
    if msg ~= 0x0100 then return nil end
    if key_hit(hk_toggle) then act.toggle() return true end
    if key_hit(hk_prev) then act.prev_track() return true end
    if key_hit(hk_next) then act.next_track() return true end
    return nil
end)

events.on("paint", function()
    NLC_UI.tick()
    -- 音量：图没就绪先挂着；应用失败最多重试 3 次
    if pending_vol ~= nil and ds.audio and ds.has_audio then
        local v = pending_vol
        pending_vol = nil
        if apply_volume(v) then
            vol_retry = 0
        else
            vol_retry = (vol_retry or 0) + 1
            if vol_retry <= 3 then pending_vol = v end
            if vol_retry == 1 then dbg("音量应用失败，重试中 " .. tostring(v)) end
        end
    end

    local nowt = now_s()
    if playing and backend == "dshow" and nowt - last_poll > 0.25 then
        last_poll = nowt
        local in_seek_cooldown = (nowt - last_seek_t) <= 1.5
        local p = ds_pos_ms()
        if p and pos_ok then
            if in_seek_cooldown then
                -- seek 后冷却期：DS 可能还没跳转到位，用目标值而非旧值
                -- 只在 DS 位置接近预期时才采信
                if math.abs(p - pos_ms) < 2000 then
                    pos_ms = p
                    if math.abs(p - now_ms()) > 2000 then
                        start_t = nowt - p / 1000
                    end
                end
                pos_bad = 0
            else
                if math.abs(p - pos_ms) < 1 then pos_bad = pos_bad + 1 else pos_bad = 0 end
                if pos_bad > 6 then pos_ok = false end
                pos_ms = p
                if math.abs(p - now_ms()) > 2000 then
                    start_t = nowt - p / 1000
                end
            end
        end
        if ds.dur_ms > 0 then len_ms = ds.dur_ms end
        if len_ms > 0 then
            pcall(function() time_lbl:set(fmt(timeline_ms()) .. " / " .. fmt(len_ms)) end)
        end
    end

    -- 放完自动收尾：歌词立即消失，不把最后一句留在空气里
    if playing and len_ms > 0 and timeline_ms() > len_ms + 600 then
        ds_stop()
        backend = "none"
        playing, paused = false, false
        pos_ms, len_ms = 0, 0
        clear_world_state()
        pcall(function() time_lbl:set("00:00 / 00:00") end)
        set_info("播放结束")

        local advanced = false
        if auto_next and auto_next:get() and cur then
            advanced = true
            if repeat_one and repeat_one:get() then
                play_song(cur)
            else
                act.next_track()
            end
        end
        dbg(advanced and "歌曲播放结束，已自动切下一首" or "歌曲播放结束，已清空世界歌词")
    end

    if in_game() then
        safe("lyric", draw_big_lyric)
        safe("world", draw_world_lyric)
    end
end)

events.on("unload", function()
    NLC_UI.save()
    ds_stop()
end)

set_info(string.format("DShow:%s | insecure:%s | ffi:%s",
        ds.ready and "OK" or "-", HAS_HTTP and "OK" or "-", HAS_FFI and "OK" or "-"))
if not HAS_FFI or not HAS_HTTP or not HAS_FILE then
    local msg = string.format("未开启 insecure：ffi=%s http=%s file=%s（菜单 Lua/Allow Insecure 打开后重载）",
            tostring(HAS_FFI), tostring(HAS_HTTP), tostring(HAS_FILE))
    say("⚠ " .. msg)
    set_info("⚠ " .. msg)
    notify("需要开启 insecure 模式，否则搜不到歌")
end
if not ds.ready then
    dbg("DirectShow 依赖缺失，播放会失败（检查 insecure 与 ole32）")
end
pcall(function() if act.update_sel then act.update_sel() end end)
say("netease_lyric_fade v10 (starlose) 已加载")
dbg("lyric_fade v10 加载完成")

end)
if not __body_ok then
    dbg("boot: 初始化异常: " .. tostring(__body_err))
    pcall(function() log.console("[音乐] 初始化异常: " .. tostring(__body_err)) end)
else
    dbg("boot: 初始化完成")
end

end

local nlc_env = {
    ui = nlc_virtual_ui,
    NLC_UI = NLC_UI,
    nlc_input_blocked = nlc_input_blocked,
    nlc_pointer_over_panel = nlc_pointer_over_panel,
}
setmetatable(nlc_env, { __index = _G })
setfenv(nlc_bootstrap, nlc_env)
local NLC = nlc_env
local nlc_boot_ok, nlc_boot_err = pcall(nlc_bootstrap)
NLC_UI.boot_ok = nlc_boot_ok
if not nlc_boot_ok then nlc_report_error("bootstrap", nlc_boot_err) end

-- ============================================================
--  УТИЛИТЫ
-- ============================================================
local function safe(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
local function clamp01(v) return math.max(0, math.min(1, v)) end
local function clamp255(v) return math.floor(math.max(0, math.min(255, v))) end
local function white(a) return color(255, 255, 255, clamp255(a)) end
local function black(a) return color(0, 0, 0, clamp255(a)) end
local function lerp(a, b, t) return a + (b - a) * t end

local function timestamp(n)
    n = math.max(0, math.floor(n or 0))
    if n >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(n / 3600), math.floor(n / 60) % 60, n % 60)
    end
    return string.format("%d:%02d", math.floor(n / 60), n % 60)
end

local retry = false

-- ============================================================
--  ШРИФТ
-- ============================================================
local FONT_SIZE = 13
local FONT = nil
local function try_load(name)
    local f = safe(render.font, name, FONT_SIZE)
    if f and safe(function() return f:loaded() end) then return f end
end
FONT = try_load("Microsoft YaHei") or try_load("msyh") or try_load("C:\\Windows\\Fonts\\msyh.ttc")
    or try_load("msyh.ttc") or try_load("Segoe UI") or try_load("Tahoma") or try_load("Roboto")

local function text(x, y, col, str, size)
    render.text(x, y, col, str, "", size or FONT_SIZE, FONT)
end
local function tsize(str, size)
    return render.text_size(str, "", size or FONT_SIZE, FONT)
end

-- ============================================================
--  ПРИСТЫКОВКА ПАНЕЛИ
-- ============================================================
local DOCK_W, DOCK_GAP, MIN_H = 350, 8, 480
local PW, PH = DOCK_W, MIN_H
local HEADER_H = 56
local dock_anim = 0
local dock_edge = 0
local panel_win = { x = 0, y = 0, w = PW, h = PH }

local function update_dock()
    local mp = safe(function() return NL_UI.position() end)
    local ms = safe(function() return NL_UI.size() end)
    if not (mp and ms and mp.x and ms.x and ms.x > 0) then return false end

    PW = DOCK_W
    PH = math.max(ms.y, MIN_H)
    dock_edge = mp.x + ms.x
    panel_win.w, panel_win.h = PW, PH
    panel_win.x = dock_edge + DOCK_GAP - (1 - dock_anim) * (PW + DOCK_GAP)
    panel_win.y = mp.y
    return true
end

-- ============================================================
--  ВВОД
-- ============================================================
local slider_active = nil
local mouse_prev = false
local click_used = false

local function in_rect(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- ============================================================
--  СТИЛИ
-- ============================================================
local C_BG     = color(13, 14, 21, 244)
local C_BORDER = color(255, 255, 255, 16)
local C_CARD   = color(20, 21, 31, 255)
local C_SEP    = color(255, 255, 255, 10)
local C_FIELD  = color(12, 13, 19, 255)

local LABEL    = color(206, 209, 222, 255)
local SECTION  = color(96, 99, 118, 255)
local VALUE    = color(190, 193, 208, 255)
local SW_OFF   = color(50, 52, 64, 255)
local KNOB_OFF = color(138, 142, 158, 255)
local KNOB     = color(255, 255, 255, 255)
local ACCENT   = color(140, 148, 255, 255)
local SPOTIFY_GREEN = color(30, 215, 96, 255)

local function refresh_accent()
    local c = safe(render.theme, "accent")
    if c and type(c) == "table" and c.r ~= nil then
        ACCENT = color(c.r, c.g, c.b, 255)
    end
end

local RH = 36
local TH = nil
local function text_h()
    if not TH then local _, h = tsize("Ag"); TH = h or FONT_SIZE end
    return TH
end

local anims = {}
local function anim_to(id, target)
    local v = anims[id] or target
    v = v + (target - v) * math.min(1, globals.frametime() * 16)
    if math.abs(v - target) < 0.005 then v = target end
    anims[id] = v
    return v
end

local function row_text(x, ry, label, max_w)
    local value = tostring(label or "")
    if max_w and NLC_UI._ellipsize then value = NLC_UI._ellipsize(value, max_w) end
    text(x + 14, ry + (RH - text_h()) / 2, LABEL, value)
end

-- ============================================================
--  СОСТОЯНИЕ SPOTIFY
-- ============================================================
local STYLE_NAMES = { "默认", "极简", "玻璃" }
local spotify = {
    enabled = true,
    filter = "",
    scale = 120,
    perimeter_wave_enabled = true,
    perimeter_wave_disable_playing = false,
    edge_glow = true,
    glow_strength = 36,
    glow_response = 180,
    dark_wave = true,
    wave_opacity = 24,
    animated_fallback = false,
    vertical = false,
    style = 1,
    lyric_size = 12,
    lyric_offset_y = -8,
    lyric_offset_x = 1,
    lyric_alpha = 220,
}

-- ============================================================
--  БАЗОВЫЕ ВИДЖЕТЫ
-- ============================================================
NLC_UI.list_scroll = NLC_UI.list_scroll or {}
NLC_UI.list_last_selected = NLC_UI.list_last_selected or {}
NLC_UI.wheel = 0
NLC_UI.wheel_consumed = false
NLC_UI.text_scroll = 0

function NLC_UI._visible(ui, ry, height)
    return not ui.vp_y or (ry + height >= ui.vp_y and ry <= ui.vp_bottom)
end

function NLC_UI._utf8_next(value, index)
    local byte = value:byte(index)
    if not byte then return #value + 1 end
    local length = byte < 0x80 and 1 or (byte < 0xE0 and 2 or (byte < 0xF0 and 3 or 4))
    return math.min(#value + 1, index + length)
end

function NLC_UI._utf8_prev(value, index)
    if index <= 1 then return 1 end
    local previous = index - 1
    while previous > 1 do
        local byte = value:byte(previous)
        if not byte or byte < 0x80 or byte >= 0xC0 then break end
        previous = previous - 1
    end
    return previous
end

function NLC_UI._ellipsize(value, max_width, size)
    value = tostring(value or "")
    if max_width <= 0 then return "" end
    local width = tsize(value, size)
    if width <= max_width then return value end
    local tail = "…"
    local result, index = "", 1
    while index <= #value do
        local next_index = NLC_UI._utf8_next(value, index)
        local candidate = value:sub(1, next_index - 1) .. tail
        if tsize(candidate, size) > max_width then break end
        result = value:sub(1, next_index - 1)
        index = next_index
    end
    return result .. tail
end

function NLC_UI._utf8_encode(codepoint)
    if codepoint < 0x80 then return string.char(codepoint) end
    if codepoint < 0x800 then
        return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
    end
    if codepoint < 0x10000 then
        return string.char(0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
    end
    return string.char(0xF0 + math.floor(codepoint / 0x200000),
        0x80 + math.floor(codepoint / 0x1000) % 0x40,
        0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
end

function NLC_UI._commit_text()
    local control = NLC_UI.text_focus
    if control and NLC_UI.text_draft ~= nil and NLC_UI.text_draft ~= control:get() then
        control:change(NLC_UI.text_draft)
    end
    NLC_UI.text_focus = nil
    NLC_UI.text_draft = nil
    NLC_UI.text_caret = nil
    NLC_UI.pending_high_surrogate = nil
    NLC_UI.text_scroll = 0
end

function NLC_UI._before_action()
    NLC_UI._commit_text()
    NLC_UI.key_capture = nil
    NLC_UI.key_capture_original = nil
    NLC_UI.pending_high_surrogate = nil
end

function NLC_UI._reset_transient(commit_text)
    if commit_text then NLC_UI._commit_text()
    else NLC_UI.text_focus = nil; NLC_UI.text_draft = nil; NLC_UI.text_caret = nil end
    NLC_UI.key_capture = nil
    NLC_UI.key_capture_original = nil
    NLC_UI.pending_high_surrogate = nil
    NLC_UI.color_open = nil
    NLC_UI.text_scroll = 0
    NLC_UI.wheel = 0
    slider_active = nil
end

function NLC_UI._focus_text(control)
    if NLC_UI.text_focus == control then return end
    NLC_UI._before_action()
    NLC_UI.text_focus = control
    NLC_UI.text_draft = tostring(control:get() or "")
    NLC_UI.text_caret = #NLC_UI.text_draft + 1
    NLC_UI.text_scroll = 0
end

function NLC_UI._insert_text(value)
    if not NLC_UI.text_focus or not value or value == "" then return end
    value = tostring(value):gsub("[\r\n]", "")
    local draft = NLC_UI.text_draft or ""
    local caret = NLC_UI.text_caret or (#draft + 1)
    NLC_UI.text_draft = draft:sub(1, caret - 1) .. value .. draft:sub(caret)
    NLC_UI.text_caret = caret + #value
end

function NLC_UI._read(source)
    if type(source) == "function" then return source() end
    if source then return source:get() end
    return nil
end

function NLC_UI._write(source, set, value)
    if set then set(value) elseif source then source:change(value) end
end

local function widget_toggle(ui, id, x, ry, w, label, get, set)
    row_text(x, ry, label, w - 76)
    local on = NLC_UI._read(get) == true
    local t = anim_to(id, on and 1 or 0)
    local sw, sh = 34, 18
    local sx, sy = x + w - 14 - sw, ry + (RH - sh) / 2
    render.rect_filled(sx, sy, sw, sh, SW_OFF:lerp(ACCENT, t), sh / 2)
    render.circle_filled(sx + 9 + (sw - 18) * t, sy + sh / 2, 6, KNOB_OFF:lerp(KNOB, t), 24)
    if ui.menu and ui.clicked and NLC_UI._visible(ui, ry, RH) and in_rect(ui.mx, ui.my, x, ry, w, RH) then
        click_used = true
        NLC_UI._before_action()
        NLC_UI._write(get, set, not on)
    end
end

local function widget_slider(ui, id, x, ry, w, label, get, set, lo, hi, step, fmt)
    local inactive = type(get) == "table" and get.inactive_state == true
    local val = tonumber(NLC_UI._read(get)) or lo
    lo, hi, step = tonumber(lo) or 0, tonumber(hi) or 100, tonumber(step) or 1
    if hi <= lo then hi = lo + 1 end
    if step <= 0 then step = 1 end
    local f = math.max(0, math.min(1, (val - lo) / (hi - lo)))
    local bw, bh, tw = 58, 22, 96
    local bx, by = x + w - 14 - bw, ry + (RH - bh) / 2
    local tx = bx - 12 - tw
    row_text(x, ry, label, math.max(40, tx - x - 22))

    render.rect_filled(bx, by, bw, bh, C_FIELD, 6)
    render.rect(bx, by, bw, bh, C_BORDER, 6, 1)
    local vs
    if fmt then vs = fmt(val)
    elseif step < 1 then vs = string.format("%.1f", val)
    else vs = string.format("%d", math.floor(val + (val >= 0 and 0.5 or -0.5))) end
    local vw, vh = tsize(vs)
    text(bx + (bw - vw) / 2, by + (bh - vh) / 2, VALUE, vs)

    local ty = ry + RH / 2
    render.rect_filled(tx, ty - 2, tw, 4, SW_OFF, 2)
    if f > 0 then render.rect_filled(tx, ty - 2, tw * f, 4, ACCENT, 2) end
    render.circle_filled(tx + tw * f, ty, 6, KNOB, 20)

    if ui.menu and not inactive then
        local on_track = NLC_UI._visible(ui, ry, RH) and in_rect(ui.mx, ui.my, tx - 8, ty - 10, tw + 16, 20)
        if ui.clicked and on_track then click_used = true; NLC_UI._before_action() end
        if ui.down and (slider_active == id or (ui.clicked and on_track)) then
            slider_active = id
            local nf = math.max(0, math.min(1, (ui.mx - tx) / tw))
            local v = lo + nf * (hi - lo)
            local scaled = v / step
            v = (scaled >= 0 and math.floor(scaled + 0.5) or math.ceil(scaled - 0.5)) * step
            NLC_UI._write(get, set, math.max(lo, math.min(hi, v)))
        end
        if ui.released and slider_active == id then slider_active = nil end
    end
end

local function widget_button(ui, id, x, ry, w, label, fn)
    local bx, by, bw, bh = x + 14, ry + 6, w - 28, RH - 12
    local hover = ui.menu and NLC_UI._visible(ui, ry, RH) and in_rect(ui.mx, ui.my, bx, by, bw, bh)
    local t = anim_to(id, hover and 1 or 0)
    render.rect_filled(bx, by, bw, bh, C_FIELD:lerp(color(30, 32, 48, 255), t), 7)
    render.rect(bx, by, bw, bh, C_BORDER:lerp(ACCENT, t), 7, 1)
    local shown = NLC_UI._ellipsize(label, bw - 12)
    local tw, th = tsize(shown)
    text(bx + (bw - tw) / 2, by + (bh - th) / 2, LABEL, shown)
    if hover and ui.clicked then
        click_used = true
        NLC_UI._before_action()
        fn()
    end
end

function NLC_UI._button_row(ui, id, x, ry, w, buttons)
    local count = #buttons
    if count == 0 then return end
    local gap, cell_w = 6, (w - 28 - (count - 1) * 6) / count
    for i, descriptor in ipairs(buttons) do
        local bx = x + 14 + (i - 1) * (cell_w + gap)
        local by, bh = ry + 6, RH - 12
        local hover = ui.menu and NLC_UI._visible(ui, ry, RH) and in_rect(ui.mx, ui.my, bx, by, cell_w, bh)
        local t = anim_to(id .. ":" .. i, hover and 1 or 0)
        render.rect_filled(bx, by, cell_w, bh, C_FIELD:lerp(color(30, 32, 48, 255), t), 7)
        render.rect(bx, by, cell_w, bh, C_BORDER:lerp(ACCENT, t), 7, 1)
        local shown = NLC_UI._ellipsize(descriptor.label, cell_w - 10)
        local tw, th = tsize(shown)
        text(bx + (cell_w - tw) / 2, by + (bh - th) / 2, LABEL, shown)
        if hover and ui.clicked then
            click_used = true
            NLC_UI._before_action()
            descriptor.fn()
        end
    end
end

local function widget_selector(ui, id, x, ry, w, label, get, set, names, zero_based)
    names = names or (type(get) == "table" and get:items()) or {}
    local idx = tonumber(NLC_UI._read(get)) or (zero_based and 0 or 1)
    local val = names[zero_based and idx + 1 or idx] or "?"
    local bw, bh = 116, 22
    local bx, by = x + w - 14 - bw, ry + (RH - bh) / 2
    row_text(x, ry, label, w - 152)
    local hover = ui.menu and NLC_UI._visible(ui, ry, RH) and in_rect(ui.mx, ui.my, bx, by, bw, bh)
    local t = anim_to(id, hover and 1 or 0)
    render.rect_filled(bx, by, bw, bh, C_FIELD:lerp(color(28, 30, 46, 255), t), 6)
    render.rect(bx, by, bw, bh, C_BORDER:lerp(ACCENT, t), 6, 1)
    local shown = NLC_UI._ellipsize(val, bw - 10)
    local vw, vh = tsize(shown)
    text(bx + (bw - vw) / 2, by + (bh - vh) / 2, LABEL, shown)
    if hover and ui.clicked and #names > 0 then
        click_used = true
        NLC_UI._before_action()
        if zero_based then NLC_UI._write(get, set, (idx + 1) % #names)
        else NLC_UI._write(get, set, idx % #names + 1) end
    end
end

function NLC_UI._text_input(ui, id, x, ry, w, control)
    local label = control.label or "文本"
    text(x + 14, ry + 3, SECTION, label)
    local bx, by, bw, bh = x + 14, ry + 21, w - 28, 27
    local focused = NLC_UI.text_focus == control
    local hover = ui.menu and NLC_UI._visible(ui, ry, 54) and in_rect(ui.mx, ui.my, bx, by, bw, bh)
    render.rect_filled(bx, by, bw, bh, C_FIELD, 6)
    render.rect(bx, by, bw, bh, focused and ACCENT or C_BORDER, 6, 1)

    if ui.clicked and focused and not in_rect(ui.mx, ui.my, bx, by, bw, bh) then NLC_UI._commit_text(); focused = false end
    if hover and ui.clicked then
        click_used = true
        NLC_UI._focus_text(control)
        focused = true
        local draft = NLC_UI.text_draft
        local relative = math.max(0, ui.mx - bx - 6 + NLC_UI.text_scroll)
        local index, best = 1, math.huge
        while true do
            local distance = math.abs(tsize(draft:sub(1, index - 1)) - relative)
            if distance < best then best = distance; NLC_UI.text_caret = index else break end
            if index > #draft then break end
            index = NLC_UI._utf8_next(draft, index)
        end
    end

    local draft = focused and (NLC_UI.text_draft or "") or tostring(control:get() or "")
    render.clip_push(bx + 1, by + 1, bw - 2, bh - 2, true)
    if focused then
        local caret = math.max(1, math.min(#draft + 1, NLC_UI.text_caret or (#draft + 1)))
        NLC_UI.text_caret = caret
        local caret_width = tsize(draft:sub(1, caret - 1))
        local total_width = tsize(draft)
        local available = bw - 12
        if caret_width - NLC_UI.text_scroll > available then NLC_UI.text_scroll = caret_width - available end
        if caret_width < NLC_UI.text_scroll then NLC_UI.text_scroll = caret_width end
        NLC_UI.text_scroll = math.max(0, math.min(NLC_UI.text_scroll, math.max(0, total_width - available)))
        local th = select(2, tsize("Ag"))
        text(bx + 6 - NLC_UI.text_scroll, by + (bh - th) / 2, LABEL, draft)
        if globals.realtime() % 1 < 0.55 then
            render.rect_filled(bx + 6 + caret_width - NLC_UI.text_scroll, by + 5, 1, bh - 10, KNOB)
        end
    else
        local shown = NLC_UI._ellipsize(draft, bw - 12)
        local th = select(2, tsize("Ag"))
        text(bx + 6, by + (bh - th) / 2, draft == "" and SECTION or LABEL,
            shown ~= "" and shown or "点击输入，Enter 提交")
    end
    render.clip_pop()
    return 54
end

function NLC_UI._list(ui, id, x, ry, w, control)
    local items = control:items() or {}
    local visible_rows = math.max(1, math.floor(tonumber(control.height) or 6))
    local row_h, body_y = 24, ry + 20
    local body_h = visible_rows * row_h
    text(x + 14, ry + 2, SECTION, control.label or "列表")
    render.rect_filled(x + 10, body_y, w - 20, body_h, C_FIELD, 7)
    render.rect(x + 10, body_y, w - 20, body_h, C_BORDER, 7, 1)

    local max_scroll = math.max(0, #items - visible_rows)
    local scroll = math.max(0, math.min(max_scroll, NLC_UI.list_scroll[id] or 0))
    local selected = tonumber(control:get()) or 0
    if #items > 0 and NLC_UI.list_last_selected[id] ~= selected then
        if selected < scroll then scroll = selected end
        if selected >= scroll + visible_rows then scroll = selected - visible_rows + 1 end
        NLC_UI.list_last_selected[id] = selected
    end
    local inside = ui.menu and NLC_UI._visible(ui, body_y, body_h)
        and in_rect(ui.mx, ui.my, x + 10, body_y, w - 20, body_h)
    if inside and NLC_UI.wheel ~= 0 then
        scroll = math.max(0, math.min(max_scroll, scroll - NLC_UI.wheel * 3))
        NLC_UI.wheel_consumed = true
    end
    NLC_UI.list_scroll[id] = scroll

    render.clip_push(x + 11, body_y + 1, w - 22, body_h - 2, true)
    if #items == 0 then
        text(x + 20, body_y + 7, SECTION, "(空)")
    else
        local first = math.floor(scroll) + 1
        local last = math.min(#items, first + visible_rows - 1)
        for item_index = first, last do
            local row = item_index - first
            local item_y = body_y + row * row_h
            local is_selected = item_index - 1 == selected
            local hover = inside and in_rect(ui.mx, ui.my, x + 12, item_y, w - 24, row_h)
            if is_selected or hover then
                render.rect_filled(x + 12, item_y, w - 24, row_h,
                    is_selected and color(ACCENT.r, ACCENT.g, ACCENT.b, 42) or color(255, 255, 255, 10), 4)
            end
            local shown = NLC_UI._ellipsize(items[item_index], w - 54)
            text(x + 20, item_y + 5, is_selected and KNOB or LABEL, shown)
            if hover and ui.clicked then
                click_used = true
                NLC_UI._before_action()
                control:change(item_index - 1)
                NLC_UI.list_scroll[id] = scroll
            end
        end
    end
    render.clip_pop()
    if max_scroll > 0 then
        local track_x = x + w - 15
        render.rect_filled(track_x, body_y + 3, 2, body_h - 6, color(255, 255, 255, 12), 1)
        local thumb_h = math.max(18, body_h * visible_rows / #items)
        local thumb_y = body_y + (body_h - thumb_h) * (scroll / max_scroll)
        render.rect_filled(track_x, thumb_y, 2, thumb_h, ACCENT, 1)
    end
    return body_h + 28
end

function NLC_UI._status(ui, x, ry, w, label, source)
    local value = tostring(NLC_UI._read(source) or "")
    if label then
        row_text(x, ry, label, math.floor(w * 0.38))
        local shown = NLC_UI._ellipsize(value, math.floor(w * 0.58) - 24)
        text(x + math.floor(w * 0.40), ry + (RH - text_h()) / 2, VALUE, shown)
    else
        row_text(x, ry, value, w - 28)
    end
end

function NLC_UI._keybind(ui, id, x, ry, w, control)
    row_text(x, ry, control.label, w - 154)
    local capturing = NLC_UI.key_capture == control
    local value = capturing and "按按键…" or ((tonumber(control:get()) or 0) > 0 and ("VK " .. control:get()) or "未设置")
    local bx, by, bw, bh = x + w - 128, ry + 7, 114, 22
    render.rect_filled(bx, by, bw, bh, C_FIELD, 6)
    render.rect(bx, by, bw, bh, capturing and ACCENT or C_BORDER, 6, 1)
    local vw, vh = tsize(value)
    text(bx + (bw - vw) / 2, by + (bh - vh) / 2, capturing and KNOB or LABEL, value)
    if ui.menu and ui.clicked and NLC_UI._visible(ui, ry, RH) and in_rect(ui.mx, ui.my, bx, by, bw, bh) then
        click_used = true
        NLC_UI._before_action()
        NLC_UI.key_capture = control
        NLC_UI.key_capture_original = control:get()
    end
end

function NLC_UI._color(ui, id, x, ry, w, control)
    local expanded = NLC_UI.color_open == id
    row_text(x, ry, control.label, w - 104)
    local r, g, b, a = nlc_rgba(control:get())
    local bx, by, bw, bh = x + w - 76, ry + 8, 62, 20
    render.rect_filled(bx, by, bw, bh, color(r, g, b, a), 5)
    render.rect(bx, by, bw, bh, expanded and ACCENT or C_BORDER, 5, 1)
    if ui.menu and ui.clicked and NLC_UI._visible(ui, ry, RH) and in_rect(ui.mx, ui.my, x, ry, w, RH) then
        click_used = true
        NLC_UI._before_action()
        if expanded then NLC_UI.color_open = nil else NLC_UI.color_open = id end
    end
    if expanded then
        local rgba = {r, g, b, a}
        local names = {"R", "G", "B", "A"}
        for channel = 1, 4 do
            widget_slider(ui, id .. ":rgba:" .. channel, x, ry + channel * RH, w, names[channel],
                function() return rgba[channel] end,
                function(value)
                    rgba[channel] = value
                    control:change(color(rgba[1], rgba[2], rgba[3], rgba[4]))
                end, 0, 255, 1)
        end
    end
    return RH + (expanded and 4 * RH or 0)
end

-- ============================================================
--  ВКЛАДКИ
-- ============================================================
local TABS = { "播放", "歌词", "浮窗" }
local cur_tab = 1
local scroll_y, content_h, sb_drag = 0, 0, false
local tab_transition = 1
local prev_tab = 1
local anim_dir = 1

local function draw_tabs(ui, x, y, w)
    local bh, gap = 28, 4
    local columns = math.min(5, #TABS)
    local inner_w = w - 28
    local tab_w = math.min(84, (inner_w - (columns - 1) * gap) / columns)
    local rows = math.ceil(#TABS / columns)

    -- 每行一条轨道（外框），和原版一致的分段控件风格
    for r = 0, rows - 1 do
        local row_count = r == 0 and columns or (#TABS - columns)
        local row_width = row_count * tab_w + (row_count - 1) * gap
        local row_x = x + 14 + (inner_w - row_width) / 2
        local sy = y + r * (bh + gap)
        render.rect_filled(row_x, sy, row_width, bh, C_FIELD, 9)
        render.rect(row_x, sy, row_width, bh, C_BORDER, 9, 1)
    end

    -- 只有选中项画胶囊 + 强调色下划线
    for i, name in ipairs(TABS) do
        local row = math.floor((i - 1) / columns)
        local column = (i - 1) % columns
        local row_count = row == 0 and columns or (#TABS - columns)
        local row_width = row_count * tab_w + (row_count - 1) * gap
        local row_x = x + 14 + (inner_w - row_width) / 2
        local sx, sy = row_x + column * (tab_w + gap), y + row * (bh + gap)
        local active = cur_tab == i
        local t = anim_to("tab:" .. i, active and 1 or 0)
        local hover = ui.menu and in_rect(ui.mx, ui.my, sx, sy, tab_w, bh)
        if active then
            render.rect_filled(sx + 3, sy + 3, tab_w - 6, bh - 6, C_CARD, 7)
            render.rect(sx + 3, sy + 3, tab_w - 6, bh - 6, C_BORDER, 7, 1)
            render.rect_filled(sx + 12, sy + bh - 5, tab_w - 24, 2, ACCENT, 1)
        end
        local tw, th = tsize(name)
        local tc = SECTION:lerp(KNOB, t)
        if hover and not active then tc = tc:lerp(KNOB, 0.35) end
        text(sx + (tab_w - tw) / 2, sy + (bh - th) / 2 - 1, tc, name)
        if hover and ui.clicked and cur_tab ~= i then
            click_used = true
            NLC_UI._reset_transient(true)
            prev_tab = cur_tab
            cur_tab = i
            scroll_y = 0
            sb_drag = false
            tab_transition = 0
            anim_dir = cur_tab > prev_tab and 1 or -1
        end
    end
    return y + rows * bh + (rows - 1) * gap
end

function NLC_UI._group(x, y, w, title, height, plain)
    text(x + 4, y, SECTION, title)
    local cy = y + 20
    render.rect_filled(x, cy, w, height, C_CARD, 10)
    render.rect(x, cy, w, height, C_BORDER, 10, 1)
    if not plain then
        local row = 1
        while row * RH < height - 2 do
            render.rect_filled(x + 12, cy + row * RH, w - 24, 1, C_SEP)
            row = row + 1
        end
    end
    return cy, cy + height + 14
end

local function group(x, y, w, title, n)
    return NLC_UI._group(x, y, w, title, n * RH, false)
end

-- ============================================================
--  ШАПКА (ФУТЕР) С ИКОНКОЙ SPOTIFY
-- ============================================================
local function draw_spotify_icon(x, y, size)
    local cx, cy = x + size / 2, y + size / 2
    local r = size / 2
    render.circle_filled(cx, cy, r, SPOTIFY_GREEN, 32)
    
    local function draw_arc(radius, thickness, offset_y, start_deg, end_deg)
        local steps = 24
        for i = 0, steps do
            local deg = start_deg + (end_deg - start_deg) * (i / steps)
            local rad = math.rad(deg)
            local px = cx + math.sin(rad) * radius
            local py = cy + offset_y + (1 - math.cos(rad)) * radius
            render.circle_filled(px, py, thickness, color(255, 255, 255, 255), 12)
        end
    end
    
    local s = size
    draw_arc(s * 0.38, s * 0.08, -s * 0.15, -55, 55)
    draw_arc(s * 0.28, s * 0.07, -s * 0.02, -50, 50)
    draw_arc(s * 0.18, s * 0.06, s * 0.11, -45, 45)
end

local wyy_icon_b64 = [[iVBORw0KGgoAAAANSUhEUgAAA5sAAAObCAYAAADda5UQAAAgAElEQVR4nOyWWXMVxxXH/z3bnTtzF+le7UICyUhABEGAkJAQQgjZYDCOwXbw8pJU+SmVh7zkS+Q9D6k85MEVUqFIsEDFrsJmMQZkFgkhJAGS0IKE1rvPPqk+l5BUnE/gcld19b0zPX1On/6f32nmrK7gp/YjaYzBNw14mRR8wwBTVPiuA3d5AV4qARbUwEQJ7soSvNUVMEUBkxW4qSS8dBJMCUBQg/CMHK3BBAEsEIRvW/BMA0IgADEUge958LIZMEmCEI6CiSJ9w9QgxHgJWCCQX0+SIMZKIITC8E0TjDEI4TDEUBhCpAD2y2mkL51F9vY1si2vWUtzxUgBxHgxxII4hFAIgqpCLCkHk2Vkv7uGTN85uIlVyFXrIFWtg1xWCbEwDggCpKISSMWlsJ6NIN13HvbsC0jlaxCorYdUVkk2pJIy2HMzSF8+C3v8KZT1GxFoaKR13OUlem487IdYXgl1WzPkijWQ4sWQy6sASYI1OgxzdIj8kaproFTX5vczPgbjwV0IegjKhgZYT0dof9wvrW0v1MZmiLEi2BNPkb7SSzHR9x8CfCD51QlYY8MIbNwMbfc+qFt30vlkb/TBejaK4PYW2m/meh+MwXvQ2/ZB/fkOZL65hNTlXoixYujtXQjubINStRbu8iLM0WGyp7xVD2t8DNlb31BM9Y5uwPdhDNwFJAXBrU3wMmla23ds6Hu6IRaVwBwegJfJQN2yjfbE9+YszEPdvA1yzXrSmvnoPlLnT8McfUw+abu7YDx+SD4Gd+xCqPMAaSV75wZS57+CMfA97TFy5GOymb19HUptHcJHjoMHInu9j2yFug5CLIhRnHN3vkVu8B7EaAF9F6hvgDU1gezNq0hfvQAvm0bkg0+htbTTudlTE9DaOqG17iUNWhPPKYbm4D2kv76Yf9/Rjeixz+AlVpG79x2Uuk0IdR+BVFYBd/EVadOZmSL/jIF+yNU1iB7/FZR16+mccvfvwnwyCDEeR+TwRwjuaKUcsGem4C69ojl8z77jIHzkY4T2vgNnZRnmwPewZ17AmZshjfJz0LveRfjwhxCjMdgzk7Bnp2FPjZOenNkpipk9PQmtvQuxL34HubYO5sgQzMcPYU0+J02HD30ItWErxdRLp+C7LsXFz6TJljP/Evbkcziv5mBPT8B49ABMD6Hw179F4edfUE7zNTkruHbchXnyl9uF60DveBuR949DqlgDj/PDtgBuw7LgWybF0U2swF3irEnCWV6En0rAWVokFjhzs7DGR6HUNyD+m98jfOgY/FwO9uwUfCNLvnq5XN7/XBZ+NvNmpN9GDn4uC8804XObnGury/n47TuAyC8+YXJldX6+Y8P3fAbPo/fwPeYD+f+80Zh/7/s+Q77n3/HffO7/NJ/Wed3/uzFGXOPj/22M+dTxeg5j3IDPmQBGI39H/2kFes58JsnEQq7V5OkTPtc5mEA5QVyWZfA5LKCCqSoEznZNh6DpYJpGHBf0MD3n+cTZzDnGtBBSPX/H0h//APPJCJSaKkilFRBCUWIu8TlWRFznLBUj0fx/PUzrc9ZDFKmO8NohxuJwFuaQOnOSclGQZMhrayFEC+k73iXOoPpNxPhkz0kk/vpnuMlVBBq2QqmugVRaTnnFuSzEisiGEC4gXzhzkqf/Rtrk73keSsVlNF+p20j5sfrln4htUkUV8ZqvyX2QSiogFMYhl5bBS64idb6HfOSxU3+2BYHN2yEWFCJ9uReJU1+SjoONzXm/auqgvLWB6gr3j8eR52Hq0hnKDV4z1B2tlHNc24mTfyHGqI1N0Jr3QKmth7u0iOTZk8j136TYcqZrTa1gQR2p3lPIXL9C+wl1vA11ewvFN/P1RaTP/RMQJXqmtewhX8h27ynyQ+86SOznZ2Q+eYT0pR74jgu9Yz+8ZBKJ0ycoh7XdncQduaYeXjJBdc2afAZtVwfVyNTFHpjDg9Ca2hDqfg/K+g3Eq+ztG8T1wKYtZIfPyfXfIkby+mIMPUD6Qg/pQ2vfTxpNXz5DOoq8/0vKW+4rZ0qo8x34toPUuX9Q3kWOfU7nmLrQA+flFDFNKq0k7nM2hd79AOrmRmSvXaE9B5t3I7ithWoR10Bw+y4Em9up3uTu3qTawVnPWWRNjkOMRqkmMzA487MwHt3Pa6e4FHrnAdIxj9m/uc71GTn6GZSqGmS/vUr3Cr2tkzTA7z3m0xHkbl+Ds7yUr6/N7YBt5WtA/y26R/AY8ZoqaOE85ybGYIw+hvHgDtz5OQSbWhE5+indEcwnQ7BGh+g7ZW0t9H0HKW68JvB7GRNEqj+c69xvriker8jRT6iecbbaL8bpPJ3FeVjPxwgrwdZOujcIQf31/W6ZcgyCSHcW4vncNLGT3yvo+4VXcF5Ow00nEWzcifDhj/Ia4Ay1DPiuR3rgtQScqXx03TwLPfdN/yES37Au3zmvhP9wg/tDHOEjE0jrTBSIbz9Y7Kf242gA/gUAAP//7JfBCgIxDEQzyUT//xcFQbwruNttJO0q3vbkLQ+GUnooTS/zWF9ZFEVR/J0sEiln9HFTykcWn5TZFBe0BrgTq1NIB3kSy5jDzMPSQkxFVSUUoGOI5POB9XrRWF5IgZ2y2fUrmz1lM/a9zJKUspllKjqkT/8bZ7k/ks3fQpRF6lA2NX7KVyDl0j6yaVNGh2zuqyKEHimO7X6L/nwEyBDYlNNvLMRsy8CswfgCuYBcQW8j7hv8tI35jnmf5/wxn1wURVEUf0VE3gAAAP//7JrLSsRAEEVvVXcyeUwyCsH//wWXfo8ICg4iDlmYdJVUJaKC29nVgaYIHUhnee7tkM0gCILgumzS5wm33VZwEiOdbiEmnNmS7sqi7gHMowKTEk0QvYPIRIobLmWEohGgRkmZj0NCKWl9esyXh/tMqWJdPlnXhbUUgq0thWeV4rKpsp3Dny2lt3dcPn/OuLebf1AVQLwl3aVUf6X2/L9s7nLpbeW3lPp0UbT/F5u07Qsxi6f/LpFZua5F1qXI+dXEsyDllap6ocRqk3O1UH2Y6dDM1LRv1HYv1PbP1PVnbrsPPg7v3PUXHsbZbrVYs2J402nfdNkM4wyCIAiuCIAvAAAA///smstKxDAUQO8jM7mporiw/v83KeLKpQoDojI2SdskkqTtiMh8QQ5kE0opNFBO72my2Wg0Go3zZElS9XNR8s0iWwS4yFvZU4qRlSBznkYaIN4BkQYiBmZGMRjdgP7xPudrmJyn+fCmk3e75IYuet9FO1wl566Ts330tk/O3oG1fRz9Td6P0ygwTZJC4BSDghgwZ8Ilvx19FckwQ55aQgqbQJYELK2ymbJsnvZX2YS0COU/Albuc7qsrHUGSnBGNqHmYZtsYk3HsMjmKp+LtGJNzbAmZ2UKrDVQd1nS2JKb0TEiYUSl5sBqxL3+zotE3lHMK4p5QZEDaf2F5uKDtBzJdJ+gxc63zxbEzP7pIURnE+5VfQ7E/BcgAtEMRBMwO2AekZVdpqRTeb853f2Vw20T6nwusrw2Go1Go/EXAPgBAAD//+ybTU7DMBBGZ8ax86O6AbFAIFhx/yuw4xhIbCohIdHAgqZpxoPGsUtBwAn8pCySjJJsv3xvStgsFAqFwu/IoqKqhkmrdRxBvwbSQKctYNrZhJjH2Mk43koIV7T7uJPDdImuvkbrPNW1p/68Cm8Dvuu+2sM9As8o+722kAQ8VxKCgXl2EtgCcyvMDSxHK4EdMLs4I4H0m45qq2qzh7RT9E11lWN796XBQrr+Yw7g/6Yvh8qMnMi2fym08T16LwDwsrYJWrZiemBSawUwnWYd90TL1WCnCqy1eV7jKgGhtsAOyDRI1IMxF2jMDRiz07CIFMPiBFGvNROQYWoabUfD/LwRHrZCvku7n9WE1o7o6ldq2i213RN1qw15/0i+f6H+bNBdfUyNqGgbq9+Vfj7EvX1tp3MzXCgUCoVCBgA+AQAA///snEFOwzAQRf+MXaOm0CpCsEFdseH+lwEJBGIFC6iTkNCE1B7khFZpG05QP8n2aCzb66/vmSg2I5FI5FTZOpbBnVThX6vSYGXAPAWzIW0mgpZ9bql5vCd1dc2SWeXbJjQlIR/E4k+tpCgWrswvnV3dSlUuN7m9k+rrxmV26aty3jUUI8Imt2hfnuHLoSs40Fc7AXc8thoNOKiqpEFAR8m9g3SQo+Gjo9WaI/eN8o9IHUt3Ob9zSuVv3te6cnBe9u/qY4bAADAiSCBIMdDO23inp32/kgE40eD5vGsY4suy32fKpa4+fL1+4tnq1RfZgzq/eFeL9I2S2TdNZ2vSykNrYT0RmpyB09Q5++mdXYX6USFjXOeOMjdg1fQOqWpDzWl0QCORSOQEAfALAAD//+ycu07DMBRA77114jycpnRgY0BC/ADfzcrPsFSqUEEwgRIndtKL7DRtCY+KFXymxE4sZTyyc4JsBgKBwH/DHR11dehcAS2W/uN9QdSaJbftBVdv16T1Jc3Lc261tOtV8np3S0gUcV2JrdYzX6muK+SmIdZ1zNZINu2cO6vYmAV3NmNjlCsagpfTzheMnWCinMgkTIRyKpUIJ2RyuPg8/YMk4on5X/FdIOirwd2OJx4/Mt6MkomDM+LxO5M14LAbi/xxeD/NhyVHuUWxK5e7irD7b7VphjLk5mGOQkiMYwUiuqJY3qAQ/p9QiKIOZdJjLBmTlMmFhpK0pzzvGMD2z09byvKGsqKiNHukTK1IFfezolxTefbiatkOV9j1wrk/uhwIBAKBPw0AvAMAAP//7J0/SwNBEMXfbLJ3l4ClWKS0sPP7fwQrKxtRRIyKYBLz50wu2d1Zmd0ziqBYpDmYHwzHNVdc93hv5qnYVBRF6TT05RjJTp0McgQzv5t+2p0kMwSRTWOLVP3hnx6kYsCCebi9uznmxWwU5rNTnk7O/XJ+FuvViJvNwD+P++HyIp/Fdx5RqkhEbEo9yS6AXJsYNT9cyr1z2e4kyrOwoOJQIq+L0L807iH+0F/fSBUycYtYrz4jxaJwKzCqGHHy3Q1N2lhWPMteqlExEu2tBjmGm+pVjqSayCPwEoRHs36/5nV9xYu32zB9fYm7ZgJbbtz43sHL9eFSrvAGkDigpsnTc2irVfbz2/ElRVEUpRsA+AAAAP//7J29qsJAEIVnN87G3as3KoKljY3lfX+w8wm0sbxgp4U/mBg3ycjsGlDwARTmawNJm8MZzidhUxAE4RtpF147SfjZZ7SNAYAddzwuQ2iAikuX8su8du5Pd+1UoZno38yyQzVfLqDa/muiBpvzyVJZ9uhWZlRexzzKA947Cu1XEVy7HDDDiE5dhW9AVccwkrw5h1XPIznv6krhI3gJcxSb5/b8Vj1Ob9vHnr160XcKRR7PsDH6Puu97Sg0I4WICs1AmXSm0vQYBox6/YL1LH63axrvuU2/6dQetXMb/dNfJ9lwlQxHB/Ye8jvZFwiPJjQ4+VqNjSAIgvBdAMAdAAD//+ydsW7CMBCG7+y4WUjFRNWlW9UXYOf16UDFMxQqSNKqQEJognOuzokgQowIgXSf9Mv2bC/2f75fLpuCIAj3QBudAUqhdyu1DsGYBypLYxdz1L1eQNscKc/QWYtU5KErttomi9c6TYY2XY7q3583KvInH669r+BvOoFiPGkuFMGJM6k6paadpjbNtP3vyC7lRctRhauBnf08w5n8l+PI4qZMvOQy3GzjeyC1TZgilnPwcnBG960B/2ggGDz7+BvarHY2jT/AuXfUekDZ+lN9xwmfTRX1SUWRs1+zmh85wBiOhSFArLyUYtXifAqCINw4APAPAAD//+ydTQrCMBCFk7RUY3/jH7gQXAmi9z+AK924VnApuBHBNiaidiIJikU9QMH5IBBeLjDD5L3BZhNBEKTOvCaYQeD2UvqdnrmnWeYlYuqLYmzOcqQWc35ZLVugpAfFyXoqCSjpG60pyFyYix7AWQ5B6zYo6byTNsHV8Rm+83mvCL/Leiz2/wL6HXj0ln48VmT6WutZ3gjIE7nvgcDxwG/73YRxnrIwnrEmz2lkPZ+cumYzjAC0ukKRl14qChZG9mxZnGy8VKz9br+037pp0HhOPjEJF0EQpHYQQh4AAAD//+ydMQ+CMBSEjyIwSQyuDu46Ofr/NxcGf4CGqMSgEi0VA21NsQIjky7vG7s2b+i7ux49NgmCIP5KV4PxrbeAY6stAM/2VGrFuVMlO08zNquS/VxesrUSxao+HRblNh6r/Obr1xOqeEAJAVUK6EoC0oo/bqeOtp2PgQ83oNsnhtC3RHcMVkYbtLF1QxYc9WeJEkEj0hLL9qdcmwFtsqHhBG4YGtvtVfF7LrNzDI0N84MpvFEq06M5r818gLkmB1q36mfTH9qbK1qKEARB/B4AbwAAAP//7J2/DoIwEMavBZMWLQRkIDEuDs4uvrKrb2J8AKKJo9GIiAhoqTnqnzfQ5X5Jh443XNLmu+87+mwSBEH8A1RjcIxRCHDCqPOpoWetLUtXZ8cJl/0ZE2LKpZcw6Zn7bsPy5cLhKlD6fAp1no1NVSU6z4bmWmAyLAD6K++NDfHR3wRS8xmNfY1A4sXQ+5v4MZ91LMYqkW8rZmuPqbEtSru7FXOtLjm0WR/YYR8x11WNTHtceKNK+XPmBwXU9a3ZpqiCPrjyb1x6Gz7wV04Qrp0wbnkUd8qn7S9pa6VdoARBEL8DAJ4AAAD//+ydsQrCMBRFXxqLVFScFIVO/oCLn+Dv+xGxVYqitmmXJi+RJEQnXURweAfekD3Lzc19l8QmQRDEr2HP1n6XhBx4n9H1WhrjvrkmqjwkfDIDdRQjdSrXeK42eL/uTNtuwdqFK/bXhQAphBeRjMdMZczdsZfj5M4+S0lKkvgz4n2N25PTD9lQg2DaBoysQwuphRSszf04narBu/JsPIV0lQNo3WN92+OlWqosG1qNRdLJDuaL3rQNQ1mHBCnn4RkmuKD4viSVIAiC+BoAeAAAAP//7J29CsJAEAY3u1Ewep4XC8FaUHxw3ykQsBEiiOaHGEHdnFyiprDVQtiBfYQrPuZgZGwKgiD8gqZliYBqDGSmYJEsaa05VysMhiuahLO6KoNrHA2K84aAa+TTocdZGtZFPuc8XdiqnHGePTMVLlcBrbGk9jxnKtG22RG3Yz3ohqf9/PIoCH+Bs55vA/o66EzovT23HtG/AKdHZ0P7XGTrWxz5qCdLHKoClb6SCdnzfb7tE9cKLcmYBEdqS9pEZKY715pt3okYT0EQhO8DAA8AAAD//+zdPQvCMBAG4GstHYqtUPEXuDl37J93ENxEBxc3RVD6kbYuhuRykpSKQydxknvGzFkuufeOi03GGPutfpbrJPBBKR9F7enbNdSiTnVVrLARuXl0OSAuScrkedxPzXYNpmn6nKVtIRzWTQzTNt1vZegybYz9NXff+12xY08lY2e22MS6BDhTQmQy8LzMRZ9t7jOKwJ+lNv9pgvmigjg+YSt2urhvSMkDdu0FiLSbdvsuaeGjCZ0xxtjXAOAFAAD//+zdvQrCMBDA8ctFqFZqq/ixKjo4+gq+uJujIIKLFBRBEFRsG9tqaxJJK7i46Hy/MU+QcOH+9NgkhJB/mEkILxuXJmzPa3axmAdkztBxR5V2d5If9uNkPrOy9bKiktiWl3NPimioYzFQ99QzW2FleAUVhaDS7HPFxbJdycz9lyMw5DSlJOQbrcvmqyqXYenn+8xMR1MBSghgIgJ0XFRR0Hmejhbu/Gbmb/qsWp3mWz/Q2UNyp6GYZd3Qrq+w4S641zqaHwmm9WkULVtqfhJCyG8A4AUAAP//7N0xDsIwDAXQn6gIhYGFhStwBwYOwHm5AhMDp0AC2kJpq4JkG7kgFhjo/p/kNVuGL8cxwyYR0TCv1Of7LkWCr3Kwpo7atSr5aSZFPtfqugTCWm/VqtvvkhwPMDGEUfYdGt97R2Ji25JoMO/6ewj0+jUD6kSgZd4XgGlfqovPq4GU4HPR9rgX2tQbvZRjKc5bmLUhy+qYJn7Pzc9BjP7rrXHWk4joDwCeAAAA///s3b0OgjAUBeBrC0ZBgYC4upA4+QT6/C66OBl/EycFMaj8CaHVWGAw0cn1fm/RnJ578LGJEEK/1BuXsgxUN4BaNlDvpJCuPqSm5fA0HSSzaTNbL2UWhcDOrsrjUGMX32G3YFS4xzbzPWCBOHECpFWI1FKcCSL1h9uGWDv5nGlACP2t6nuKlJNX3U9e9p7LBLSaW5EkYPcrwGFv8jia5LuVKi3mY6LpOe31M9rROIvD9PlIYmrZ777nlhrmhiiquHT7/uKOiSdCCH0BAC8AAAD//+zdsQrCMBAG4EtCiwiWgnaTKj6Dq4uv7uJLFHRwkqZNSmmkvZwEqx3E1em+/cbAXcL94WGTMcZ+Gf+lpGEAbCxgpTNszI4e3RGkPGB537fXYo6VjtEY6VsbUjFD4ymASLzrVcavloz93SetWb5CtUZf1zmIgLoM5xvgUmxAilxEMYlZ2PdMQS3SQS1XViWJjtbbs3fuhLYm79wNTd1R30/71YwxxiYA8AQAAP//7J3BCoJAEIZHR4oKctWkRwjCd+/WpVtP0CmIig4RyKaWGWTpasya7xA4H8wLLAzM8s/8P382GYbpLj/lg1boyDXWsCxA4erMyuqRChzbATlbljKcPJcLMIcjWyWRX8pwrrJ0piLpqXsCVHVOGZfNS2rlks4saa0PrWYQ1SMuKx8M83e0d586pxYMUNSsbwDMwIivoPoDNF3XR+H4Ko565nE3/ey3wWu9utVVlReXc42Od0LH26AtDtp9uigaxbN102UYhukiAPAFAAD//+zcMQrCQBAF0L9uNGCjiAhCSGVjZeMFLKw9pwext7FScgFRBDcT1OyMDIgIFrZC5h1hi2U/82ctbBpjmus1+ZBYQyoCen1wGcAURlLRVIRXrt1Z3ovD5LbbgkNwSkclItJ6h1WfwHX9j2O0B6cxf+lj7/Prx2e9H7hG1NB5Osqj2OdwLoNgoX1cPxhyMs44nc03iLxmKi8crmchYm1EWDXeGNNoAJ4AAAD//+zdzQqCQBDA8RlX/MwMugRGdOrUNXr4Tr1GB4lCKlczwoLMnY1S6R1qfg+w9+U/w/BnkzH2P9rCgJbdlExhToygP1PpcXxbr1xAtNVZQi1PQ7oU0fOwX9S5nKs8BSULoLKtlVZbLsV31BZ555Kx39HVyHft7HY+CZAUCCAQn5u3FQCVCWhFgLazpEyqKt5MzVFUAulHney04flXEYSZ4flbEQ5idHt3dJzmbc3XVRhjPw4AXgAAAP//7N07CgJBDAbgPzOrsA9kEAQvopWNrde2FVywEixsRGwEtdkdMxMZ8IVHWPMdIF1CQgjRYVMp9X9SA+m9AzAlooXf7ybNZu34dBzEyxnxdqXIbMHcg0SREMiUfZji2YDqQKlUt71yPG07vw4+35kvn1qQ3hc19aoCMKc8n5miEuuG0ZSF2NH4QDbbCt+XsW0zMlkNDr/RlFKqmwA8AAAA///s3UsKwjAQBuCZJGra2tZSxJW4ceHOjRd36UFEqPjAgoK2ulGKSU0lLeIdynwHyDrJPw96bBJC2sNeAG1JXE82e/HssNcgtLvyhiidGfP8MQoRqH0inqtlBMbM9emw0Od08skzKPNb3XsJNrVgTXJZJ5mC0wAQQsjfr4rB2I8rDUZVHBTwCl4SeQbMv4CIYzBFEZnHfaSza1ymxyk67k4lmzd2uoqH0ZZ5/TULBjm6LqB0mjMp8SSEtAUAfAEAAP//7N0xCgIxEAXQn8m6cdfKXsETCFaCp/Ce9t7C0sLCwhMoqxZiJiMJi1h4guW/OgfIH5g/DJtENCz9uZLyYctNPXlvSnWJlLao6w28n71OR/++nAWqI0spQNVyg2wuCHITD7Q/+5UMmET0TxluCVwlcN6Apn9Tgiigtyu06wwiUyeyfsJWLjRRmtaq+eIhYbw31R00HhD1/j2fUhrGiIgGAMAHAAD//+zdSwrCMBAG4ElabINtVegBBMEDCO7cev+VCxUKrQZL3WgpNrZ5SKKCW5eF+Q4RMpnMP1hsIoSG69vJDBnQKLFhHXNZ8kWXHWZGtEyL1ut5MZYXvpLnfKOqcmmEAF03oK6N27lHgs/spUuQpe+dlxQvewihP/w+Stl0Wxs65uY8DTEKfFDg6wcw4t/BSwP7+yJ97ndb3dSjnhdrGsW3Ljv2QEhHk0lFQ3aiUZx7yVTYfZ7uTNLY8UQIDQwAvAAAAP//7N2xCsJADAbgJCi99rgOurv5EL6Dm+/bQZw76OYoFKV01FKud0a0Ijo7Ff5vzy1ZEkJyaDYBYMR+JpAzTrOVhrju9uWy3RXzUJ+T0NSi7c1o36fqvWoMLGZKZHQI/y4SMcUEgH+9rttOhr89n9eq38+JvX/2NEN1onipFt0h2bB1XlweJTEqLr9KZksi2hJzQUxH5AMARouIHgAAAP//7N2xCsIwEAbg37TSSmOHFmIV7OBLOPj+k4uTOBQ3KZSiRsEabBJJi9AXEDrcB3mCwMHlJ3fUbBJCxs8lmG7ia5dgzsEi7k3CWc54vNEPuXgf9jDytjbXequK064tL6Ktym5Ru2nQJ5jT3xnsvaTekhDyT8MHLOb3tUxrGKXcNNvAagSwFVgIeEkCP1vBGp2ap0y1vOeNyM66rl5WKeWJZcEifmQ8/ri0s/vj6WqZbekKCSHjBOALAAD//xrtbI6CUTAKBj+ALZcFdTjBMwbMIozMLNZM3Lx+/398N/12dB/D9yP7WP//+c31/89vbtCF6gx//4AvVWdmgS49Y4QSo7OXo2AUjIKBALATbEHlGCsrAyML0soMJiaG/z+/M/x++pDhz8tn/L9YWMwZjh3UY2Bl+8UiKPyPRUr6IxMv31oGVtZ3jMzMj0FaGGGHloHNHb3HdxSMglEwCAEDAwMAAAD//+zduw7CIBQG4COkiQSjt4EAACAASURBVGgopouX+CKOPr+Dg0NHDbHGGuOgBizlYsAOPgLD+SYegcPl/3HYRAjlIW6Y4pMzSoGwye8GM57eM7YivFwHpeZ6v6O9PPH+2iy7+rCxbbP1r6dw7S11YKbuy/GQrxHXBFNkEUIZ+u/kHULNfAwz0xqCgwIsCK9ABAdQLC7pD2jHZ8apt7PyWBNRjdzjboJWHyKqM5mWMhirYlULDp8IoWwAwJe9u0lBGIihAPwyP3ZaGKTWrQt3XkC8gUfxhIILwYsIguJKFKsdKCqdkbEKHqGLfJtcIY+EhMMmY6w7fuuyugdIFaulxEyl7c+fh93MbVapd3ftb6VuyqsNjzqL62hkFIT2be9Gf+GSwL/sGGPd9g2eFGv86xknnkkApb7NjELgddyjuZwmSMxC5UUtB0PIvKjImLMajdcizZbeVdvPgbMQOGsyxroBwBsAAP//7N1NCsIwEAXglzSItT+6EkvBgwie3Z1LDyBIi1QEa6kV20XSNJIWxRMownyb3GBg8vIILZuEkN/4SDJt94gJx+HhLNK3Mq63m5CBTWWWzuVhv9LXy1odk2V7ztDmBYwaVkg2sh3MIb2035YQQsjfel+SDWdfGehTzxbdvYLOq6BTCJRIwX0BEcUQixjgjm+aJjT1Y6fLomMTr+Kul7Cxe7KvQ4yU/Zx9zVxCCPkaAE8AAAD//+zdMQ5BQRAG4NnBznsUm6dWU4gDuIHeJbWOodJSaF7yWpq1nrW7IzZIXIBE5jvFZPLP/DKdCSF+iPMmH4kekVnTqYZzf9gt2u1mHJq6ihfXY2sNh5tJ1xbAe0DqAuvnh8dXFE1iskKIf/Nx46lyl6fi9K5niqcjpLPl0NQzp2mEmpbMzDSZ7rE/WGFRrlVRRiSXkyJCCPF1AHAHAAD//xotfUbBKBgFdAKwhhMz6OAeVkYuLklGDi6xv2/f8H07fRS0v1Lj582rdj+vXnD6ce2S6J8nHyDn+YCuD2CBnCQLbnRB8WgHcxSMglEwMgB0QA20D52BGXqP51+G/18+g07aZvzzk0Hg3w8GASYeBgZmUSEGZhEx1Z83rvxmZGLiYnlw7z3D379f/7599ZuJk+stEzfPc0Z2jo+MsM7n6EznKBgFo4CWgIGBAQAAAP//Gu1sjoJRMAroA/5D75xjYQEtmxVgZmO3Z+bhc/795KHm72eP///79IH37/v3gn/fveb///MHAxMvdLsleOaSCbKfCW2Z2SgYBaNgFIw4AD2ZG14OsvxlYAbdG8wCOdH2153r7L+fPHT4cfmsDhO/4G8WIdFvDKysn9gUVE4yCQhtBd/jyco6epDQKBgFo4D2gIGBAQAAAP//7Ny7CsJAEAXQOzE760YEU2ggIvgrVn6+hW1Ai2DiItiI5LGrkpjCwjLlnF+Yau48pNkUQoxrSMr7W0zWIO+IlFoQ64TCMPY3G9fHwxbA3l2LXXPK5s5e4O9P0HuYZHYrY8xSGCGE+OcnfOsbT0X9R1u0Dby1watG2mbntNsKUckSk3TTBXbrykQRGbNyRf4g5orMLCfWJekpELTf207IxFMIMRIAHwAAAP//7N0xCsIwGAXglz+QaFJFF0cRN0/g6uruFT2A53DxBEJB6KiDCSJtKg3t7tDxffDfIS9/wmPYJKJxDWHT2FxfAq2tmvqd+OKojN1/y/s8hbdDm1YpBpe6p2B1A5n0B6d+k0lERH/qu4gByV8ORIZ+YYUUA9pHifh6bj+360mcP6Smqc16U+nF8izF7JIvBo0FugHDJhGNBMAPAAD//+zdsQ6CQAwG4L8USeAiDsQ3YHH3KXxxJycHBxM3FSTnIBFO4E7j6eAsa7+naNP+rTSbQohxfieZkwiUqAzMWV8cVbtZs6tv+WO3XVp9WT37bmGvGvas/fYWveuakPzBC58hkvVYIYT4H32C7v7H8Pf6rDMGaBoMpU7dHWkQI+f5DDxN0R32bRArM1SFBofOlidDzDUlSlMUNZLtFEKMAuAFAAD//xrtbI6CUTAKKAOwziYHJwMTHz8Di4i4IRMnl8fP65fVf1y9yPH3zWu+v29eCv59+1rq39fPoCtOGBgY/0KsZGaCnKw4eqLsKBgFo2AUUBcgL7MFl7H/GJiZ/oMPGvr/6yfDrzs3GUBbGb6fO6XMIir+k1lM/AcTJ/czFhGx8yxikruZ+ARvM3JyQvSOdjZHwSgYBeQABgYGAAAAAP//7N2xCsJAEATQWfX0YidCqsRCBMFfEfxrCxtbERvFBBUCR1BBvUuQi4qWWtjNa+4PFgZudhk2ieg3fptsQwFl4V8RrUOIhDbZyGU+i1x2GNt9OrmtFpFNtyhN7jcmVj9jpVV/dIJevSAiIvqfz26nn7vNZ3B0zgdNlOtdDFnGtUCqu52q1z/p4Whw7XSDwmRTlyY5gLMEbSNKHd+zm+GTiL4A4A4AAP//Gu1sjoJRMAqIA6DDJ5iYGJg4ORkYWVnBmIlfgIlZSNSZgYkp+Nu5E+w/Lp/n/vf1s8zfzx9F/338wMDw4zvkwB8QZhrdizkKRsEoGAUDCmAzlOCrVJgYmDj+wYX+fXzP8PveLe5/717r/Lx2iZ9ZSMSVSVDkBaukzHVWCamdTAJCF5i4uMH1AMO/0c7mKBgFo4AIwMDAAAAAAP//7N09CsJAEAXgtxuJq5IuR1AvYOM1BC8uiKAWikUIQsCIGpLsTmSIrdYW77vCVG9/5jFsEtEP5nOTqXUlzkJk4vMs6SQkWibe7LdTf83XUt5W9WGHULyAANixBsx+Pb+GUj6RJSL6I1qfov8xo75hSg8Tpaogj6dpszztaqTWAfFs3mGx3DSnYyy+HbWXc4Hggxm6u4kGJaxtOFYi+grAGwAA///s3TEKAjEQBdCfZO1clRVEwcpKsLWw8hRe1kpLK608wIKSYNTCxoUdEjEiFnoB4b8rTPWZzwzDJhH9EF81WaNhmjl03kY2GEKcnVT73VxWbirOZnIsW3I+jeXqgbpOVxDR+ARNhkwioj+QfncqRDwPtr23n4B4p+7bzUjsYaGL7kwZU8UQb6bXX5tOsdQX71K1NgROmYi+AXgAAAD//+zdsQrCQAwG4OSuvWKHgoMIugju9w7uPrmrilZFh1JFXOQoxYtahbNDX0H4v7dI8idBsQkAHRwiUqxj4qRHTV2nUpwyFZm+FMexHLYzn6/mfrO0z0tJn+oRNnc4UWEfSKX4jQkA8He6V2zD66pf5LapHMndZZLvLCXKxsMRRZMpvW/Xgd+v6XUuFyQibIxjrdtJJ5qMANAioi8AAAD//+zdTQrCQAwF4AdxWQU7uFKEXqHHkN7UO7jRhSsPIChuRLH+ILRQ22kiM95C3neJJJCXcNgkol+ORzVeipVkBEkdBtM5/OOe1ZtV0R33ub9dk/5ynvlnmYX3JdY2saeIMUz2FkRE/ydsqIjGeAS8on+/YKcDqrrKZbcdAlhY+1Fxk7WM3dJEylBHrOl4wZaIAABfAAAA///s3DEKwkAUBNAJy0dFENuAaO89vEauKhaClaWNCIoatBEibLKbNX9FBfEMZt4ZpplihmWTqO1ebdGYJBHpaGV7IT+KOtcP13xQbzczu5xnbr2aqq2+r7KQz44TwsMfIqK/9LPrfIsR0Ts8LmeEwymNDVIz7EJGE+i9GNf73U1Lu1DvAREPY0o06hgOohYD8AQAAP//Gu1sjoJRMBIBbCaTlY2BWUCAgYmX9z+LhLTKj2sXrL4e3q3y7+MHiT9vXrH/enBX4c+TBwr/v32HjGzDZzH/j05njoJRMApGwUgF0FUt/3/+ZPj79jXD99PHNP88fZTCyM7h/u/zRwZWFY2LzEIi+/59/XYJdEjc/+/fR2c6R8EoGImAgYEBAAAA//8a7WyOglEw0gD4yHtmBgYWVqb/P76x/378kOP/z+9Kf96+dvz94K7fzzs3DX7fv8X79+NHhv+/QEtrQft3QHs4RzuXo2AUjIJRMGIB0r5ORljrEXSK7aePDD8unxP8cfmcM7OgEPi+ThZp2Qt/nj9l//ft2/9/P368ZWRh+cbAxPyNgZFx9PTaUTAKRhJgYGAAAAAA//8a7WyOglEwEgBoRPn/PwZGNjYGZn4BBkYOLgZWKRmWH9cvm3/ets7u96N7Gn9evVL4/eS++p83r3j/fnjP8B+lSTA6kzkKRsEoGAWjAA2AOqDglTIMDP//MjD8+/yJ4Q8zC8OPC2dU/jx+GMDAyKjz982rb2yqmneYhUQ2M/MJ3GBkYwfXR6MznaNgFIwAwMDAAAAAAP//7N09CgIxEAXgt5NEEQTZzkqw8A57C1tva+MNRESwFxd310YTY2JkMbUH0PddYnjD/DBsEv0DEYEonazV4XwSDIZl7NqZP+yWt8165ffbacqFv393UmiDwjBcEhHRF3lSpr9G/tmwSHhdWzwu9dgFVDIylZqUSPPFMTa1Q/BNsncHUREiAcAzdzOJ6BcBeAMAAP//Gu1sjoJRMBwBdNSYkZ2DgVlQmIHlxzdmZhFxwz9PHhl93rlJ5u/7t8J/Xz4T+HnzqvbvR/cl/n3/D96PCVoa9Z/xHwMjI/Tgn9F7MkfBKBgFo2AUEAtAhwj9h5xe+/8PaE/nb4Z/X78w/LpzXfHL39+hTAKCan/fvP7DJCj8hEVI9CgTv8AJyEzn/9GZzlEwCoYjYGBgAAAAAP//7N29DcIwEAXgd3YQcgGWKNiBjgWyAGJ/AXJQCgoEogAFDHaMkWEEuuh9A1xzzf0Uj8sm0RCVrDSlJPuH7k9HnS7n5fverV5us46tW8S2MWUAyCFARhXUlPmYRET0p5LTXC6XBtDmVyr3AXG/07HZ1srauprNMZ5Yl25Xm4EuP/0BIh7y/XQmtoBoQAB8AAAA//8a7WyOglEwHABsCSw7BwMTvyCY/vv+3f/fD++Z/7h01vbX/Vuav5891vp197bmn1cvOP+9/wAedQafLsv0l4GRafQKk1EwCkbBKBgFNACgScs/f8DnAPz/+w68v5Ph1jXlvx8+eDLx8Un8e//uI7OI2BNmEdFdzAJC1xk5OOHnDIyCUTAKhjhgYGAAAAAA//8a7WyOglEwHABkuSvj/x/fGf+9f8v4/89vjn+fP8v/uHTO/9vRvYk/b10TAS1t+v/7D7hjycjJNnrczygYBaNgFIwC2gNQncPGxsAIXUADXlZ78yrjz0sXTZh4uEyYRcQYOASF7v3/+uXf33dv7v3//u0P5ORbpn+j+zlHwSgY4oCBgQEAAAD//xrtbI6CUTCUAXRGk5mPH3TKrOSfF88Mf16/CJq9FPj98L7wj8vnLH/duyXy9/0PBgYW6EwmC2hPJgvkkrRRMApGwSgYBaOAXuDfPwbwYXS//zL8+wGavPzGwMD0huHXvVtKX3ZtDmSVlBb5+/bNfyYu7mcsohLHmAUErzBxckEc9290pnMUjIIhBxgYGAAAAAD//xrtbI6CUTCUAewAHyZGqX/fv5v/eng3+NvpYy6/7twQ+ff+LcO/b1+ZQCfLMvGP7skcBaNgFIyCUTDAALynkwF8gi0zB8Qp/3/+YPh1+zrD77u37JkFBG2ZhcUZ2TW1r/7//Zvz76ePT/79+P4BrHB0u8coGAVDDzAwMAAAAAD//xrtbI6CUTCUAHQPC2ikF3ScPLOgsBEjK7vt74f3pP59/aL858VTk1/3bov/efWSgeEn9GpMzl/gq0xGwSgYBaNgFIyCQQPAd3T+g8x2fv/B8O8XA9O/r1+Z/v34wcDIwqTz/9evAJYr0sIMf/++ZOTgfMwiJn6OWUDwCXimE6R3dKZzFIyCwQ8YGBgAAAAA//8a7WyOglEwlAB0JvPfr58M/7594WX499+L4d+/3J+3r/P/v3ia6f+PH8wMLCwMTOxsDAzsozE7CkbBKBgFo2CQAvA2EEYGUJ0F3tkBrbP+ffnE8OP6FcYfly/YMPELWLArqrzmMLE8w/D/P9u/b1/X/fv18x9YL9PoyQOjYBQMesDAwAAAAAD//+zdvQrCUAwF4MSbS0WHavFvcXFz9i18eJfiICJ26ODPqhVvexsJfYkK53uJkBzCwbIJ0Gd2uWWmwWhMbpKRmy23LH73zQ9ZXVzScD3vm1u5sBLt9hVIo6WeDbFIN4jtLxPdZQAA8A8s5YyRKAZuK5L4fgqrrjkZJlbg6U/HjYb6zuJLma9yl04f+qm6WYekE6B/iOgHAAD//xrtbI6CUTCYAXQm8//v36B9LTyMzMxO///8Tvh26ojy39cvWf5++sjG8A9yLRkTDxukY8mINNo72tEcBaNgFIyCUTBUAGhPJ2hvJisDAzM7pD77+/kjw/cLp4V/3r7uxSIu4coip/SAQ0XzFAMzC/O/Xz93Mfz5Azm0lnF0pnMUjIJBBxgYGAAAAAD//xrtbI6CUTCYAGj/ChMTeE8mIzc3A7OouATD/bta38+dkPh+5pjc76dPnX/du2Xy++Fdhj+vPoLvK2PkZIDOZDJB8GgHcxSMglEwCkbBUAdMkNnK/79+M/z7/pv57/svnH/fveb8++GDHsPXrzz/fv1g+3nnhiabtNx5Jj6BUyxikj+YefkZ/v/+NVoXjoJRMFgAAwMDAAAA//8a7WyOglEwqAAjuIL8/+8vA+Pff0yM7JzG/79/C/127qTRz9vXpP//+M3ByMLw7/+fP0xMvKMzmaNgFIyCUTAKhimA1m+M7KwMjP+hK31AM52vnv//9uGtzPcr5wNZxCW9uWyc1vDYu71mZOe4Dl5KC8KjdeEoGAWDAzAwMAAAAAD//xrtbI6CUTAYAKhiZGZmYOIXBOVJpR9Xziv9ffNa9feDu2Y/r120/3nriuzvBx/BfVFmPtBdmUwMjMzMo8uGRsEoGAWjYBQMc8AIOVkdNBD79y/D/19/Gf9//sn2/89ntj9vXoHqQVeGX78+/X7+7BqLiCgDq7TcdSZu7gvMAsI/GZlZRjueo2AUDCRgYGAAAAAA//8a7WyOglEwWADoICBObsl/3746/Dx30uv72RNmf1895/z3/h3X/5/fGVhEmaGVLuNoJ3MUjIJRMApGwcgCoFlO0CArB/SuTvA+TSaG3/dvS39+8Szx+5njP1nlFf9w2bqs4jK2eMPIyXUXcjfnaGdzFIyCAQMMDAwAAAAA//8a7WyOglEwEAB8bDszAyMHJwMjEzMHEw+vwf9fvzR/3bkh8+vBbaufNy5b/7x+hff/tz+Q/iUrAwMjGzt8dHcUjIJRMApGwSgYkQA+2Aq6a/Mvw98Pv9j/vPzK/vvVK4bfzx8z/Pv2zevP08c/mPgEzv3/8eM9s7zSPSZevseMbBzgFUSjdegoGAV0BAwMDAAAAAD//xrtbI6CUUB38B86IssAHqVlZGGVYeLkjvn/9YvPt1NH2P5//8r179dPTrAcNyNUPZQerSNHwSgYBaNgFIwCCGBiZmDiZGRg4IQcKPT/21eG76ePKv24cC6VVUnpGYeW3g0mXr71jKzsbxmZmb8xwuvS0cp0FIwCugAGBgYAAAAA///s3T0KwkAQBeDJDP4ENAZBSZVUuYC38OQ2HiCFVRRMIYjRZLMSZ2VRbKy1et8lhsdjZhA2AX7Nuc9Opm8yeRIJR3HeH8rMbDcj15nVfVesH+dT1ldH0sa3mEQ8ltdFPf8/DAAAAL7xe0aqkpqW9EahmjrU9pIEzKnEc9FrvZRFUjhr9zydlcFgaBE4Af6AiJ4AAAD//xrtbI6CUUAP8P8/AyMjEwMjKxvoWhMhJl5+97/v3/r/2rVZ+PfLp4L/Pr4X+ffpI/gKEyY+kNrRvZmjYBSMglEwCkYB0QB0RycjKwMT318GJp7/4M7nz5tX+f6+e+38/dQRUw5d46vsOobbmXj5tzCysj0GGzva4RwFo4C2gIGBAQAAAP//Gu1sjoJRQEsA6mSyczAw8Qkw/Pv6WfTHmaNqP29fN/t544r/r7s37X8/uMvw5/UnBgYW0GwmI2j/JuQAhFEwCkbBKBgFo2AUkAZAhwixsEK0/PrF8PfrB7a/bz+I/Ga9LfL3/Vu5vx/ecTLx8vP/+/r5Aaug0F0mbp4bjBycnxlhezlHO5+jYBRQFzAwMAAAAAD//xrtbI6CUUAr8B+yN5ORnZ2BWUCQ4e+71zpfdm1O/3bykPG/Tx9F/r5/D64MGbmZIROYoOWyozOZo2AUjIJRMApGAfkA1mFkYWFgZPoHr1//PHvM9PXdOyMmfgElJk7OH+zq2ocZuXgmM7GzXwUfHDR6KMIoGAXUBwwMDAAAAAD//xrtbI6CUUAtAB0VBR/sA5rN5ObmZeTkVvz76YPIj0vnOP88f+z17cBO3+9XbnGBt2GCZjNZQUe5s4x2MkfBKBgFo2AUjAJqAthVKeC6+R/D3w+fmf59/yzExP1CiEVCguH3k4eC308efvlHSnbv33dvvzJx8bxk4uZ5wcjO/gd0yi0YjM50joJRQBlgYGAAAAAA//8a7WyOglFAbcDCysDExc3AxC8gz8THn/Dr3k3rz/duMf999Vz07/t37EzgE2Yh+zEZmUZnM0fBKBgFo2AUjAKaAXAdywQ5eI/lL3i7CuiMhO8XTgn9fvQgilVB2Y5VROweh4HZbiYBoZ0MjEzvQfU4bHXSKBgFo4ACwMDAAAAAAP//7N0xCsJAEAXQvzFhcRe0UMHKKinSeQ5bb2xl4RnckEkTEC0EFdZRWfEEKaz+u8TwGWY+wybRYL8hlO4s0+Mf52HGzuupX972u3nsZBO7ZvtswypKA72+kfl0m1kwYBIREf1LmrnfqrEcUMXrcYe2YuNRyiihtFW9Ns5PUORTW9WH0WwRMufOxqZOlQs3nERDAfgAAAD//xrtbI6CUUAu+A89AIiVlYGRmYmBWViUgVlQSPbb9UveP65ccPh1/7Eaw+9PYn8/fQRXckw8fyBLekY7mqNgFIyCUTAKRgH9AajTyAjdvsIEupIMcl3Kz9vXef5++mD9/dxJVU4j8+s8noHTWKVlDzPx8DEw/H86OsM5CkYBuYCBgQEAAAD//+zdMQoCMRAF0JmsTlistEvnAUQLKw/hoa0EGzvB2iKSXRdFlEQmrBC8gDY2/11i+B8+g7AJ8CMWKdvMfO0m2gan/jRNx8M87nfrx3azUp+pGhOxNSWMslgcLAAAgH/6vBUrta8x1KdEeo+DHDpHTE6b84xFvF0sn/nSvFjkxvUo8FBijy0nwHeI6A0AAP//Gu1sjoJRQCr49w9c0TDx8DOwCAox/H7+VP/7mePRP6+eV//z9LHAr3u3pUGVGLMAA3iPCHhfJrhaG62cRsEoGAWjYBSMgkEDYIcIsf+FHiTEwPDn1Qvmz9vX+fy4flmTmV/gNbu6zikWUfFNjMzMj0ADzGAw2tkcBaOAOMDAwAAAAAD//xrtbI6CUUAsAF0YDTpKnZMLtEeT8++Hd8I/rlyQ/nHpbNDXw3ujft28zPnv61cGht8MDIwcLAxMPGyjQTsKRsEoGAWjYBQMZgCq28GDwqDB5L8M/z5+YPjx4oPqr7u3VdlU1P8xcfEo/Lh8jvH/z5/7mXn5XjKysL6GdzpHwSgYBfgBAwMDAAAA//8a7WyOglFACIBmMkH1ERsHAwM7GwOLuATD72ePJX9cOOn188YV15+3b2j+ffeaE7QUB7w8h5VhdF/mKBgFo2AUjIJRMNQA6F4y0NEK7H8Z/v/9y/D76SOmb8f2a/28dS2eXV3bnsfRcwmbivoGJkFhBobH9+Htg1EwCkYBDsDAwAAAAAD//xrtbI6CUUAAgPZagg4T+PP+jcC/H9+E/jx7Kv3r3k2D72eOh307edjm75sfDEw8DJB9maN3Zo6CUTAKRsEoGAVDE8CW1YLwv38Mf99/ZPj77qPw/99XhX/evGrM8J/hG/efXy//fnj3koGJ6TsjO8dHRmaWbwywmdFRMApGASpgYGAAAAAA//8a7WyOglGAC4BGLBkZGZiFRECnzDL8enTP+Nvxw2E/b16R+f3ovsjve3eU///+zcAIWk3DxAgZER0Fo2AUjIJRMApGwdAHoI4nCyMDw7//DAz/GMB3c347tt/2z5sXgsx8/M9YxKWusohL7mDiF7wF9itooHl0pnMUjAJUwMDAAAAAAP//Gu1sjoJRgAMwsrGBpig5/r57zfvn2UPJ76dPBH7ZuzXl561rTP8+fQNXPkxcLAyMXKN7M0fBKBgFo2AUjIJhBcCdTVawjxhZ/jEw/PnD8OPqFYVfD+8osCuq/OMwsjj9+9F9ZiZe/v8sIuKvGRgYPoBOqR8Fo2AUIAEGBgYAAAAA//8a7WyOglGADsAzmkygGc3/oIMBvp876fr91BG73/cf6fx5/Zjp/48fDAxMoGWzo3szR8EoGAWjYBSMgmEPGCEnyoMWMIHOZ/j19DHT/38Man9evohgu37JlMfBcxW7pu4GZhFxyGFDozOco2AUQAADAwMAAAD//+zdMQqDQBQE0NmvGwsLsfYcsclJvKra5AwhEGwUhNRarIugu6LiKZx3ic8vZobPJtFlPyYiClrHgE/8ZLKl717mXRemKp/OAkF65jn2VloiIiK6gWubM3ocsyfrMMINYzo33zz8fXLlsEJUC5E/vJ9VqC2ObnqimwOwAQAA//8abTGPglEAGoFkYmJg4uYF1Sj/WUTEbBiZmLx/XLso+f/nT+mft2+oMYBPox3xITUKRsEoGAWjYBSMeAA+ogF05fav/wx/37xi+Hpwl/XvV8/Z2NU0bzLy8F1kFhI5+ufVixcM/0dnOEfBCAcMDAwAAAAA//8a7WyOglEAmqX894/575uXXH9evVD88+5N4N9PH5J/3rrG/Pf1S4Z/f/9B78wEXeI8umx2FIyCUTAKRsEoGLEANMPJChl9ZgQNVv/+zfDj8gXFn3duKP4xNn/BbmRx6P/PH2wM//4dY2BmecPAyPiNgZHx/2iCGQUjEjAwMAAAAAD//xrtbI6CiXsPfgAAIABJREFUkQtAlQQzCwOLmAQDIzs71/fzJ/2/Hdvv/uv+HdPfTx4y//34nuH/n39I2zJHO5qjYBSMglEwCkbBKEAC//9DJjC//2D4efu6xN/v382ZWFkFGFlYnJkFhbcwC4psYOTkhF+nAhm4HgWjYIQABgYGgEY7m6NgZAJG0J0mzCwM//6y/fv2lfH3/TsWX/Ztj/6yY6PHvy9fGBhZmMCdS0aO0bWzo2AUjIJRMApGwSjAAqD3azJxMYM7kX9fvWL48/KVPLMAnzybvDLDvy+fOf88f3KXiV/gLsOfP78ZmJn/gLbrjAblKBgxgIGBAQAAAP//Gu1sjoKRAf7/B48oMjKzgCsHFmHR/6wS0pq/7960+Xb8kNTfVy80f1y7aPT38xcGhj+gmuMfAyMT82jiGAWjYBSMglEwCkYBYQDrQv5lYPj/9QvDn5fPGb6fOGT17/27YnYdgxPMouIHWUTFr/9582p0hnMUjBzAwMAAAAAA//8a7WyOgpEBQGthmZkZ/v/5zfj/1y+WP6+ey/z7+sXtz+tXkd8vntH4/eAOF+jiZiYOyElzo1eajIJRMApGwSgYBaOAaAA9rZaRHbRN5y/D37evGb6dOqLw8/plBc7nT7W5rB1YGDk4fzL8+/eagZn5G2jH52iPcxQMe8DAwAAAAAD//xrtbI6C4Q1gM5ps7Aws4pIgAfZvxw74fz991PbXvVsGP69f1vzz/Ann/2//GRhYGBgYWUc7mqNgFIyCUTAKRsEooAz8B81efv/J8OfnK4YfF05p/f30MZhVRlaeiZvnLouI+HFmIdGLTJxckKvUoPd7j4JRMOwAAwMDAAAA//8a7WyOguENIHdngjqdjP9//2L48/iZ/pft6+O+7Nrs9ffjO4Z/v35BlPCN7s0cBaNgFIyCUTAKRgEVABMzZCsOK8So308fcf16+MiBTVHBgMPQ7Nb/Xz95/n18/4WRheXe/z9//oPbKaMD3aNgOAIGBgYAAAAA//8a7WyOguEJQDOa//9DZjRFxFj+//ph8O3ofuOfF89afDt9xPT306cM//8yMDAwg2YzGcEVwygYBaNgFIyCUTAKRgFVwb9/DP9/MzD8/8nA8OflM4GfN6/oMnJy/v797Ik8u47BERZxqb0souJv/n39wgA+1vb/6MraUTCMAAMDAwAAAP//Gu1sjoLhCUAjhJBRQm6G//8Vfj1+4PntyIHQH+dPav/78Y2RkZ0FIj26bGUUjIJRMApGwSgYBbQCTEwMTNxsoNYIuOP5694tjj9vX1v+uHDWguv5E1VuW+cPbKoaOyHnRYzOcI6CYQYYGBgAAAAA//8a7WyOguEBYDOZLKwMjOwcDMyCwszMgsJGvx7dM/1+7oTK74ePrH7duqzz59U7RtDeTCZW5tECfRSMglEwCkbBKBgFtAew9gZ4lvMf499frxn/f/zA8J2R0fTfx/dxnBZ2YhwaugdZRMQegU6xhbVpRsEoGPKAgYEBAAAA///s20EKQGAQBeAXf0oUB1CK29jJye2UBUmKjezwNz8L5AYWet9ubjDvTcOwSf9wXzIPI4AIjn1LAGQyjflWlZHuhgDKwPL5m0lEREQfeoKjUrDUO+u2DnXfFLLMqe16qxMn3bXPgIU4/QOAEwAA//8a7WyOgqENYDOanFwMTNw8oLutRL8dP2j34/I56x/XL9v8vHtD/8+zJwz/Pv9lYORiYGDkGF2iMgpGwSgYBaNgFIyCAQT//zP8//uX4d/330z/fzGw/7x0zvgzO2cku6auJCMb2ztmPsEbjOwclxj+//81ejvKKBjSgIGBAQAAAP//Gu1sjoKhDWD9RiYmBkYmRoZfj+8bfNm3M+3b8YNWf968ZPv3/h3olDdGZiEmqNrRjuYoGAWjYBSMglEwCgYQgNssTAyMoNNqOf4x/P34nunL3q0ev+7etOQwsXzCIiC8hZGZ+TMDI+PN0XbLKBjSgIGBAQAAAP//Gu1sjoKhCaAzmkyc3AzMQsIM/z5+UPhx/qT595NHPH9cOG318/Z1nv+//4IHBJnYmBgYWFihg4OjI4SjYBSMglEwCkbBKBgkALQF6MdPpn9fGDh//b3JycDKKsEqKf3v3+ePPMyi4keZ+PiPMfHwvvr/48foXs5RMPQAAwMDAAAA//8a7WyOgqENQJchs7Ay/Lp9w+rTplUFP86e0GD4+5cTPGLIDj1pFrRsdrRwHgWjYBSMglEwCkbBYAOMjAyM7KwMzGyQxVe/bl799+f5Yz0mbn51NjVNQwYGxq8Mf//uBl+LMgpGwVADDAwMAAAAAP//Gu1sjoKhBaCdRkZOTmYmXj7Ff29fK31/8kjm+/mTvj8vnjH9/fQjAxMX6LRZ6N2ZTKNXm4yCUTAKRsEoGAWjYDADUJuFkYHhzy+Gf9/+M/3/+Ybj/89fHL8f3LX5dnD3o/9fP/OzSMqcYxYQugc6BJHh7UtIe2j0DIpRMNgBAwMDAAAA//8a7WyOgqEHQAcCsbJLMLCx2f26d9vrx+ljuj/v35L4/+v3fxYBZkZwB3N0f+YoGAWjYBSMglEwCoYKAHUemVkYmHj+g9sv/75/Zfh5/RLLn2ePA34/eaDN4+ozlUPb4B4jG/vojqBRMHQAAwMDAAAA//8a7WyOgsENYDOZrKwMTKATZ3n5BBk5ubT/Pn9i8/PqJatft2/Y/rp2UeDP+98MTDwMDIxso1ebjIJRMApGwSgYBaNgKAJGyIqsf//A17j9ffeO+e/rd4L/f/4w+//7/4s/r178ZxGTvMrEzXuHiYv70/8f30a3CY2CwQ0YGBgAAAAA//8a7WyOgqEBGJnAy2IZ2Tk0GNlYk34/fez4+/kTvr+v33KDlpEwCzBD1IyCUTAKRsEoGAWjYBQMVQBdHssIOtgQCv5+fM/wZc9Ou193ryjxuPhs4dQ1XsnEwXn5749vf0fjeRQMasDAwAAAAAD//xrtbI6CwQmgI3WguzOZuDgZ/r5+IfPj+RPt7+dPef26c9P996MHUn+eP2P494OBgYmXCVIoj47ujYJRMApGwSgYBaNgOADwADrk9Nl/X78x/Hn7TeDf1/cCzHwC/xn+/Wf6//unFhMX9w0mXr67jBycH+E7h0bbQqNgMAEGBgYAAAAA//8a7WyOgkEKoJ1NLh4GJg52hu83z5h92bU59/v5U2p/X74Q/vvuDQMjGwsDE+t/8F1Vo4XrKBgFo2AUjIJRMAqGD4C2a0CznGysDCwifxgYWVkYft64rPTv88dwVmk5Gw5Ds6NMXDwrGJmYzo1G/CgYlICBgQEAAAD//xrtbI6CwQX+IzqZjBycDL+fPlb6/fie5rdjh4K/Hdvr8OvBXQaGv5AymJGdhYERdPXJaEdzFIyCUTAKRsEoGAXDFUCvRwHt5fzz+iP3vy9Xuf99/SLPyMMnyCQo/P////88bArKtxjZOV4wcnIzMHz+ONo2GgWDAzAwMAAAAAD//xrtbI6CQQagnU0ePgYmDi7mb8f2u37avCrl1527sv9/f2VgZGZhYGCGunh0RnMUjIJRMApGwSgYBSMB/IcsrWXiZGZgYGZi+P3iOcO/k0dk/7x8FvHn2VMdXo+A6Rz6xlsY/vIyMLwaXU47CgYJYGBgAAAAAP//Gu1sjoLBAWCnznJwMTKysgn9efVc6s+7K3pfD+4K/HbiiMm/9wwMzEIMDIwsoEKWGXK31GhBOgpGwSgYBaNgFIyCkQRAbaB//xj+ff/B8O/rY56/b17y/P34UY6Bien1vx/fvrGIit9jZGV7wMjKxvDvz+/RttIoGFjAwMAAAAAA//8a7WyOgkECIPdKMfPwcTBycGj/vH7J59vJI66/bl+XAe1VYBb4Dd6rAL/AeLTwHAWjYBSMglEwCkbBSARMjAyMHJBlXv///mH48/wxw9cDO1z+vnmlxG3juIhdx3AuEw///3/v34y2l0bBwAIGBgYAAAAA//8a7WyOgkEBGNk4eBiZmaT+vHml8+/DO/vv5056fT93XOXfl18MTFysDAwcrIiO5igYBaNgFIyCUTAKRsGIBYzwMyv+//rF8PfdW4a/799K/3n9Uvr/j29f/v38+YFdU+8UIwfnI0YuLsj9naOdzlEwEICBgQEAAAD//xrtbI6CgQXQ+6SYeHjlGVlY/X/euGz14+IZrT8vX4sz/PvPwMjONNrJHAWjYBSMglEwCkbBKEAGsO1HLNCm/L+/DP8+fmD4euKw8Z+3r0V5//6dy2XtNINZQIjhN+O90c7mKBgYwMDAAAAAAP//Gu1sjgI6A8hyWdCeA0ZWVgZGdnZRBgZG+X8fP3j8/vwx4Oflc/o/r9xk+f+XgYGZnwVRiI6CUTAKRsEoGAWjYBSMAlTAxAy9j/Mfw79vXxn+vP0i9vfNCzEmHv4PjGzsz5mFhK8zMDC8gd7F+Xc09EYBXQEDAwMAAAD//xptyY8C+oJ//8F7DRjAJ87yMjALCJozMDNH/b5/R+/v+zcyv18+Z2HkYGBg/M8wOqM5CkbBKBgFo2AUjIJRgBdAZyyZmMDNJiaOP+ADhH6cO6H/7+P7UnYjsyPsqlo7mXn5Tv379P4rSG4UjAK6AQYGBgAAAAD//xrtbI4C+gHQPVEcHOClHH/fvRH/dfeG+q8Hd4P/vnoR/uv+baY/r1+BBuYYmDjZwJOfDKMrPkbBKBgFo2AUjIJRMAoIA0YmcNsJfJjifwaGX/cfi/5+8lj07+ePsgx/fnOzq2iyMLIwX2Rk53jNwMg42sIaBfQBDAwMAAAAAP//Gu1sjgL6ANBIGisrA7OQKAPD718M38+dcP6ya3Pcz6sX1H/du8X099NH8L1RjMyj8TEKRsEoGAWjYBSMglFAFoCuCmNkh+xa+nX3ttj/79/c///88Y/T2OInk4DQW4aXL/6OznCOAroABgYGAAAAAP//Gu1sjgLaA9CMJjs7qMPJ/PfVC5Hfj+5pfNm7LeTrzk3uv188Yfj/4zdkNI6dDeGU0TG3UTAKRsEoGAWjYBSMAhIBIwSxsYLbUn/ffOD4+/qDKmhlGRM3708WEXF2hn9/HzCysb1k+M74aTR0RwFNAQMDAwAAAP//Gu1sjgLagn//GBiZWRiYBIUZ/r59zfb97PGAb0f2+X+/fFbvz5tXDP9//2ZgYGaE7+McBaNgFIyCUTAKRsEoGAWUAsh+JEY2yAD+7wf3pL7s3urNrq6tyiojf4OJX2Ab45dPh0dPqR0FNAUMDAwAAAAA///s3DEOQDAYBeAXmi61uEZvYHIOB7WZXMBksVok0jQiRGhLcAW29x3h315e/sewSf+5G00pAe+FN2O6tU22VGWx1lXurAGcex/auThLRERE9K1nK0M+YdMZq47B6jBPGmfoI5VIhLBDiA5RPN31AK9PnwNwAQAA//8abeWPAuoD0CgZaEaThZWBWUySgeHbV/bvp4+EfN69KeDXjavafz+8h3c0wXgUjIJRMApGwSgYBaNgFNAMMEJb/H/evGT4fv6UBIuYhAezkIgEs4DQBmYBgdUgOdBKtP+gvZyjs52jgFqAgYEBAAAA//8a7WyOAuoDUAeSlZXh/58/7H/fvOL5ff+2+Ze926K/7tth/f/HDwZG0GwmMzP4rs1RMApGwSgYBaNgFIyCUUAjAO03glaagZbU/v/2neHX7Xus/z6+12JTUdf68+4N6+/HD14wcnBeYvz37wsDK+tfht9/QKvSRmNkFFAOGBgYAAAAAP//Gu1sjgLqAdiMJhsbAwu3BMOfVy/kvx3a7fv91FHHH1fPa/7//gNiFeiktNE7NEfBKBgFo2AUjIJRMAroC0BnZDD/Z/j35TPD74f3Gb6fOGjO8P0bE9f3r+s5dI1WM/EI/P339QvD/58/R2c4RwHlgIGBAQAAAP//Gu1sjgLqAdCMJmj/5d+/nP9+fhL5dfOq+9fdW5K/nT6myfDvLwMjCzOkkGMcXTo7CkbBKBgFo2AUjIJRQG/AyMrKwAg6qPb3b4bfL14y/Pt2TO7Pk4dy/37+4GBgZHzGoWt89v/v318ZWFj+grc8jU5wjgJKAAMDAwAAAP//Gu1sjgLKAXxGk52BRVSc4e+nD2LfTh8L+7Z/p++vO9cV///8C7k/k4URejraKBgFo2AUjIJRMApGwSgYMADa0sT0l+Hft68Mv588Yvh27KDRv8+fs/++f7eH08hiGYuYxKe/798y/Pv5Y3SGcxSQDxgYGAAAAAD//xrtbI4CygEjIyMDMzMjw9/frP8+fWD7dfu63bcDu6K+HT9sAFoty8TFCrFidOnsKBgFo2AUjIJRMApGwYAD+NkZf/8y/Pv+neHntUuSvx/eDf777YsMIwfnfS4unkMMf//8YmBmhsxt/hs9rHYUkAEYGBgAAAAA//8a7WyOAvIBaKTr/38GRg6O/yw8fLx/3r8x/npot9n3c6ccf925ocrwm4GBAdrPHO1ojoJRMApGwSgYBaNgFAwigHSGxv8fvxj+/PjF8PPyOc3PPLyp/3//luHU1t/AIi71FjzD+fHDaMyNAtIBAwMDAAAA//8a7WyOAvIBeNqSiZHh3z+Rfz9/aP66eyvw6/7tgT+uXJZhYmZkYOIZndEcBaNgFIyCUTAKRsEoGJQANGkAWk4LuhMdNHP59w/Dn6eP+L7s2hz8/8d3KUaG/y85jCx2Mfz5/YeBmfkfWM3oitpRQApgYGAAAAAA//8a7WyOAtIBfEaTk4FFSITpz/s3Oj8un/f7fvK40++H92X+gw4w4/gPXl07CkbBKBgFo2AUjIJRMAoGOWCETA6AltQy/PzB8P3McR2G798TQDcLcBparGeRkX/278tHhn+fPo7u4RwFxAMGBgYAAAAA//8a7WyOAtIBZNkFaEaT5//PH3K/H9xz+HZkn++PS5eVGdmZGJj5WEdnM0fBKBgFo2AUjIJRMAqGCmBkYmBkYYJPKPx5fJ/384O7wX/fvtZk4uB6wSwqvg4sx8j4H9zGG+1vjgJiAAMDAwAAAP//Gu1sjgLiAbQAYuLgZGNkY5f7+/aV6bebV02+Xzpv+/vxA4X/v0FHav+DXH8yCkbBKBgFo2AUjIJRMAqGEABNFIDaev8Y/v/8x/DvGwPDz1tXNT7v2hT7n4FBhENbbzuLuNSjf59BM5wfIB3O0cmFUYAPMDAwAAAAAP//Gu0VjALiAWIjudT/v3+sfj26H/jtyD7LX3fuiDGyMjEy84/OaI6CUTAKRsEoGAWjYBQMTfAf0o5jZmFg5PjPwMT6l+Hvt69MX4/s9f3/65cSAxPTBy4BoUfQGc7ROB4FhAEDAwMAAAD//xrtbI4CwgBpjyaTgCD/3zevTH5cvej5/ewZ899PHor/+/6fgYn5L+QY7VEwCkbBKBgFo2AUjIJRMPQBExPD/58/GP59+cb089JpHYb/jJH/3r/h49Qz2sMiLXf/3w+Q3GeIN0c7n6MAG2BgYAAAAAD//xrtbI4CwgA+o8nIz/Dvn/bvJw/tvp84aPXz5l0xRnZGBmYBNsjKi1EwCkbBKBgFo2AUjIJRMPQBIyP0oEcmBkam/wx/3r5m+L1zq+efV0/UGFlYvvFIyt4H39M52skcBfgAAwMDAAAA//8a7WyOAtwAMaPJwcTGJv/3w1uzX7eumv+4dN7+95NHcv9+/GVgYmFkYGRjHj2ZbBSMglEwCkbBKBgFo2A4gv//Gf5//8349wMD289bVzW/7N8RzsDGzsauoXOIRUzi7v+fvxj+ffkE8fho53MUIAMGBgYAAAAA///s3UEKQFAUheFzXTJVlDK1BHMzY4uWAXugXvbwJp73JJmxAZ1vF3+3zmVs0rfnoqlxJd63u1l7Ow2NM1sODUGzRO5FMoYmERER0S9dvzjTBJo7wCPYeezC7mqBHHFRLqIRI5PeATgBAAD//xrtbI4CTADtPDJycDIycfNK/nnzyu7XneveP86fs/j96L7wv8//GJh4mRgYWVlHO5qjYBSMglEwCkbBKBgFwx4wgs/m+P/7J+O/z984flw6o8XIxBby7+vn/+zaBsdYpGTvMv4DnWD7hWH0AKFRAAcMDAwAAAAA//8a7WyOApyAkZlFhIGJyfjPk4dO344fMvv98Ck/IyszA7MAdI3+aEdzFIyCUTAKRsEoGAWjYPgDRuhdnCCKk4nh3+fP/7/s3+P458UjFb4whi4eGfm74EkIUGdzFIwCGGBgYAAAAAD//xrtbI4CBIDNaHJycTMx/Jf+8/a11Z/rlxx/nDtr8/vJQ8l/X/8yMPMyMTCMzmiOglEwCkbBKBgFo2AUjFjw/8d3xj9vGXh+MFzSZD64K4SJh/cPh6bOCRZh0Tv/wTOcX0fbiqOAgYGBgQEAAAD//xrtbI4CDMDEyir59yez/e+Hd32/nTxi8vvJcyFGJmYGZn5G8Lr90cJjFIyCUTAKRsEoGAWjYIQC0Em1rKA9nL/B9I8Lp20Z/v1TZGT438di73qHkZWNgQHU2RwFIx4wMDAwAAAAAP//Gu1sjgLkGU0GJi4u/j+vX5r/vHnV98fFC1a/H9wT/veNgYGZnxl8ye9oR3MUjIJRMApGwSgYBaNghANGRgYmVhYGhj9/GP68eMX34+8pLUZWjsD/v359Z9fSO8UiJnEHdDXK/+/fR9uOIxkwMDAAAAAA//9iGukBMAoQgImdnZ2RhU3l96MH5t+O7Tf9dec2HyMbKwMTHwsDA9Po9SajYBSMglEwCkbBKBgFowAKoLcWMHGwgJbVMnw9fMD6/fJ5NT8unrFnYGFhYOLiGQ2pkQ4YGBgAAAAA//8andkcyQDaeWTi5OT4/+e32J+Xzw3+vn5p+/3sSftfD+5K/Pv8n4GZn4WBkWW0ozkKRsEoGAWjYBSMglEwCpAB9MRZRkaGfz++M/x5+03g37fTAl9FxYOZBIS+cGjpnWHmE7gL6nj+//lztC05EgEDAwMAAAD//xrtbI4CBiZOLtF/P75b/Lh03e/HqaM2v58+E2FkAc1o/h3dozkKRsEoGAWjYBSMglEwCnAD0B5OFhYGZoHfDExsbAw/rpy3YGBmkmH4/28ij53bXUYuboa/v36NtidHImBgYAAAAAD//xrtbI5EAL3/iJGDk4GRhZX775sXpj+uXQ76ceGs/c9bNyX+/2BgYBJgBRccowXDKBgFo2AUjIJRMApGwSjAC0DLadkgK+H+PH0q+O3nD0FGNvYgRgaG9+xaBheYBYXvMXJwMPz/De10jl7DOTIAAwMDAAAA//8a3bM5IgF0+SwXDwMjO7v0r7u3Lb4d2m3/6+4dQUZ2FgZGHqbRezRHwSgYBaNgFIyCUTAKRgHxgJEJelItE/hgoG/HDpp/WDa36fvZ466gFXPMfAKQ9iXDaPtyxAAGBgYAAAAA//8andkcSQB26iwHFxPjt++Cf1481fjz/Injt7MnHX/dviXx7zsDAzNoRpN1NFmMglEwCkbBKBgFo2AUjAISACNsDycTw/+f3xl+v/om/PfdK2FmIZFAZhHxl5z6RucYObkfMbKzj+7hHCmAgYEBAAAA//8andkcUQCyfJaZh4+TgZVV9efVi4Gftq2L+3n9iiojGwsDEzcjoqAYBaNgFIyCUTAKRsEoGAWjgFQAmt1kZmFg5GIA0z+uXTL+vHVt9Y8r550Y2dggp9SOrqAbGYCBgQEAAAD//xqdwhoJAHmPJgMj25/Xr/R/Xr0U8O3McZ8fly6p/v8FukeTlQF0zckoGAWjYBSMglEwCkbBKBgFZAPoxAUjGxN4nuP3w3si/799FWHi4AhiZGZ5wa5tcA08w8nBzsDw989oOA9nwMDAAAAAAP//Gu1sjgQA7Wwy8wky/P/1k/Xnras2X/ZtC/r98L4EqCBgZPk3OqM5CkbBKBgFo2AUjIJRMAqoBhhBd7SDwX+Gf58/Mnw7ftDs76ePYny+3+ZyO3rMZuLgZPj37SsDw79/o4E+XAEDAwMAAAD//xrtbA53AJ3RZPj+jfPPsycSvx/ft/h28rDHzysXlP//ZGBg4mVlAN1/NApGwSgYBaNgFIyCUTAKRgHVAOjAIOhhQP++f2P4dfO2+J9XL8SZuXk+MAuJ3GfXMbzKyMr6nJGdAzLD+f8/RPV/6BWeoMkSuAAUoPNHweAGDAwMAAAAAP//Gu1lDGfw7x8DI2hGU0AQNKIk/P3M8dBvR/cH/bxzXYmBmZGBkf3/6IzmKBgFo2AUjIJRMApGwSigAYAeTMnMDGb+Z/rD8P/Hd4YfVy4YMvHylzEwMi7gNLZcxsjKysAAwv//MzCCO5gQff///2Ng+PuPgQFEM0D2eILFwBOhox3OIQEYGBgAAAAA//8a7WwOVwCa0WTnAC2bZfn79o30z+uXvL4d2Rv67fghE9AeTSZuFgZQh3MUjIJRMApGwSgYBaNgFIwCmgHwlSgMDAygXsefPwy/7twQ+/ftiysDB8dnJk6uJyzSctf/ff/2hpGR8T8DMwv88CBQJxV85zsT5P5OBiZGMJuRCXa+6eg1KoMeMDAwAAAAAP//Gu1sDkcAWvvOzMzALCzC8Pftm78/r170/rJ7a+LPOzdUQb5lZIVt3h7tbI6CUTAKRsEoGAWjYBSMAtoD0Mm04P2bP38w/HnxjOHHhdPmjOwcBazikiv///69kombh4GJhw8yy/n3DwMzNy8Ds6AQAyMnF8P/P38YGFnZGJi4ucHbw/4zwjqco53NQQ0YGBgAAAAA//8a7WwONwCa0WRjZ/j/9Qvz3xfPRH/cuKz/9ci+4O+nj5r8+/6LgYmdBdrJHO1ojoJRMApGwSgYBaNgFIwCOgHwgUGg42n/Mvz98pXh59WL0n8/fghkk5L5wcQn8IBFXOoGE7/gZ0Z29n8Mv38z/BMSAs2gMDD+EWD4//snAyM7F+QueNAeT3gnc7SzOagBAwMDAAAA//8a7WwOJwDao8nMwsAkLAI63Yvl26nDAV/37wj8cfW8zv/fvyE+KuhIAAAgAElEQVT7tEdnNEfBKBgFo2AUjIJRMApGAd0BtGPIwszA+O8fw9+PHxhA7VMmNlYDdlHxCCZ+/s0MrKxHGBgZfzEwM0GWzDIygc8fYYDRo23YoQUYGBgAGu1sDhcAmtFkYQFtvGb6++G9wM+bV82/7t0W8WXfdnvQsdLgzdlMDKMHAo2CUTAKRsEoGAWjYBSMggED4DYpMzPD/++/GP5+/8jw5+VzVRZxaW4WcanvTJzcTxk5OO8y/Pr5B7xfE9x+ZULg0Xbs0AIMDAwAAAAA//9iGk6eGZngP2RGk5WVAbTWnYGJ+f/Py+d8v+7dlv/jxhUdUEcTcogXIySTjoJRMApGwSgYBaNgFIyCUTDQgIUJfI7I39evWb6fPyvx6+4tHUZmZi1mfkEe8P7O0fs3hz5gYGAAAAAA//8andkcigBlVIeJgYGVEbSRmunf92+8P29d0/t6cFf4t0O73f+8ews+uYuRabSjOQpGwSgYBaNgFIyCUTAKBg8A778E7QL78o3hz/sHbEy8PFos4lIujCys3xj+/rnMwML6ioGR8e/oxswhDBgYGAAAAAD//xrtbA4FAF6rDsHg454ZIcsJwGvXWVnB9N+PH5h/Xj7j8WXftpAfF88Y/nn7iuH/r9/g5QeMo0sORsEoGAWjYBSMglEwCkbBYAKw5ikLIwMjw3+GP88eS3w9tMfx3+ePTOxaemwsgsLHGFlYPzD8//d3tL85RAEDAwMAAAD//xrtbA4FAF5G8B+yYhZ8me1/6AW3oH4nCxMTNxfHr3s3Db7u2xb+ZdemwD/Pn0A6mqAOKWit+ygYBaNgFIyCUTAKRsEoGAWDCUD7j4xsrAyM7AwM/z5+5P7x+oLm/98/eBi5uBhZJaW/M3Kwn2dkZnnL8PfvaNQNRcDAwAAAAAD//2JhHF1eOajB/79/wXcL/f/1k4Hhzy+Gf1+/Mfz7/pXh39evYP7/P3/YGVlYHH7evOr/4+IZo9+PH4IOCYJcfDs6ozkKRsEoGAWjYBSMglEwCgYzgDVXoYfN/nn+RPLb8YP2zDy877gd3G6xiIi9/fPmFWTy5f/oDOeQAgwMDAAAAAD//2IZ7ZAMUgCLF9BIzt8/DP9/fAN3Iv++fcvw9/1bhj/v3zIy/PzO/Pf9O7V/nz/6/bp7M/zn7Wt8/798Y2BgZgBffDsKRsEoGAWjYBSMglEwCkbBoAbIM5xsoD2cX1h+XLygwczL58oqq3CWWUDoDcOf3z8ZWNn/jvZbhhhgYGAAAAAA//8andYcCgA0ivMfsnQWtGz9/98/oM4oMxM3jyzD39+WP+/d0vtx7RL/33dvGcGjQqOz1aNgFIyCUTAKRsEoGAWjYCgBRqRVeX8YGH7du63yZceG+K+H9yT8+/FDjEVElIGJgwPRLh4Fgx8wMDAAAAAA//8a3bM5FADs2hLQ5bYsoFEfDkZGlm8S///8tvz76ZPr72dPFP68fAE5eZaddXT57CgYBaNgFIyCUTAKRsEoGJIAdJ0fI8t/hr9vXgl82bfD9++3r3KMHNyvWSVlNjJycPxhYGX6h1h7OwoGNWBgYAAAAAD//xqdAhsqADqKw8jGxsAsKMT8//dv1R8Xzzh/P3nS5M/zJ8LwuzRHO5qjYBSMglEwCkbBKBgFo2CoAmh79v+fvwz/vvxh+HX3lvq3I3tif5w/Gf3/1y9+Jn5BBkYOztEZzqEAGBgYAAAAAP//Gp3ZHCoA1pH8/5/n/69fMn+ePbb6dvqo9c9LN+QYORkYmDhH92iOglEwCkbBKBgFo2AUjIJhAEDX/YHu4WT+y/Dv4weOb8cO+jKxcwoxC4k8ZhGX2svw79//0QmWIQAYGBgAAAAA//8a7WwOdgCb0eTgZGDi5mH49+G96I8r5wO/nznm9efFU/n/fxkYGP+N9EAaBaNgFIyCUTAKRsEoGAXDCoAnWpjAh2T++fqV4cflc/pMQkJJjMysIqxqWjtZRETf///3j+H/z59IZ5tArwdEnvUc7ZMOHGBgYAAAAAD//xrtbA52AJvR/Pef4f+vXwy/Ht03+nZsf/D38ycNGf7+ZWIWYAZnxFEwCkbBKBgFo2AUjIJRMAqGUxsYfF/8P8jtDL+fPuL+snd7OMNfBlEeNrbnzMKiB8HXA/7+BVH/nwFxtC0Dw+jWssEAGBgYAAAAAP//Gu1sDlYAHY1h4uRkYODmYfh154bI9zNHvb7s3en388ZlrX+fvzMxsTExMLAwjw7ZjIJRMApGwSgYBaNgFIyCYQoYwejfp4+Mf798Y/zOd8KAWVIqhJGZmZmBkekCAwPDO9ChQkwcnJCVgOwcDAygQ4aYoW3k0X2dAwcYGBgAAAAA//8a7WwOVgAbjYFeY/Lr/i2DT1tWZ387csSAgfk/CxMHC1TNaEdzFIyCUTAKRsEoGAWjYBQMU8DEBD4gEzS7+f/Xb4bfTx5yfz952Pf/t2+MzPyCn5gEhd4xcXExMAsIgTEjEzMDEysbAyMzC7SzObrfbMAAAwMDAAAA//9iGb2TcTABRgZGUHwwMzEwskIO/Pn77o3Izzs3bL4d3R/08+Y1o79vfrEw8TMwMLKPjhOMglEwCkbBKBgFo2AUjIIRAGCTMP//M/x995rzx8Wz8v///DHj1DM6wywqeofh3/+P/3/++M/w5zfSXk3YpMzoxMyAAQYGBgAAAAD//2IZnVoeXAC00ZkRtN6cFeKsX4/ua3/dvSX924nDdv9//GBiFmBgYGRjYRgdJBgFo2AUjIJRMApGwSgYBSMCgPorzMwMTBxM4H2Zf14+/8/ELyDBrqJuwMjKfoORje06IwvrR5Aa5I4pCj0K6A8YGBgAAAAA///s3T0OQEAUBODZtQUaHXEDjUahcwWnloi/C9Ap3GCJn0X2FhLzHWFeOZk8da+ayX+FuWDvcWttG84Ajky2oS7XtsqPafQBA6EkB89ERERE9D/SjjcNnt2Ic5mjremKB9i9NLtUGPfC9fl/80sAvAAAAP//Yvn35dNID4OBBUijL/9//WT48/IFw+/nTxn+ff4kz/D3l//3i2fcfj99xP7v5y8GJjZGBpQRm1EwCkbBKBgFo2AUjIJRMApGEgDtyeRiYvj//Rvrt9NntP5+fcPBIiB4h11T7wIjC8uf0XbyIAIMDAwAAAAA//9iYfj9e6SHwcACJkiGAN0LBLon6P+f3+z/f/8S/P3wjsWve7edft68ofX31Qsmhn+gzc3MkOWzo6M1o2AUjIJRMApGwSgYBaNgpAJQe/jnT8Z/H/9w/HpwR+v7qaP+zKISvzn0THazKag+hRwo9BvlJpRRMACAgYEBAAAA//9iAc+UjYKBA9DRF0bQJUKgE5w5uQWYuXn1/n3/Zvb77k25P0+eMjCy/Wdg4mSFqB3taI6CUTAKRsEoGAWjYBSMgpEM/v9nYGRhYWAW+gM6dfb/j0vn7Bi5uMWYBYTfsatqPgVdhfL/z+iE2oADBgYGAAAAAP//Gj3SdKABqPMIurQWdDcQKxvD/+dP5X7euOz78+olq9/Pn0j8+/aLkRm0T5OFdbSjOQpGwSgYBaNgFIyCUTAKRgED7EoUFgaGP38Yf794xct44Ywps5BIGBM39392Tf2zLGLiz8Dqfv4CHyoEbkX/+z96FQo9AQMDAwAAAP//Gu1sDgYAGp0BT/f/Z/jz/InytxMHHX9eu6oAchkzLxN4bfpoR3MUjIJRMApGwSgYBaNgFIwCJABe9cfAwMjCwPDv04f/347s8WD4+0eBkY29A97ZZIKqAfUzIQQDZH3t6N5OmgMGBgYAAAAA//8avfqE3oAJcposIyOUZmcHdyT/vHop/evODcNvxw74/rx1Tevv+6+MzHzMDAyszNBMMQpGwSgYBaNgFIyCUTAKRsEoQABox5GJkeHfl0+Mf95+FGZgYLRmlVXwZhGXesrIxfWI4e+/t+B77MEzoezglYSMTIzg6wZHAY0BAwMDAAAA//8andkcAABO8IzQRM/FA5r+Z/h175bp5y2rS76fO6H2/9cvBkZu0LQm02hHcxSMglEwCkbBKBgFo2AUjAJcADR5w8wC6XQy/mH4+/Hjn+9XzlsxCQi/Z5GU2cjMJ/CWkY0V3MlkFhBiYOIHXVrPzPD/39/RIKU1YGBgAAAAAP//YgFtrh0FdADQw33+/frJ8O/LZ/A1J/9//wbNbIr9+/ZN9fuZY8HfTh+1/v3oJQMTNwsDI2hGc3R6fxSMglEwCkbBKBgFo2AUjAL8ADSRA52p/PfpA/OPc2e1/v/+85fLzOYWu47hKSaG///BkzlcXAxM/yCHcjKMzmzSHjAwMAAAAAD//+zduQ2DUBAE0FnAXLLk2HRAQge0Q8ME0AHgwObWR+ISXxYxCdm8KkZazawlx/AM3c/SBWZsXYv5U2Ktv1i6BuvQR0v9S6Y8jTEpGHp0VvhLk4iIiIjoiv/gpuHoI5rMRWWKlwVuGL3N58sX+zFsajxrbBqz9v0A7AAAAP//Gr36hE4AfAQzKCP8+cPw7+tnUEeT5+/7NyK/7t5y/nXvjs/vxw84/33/Br5KEzKhOZoBRsEoGAWjYBSMglEwCkbBKCAaMENmOP99+cH458lDsR8Xz1qziEq8YFVUPsAiInofdPsDBIyeWUMXwMDAAAAAAP//Gj0giF4ANFUPHnUBLRNnZmDi5pX6//e33f8/v43/vnrB9O/9BwYGFkbwnUGjIy2jYBSMglEwCkbBKBgFo2AUkAGYmBiYuMEn0DJ+v3DG7P/PHxI87r7/WGXk7jPz8EImf0a7P/QBDAwMAAAAAP//Gt2wSWcAOQWLnf3vp2cGv+/dCfj14KH+n7ev2f/9+M3AxM0KPRRoRAXJKBgFo2AUjIJRMApGwSgYBVQD4Ps3//9j+P34tej/b8dFmYWEAlmkZN4wsXGcYRYRewm6cvD/zx+QiSAYHp3soT5gYGAAAAAA//8a7WzSC0BnkJm4uBkYObkE/zx9pPHt6AH9Xw+fCTD8+8vAyMEMvytoFIyCUTAKRsEoGAWjYBSMglFALoB0HJk4GMBLZn/euGLOJCDMw8zLP5lLRn4jaJUhI2jV4d8/DP//Qk+lHe1sUh8wMDAAAAAA//8a7WzSEsAO+gHfpwlK7T8Y/rx+qfTr3i3XH1cu2P28eU3m72cGBhYh0OmzLAyjS5pHwSgYBaNgFNAXQOsd9OqHUH2E7WyB0fMGRsEoGAWDCYDa32yMkBnO+3cl/v//L8EqLvmYRVL6JouQ6Mu/3768Z2JjZ2AA37sJOq929HRaqgMGBgYAAAAA//8a7WxSGyBPwzNC9mCCTvxl4hdk+P/lM8PvR/eNvx09kPjr7i1FBhZmBiauv/BrUUbBKBgFo2AUjAKa11EIDlInE8L+j7yk7D9aJ5QRiWZEDKgyMjAircxBW4o2OlMwCkbBKBhAwMgMOXkTdN3g37dvGH5ev2TJLCKWzCImsYWBhfUgq7gEA7OgKAMDOzvD/z+/R6OK2oCBgQEAAAD//2IZrQioDJAq3P+/f4GuNgHfqcn06aPQ37evpL+fPeH7/cwx8z/PnzIwsrMxMHCOVsajYBSMglEwCqgM/v9H6kz+h51PBwHY6hzQdQBMjODRffDVAKDzA6BXBDBC1UM6otDD7v79Z/gPPvjuH+KuOmhHFqSOEWonA3zCE+mqgdE6bxSMglFAL8DIDB81+/f5I8OPS+fV//34wcWuqvGGVVHlIjM3zycmLt5/oNs5/v/8ORot1AYMDAwAAAAA///snTEPwiAQhR/XamsTY3RwcnF3cdS/4o92cnB1IeraKFXgDIXGpHN1uu8HQEIIj+PlHnkrJsJwkAJcFGP/qOG0xltfwMbs7P12aE7Hfdjs3WuxkvUXBEEQhiK5kuwd4BgcWpF8z8QMtV5fekJsQEagsoQqJqCqSoF2Y4CyVFRahE/ROfQ4NQ28MWDzbN0AtmmcLmeDv/WuSvO1d75MRaeBRPsEQfgH8eRTo5iNYvUVbF/LfL5YF5vtiqazM4i8BAT9CAAfAAAA///snUsOgjAQhqcNiChh49LEG3gOE2/gxd1oIBqMKxNWUKZQzHRKwtrHbr6E0LQ7FjRfH//IzuavodlUheNIxqihfi2xvG6wuBzsvTz1jwpc184mevn+giAIwodM24fT0VfgRU8vilHM5bTCdQ6q90zy6AWS2iSRFJJB4rdIQFPfKgOdpqDXmc8aUHHCcjg6lkzsWC6NAaoN7ZoGRjRBQgdfS9qPW+QHEcDa0MdvoHYI5FCzbANBEIS/EXE2iqtbGLFN7K3Y98/qGG93oPP8rBaJ84t083+p8D0A8AYAAP//7Jy9bsIwFEY/2yg0CT+WQqpuHZDahSfgRXhgJvbOSK2KhCAoFUkEAtmgazsSK4Ju9ywevVi2zv18L/dsPp2bh19IIdL+u0x6U9vUk/PvN8xfBaGEP/QMwzAMcy83gum+shqLywk+XaSnh8JI3YXSGVT+CjXUUNkIKh1Aag0Rp5BJz4sniWUUOcEU0YsfZtfKqUsgw6R0hC+0tBetJJVOPoNYUsLZCuihcS0ktq5gqz1MuYMpC5zXK5hiA7M/wB5D22cMN8DDCa9LO1k6GYb5B8K9SfcjOsDpZ/khF/NZJ3/bRuPPL5XlQFn4whkVxdoJtcxjALgCAAD//+ydPwvCMBDFrzYRRRGVIq0igpuTX8PZb+0kuAuC4p9WaqjViiZV7gLqLLrI/cZsWZI83nsXVjy/whV4ccr75Tw08X6so3BgDjE9CJxq8T/3zDAMw/yIV//yCfYrXQFOWdhhdCV0JCvg1upQ8HwQrQBk0CGhKVq+XW80rdhE5xLdTBSbKDC/EWu93SA/n2yFJD3SUDyTKBKYOtrCdbkAvVmBXi/BKEX9qbu20Vz8Aoy6n5gMgrd+J8MwzBdxSvQ+Bx3uvGw68US7O5K9/kxk2TxPE0UJECEp9fE8h9jp/BwAeAAAAP//7JzBSsNAEIb/bLKx2YBN2kPBIoIWxKunvlvfpyffw5NgoS31UpBQiiAedEnTTbuV2c0TSLyU+WAeYC+z++//z7DYbBu6LIVAeNmFrcp9vSluypfnx7p477lokzyv4zIMwzD/CD10rPWx09r6GczGZBQxOYMxwrwPeTtCPHrAxd095OAKAYlJlSJMUydCg0SBVvx759JHal2Etk1BJ2nzeuYEr8h6gDGwFLutds7tTH6+neN5/PrE4WOLajmDWS1g1m846h1OZTPbSUWvk0h4d5VFJ8MwbSGafkJ7zrTGfv461h01iYbX0yBRTxSrpR4qstx/wlGx2Pw7AH4BAAD//+ydvQrCQBCEJ3+XIERCOpuIKbRQUfH9a21UFMFCwcoqMTYBjcmp7HHYCYqCzX5PcBzLHcPszrLY/CX0IZKjWZWGPGV+ud91LqvZqFgvGzIvYJGjaXPBMgzDMG+gUl9velecgFHTc5ckHm0bpl+HFYRwohhubwivP4bXHSjX8q/Qui9yBkjgvjgHtdaK+RTnxkQ5r9UxgUwT1ZoLCh6SpXI9VSubvgMWnQzDfI9+RyhxW0pct5uoytJINFu5E7cXpnAPdhAWhmneoWfen4nbzOcAeAAAAP//7J29CsJAEITnuJhEG8GoKUSxlhQiPoKdD+B72trZWImNYCWoqIiojRF/Eu9kj9gHItjs19y9wszs7LLYzIpORKZJLXOQxRK5tvo+nfTC0XDwmM+61GcRvBCIYRiGSYP6LuMB1A1mIkZ6EhY57rUG7HoT1C+S5ap5LfpXfDMq+3ehmRJKY92gA8vz4QZtxOcjou0G6nLCa7VEfNgj2q2hQuqE0ugbIJzkLAsLT4ZhMiKS6sD7GkLFEZleLcd2+yJfGEOIBbR+cqL5AwB8AAAA//8a7WxSCsD13X/woQn//v5hZGT9yv7n+RPZb0f3BX/ZuSkMNFoLPg2QeXRUZBSMglEwCkYBHgBr2ICWt4JmB3lYGJgF/oM7lKBOJruWPgObqgYDu6omA4uULKTDycs3ZEOURVwSjDkMTBj+ffrI8Pv5YwbQHdQ/r19i+P3gLsPPm1cZfj9/xvD37StIBxx2UiQDUliNdjpHwSgYBeQA2D510MAe6HCzL18U/n39Evz/F+jKCIYHDExMkEs3R0+npQwwMDAAAAAA///s3U8LAUEYx/Hf7o7dOPizkaLkJOFAyUvw6rlslJQcZDlglbDTzljtjJJy2dz0fN7FNM/zfdhHbICkY+iC3iPJud9vkEGQicRqxBezMV/Oh+J4QMxjGDm6p0kIIeQ7fTJEqh+8pChr5gCrWILd6sBp9+B0++/fS7cMy62oEVq1d/knzHwBtp0Bcytg1Rrk+YTsbovI3yD0pmq3k6+XiLkAxCv4bundTn0/z6SHJyEkPWaoMJnY+4XQm3RZvdHM9gZhUvOW1wuN0P4KwBMAAP//Gp3ZpBSARkZAI64/fzL8efFU4NfdG3Y/Lp6O/nX/rjSoNgQfcjBaAY6CUTAKRsEowAbA9QQLAyMbK3ivI2hLBquoJHjJLKeFHQO3nQsDp5HFiAg6Rg4uBmYQFhWHi/1985Lhm6IKwzfRgwyMXFzgE2z/gk6x/fWbgQF05QqoIQg6LWl05mEUjIJRQAZgZGUBr1L89+4Dy4+vl4VZ5ZU1f+sZ6TCJiF9h+P/3JwMLy//Ra1AoAAwMDAAAAAD//xrtbFIKQBUcExMDE58A6NAG1j/Pn8r8uHpJ9s/LF8zgJbbMozOao2AUjIJRMAqQAGxP5k8Ghv8/GBiY+BnBnUvQElnQvks2ZXXwMlnQclk2JdURHXLMIuIMHIZmDMxCIgwcOvoMf9+9Bc92grao/H50H3yNCuhkW1BYgupc0P5WcOMRfOLk6EDvKBgFo4AAgE0Igahffxh+3rhi8HnXptz///9v5NA3Xg8qe/5/+sjw7/cvyCwnfAn/aMASBRgYGAAAAAD//+zdMQvCMBAF4BdDanAQdBFFkXYQHHTUpf9/drAWFBS16iIOKrVNNJUmk2NxvQ/yH+7g5R4tm/9i9iQyL7JUfG7XiT4d++9zwotcgUlBKWVCCCG/yn7MmucO3jQZxDBAfTxFYx7CC0Z26SwHHFtTQiB6A/swC228Vu+30JcEWbSAipfI15GtUzGv1PV10rcVQkhFzHM1S/qw8x/Pu8+klLzTXfFWe1NoZWCMm+gprVgNgC8AAAD//+ydTwsBURTFz/uTwYLGlPKnlK1S4nvYWviOtvMNZMGGlPKnJCRLGc/MvPQedrOQ7dzfRziLW/fezjmSRPsTxmxnGS+60KdDHEwn/Zs/GqjlomULqq2sjC4fBEEQacdcwmPjydTvZFXHeBQL1o+ZbXVsbYkJysk0mhBeGaLkpV2xZISwoUjMyUFWapDVOuJ2F2q3RrhdQS3nCPcbRJcrtPrsnF9fpxQAF1TQThBEMp/AIB0o6PPRzJPeYzoeInr6jMsZL7p3ns/bGqr3h5N0/AkALwAAAP//YhktdMkE//8z/P/9G3SKFePfl89Vvh3ZG/Zl1+bQf7/+MjBxDJ9DG0bBKBgFo2AUUAjAdzAzMzAyMTMwcvwHX1kCOl2W28mTgcfVj4FDW280hEkATDw8YMwiKQPWxAG6LuXmFYZv4vsZvp87wcBw4wrD30+fIA1C5BNsGRhGO5qjYBSMAuwAOvkGOngMBH4/fiD97ej+yH/fvv5mk1d+wMbO8Y2BkxN8Ujj4DuDRsoQ4wMDAAAAAAP//YgF3mEYBcQB8tRcjw78/oJMDf4OOSeb+9ei+2fezJzx+3b1h9ffjX/AoKgPH6DT7KBgFo2AUjHQAql////4PrjtAg5CsMnIMLLLyDBxa+gys8ooMnEaWDOxqmiM9mCgGoBN6mbQNGJjYORnYFFUZft69yfDn9SuGvy+fge/r/PPiCcOfN68Y/n2DHlrLycjAyAzdRTRaV4+CUTAKkAH04M8/r16w/7h8TolJUFiJTVGFE3RiNgPL6O5DkgEDAwMAAAD//2L5D9rwOgqIA6BKiYmJAbRMFnQnz+/HD4R/3rnu9f3M8YQ/r18KM/FCTRmtvEbBKBgFo2DEA/Cl4ax/GZh4+BhYxCUYOA0tGDiMzBm4TC0ZWCSkwVeYjALqACZefvB9naC7SDnfgTqaLxh+3boO3s/589pFhp93rjP8efkCfIotuKM5Wk+PglEwCrAARmZm8EqU/z++ge/9/fP8qcTfL5+V/v/5fYeRlXV0OpNUwMDAAAAAAP//Gl1GSyr49w/cgGDkAfUs/3P8vndL/uel8yL/Pr2HHPowWoGNglEwCkbByASg+vTfPwbQdgqGv6AOEDsDq4QsA4euMfiuTA4dQwZWBWXw3kxGVrbRREJNAKp7GUHLlJkZWKXkGFjAe19FGFgVlBjYtfUZft2/w/Drzg3QSZMMv58+ZPj7/jPE8v+wPZ1MkD2dTEyjy+NGwSgYyQDWjv8POi38F8OvW9fUv+7ZGsPEwsrJaWG3nYmH7yfoMDLQlYcQRaPlBV7AwMAAAAAA//8aPSCIFACuzKAYnAi/y/59/ZLnz6sXkLvS2Ef3ao6CUTAKRsGIBoyMkD0/rEwMrDIKDJz6xgw8Lj4MHCag2Uwp6Em0zCM9lGgLQPUxGxsDq4w8A4u0LAOHgSnD3/dvGX5ev8zw9eAuhm/H9jP8YrjLAFrZBT45HnxFGePo4UGjYBSMAjhgZGUFdyZ/P3kEauuHMnFyc7Ipq99glZS5ATkdaLSjSRRgYGAAAAAA//8andnEC/5D0hN0+Swj6PRZbh7QnV6cP69dcvp6cHfgr7u31P7//Ae+2wsxGjIapqNgFIyCUTBiAOjOzD+guzMh9zyyyMgysCurM3AYWTJwaOszcBqYgu/RHAV0AozQOzZBh8+CCBZW8LJlRk4u0H3Y4FNsf9+/w/Dn9QuG348fMfx585Lh76sXDP++gu7RY2Bg5GAAHwICBqMD8qNgFIxMAJtY+v6H6c+Hbzf0t+oAACAASURBVOw/b141/3HhVAgTJ9dOBhaWG0wcnJ/BHVLQstv//0dPp8UFGBgYABrd6YoXQK8ugVc2jOCRjr/vXit+O7Q74cverV7/v3xmY+IaPU59FIyCUTAKRiwAFf1MjAxMrCwMTIKCDJyGZgzcdm4MnOa2DKxiUgyM3NyQ+mG04zKggJmHj4HT2IKBTU2T4e+LZwy/7t9m+HH5AsPPG5cZfly9yMDw8hnDv29/GBhh93SOxtcoGAUjG4BWqrBDBhH/fXgn8P3E4XBGBkbQ8vw3rHKKn8F9BOiBQqN9AByAgYEBAAAA///snc0KgkAUhY8z409mbSKM2rRoUaiF0LJX6MGjINq4aBsREbYUTdOYSWgRtA683zNcGLhzz/kESaN/IIdMYyjzDFWSSGl0t7icgnS/XafRYVWcYxs6wFo6+TQJgiCahNRfPXJUJcAMBtFzYc4CWPMQ1mIJ0w9hjCc0Ev+E1M9wrvKcKtPZdyHcEcypp4qF5G9ndoxUe+0zvn+Om3jt6VRVtvTYE0Sj4O/lU3G7Oslu4zGn44vB0GJ2G5VWZ7yr+qyW+AbACwAA//9iYeLkHA0ZXICRCXxq3f/Pfxn+/fzB8PvhPbHfTx/5fz93Kurvu7dCoKU2DEyjo5+jYBSMglEw4gBoMcs/CM0kIMTArq7FwOMRwMDj4gk+mIaRlX10NnMwg///wPHEzCcAHiTgNLECHyL09dBuhm/HDjL8/3EJfPI8w++/o3E4CkbBCAbg02kZ/zOADgX69+TJ/9/PHgv9//lTELQ8Hz6bCV1yOwqwAAYGBgAAAAD//2JhYB5dSYsTgKbGmVjApwaCOuX/vn0V+Xn9kv6Pi2ek/354C93LOVoJjYJRMApGwYgB0BlN8JZAPl4GFhk5Bg4dAwZOQ3MGbjtnBlZZxdG0MBQAaDAZdAItCytkJRwPLwOziBhkT6eYJMPPa5oM/96+YfgFPrn2DcPft28QM9msTKP37Y2CUTBSAKyt/+sPw78fv5h+3rul+vXY/lBGbh4uNjXNE8xiEl/+f//OMHqVJA7AwMAAAAAA//9iAa8zHgV4AHRUk40dtCZb7O/b15x/X79k+P//L3RZzWjYjYJRMApGwcgAkKFr0EFATKArNhSUGLjNbRm4rJ0Y2LR0GVglZUbTwRAGoEMAObQNGNjklBh+G1uA7tJm+HHhFPgU2x/XLzH8ffeWgeH7X4b/LP9Gq/5RMApGCoBNXrIyMzAx/2f4+/qV1Nd922IZWFik+QSFX7LKKFz++/s3AwOsszm6EgIVMDAwAAAAAP//Gh2awwD/4UegQ2Y0uUBHpvP9uHjG9tuJw76/792R//ftFwMj6Iq00XvSRsEoGAWjYPgD6J6cf9//gO9kZBYVZOBQ12HgtLRn4DK3A3dQmEVERxPCEAeg5XKgw5yYuLkZWCQkGVjlFBlYxCQY2NS0GNiU1eB3dYI6nX8/f4U0FZggq6AgS+1GG5mjYBQMWwBe7fif4d/nz2w/330WZhI9Zc+monGRRUjoPwMz6yMGJqZPkLpidBIPBTAwMAAAAAD//2IZXWSMBGBBAa0vwEcaMzIy/Hn3WvrrgZ2xX/bucPr/4ys/EwcTtIYZBaNgFIyCUTASwH/w8lnQICMDA5uKBgO3szcDl5U9A5uSGgMTN+9oGhhu4P9/BmYBQQYOXSMGdnVtBk5tfYbv1y4xfDu4m+H7hTMMfz7dBW3jgo5PgxqXo3enjoJRMKwBaBKKgZHhPzMjA8Pf/6BDQzl+XDjty8zD94tVTmkDs6jYJ4Y/fxn+//0zmg6QAQMDAwAAAP//7J2xCsJAEETn7gxCEoKowSagYKG9vam08p+tLYIQ/AArEUMkCBIT3ZwknBZ+Qtz3EbvczcxOB1wu/YMAKoJ+PUFp4mqioIijzSOOwvKY+soFpGOB/bMMwzAtxxx/qPeBrLN80wG6sznscA1nuWoeId8+RqZdGHeTMA4mNfAhhyNIu87pTmAd9qhuGSg5g7IrqvtH6TQKJ6ucDNNSRPPLRMnFy6PdQrneSfX6WysYQ+scuiyaKhRtYori32cBgDcAAAD//+zdQQ4BMRQG4L+jYVJ2REQcQGxIRISNhZVYuPbEhhOgI+YEk6CtVtouOMPM+87Q5PVPX9/jjMLmTxLHmru3hdMa5iEHOpe71/l4sGUpkjZi+ywFTUIIqTz/mhkuCjYOkBHLNTrbPdLpAnw4AtXPeuG9PsRqg9Z4gnQ2h7ld8TxlYU+nkhe4j//LaWPQbNDZIKSKmG+bb7IQKk2RJ6q4d4UxYRWK9TVDKTgYsP9JtXUG4AsAAP//7N0xCsIwFAbgv2lCbEBwqtohIHgGl47iIHhtQcwg3YRCl4Kb6CBWamolqeAd2vdBDhB4Q8LL/8L9BYv8C8JNqBMCwUe6FvmkMvv0aQ6r5nblTND0WUII6b1fRrOtLBCFEFr7rzHGmx1UukYYz6gGBsj9S85jt6YQiYZdluDzxGc6q9MR7yKHvZRobdPltljoD6aEkB7xjakWcC8gHzWri3zxysw2GEUWjJ2ZlHcXrQiU6vY89EGsAL4AAAD//+zduw3CQAwG4P+IL0qigAgCRAG6BiHqNIgBKFmAqRiFloqKmiFOooggXVLkchfEQxmC+FvBLizbsqn9EcN+HIQkeDIGXEPmrsdGa69xleDrs4wx1g2Ns3AlQKH4PPyPd3sE6Qa9YcIZwCDCCLRQiJIRgnQLqZYozicUjwyuKt/1AwTZdmOKay3G/kg7nLKwz2xSXC+HOs/nNJ0d/dX65qsIXn/wbVrWptuRB/ACAAD//+zdsQrCMBAG4D/XWIMGwcVR6uCmDr5ENx/bwUE6C5YWXdVaFSXFVBKFvkO9b8wLhNzl/pPc3m3mcnwgUCBhi9OgOmTTZ7KJTbqbvC8PIlegCDl9ljHGWsvdBeI7t089DTkaQs3m0PHKrzeR3NFkP0JKCKlBfe0PXIItBcLv6TTZHtUxh71dURvTpNUyxtrDFZKCGrY4q1eyjWxZKrVYrjvjKAfRXYRd4384/Ps7C8AHAAD//2IZnapDOn0WdJcmAwPDnzev5b/s35n59dBu+7/v3ogysjOMVhSjYBSMglEwzMH///8YGBmZwQc7sAgIMnBZOjJwu3ozcOgagk8mHQWjABcApQ8uWxcGZnFphu9njzN8O7Sb4efNawx/Pr+FzHDCrkYZneEcBaNgeADQIWLMzAz///4F79/89+MbAwMrqzYTF/clRmaWWwz//r0FdzZHep5nYGAAAAAA//9iYRid3oWPOvz/+pX93++ffD+vnLf5emSf94+L5yXAM+VsTAyje1tHwSgYBaNgGAPQcqcffxkYuVkYWKXlGLjMbRl43H0YuO3dwYcDjYJRgA+ABqtZJKQhWFiEgRl0ki0HF8P38ycZ/n/5DL4OAXRtwujBQaNgFAwjAOob/PnDwPD7P+h0au4/zx5b/Hn+7DWrtNwHRja2twygjihIHnoOABiMtJlOBgYGAAAAAP//Yvn388cgcMbAAkZmFvDBP3/fvRH6/fyJwY9rl8z+vnrO8v/nXwYG9tHLmkfBKBgFo2C4A9Do9L/PDAyMXP8Z2NS1GbjsXBjYNfXAe/NGwSggBbDKKTFw2bky/Pv3j+Hvpw8Mv+7cYPj37iMDAxMDoj0xOtsxCkbB0Aeg02dBs5scfxn+/fjB+fPmVVVWSVkrdk3tXUw8fOAZT8ZfP8H1CyLPj7C8z8DAAAAAAP//YmH4/WsQOGOAAHjaErZXk5nhz6vn4t9PHXH9fvqY1Z9XL7gYYAdIgUYuRiuGUTAKRsEoGH4AfIDDHwZGdnYGVhluBnZdLQZuBw8GLitHBhYp2dHTREcByYCJl4+BXc8IfHUOaEn2Nx5ehh+XzjH8//IJMcMxOoA9CkbB8ADgq1AYGBh+/WT5/fiJwI8r543ZtXSdWWXkXjMws7xi+Pv3C+TOXsgd/f9HWmeTgYEBAAAA//9iGQRuoD8AF/QMkJOkmJnBI9eghsb/nz+4ft27pff70V2p/79/sTOwMUIaGqMdzVEwCkbBKBh+AHR8/T/QFSf/GZj42Bk49IwZeFw8GLhMrcB3Ko52NEcBJYBVUZmBh8ED3Ib49/kTw+8Hd0BL7SBnhrCOzObXKBgFwxEwwlYr/GNg+Pv2De/PS2cCmXn5mJhExDawiIhfAdcnnJyQQ2L+/R1ZaYCBgQEAAAD//+zcsQrCMBAG4D+mIUVCaXfBVRBRUAdnERdfXBxcAqLgrIPgVG2NSSXpIwgi7X1PkCGQ5L/LRYjEHyzjt8Km8NmCfcMVT59qdyvnstf5uChPh6G5XFVHCjBB7bOEENJIoaJpwSIBnknEgxHUcg212kD0+vBJNCHf4EkKPp7WA0SKHLlzKPUeMBZo39WLkAar3xXggL3f4sduO6uMqeRkrnmS6lD99GcK8388WzYrB8AHAAD//+zcsQrCMBAG4D9nWxM0FNwFKQguXXTyCZx8c4cuLuLg5CKtmaRGEiShvoGItPc9wa33c/cnQso/GOO34o9mTBoNnGngmnruzH3XHqu9q28arrvDJgFu62WMsZ4JIWJYAB4elAukiwJqs4Us17HghRdN9k1ZsYyFU/Z8Qlsd4C0wUsMtC2Gsl0I7bZrAv56wlytoOpllq1KTzkFj1V1Jfv7zBgTAGwAA//9iGYmVKiMLGyTSmZjAM5s/b19T/Xn1UsCPC2ds/75/y8gAXzk1WgmMglEwCkbBsAP/IBU+IwszA4ukNAOnmTUDt4M7+EAgptEDgUYBlQHoWhROQzOGX3dvMfx+dJ/h14M74INDGP78ZWBgGT2ddhSMgmEBQJ1NFiaG/79/Mfx9/4Xh15OHgr8f3zf5+/rFdWY+/pvM3FyfwYNLoNNpRxJgYGAAAAAA//8aoXs2IffeMLFzMDDx8TP8//Gd79et61K/7j9iYvj/A7KXYnS0cRSMglEwCoYf+PeP4T9oGSMLEwMTDwcDq6wC+B5Ndg1t8MEuo2AU0AKArs/htLBj+Pf1C8OXPVsZvl84Db5qh4lntLM5CkbB8AH/wUtlmTj+MjD8/sX76+ZV1x8XTrMyCwgvYpGUOQHy5v/f0GW0I6WfwcDAAAAAAP//YhmRh9+AT6FlZPj38wf337dvlH8/eWT0+/F90b9vPzEw8zNBOpujZwKNglEwCkbB8AT//zMwCwkzsKtoMHDbuTBwGpgxMItKjEb2KKAdYGVn4NAxAC/RBm3f+fnoPsO/V28g1oFm2kcPoxoFo2DoA3Bfk4mBgQt0UtBf1p83b2gy8QsJssopnWdTVT/FwML2D7SFY0Rdf8TAwAAAAAD//2IZWUtFIRHLyAZZOvz33VvNHxfOxPy8ecXp38/vvIyso/snRsEoGAWjYNiC//+g11EwMLCISjBwO3kycDt5MbDKyI3G+SigPWBkYmCRkmFgVVRhYJNTYPj16xfD/29fGf7//Td68vEoGAXDBYCW04Lu3vzzh+Ev6BTqxw/Yfz97xPPnzWsmJh7efwygmU1QXwO6nWPYAwYGBgAAAAD//xqZU3jgZVS/mX/dvWXw/eTh0F83rkmB1lAzcsLu1BwEbhwFo2AUjIJRQD0AKvdBp89ycTKwCPMycBqagu/TZNfSGw3kUUA3wAy6g1NFA3zNzv9vXxh+3b3DwPDn3+jptKNgFAwnADp1FlTn/PzL8Oflc4YfF8+qs0jKWLGraF5mFhF7DxpcAu/bHgmAgYEBAAAA//9iGUn3vcDuzPz37StoGQvHnycPhH4/ecT198MnBkZ2ZvBIxOjM5igYBaNgFAwzwMgIvn7i39f/DKwC7Azs2gYMnKbWDCxio0tnRwGdAWh2U0KagU1Zg+H33ZsMv+7fZfj/d/Q4wlEwCoYdAM1wsjMw/Pvxjfv7+VO2TJycXMw8fFNZFVVOgvL7X1BnE3zv/zDP/QwMDAAAAAD//+zdsQqCUBgF4PNfL1fMtqagrUgSwYaWWnr/JaHQJWhTEHoANb2G+Q4Ner7H+A//OXpOMe5vU9R2aIt8VaXJsbon+/Zdom86iFHjJYKIiKbF9mO7uCPQ6w0W5yu80wXOkoVA9GfWYhh4d4MI9eMG0eyIIJokEShPD7+bpnm+QhFsze6QuWGcKt+vIfKZRcAF4AsAAP//YhkRHoWOHDBCj7T/8/yp8tf9O+O+nzlt8u/LZy5G2PKV0VnNUTAKRsFQBaByDrQfEXzaNtQPjBCCEXoo2ogs42DLZ5mYGJj5OBlY5RQZ2DV0wJ3OkXjP9CgYYABqi3DzMrDJKTIwCwiBB0L+w29C+D965dooGAXDCYD3Zv5n+P+bgeHv+3fsP29edfpx+dxTVnml00w8vDfAezthp9MOV8DAwAAAAAD//xoZM5vgU5/+gWY1mf9//87689ZVm2/HDwT/uPmQm4WfhYGRg2W0gB8Fo2AUDD3wH+lieDBmYmBkxHKVAvKpd+DBN4aRU+ZBO+Gg02dZ5JXAM5qgJYxMXNyDwHGjYMQB8F18LAwsYuLg5bTMImIMf78+goTC3//g2fdRMApGwXABoHqZAbyc9v/f339/Xr9kxiwg9Jfz//8vHNr6NxiZWRj+/xzmezcZGBgAAAAA///snT0LwjAQht+00QoZHKVKR4cOOjiLuOj/nxR0UoujikttmyZySfsThFLvgZApcGQI95F7T5qy7IAZv4Uedmtq1PdborPrsjgd1vXroaBbJ4y/zzIM02HaYJEql1r7SoiG222TLxQSCCJS2w6BIPSxJKmvltplVWmhbmJM6hoY+DM0b9L1s/et8unuzLYbZDyD2u6hNjvISdwBA5l/RkQjyGmC4TyFyXOY99Or0obsjzBM3xBSwFY6qLLLuDgf02ixUiQWRqOQbPHpd+smgC8AAAD//+ydvwrCMBCHfw2lSVt0cXcUHHSwg5Obb+ArO7l3EEEQRJwsdbD/e5I0vkOJ9z1BCCF3Sb7c+dS4f9iELUFcXy+L4nQ8VOc0AaEWEYKhtxXfJDIMM2J+UcgUHJDwlFZjbVKqk1PhQ6gQIoogwhjwbVcrrZCWJfqyABUf6P1+UHZoMG3tq5+T/b6sUuwFEmKqIJcrxLs91HozgsExfw+RUbrDZIsuz1ClOajR6/XfJ4ZhHMPYDCZee132Qnu/zbrnY96/cyniSUOtLkft8NdtAF8AAAD//+ydyQrCQBBEK5lMIC6omEtQUQRvXgQ/wW/36kICigcPboiIJzF7ZDrJP7j0g/mGZrqquv4is6lXasjiEMnj3vTd1TTa75wsjoTaNHBOk2GYj4NyhoWCmRbOVz1XIoVtk/1O9gYQrTZdVNWrdeiWRVtS9VCqI6USqj6YgY/09UR8v4EG3uWI6HRAfD0jfYW56qmmnShVT+Orj6ZlVHGVQjSqMIcjqjiRHe7TZD4ETYPZGyAZTxBuXATeEpna/bO7m2F+D2rDUE4jqBlc8bfrmbHo36TTnWuG9MiN9KvtIADeAAAA///snT0LgkAYx//nyylNRdEQElZiIJEgjX3/vUKDoKEgosItSvOyuLOWllbR+8F9gJuOe/4vj1bJifYvT0b44mR2Ovaz3dZi8UUnuv6dNEgkEkm5UJTi40hJ8UhpGhTDFMolHbqgrgfTn0G3bNCBI4pGCP0jieQ58tsV2WEvTrpeIQkXeGwisPgsFFCRHRH59gpk+fkdGKA2WzCmAQzPh/IpiZNIyoDa7oCOxtC6vcLKXqPlABJJvRC5FvBKhVdyRxot54QaDXMSJNR2Qu7A4XbaSgLgDQAA///snUkLwjAQhZ/T2IK2ilYqetaC9eRP8P9fPXlQFBdsQREV0cZWJm5Xby7NdwoEwkAIWSbznkj2u/+dbvbNZG+17aYdL2a903DQl9HKSY4JDCO5HeI0Go3mUzzEepRanXzVVeYBUatAeA2lmmq4LkS9qS6VnNHk9iOzSbbzXvBEILsEs9VRoiQ8ttkOIOdTsAXUJQohw6XKdMaTEWS4VvFQ4Z7lfJYc/MIDZaq8C9MTQEUblt+B5Qcgp/wFsWk0r6/xSiSoWkMuzwXXh1tfRrz3NJrMIVh99kzn8YQ31EB4zYbldwWZlpSH/X+ufQBXAAAA///snb0KwkAQhOeSS0z8RdFKREERRLD2eXxfC/EHFFLEWpKghZ56iVwuYm0hatjvCbYabm53dnl8Ov5AGZ+BOW76U3D1vYlYzGdis5wm4hwzDr2ukcScIIhv8tQgQ2U6zGxhD4dRqaYdj8JwnI1/dmD3Bumj1KjVwYxnBOB9DVMdFN5ogdebcEYTxOICGYW64+l7ENs1Lk4RSFaQUQA1BfLiD4xmlkFVMQlWTfQB/W4/Ndek+cSvobrtrFTWp9msQFdHZpMgcggDs7T9kOEJN2tvy+DQTuR9ANPdMc6zdXY5A8ADAAD//2IB7ecZfgBSUIOWnYHAn2dPxL+dPGz06/Y9vv+/f4IbdaNgFIyCUUB3ANpH+PcPePbyP2x7BohmY2BglZBgYFVUAXcyWWXkGVilZCF7M6VlGZgFhRiYhcWo41qkw4YYwHvaucEYtNyUVUKKgU1eiYFdVZPh94O7DN/PnWD4eeMKw58Xz8HFKvjsbjYWyKqRQboFA3SnJsOffwxMwoIMbPKKDJxm1gysckqjjfdRMDgBqK0CyoO8fAxM7NC2CfiI6dGVV6NgFAw7AL6K8T94NdO/r5/Zf927ZfXj6vkv7AoqGxi5eE6DT6f9M8zu3WRgYAAAAAD//+ydTQrCMBBGJ4naJiq6ERGXbgRd1I1gEaSX70a8gaC4K3QVhIrVRDKN4gWUUubdIT8z8+WlhfGopuG7gowLd7EbPvNsXJ6O3UeuQQzEp7NAEATxV977Ev+S8BiD8c5gEYGKd6DiBILZHJgMK0EP9+bZX047rK1stq7AnUzxPajRGotezRi+5TTFFeB290naGjdfsaAH/N5EbRKQ6y1Ocgmirrj0gOj1gYdtsGhRtuTIJ4gm4s9OLt2670B5OUfFPh0xLrJwuTpwqYwT+TUKAHgBAAD//+ydMQvCMBCFX9okpSoFta0VBccOdnMRhIL//wc4VNRVECm4aLWN5OjQyVFryQfZM12O3L33ODkXdgzK1Xw9UV7OSXHM0uKQpeUtdylXk6wWWTet/g0GQ7vQjSNNMhU5y1IWpudBhBFNKvk4gDUcgfsTSK0rjJd0vl6XGxmbrFYZ2H6A3mZLISliOkdx2uOR7VDlV6h7AebwdunemzXdZhDRDO5qXWs1vV/ezGD4CJmB6XVaKaF09rnpTwyGTkMGpUrprSEOKRZOnIRWf1Dpt0pvYNLWaVXSx9PfxzMCeAMAAP//7J29DsFQHMXP/ehth0YtwtSkZSBh9gY2D+FhLSQGC4nBYBJBIkW1da9cZbZJ6f29w/8rOf9z+EcHwx9ES1LkOaLJatm/TsejdLPuEdtR1I2JOTQNBsM3ISBQTLceCepVIfwQdqcL0Ww/fwmtsAVea4BWPBBugbDiqE106Lw7GEL4AeLZBNqe/baYI9vtX+OvQIPw/atpcRDh5BJkPwDTpkDGDM5QZBjL6/5Z+yXIPjcYyo6OOlEK8hJDHg+ZjE6OSpM65H2rpCT5lam3hz/wlwHwAAAA///snc0KgkAUhY/OaCikEJghgkH0AG56pp6vt2jlxkXrWgUSRNEfjsWdMXqCyOR+TzCzO/feczj98NC+7WVUFyCkFnSA1dTVfnwti/yx3QkjQlhwMAzzJeiKSXUbSpk8Jl0yXVp+eTp/SblBd94OmGkGmaR6yCS7Z1chex9dXe3chwhHgDvQnZ63Yg11qNCca9i+aDOcP/5EYwpJrSCEnCRwpjPIKDZvY5gu09YbaQGKnre7MwzzGSApu3k6yvumXFyieOmk2cry/EK7noaBXkA/1Z/3bwJ4AQAA//8aPvdsQke1////B1u6xvT343u2Py+f//v7+SszMyczoiAfBaNgFIwCGgDwwglGyFZL0L5MJm4uBlZJaQZ2Q3MGbhsnBk4TKwYWUTFwwxIyk8E8JE6eZOLgAi/zBe8fBS31+/md4fv5Uwz/P38cNCtFwGX/XwYGZl5eSIdeUmZ0RnMUDA0Ay0Ojq65GwSgYUYCRHXKq/M/b10z+//ypya6l941D2+Aiq6TMP2ZRcfDVXf9//BzaI1AMDAwAAAAA///snbsKwkAQRW+yidklIloHAyIICRLBSvz/3srC0sJHY0iTGPNa2ckvCL7m/MLCDjN35l7nJ25ZhKD9Zl0UaNObyYuLm9NxWx32mzZLXVQtoAS7ETIM81pIxWzJPNIyPaMvSQk0aqUYjeEEU8rD9KIVZLKGG4Tf+QC05icwWMSwHHNX9qD/tNzt0N0z6LIGBqIPpn9XTex6Z18xHMGdzWmF1sRfMczHY5pMo16QCy3DMH8DDZw7NJer0nmu7PFk6UVJaEl5tqWqbeVrbabX39xsAngCAAD//+ydvQrCMBSFz21jDC71BwXBqai4CA6Ci4MP5NN2UBF9AFFwEUrStJGkgw/gYFvzQfaELLnn3pzDgm6vAtv4DuJtFGmK3K77LVDX806ekr26HCfkIlDqfDqPx1NZ3BRFmVJAIcAGI/DpAmK1Bo/n4PGsLDyjPkiI2t+j7ca2bJzIZluaFygJeUigX08QK37aSXTvdFv0iw7C4dgZHDXRAM/TQKxglanPuJwXxj2ev8AJtBZNzhyMjImIsSVRkBqtHyZTucnsn5waF5sA3gAAAP//7J0xC8IwEIVfS2yqLoqDUlQUoTSI/8af6+zSzU0E3QR1FmtMityh4C6I1vt+QcgQ7u69d1FhVIECSGvAlyh1TApn227X5pIvjTueeNQtWU1BEN6GM5me35pnYxM2NFSnxeol22XTKdRgDJ0a1PrDRx6zQoUj5eLjOnQ24yEfNZtlUcCfVwgCx3fzutn2o5Aw5Mi63OS/QlU34TMKwrdD2/PJmcWOAUizKQh/B9UXu7qkKQAAIABJREFU9gp32Gd2t5lHo8lN9ZIFD0xpM+0vK5sA7uydMQrCQBBF/8bdbDCVIFaCCCpKkIBYWNh4co9gY2ErgqgoqZIYYjYyG48QxOC8G8wUA8PM/182X3hK7yeUVVc4QiohlOqbZ+oX0R1lkkH4krWaDMPUg313q8YOLZwtcpedBPDXG+hwCW82h1DaXjHJXOeXzFrrxHE13OEYxWKF/HTE63aBiR4wcfzJMf520aLqdUn5ZW3Ibs9qXQTPfqYB0EXDpAlAsSdKccYmw/wZQlexjfn1PMj2u44eTQ9eEG6t1aCVpzR42QTwBgAA///snc0OwUAURr92WkbQxEashQhdWFh4C69tYW/DQmIh0ZZISlqduZWZtq+AMucV7mbuz3zHUYEP9aaUpOdgMjrPs8N+JU5Hn+IH8qx88vxAoQwGwwcgKraZlYi50wXzemD9gU6Ka46maIynaC2WaEx83YT9BYxpxRSfzSHDAOISItmsIYIYdlu893xV14ZgcRe2x/VGU/2b/SaFTO2QAvS4g9IUeZroybr2xVZhVpatH0ZqoKI23arBt5r1v5L6CERQEncZ30AJwXZhgq0Mhn/DKXJlZBjxdLflz8N+KK+RB9cN5DVCnmXFhLuO3k0ALwAAAP//7J3NDsFAFIXPVFtEIxFCWNhI2EgkbCy8h6e2sbMhIvFXQcRPOkZH7m1fgAUp8yX3FSZzZs451xYi4YeaiEeHjpxPB7fxaKg2q6pw7Wj3AEzDm8FgeBMKZKr4/LAFrypxW21ku33OLrqNJlKFIpcBWfb/iRsS35lOD3I24eymJhfghzt5IneOhuXlI6FZq/9EPvabPA4H3JcLkEPosfehL1cWnfzwEu+E5J/jnIdUqQynUuNB2tiWX4WancPbGZrEvQQsuq8YsWkw/BVRdpNymwrh6Qjlr937clEOZeCr3VZoGWguEaMVX0mz2QN4AgAA///snd1Kw0AQhc86mzRtCoZGq8X+4A9FsIj4LD6uVz6BglIqXogolBRtBZtim83KbPICQUqt3e9yr5ZZWHbmzJyV6nP8B7ZRlDyzF8JUV4kkGwTpxfPT0ff9bTcZRtlhSNuMYrFYCmCUzDSby+Q3n0ugoArnoAVqtlHuXcI5PoV3dmHW/oWb9y9gVcs9PDHJ9/yxDzXmpGQCNjQQMv8DZtnwnKgGqBbC652jxAqzX13LeK6KNP5icz0kowiL1xeo9wjJ8A38PlCTD+jZDGCVk4svW5kzsaj4EGUfFIaQwa6ZWab6HmSjCVnfB9V2NjOYBeAZLZPUj6JMQbZ1cYtlQ8kdZ7VGGseYDx6605vrK6fVKYGcO9oOFHeQwHONOd9a3RUAfgAAAP//7J2xa8JAFMa/xKhJKIQuDtI6CA6WdKhgF3XzL3eSDkUQcQsi0kKDopRqYi53cu/i1sXBQXy/+aZb3r37vvc+RxeY20IZJ4+2/+qiV6mQlUf+7mS+iYVY/0DuUwoa53kdhmEugZQboUhh0I4V+8GFU3+G3x/SBlY3fIPl+UbVYdugwbIpZsR7HyDfbJHMJxDfcfEZeP1mUxUztHbwSJuA9XIgXgx0AVkG8bXCfjzC4fMD6XwKlfxRg0mxPto+e47lODu4LFN/SeV0ysX9B6Ruuq8d+DpTttszc8vM/yhA7rbIFhHydUxHLH6yMMydUozqVEuUZ31cRm0lVa36EiZuK5yVGs28/KQ/uAOoNL0txyaAEwAAAP//7J3Pa8IwFMe/TRWLc+1+eBwoyPC6yxB22r++gzDwIGwgKh2VIaybstUNim1jIi8pzMPwKMje55JLIJBAwpfvN+9VjjGuYezmjYRep3RJC/kRt4vZSy8Lx131vSpjby5HURiG2Y+2VWVMFFNrI1IEOZkUiz31TfuSWqeL+t09vJtbdsz+wnFMdJX2SP2sIJMlZLwsJx7gf4myy1QuLk0/U6oMLDjOuRcSkIpcy69P5NMRsnCC9PEB2fMQefT+Gx4S9imF2DlGvTOqUoOuAVQB9+wJ8m1uHFG5iFG9atl4MxVsavi2cjxT7t8GxWuEdNBHEYWA0nBYmzPM/8a1ukXGi0AlSSA8r1drXbfFSWPmnjdz4Qea2iTRfXE0ANgCAAD//+ydz0rDQBDGv6mbTSvVm8WqB0UU/3uwT+Fr+IgefQB7qCJKjopprRSkB6Fq2qzZMpNaRPSoEJzfaQ85ZTcs82Xm+wy3uxQKVlQDC/86gOs/wXVim7bvjofR9YmLb5eJN8oW3WFXUZQ/QeJMMvihz6NM5iuwq+sID45g1zYR7uwjqNUxs7AoLaPK93Bxx3837dYeTOscVI4AyluSxRfgV2ZM/NSFllel2SpMrS5zhBKUrfxI9jJAEl0huWjirdVE2nuE63VkNrM0R58qykmMDeGLaOCnjxALNhWfZ80SIe228X52iuTmUs5EuLGN8mFDXJuDpRXdlAn8bYwe7uU9jboxPItdgY7+KMq/5uOuZBGPu0qIqrDhLhnzDOf6yLI0NwsqULEJYAwAAP//7J0/awJBFMRn171N0inCcZhELAQVLGz8FvnSYlKkjHhEFAkpBEXxD6hhj9u78J62ghYKh/uD67ZebvbNzFOZyxyRNcvTSKSA3HKovmjCr/bf53vLLhdHMeommg6H4wR0SZPATA/7S8gGqF58qOCZ83662uDSG12p8s+y4wxkjqe+tA6FPvPdY4sgNZryVOwa4o+1JoU1BaSnkMsXuKxG3GFR03mkbL+iaRoJzd1HB6ZHttkQyS5iO7J8BIT2Ln8coPO8Fig+lAtNVjDDXyi/j+hnxOtxdG2Ah3oTXumVM513nXdOLDc4R+MhzCBEPJtDPmngBrZzh8OREWwKu1mX4+nkza4WexWUuhDiuGcjQ2ITwD8AAAD//+ydPUsDQRCG37kP92QVDTYRa4UIWqSyEiGFv9cydRpTJYUWNgG7GBIhnNyRO9aVmU3KFEosjszzExZu9nbfnWcSz3KFJsFrHHMa4YmyzJMxp74sEk45fVGBDrVXU1GULUiS6eBX32FeJpeUk1hGeNiHR2Tdu3BoaZ2FhEz5FdxDn7bPRRZTsVAm/5ID4b/kNeubXTqIEB1ZRPYYlGjt3wYnaW4xRzkcIO8/oRy/wtdL+WkhQ+xBFPHPn1LozS07770JIbLh4xIBzvsEbvqBcjSEubyGuenC3vekt3Mv4RpUV3CzqfRq8istrGe2UwMtk4qi7B4W7FFMcJ+zi9XbS89cdSamc/scArc0WGmbAoAfAAAA///snb1OAkEUhQ8zsy6yKyKl0SyRDgobH4CK+L52xsrKwsJCCwuiBBIFFjRkhYX5iZkZYmUnFBvv9wKTTHKTmZxzzxHFiz/b/Oi1DvXHNJFvw65KR4nJcic7lyDcci3VnRAE8YPx/VRODBMBeDXyfZlHdYjjE0SdLuLOJcRpg+7sD7D9CEFyhqDRhBqPADWxXQ67OcwtC5bAwj3wWs0FJ4BUzd8xBnLwivz+Dtn1Fb5ubyCHa/C6VTO5V4O30UdtH0LcBwe5eVMSepJCZqmbPfnSg7SW0eUC1olknQMsLIPZHelK9G9yFtT4HfnjA9b9Hsxy4feOgUJWGhAEsQOsy4Ex6OksXj0/xavWebt8MTtkB9VPPZ87F0lhAPANAAD//+ydsQrCMBCGL7WmFUEEwdHBIuLg4DP4FL6po09QUKoIguAiWCxOYtqmjdxZuzlpwcJ9T9AhaXL/5f7frl0X0BJkEGTyzE1Ox3m8XS90FA5xsN68RzW50GQYBorLG4amp7qM3RUdp5zLdKczKo7kwKO5TOY70AAGzWDsXp+6nIYEwGr+x6Z4RovigUUxHA53hj5gtIbksIP7aglq49OeaHSxK1y4AIkKBFosPIUFpomuzjmtApPG9KzWqAeowAfpjWkvUm7taAKWlL/9hn9ECNCXM8T7gOJlyJis1Eh4/TIMUxihCgG5SgBuEUZT2dk1bOuW+xJycW6zLucdADwBAAD//2L59+P7IHAGseA/eMSUmYUVtBeI/dft60Y/Lp01/fv6NXRkdvRgoFEwCkYBtCcCPfwHVGgzcbAxMHHzgfeKsSqqMnDqGTFwGJqB92YyCwiPhhiVABMnJ+SeRQkZBibQgUr/GBCzNlQH/8Ezm6AOLhMfP+Sk4NETyDHAn9cvGX5eu8Twdfc2hm/HDzL8evyMgYmLhYGJhwV2jwntLGdiYmAEbdoFLQkD5UnoTOffF28YGK9eZPgpfZGBTUUd3Hhif3gPvKcTtNoANEs9LPfegu7Q+/SR4ee1yww/zp1g+P3kCSQdjx4MNApGwShABrCO5N//DP+/fWf4df+O1PfTR13+vn/z+/+fP48ZmZl/DJmltAwMDAAAAAD//2L59+n9IHAGkQBUWbGyMYAvNv314+vft6///3n5nOHfl+/gU9wYRxsao2AUjGwAP6gEdD/gP4Z/3xgYGFn/MTCLCYIbstw2zgwcplYMLKLiDMzCIgxMvAIjPcSoChhZ2cGX+TMJCDIwgPeVQKKDpns2QTObnNwMjGyco3UAFvDzxmWGj+uWMHw/eozh74d3kOs14CPidOrkoOzp/AuekQbBv+/fMvy8eZXhz/PnDF8P7mXgMrdk4LZ2YuAwsWRg5OGlj9voDP68es7w694thl/37jD8ffeZgYkTuvR4FIyCUTAK0AD4hGpGBobfzx6qfT1+MPbft6+sbPLK8xgFhX78//NjaKzkZGBgAAAAAP//7J29S8NAGId/l8vHhbSgUJUg0smho+DU1cl/uFsnJwfFwUFdpKK0hg4xJk2T5nJy1xQ6lmIgJfdstx3vcPB+3POaPAobcI3dUCM5QlCxTI+yl+er1ce7z8MfJfogavxGP9gaTavh1XSDacLwHNBjC/T0TIlJ2PUQ3Ztb2JeDtkepPihVXSmZcBKb1asE2NhoZQHS64C43jqZ0azDU6zUipP08R7JeIT8dQ56Qvazzf4XstMpCwJm1eVLE5RxjPztCyIHiulEncs8g3XRV4ZowhgMxz34rrU0MxefEyzuxlg+PYAHAUQGQFpoqz+uGo1Gs81Geld8z3o8+u0ZDptZ/vmI2E4oMumqkQt6Gx4yAH8AAAD//2L5/+vXIHAGEQC0/4ONHXRpOO+vu7c8v587Hvz76SN9cCDD6qDRlSijYBSMTABqPP/9y/DvG2RjJhM3C3j2EnS3H4eeCQO7hi4Dm6IyA4u03GgCoQNg5uZlYGBmgcxq0qoNDbvnEdRQZ+eAdKJGKwE4AC/XvHsT3MEB7e9hBB00y8Q4qPb5gAeQmf4yMIKuXGFlYPj75hXDt6N7Gf68ecnAKqcAvp+TXU2LgU1ZY8jPWv/78I7h24mDDJ93rGf4efs65NReWFSMdjRHwSgYBdgAtLz+/+M3w//fnxn+//zBxsjGLsTEzsH47/MH0H78/4i7kAcpYGBgAAAAAP//7J27SgNBFIb/ueyVgOiSUlKkD2hlE8gj+LbpJEgIhojYaRlYrGR3K3c3OjvKnGwgVboNkZzvEWZgbufM92uY/2A0+m3bb7TL1byoX1eTcj67Nx8phJIUhcIwzDnShsvbZpv12PMhLxP41wOKVghv7uhvpj8YQnhsKj0WIo4hw3BbweryjuAus1pDhBFkELDNcw8ynr4sqWWT4k1inFZ10M2VUvRYIFovkN1UqN/e8Z2u6X+1M+j+jG4R5TlVOlXSJ3ttJ7mtXWEMTJGhel7g62GK8ukRtmxorYLHZxeGYQ6w29NI521dwe3KZJ9jlfQLaG8tPb+EJf3a6Y4igD8AAAD//2L5/3cIHKrz/x8DExsz5Gh0FpZ/f1+/4Px9/z7Dv2/fGBhBxwOPti9GwSgYWQB6yix4b+affwz/vjIwMPL8ZWCVlWXgNLJk4DS1YuDUN2FgEZcEnzI72tGkL4DsowR1ABnBM2rwmRtqdgb/QyYyQZ0VJlY28N1jo6fRIsC/D+/BJ7/+efGEAVTPMw7mLPAfdlYRaJntP4b/P3+CZzl/XDjN8OvBfYZfd2+D78IF7bfmUNdhYOTkHASOJhKwsDD8vH6J4cv+HQw/b11j+P/7L9JqLMahd/vcKBgFo4D+AFSPghZwvXur8PPmlSAmHt4vrLIKq5gFhL/9/w1aTjuICxIGBgYAAAAA///snb0KwjAUhU9ptFLERUUXHRycBF10Ehx9ZR0E8QFcXMR/BaFYHfypSFsTuY0KPoAYMN8LhCyX3HvPOWEkTVUa4/3Rscmvnn13d9XQ2WbD/VEmtqf+ICpdo9F8wrl8nJI306Y0UoAVikjU6ki22rAbzSgVVfMjaFtFXruECSFeKUFfagTpLMuKGly92XwiRJRC688nCB2HvgoDSGWs8mT2uaV++Tmp4fRXa/DbGsFqCn82BmVMiPMJVqUGIxowyCGDin5OEQQkeUOwWcLrd+ENeri7DoyYKe8I5ZcRGo1GEQwma3d4cDO30TDD0tlFvFTusFx+Jy4n8LdKVcEaD+ABAAD//2Jh4uUbBM7AA0DXFrCxMfz9+IHv9+OHdj+vXw75++6NGqijOXoe0CgYBSMMgDoTf/4w/PsOmR1g5GRhYJGUYmBX0WTgNDJnYNfSAx8GNHpn5sAC0AAheHkr6HADUB34D3YkLfUqQtgpt6B9f2B7mFlGO5tQ8P//f3DHDHTy6d+P38F7mMF3ag+h8AH3w8Az1wwM/758Zvh19wbkVMbHDxg4bl1lYJGRBx/2xSanwMDINPgGnf9+eMvw4+JZhu/HDzJ8O3mY4e+71wz/f/1mYGRjGZ2BHwWjYBSQBED1HAj8Bx009vwpqE/EysTG/pOJh4fh7/dvg/veTQYGBgAAAAD//+ydTQsBURSGXy4ykygbZGkhykL5SJb2/q9SFhZqSjby9QfIx4iSGd1xdc7wD8RM3ecf3HsW99zOe943xtlkQYZdJVPwrpfMY7Ps3WdWX56O6UiIVDQajeZL0ESTZJNmFCKbhSgUYdTbMFpdmM0u4jTNFFoy+3+UXyv1g8ePd/9i/l6/7uH53r2zzZNNktIq5wmYiiWqoSHix4Gw+VPSP5O0z3jOLLjrBdzVnD+aRqMDr1JDolSGoF6GJp3vMPS/QA67zp0jXZzpBLfRALfxEPK4B8iMkTwmwlQHjUYTDD6fTZeMgi6Qh11a7rdVkcvb6kG2tPACm7sJ4AUAAP//7J3BCwFBGMXfsEsOuw5SklwdFEn5f/yjym1LDi4uJBQ5KG2E3Rkzmg/tXcnK97vMYe7Te8333pdeVWYegVfr5skQZx2p9ruSXC98fQx5nxrD/AOvbKbWlHWyezMzHuBW6yQ0850eCq0u3FodToWNZnowtiUPJlaA0J8V2OIp4Knak92mPp+gtisa2TQySi5+9TdNJIeJ7f7cEPFyjlt4oJ/b6zigsVpbCJZvtpH1v7g7VwjI9RKXYEhGM5pNqajJtv6TZmHdwjDMO7zebxvz1oDabRrXyaiPXK7olMqDjFfcQ0mYNBpOAHcAAAD//+ydsWrDMBRF78N2HLwESjGUUuIh31AypFvG7v3NbBkLHpq5BDKVEgymCUmpA0U2yJaKnuU/SMBtdX5Ai4Z3r9696u9kRnZwUIq0EF7zdYzlLh/Jw54dwu7vGYfD8Yfpsn5cAhOAQg1/nCAy2cz5I4b3MwQ3t+4G9AyTV1NlCVXV3DTKObVLQk5odqhTAbl9M853a9T8dv9F2/85Q7sqa/KcZq22KCCzd14PHmxeIfMMqhIIkgn8K9taSzbTS1bonbWgSvPUp5vWDGPx+3mAeHnG93KBcpVC1Q2XG3Ku1LzWnu90h8PxH/EIRBr17uNOrNIn+IGMpg9r7zo+toWvPRSbAH4AAAD//+ydywrCMBBFbx/xsVSLSkXBhTsFcSGu/P+lGwVF0UKh2F0R+04ik/6CSpWcLwghGUjm3jv1DQgySUbDINO4VYbBqLie1/weDGScVT4Opsu2RvPXqKRZXt1304TljsGmM9XRbM+XaC5WYENXn4EaQp0cmSZqUD95643GN+S0v7dPn0A8H+DhHYLCdKT4P9UmPTYp8IhU2qWElCUK74JYcPAwgO1OwEYTWD0HttOH5QzUzF2r67x3HYYBHkUofI8GriO/HFH4N6T7HfLjASKtfOXkn9UWTY1G8w4q771UtSc7nelzrYPNVii7YZIoRVHtCg6AFwAAAP//7J1PS8NAEMXfLEnov9giHrRYafEjeJAe7Mkv70UstlixeCkt9mBLW8Em7lqZWUUv3lLYw/wSyG0JZNns8GbfiygJ1M2VlYxSBXa9TLPR/cX29ubavszE9YMKNppQFCVARNEkmNoBosMjlPhs5uUVKt0ekmYLVEv1q4UIn1t72/hi08l/cc94hUmD8T2sKLv1SqLBvCoYwlsVCKuchl1of4dk19fsYYB8/AhTb0ibfXR8gqR9jrjVQczPs45kd5pq+t16zTf9aU/7Z0/xM6+4yOXLWXHK5UiZj+kE2eAO+fMTtsO+FJtu8Qoy5HM0FUVRCl7/ZDl6z2E3C9j5rOxWy9Ndno1B9ElxgOG9AL4AAAD//+xdPWsCQRQcbxfFazTnF6RQFPwDwSJFrKz924KVgoVga9TInZwagxfvdje8d4i/IHDqTvmKha1237yZNzKTlBsxgWT0F4LywWQ0m7ydx6Nesv3ycsKx/noLiwcGRwZcTLpttiCRb3fhvvfhfgz405hvdpBZkuzZoQ37BPXpCJPE/8oJXo/maBWSD7GEyDacxGzTkhoTX275lY8MagJJBUHXjShuxIeJIpYRJ+slRHnGU02nVIIoe+mks1KHU6myv5NqlOHtFF1eSMjxK2zhUTyh1+cfbtxVGEDtQyTbFVTgI94soUnKu/mE2gVp/fCdTvMLJtu5phYWFveLa99G3s2d3/pdzIey8arFS3UqvVrIb2+WvJsA/gAAAP//7J3NCoJAFIVPOkoGYT/0g0UJrVu1qU29QNCi525TYC8gtIiICMJCM85Y0K5VYHQ/mI2iiAo69545R+W2Gvy8Uclh37xuN8MoCHzKsYyi9fFQQRB+l8yBMoVRqWn5mzOZoTxfwhlN5KnmHH7kuHaNbpwsGjC24uvFQZpHUTqUxNLdfPFPuk0ds2Oh8Gasn96u/HdAQhfY1za+j7YN1fJg9wdQPR+q3YHldWG6NZhuVe9nZmsWscR1xxc9weRg1zLehTrvkx1Nnv/9GjiMop255wqCIHwLNuSY9OUA9/PJi9arhWq0otJ4Gpr1xlGrijjhzAsAHgAAAP//7F3LCsIwEJw+qOmx4MWLgigigge99P//QuhBUbSCiEiltY9Edlsv3guV7kAgkFsI2c1OZsftWtmTO7YRo5llg+J+G+bRbl1eLyOdArbfsyAqEPQFbBlQwGSAE3jwJlOoTQg1X0JtQwwWKzkKf4Bvkk9WDzTnL5xtX9nk4cmPzUoem00MZY9Tp2nK1LctoeIDaTorw9+4WdtJR4MYRyuHee+hXwmc+ASbmc0Atv/DbFKeQWxpkTOrSewmFVA0d8CNUT0SmLTRI7v1gGvVeirpOCsQCFpG7chBkpWnnx+icXk+zmCMZynFa5rib1cA4AMAAP//YhlslwuDCmvQoUW/373l+Xn7ms6PKxes/n35zMfExTC6LGUUjIJhCSCtYdChX4xM/8GnSXJZ2DHwuPowcGjrgWciRtfODw3w7+d3ht8vnzP8efmc4d/Pn+CZTZp1NmEH0EJnNsFLKUf7muDZOVDHCT5DN9LCBLynkwl8Ci+upAc6RAnU4WRgfMgA3byJpBa+QBtBwggozcTFxsDARWuPjIJRMApGAQ4APmH7P3jLwN83rxj/vH7J/+/rZ26Q1L+fPyCDvYMFMDAwAAAAAP//YmEcZPfSgfZqgmc2f/7g/3X/jsWvm1dt/n18LwIeQWQandUcBaNg2ABQJwF02MZvyCEyLPIyDBw6BgxcVo4M7Oo6YDaziNhofA8hAD445dkT8F450FIeyMwmjcpteJ/gH6SjCbqCYrSzCelscvMyMLJzjszOJi4ADov/kL2YoFOu/0LOlWKATYjDtjghhxcj5IAl8FgXiGaGXj3APDqDOQpGwSgYQABduv//F2hF2CfGPy+f8f19/VLs78vnbH/evfn9/9vX/5A6chD0mxgYGAAAAAD//2IBLzcZTAB0VDuo3P/xje/P00f6v58+0vj37SsTIwvj6OzGKBgFwwr8hwwgsTEwMLGxM3AamDLwBUUxcNs4MzBycEHupoPdszkKhgQAzRaB9rX9ef4U3NkEN85p3Cj/Dxu0GD0gCAwY2TkYmHj5ILObo51NBIBNe4NXT0GWGI+WLKNgFIyCIQlg7SLQAWm//jP8efea69e92xpM3Dw3/n3+/Ozfrx/fBo23GBgYAAAAAP//Yvn77jURyugAoMtTGDm5GZj5BUCbXhl/P30k9Pv5M2aG3z8gy2JGG52jYBQMeQDeuP4HctosEzc3A7u8CgObijoDj5svA6eJFQMTv+BoJA9RALrb8ffDewy/nzxh+PfzGwPo9PD/tF6RAjpMDpSm/v4e7WzCOpt8AgyMoD2Io53NUTAKRsEoGL6ACbL96O+rl+Lfzxx1//fz+y9mYbH1zLz838ADsINhQpGBgQEAAAD//2L583ZwdTaZOL6Cj87/8+qFwL/3bxhBm/NBAQnZtD/wzhwFo2AUUAhAI3H/GRiYeXgZWGXkGbisHcGYw9icgYmPfzR0hygA7df88/QReAntn3fvwfcggpYb0nSMkBE6s/n7F2QQY3TTJvjMA1DeYuKALKP9P7hOwB8Fo2AUjIJRQCXAyALaY/if4e+nT0LfL561+c/E/IfTwu44q4DQY9C+TfAVWAMNGBgYAAAAAP//GjxXn4A29TOzMPz9/FH4z/PHej8vnw358+KZLMPvfwwMrKOn0I6CUTDUwf+fvyCX/LMzM7BIioKXzXIaW4BnM9k1dBmYhYRH43im4/bWAAAgAElEQVSIgj/v3jL8OHec4cvebQy/Ht1n+P/nHwNk6wMdLtr885vh//ev4Iv9R3tWDOAZTUY+/tGZzVEwCkbBKBjuAFTGMzOC6kDm3x+/MLOIP5Zn+PdPnJGLi/H/n9//wbObA713k4GBASAWJm4eIpTRHoDvyWJjZ/j74aPUz+uXw39cPBf278N7HvAJtMyjHc1RMAqGOgD3A0AzmsIiDOxa+gw8Lj4M3PYuDMyiEpCDwUbBkAV/njxg+Lp7M8PXQ7sY/n35wsDEwQgZcaUlgFag/6H3If778YPh/7/RnhVo/zMjFzcDEwcHpCEC7n//H92hOApGwSgYBcMOQI/SBq0Y+8sIOr/gN8Pfv5KM//4LMvz//wlUPQ+4jxkYGAAAAAD//2IZFIfugGZXQSfo8fIxMPz+xfXzxhXtn1euCP77+pGBgYVp9NS3UTAKhjD4/+sXpJPJy83AIinDwGFkzsBpZA5eOssqpzQatUMYgC7K//vxPcOPK+cZvl84w/Dr3gsGJtDh66BTzmlet0AqWZAbQB3c/9+/Q/ZvjnTAxMTAzC/IwMgFHUgeDZJRMApGwSgY/gB0X/nnT6K/H993Z5WWe8/EL3iMVUj4GcNf6N3DAwUYGBgAAAAA//9iGfBlR/BLrBjBleS/nz9Yf7968f/Pq7cMDKx/oeuRR0dkR8EoGHoAkq/BS2dZGBhYZRUYOMysGXjsXBnYtPQYWKVlR+N0iIN/nz8y/Lp1leHntUsMfz99hN6rCb3nkNaAEdrZBN2x+f07+G6x0T2bEAC6+oSJnQN8Gi04SEYnNkfBKBgFo2D4AiYmBia2fwz/v30T+XX7hgurlOwHTlPr+2wKKs/AZxqABv0HCjAwMAAAAAD//2IBXTEwkAByyiwTaCkUz59nT6R+3btl9eflc7F/334zMPKADjtgHW1AjIJRMJQAKL+ClnT8/ANu4DKLCDKwK6uD78/kNLdh4NA1ZmARFR+N0mEAfj99yPD18D6Gb8cPgy6Wpu29mugAZs+vXwz/vnxm+P/92+jMJhQwsbMzMHJygu+sHgWjYBSMglEwzAHo3BuW/wz/vn1h/XX/Fj+boooWp6k1F7OoOPgaMvC91wMFGBgYAAAAAP//7J1BCsJADEX/jGMp4k4vUBBvIYi68uZu3InQCoIbd9WVTmeokcTBI1gqeZcIP8n/3/EGtEvEq+mGiNfLtKmOy1Ae1uSfE5OnAmUVmorSQwgUIYmkWTHHeLXFaLFBVsxS4qyeWvoOF+OH8wl+v0OoSsBE2NxJFPsvMElsUsul1g+g8SANCPois3WQnDISFKSdtYqiKP+IzENrP7aSe432VpsXC0xewEoXdYdvtADeAAAA///s3b0KwjAUBeATbKNS7CI4OohODi5ODoKD+MJuPoVLC+pU/EEXwabahjaVC1V8AK1Q7vcOgZybcK5FX23+iXaC0etlHsdtvfMnydYbGxW2YP1+GThj7IuKwRB9axRSwu52IHsDOLMFnOkc9eGIi4AqgCakeh9Abzyo1RKJt0Z2vaPmCsC2y20/pQylM2RKwTwibqP9QGdNNJoQsgibdOngsMkYY9XzCptUmKdypJeTm56P/fQQ+CYKb0aF+l0mVDYATwAAAP//7N2xDgFBEAbg/84WjvMCIvEIV0gUOqUn1tGJRichUUkUsnKF3OJG7nZkyeIJcDLfW/yzs/+oX+lFZ8qj8qDbZapbfCUV1F6TayFEBfgtBGaEUQP1pId4OELUH0B1uvdXFlFtrmSg0HucZ1OYyRj5Yg4+GYRx8CgF+mjQ9H82GbgQLJGEzTfuNrULm8/TYbIkJIQQ/8tnJobrUGgWu21C6+XGZseVNVn6tWEjgBsAAAD//+ydvQrCQBCExzMHSYhRtPfnDazEwkKsfGEbHyCVtjZ2IiioSSQXgsS7yJ3B0jYS93uEbW5njpm1ZBxVOPcC+vQK83zIOLLz46GXny68UTzfWZNfaMolCOI7JqOpUGQSsBms/hDOeAJvsYQ7nYMPRjTAGqBSgcd+ZwRmsl4h2waQZwHml9n6qixTpc1KBZUmpqSIf1TVf5uV+pRYs+WDOVYpNrUQpzeVIAiitpgfTkCG1062CWYqFXfW7obMdW9mV6ui1wDACwAA///snT0KwkAQRr8sG/MjwUYsBEsrCzsL8QSWXtYqYGUtxhsIYmEkiMoGNzuyWSsvEIzzjrBTDDvM90ZWl3MzT/6x0FLZA7SGuRWyKnKiewmEVE9leeWHYX4A47TaRgEiFggnUyTLVX3iRPYHXME2oDX06YjndoNHuobK9oB+QSQuG9jIx+6rP1gjbXXNXTbFyhL+vX/4HYg4hhdEda0MCB7nNhmGYVqLZ23wAdmNo6467MZEmEezReoPR87c3oSVFsAbAAD//+ydMQ/BQBzFX68VoWhTMYjFRILNJgYxWH1ek9kkLE0kkibEoIQIqnq9yrUdfAJF7/cN/rkb/rn37j0l8BPq+5SiZcA/HXVvt6275nJAD3sjoAxSgFjVFL4fgeBreQvv4u6ETFVHtt1BYTRGvj+EUq6Is/tlKIV/OXPXCZ7rFVxzgdt0Amc+A7VdyJoU/s1NHBKpm7yGxdtY8JstEM0Ilb00wxNpeRgXUVXevQYwXnab9kstEAgEfwzPupEDsIejMPteIkWrkev2akQ3FOY4FNI1nv2Dj44AXgAAAP//YmHiExiQQAcfXsDMwvDr8T3Fn9cuxf64fsHv/9cv4qDDDBiZRzuao2AUDHaAmEFiYGAWFGbgsnJg4HHxYuDQNQEv3xsFQxuAl83euMTw49I5hu/nTjH8vn+b4fejh+CZbNBhQOA7kAcBgO22+PftK8Of50/Ae0rZuHgZGEZ4ZxN0WBMTJzf4ED6Gz59Hq9RRMApGwSgYCeA/tCMJohgZ/zCyMAsyMDLxMPz7+/n/r5+gm8/pu8KFgYEBAAAA///s3c0KgkAQB/C/i2hpHUM6RFAPEXWICLr15hJIHrSgwCD6AKEPqFVcDbd6gQ4mOD/YZxiYmf2PKgMEivRZn83/aipaDanvWk/HnnJn2c8eNyi6Qim0hJTZ945mnII1dWjdHozBGOZsDnM0gVL/7+1e8rss4nKSmewDRGsf3LHBPQeR50KEdyABWDNf09HKc5aKvV96vSDerBAHW6jtjqwxVZYnzefNZGY0IFgop7+EEEIqQqa1c1OcjkMRnnfMMBdqyzrI0l1kmB6AFwAAAP//7J27CsJAEEXvxjxWK39ARLCyiIXY++s2qSws7CysTCSEFIKSx4aVmSW/ECKZ8wlTDTNz5/gY2r3SNyhKQUURbFMbnkZnJTxt3MdKiZQIwvjon4zQ3b8leTBtNAPo/ZEzmuEudlsU4W8xZYHqkuCbnFHdrmifKWz74ZwHDwLpatabjct/zF5PllnDvFJ0Rc4ZxclDns35wg0GlHKazanXRBAEYQIoujoLOvJPL5vH/eSv1m8dH/Jws80sPQlq6uGKAOAHAAD//+ydywqCQBSGfy+DSQ7uy2jTOiJo4apNy963ZRAEPUMLo4sEUrQQBsRR4oz4BIEEnu8RzmIY+G+uRbtoXdJ6nnTpVa9M6vQ+09lzWOWFGYC3hPtfHxmGYRranT7HgR1IuGMJf7FCsNnCj9fo/C1hfoYKAyjPRxuV1edtlEx13EOdDiiT1JQ+OSFZMu2mtI1cJ//2PttN7KLOc5TXC/TjZhTavmMymzI0VlpzI1Y2GYZh+gEJesKi7KZXJOdITKbxYL7ciVEE6uqpleruDAC+AAAA///snb0KwjAUhU9i0EBxcxEfwUU3nQQ3397FX6h0b40IIs2PRJJ08AlK1fs9RMi53+FeESo2bZI+pAxOlSNbXOamyJcwdsgHTR2KgiZBdI9Qm3UuBY4ehxhPkC1WyNYbyOmMguaX4p8P1Pst9PkAmx+hT7u0ZEdVYBLgwWQKHqekyWx3731OW2cZfK3xqsoYmr0lsxm30UazKT+Mpv/7kzAEQRA/TwibofUTBsp3BXe79r0xLN7DbsxnawB4AwAA///snUEKwjAQRb9RtBXbvUcRXIje3o0o2EWFgitttVZcaNqkUTqhVyiVzDvCBML8/PyZEY1F7xDhe+RumnMyL6PDuoyjhSll0DQ2nNVkmB7SZjTVF2Lm097M6XKDgBzNlb3QmL+BcpmvJ3R6RXWK8NltIY97qCSGzi50zo0eEd7YCrm+PwC2YrOqYJr1J0VOLqfrDMjZDElwWkfa9YowDMM4hBD299JbQt/SSf24h6bIh0armiaUdwWAHwAAAP//7J07DsIwEEQnxCJQoHQUHAAhOipuQMmRoco5KJAiIAkIhPnFH7TYQVwARJR9R3CzO17NjPj5othyCYb2do3LXTrS+WYA9YiCENyLxjD/ROXR1BpWU2k+IPptdCdT9GZzRMMxC80aovIMl2QBmSyh1iuoIoMhgSZdJHogPuwOdVAofm74PxHKAYCRXmw2+JBH/acUAPiqgPGeTT5sMgzDNIBqLtL+dgfM6RjqfR6X27Rj5VmqQ+He4D3rvwiAJwAAAP//Yvn34ztdA52JmQW8FO/vx/e8v588lPvz8iU3A+iSUWbG0VpwFIyCwQRgezSZmBiYeHkZmMU4GLhMrcFLZ7nMbUdXIgwFAD41+Cd4NvPPxw/g/ZmgfZlfdm5g+Lp/F8Pfj7/AnUvQYB94Xyb4gDakcngozYZBq5B/P34w/H37huHf928MTKCOFvPIvFwSdBotM78A5FRe0CDv6J7NUTAKRsEoGDkAVpf/B53W/p7r580rhsyCQncZ2TkuMDAwvATX7/Q4lZaBgQEAAAD//+ydsQrCMBRFb2yxsSrFSXBycBQRwU1wcvPnO1WkFEQERRzUSrWxiaQ1n1C1+M4XZEsO774bOzN2WzYmiiUVmOtC3WIhT0dLnuOiGMjsBBEE8X20pMgMLLcQBbvbgzudobVYgo8mJJpVgTGI/Q4iCnEPfIjtBmm4QhqtoZ6iEE09ydTJkqpPqd9fh+k4rY4JZ9cLmNcB+1PZZJzDantFI21u4T9wKIIgCOJj5K20joRKEu8R+PNao8md4Tip9wcH/bbT92XpAHgBAAD//+ydwQ7BQBiEp1otipMGN4nwFC5Orh7YyVlcmgg3aYgEmxKHbrO2K7v6Cm2a9P/eYv75Z8YprUghF5Ly83JVzDriGk0ke3qKi7/QpMkTgqgO+jj0zWD1u3BGY/iLJXqrtclqktCsNjqjoZ3M7B1D3C7g4R7pIQQPdxDRGZIxc+m0PP1lUv64c2HkzqbiCSS7Q7IHbN832cU6oouB7EFg3E1qoyUIgqghuijIbUClSSs9HWeW2+43p/ONEwy32tWUeXymUAD8AAAA//9iYRYQpE/gs4I3AjH8ffdW8s+jB0a/H96z+fftCy9cfrSjOQpGwcAD2GFAv/4w/P3MwMAszMbAaWTJwOPqy8CuqTva0RwC4P+Pbww/r1xk+Hb2OMOvuzfBM5mg02UhB+d8hCyNBUfjMOpowrYYg/DvXwz/wEuGPzL8/0Pne6QHEQBtV2EWEmVg5OSGLKX+Ac3fjENsefQoGAWjYBSMAvIA+FRaJoZ/f/8w/P/yD9wOYPj39z9oMPL/rx/Qk9v/MzDScu8mAwMDAAAA//9iYeIToEsMMnFyghs3vx8/lP1x6Zzvj2uXbP59/crLwMIwunx2FIyCQQaYuLkYmPiYGTgMTBh4HD0YuKwcGBjZOEajabAB6JU0DH9+g2f0QBXHjyvnGb4dO8Dw5cAuht8PbjP8efMVslyWHXKFCSMH2/AMC6SZzT+gmc13b8HhMmIBIxN4vyaLqDgDs7gEA9OLz5BBhr//RgeNRsEoGAWjYKQAUEfy3x+G/7/+gw7P+/P3/Vupvx8/iDCysnxkYmf/Dak4aTgCycDAAAAAAP//7J0/C8IwEMUvJdaCg5Mo3cRJB0UQ9Ptvrk5CISUKgjiopf5JohdJgqubUur9PkQed5f3Ho9+9sUoDJRYnNpqvRppkXXs/dZgPCLhI4gKYJ1RHBGsRoh7KSTTefBoTmY0aFYVxvym0sjc15g89rvQlZlnYDYCsLyEsDn//L7FpKaRpCxoqlUKnu6yWZy9L/XfcZ24yXAMeCwBiwPgVQFr1uuqTRAEQXyC+WwGq03LbOXCSCHj/mDJu6lwTSD4TUslALwAAAD//2L5++kjXaKHiYcX3L3+8/KZyK+7N2V+P3vFzszNwsDIOnow0CgYBQMOoFecgK5KYBbiYeAwsmDg9Q5m4HFwY6DX6odRQCQAHWX+5zf4eg/QNSY/rl1k+H39CsP386cZfj++x/D7+VMGhj+/IIexsbKAZzRHBADVI4z/ITObbyAzm3Q7k2AQA1ZZBQYuWxeGf9++MHw/c5zh/8fv4D08o/XuKBgFo2AUjAwA6lAyguYW//7h+n3/jtnPm1c+s0pIvWQREbsHOq2c8dtX2oUDAwMDAAAA///snTEKwkAQRb+6wRghEFTwBHaCFmJjZeXlrQQDBsRGokYNBjVxze7Krl4hEMm8C8ww3TDz/2d8sy60gPrFJzCvow0LbHE+uSK5WTr3RTkStXo1nQIJokxojaa8A5bbRGs0QXu+gD0c06JZQuTzgVfgI1stwbcB+MaHuEbIDyFEEkOl2bfpRrWk8PpFWEFC8szMQyZx4a9B/wDr9eFMZ3jvd8Ysymg3HQrdJAiCqAx62dSXTZEzcYm6+TEcyDT1wCwzAa3xLwwAHwAAAP//7N29CsIwFAXg0x+CUFsnF3ESHXRzdxBcfGi3bi4OTuIkFLGVUrHQQpM2krS7U63o/Z4gZDkZcu+xRXRr+arrbQQyTV1ZlVMeXCZqKFU3KoC6NQnpnJQwmA1rYIDN5nDWWzirjX6kko41FTS685RzvWU2Px6Q7X1k/g7F+QQRxjCYCgurDpRfncl8p+mEVd9oqziGiO+QefbdZ/4A0/XAXA+9xRLZaAwehHX3qJrdtCh/CSHkL+iZfWGWSWKK6Dqsno8+Cg7Yls7N1gB4AQAA///snT8LwjAUxC+2tooOrhXBRXDo5iTOuvj9EVQUtfgHHSq0om2aRJLq7FQs+n5fINmSd++4s6tep9ADmFOFkkrbmrrpbj3hwWakkrTBaKFJEF9H2wzVQ/dotuD0fDTHU9QHQ9OrWbTSRXxGCYHsGIDvA/DtClocTOYzpJsl+GoBEYZQ/K3ZCcCq5H2Z/2iR1IM2Y3mSchKbBF4ZRyW4WDmwvTbcvg9+OEFc9SDOwWqv8AiCIAjidzGbTQtKSMh7hOxydsUtkorrpHJp3ktDEX8HAE8AAAD//+yduwrCQBBFb8wLJVWwFg0WYiEIdpamEb/cRhBELNUEg8FnFeNuNrKb+AkhoHM+YYsdZrgPw+x6lb6tTMOT8fPZ895j4d5n4XGcZ1zXzEJDTBBEDZTyQlV43xKw+gM4/hzObAGz49GiWSe5UAc61ZN5CpBu10h3GyWbZWEAfo6KlFUh1DFPt+kfVZTzRA5TGXIlezbf4QH2cATNsoA/t2zobhvNyRT8ekGyWoJL7+a3CoUgCIL4bVQqrVw2GbLHrcHjyOVxZMKwuHgl1XlOAHwAAAD//+ydOwvCMBSFT5/YiiIiTj4qKPgDFEFx8f8vIkVQRFGpD7R0Epo2RhIdHB18gNxvv0NI4IbknHNNPfPZlEkt40K7cjnPJZ/ugzo/HSwV1W9QGh5BfB/tnnLNGAQDjIILu+rB6Q3hdAewGk3obpb25Yek4RnSSx/7Y8QyVXYxBw+PSHYb8CiCuKRKDqPGmTyko+RNfOLRVngUgs18sFYbdq0BLZt7rf5PMUtlOJ0+kmCNeDpR3k1hcsAU90cn9cNJ54ggCOIvkfcFackRkKofJ1kvu2y1GFkVzzcKxa2yVyTs/SsHcAMAAP//Yvn3/TtNg5SJhQ20Rhh0DD37v7evOf99/gRpGDGNdjRHwSigP/iPOBeEmYGBRVqOgcvCHrxHE7TEbrSjOUAA2lkEXdnx48Jphm+HdjN8O3aQ4dfj+wx/331gYGJnAXcqwfdk8qDtyRztaKIA0BYN0B5WcFheOgc+jZVZQIiBZYR3Npl4+BjYVPkYOPRMGH6cP83w9/VL8Az6f3jjYjQdjYJRMApGwbAGoPkG0MK1nz85ft2+YflT9sIXZkHhn2yKKk8YWFhoc84BAwMDAAAA///snb0OAUEUhc/OLnZFNEKIUqJYkS0UVJ5B6XG9gQQJgoJQiJ9iFdbsrpE726vYiNzvCaaYzNwzd8493xsQpJKK1qQ4BSEQ+76IL+fM8xbAcJLCiTubDJMi5GcLJVSotHixSmXY7Q6cXh8519Pf7Jj0iU5HhIcdov1WezOD2RhyMYVcLxH7dzzJt6+ipJNJL498dr6F7htYJDavCOYTZBtNnRlr1X540Sliux6KgyFEvqCn08rtRtt9lc4pNXlvMQzD/C0GDEtAyUdGblb1oFLt5lreiIQmQfF3HwfACwAA///s3TEKwjAUBuC/MZYqLaIgguIVBDcXD+DquTuIm4MiCtrWzdpaTUPktXgCq6C+7wbJEJKXlz+Sqr/vZKhaqnUrP4UdHZ8t2uhajilDLBhjn0MFIFPebFLSLB0wm5MpnNEYstvjTeaHUThTHh2LlsZs6SNb+FC7DVRwKNqc6V2mcG0I96+m5XV0YBIGJk2hkhT3/ZYyA759VJWR/SG82RxWwwNqEiZNoC8xzDUpW2l5HWCMsd9EQUF1QV+gCBUE9m29GuRR2H6OlRLvKwfgAQAA///snb0LwjAQxV81IraKODsIbg5uggo6uvlfOwlODjooUj+hWhCUttQmjVyL4Cqog94PsmY4wuXC5d4TmXLlIxuTmTj9DVbXSz3a2t3IXvbiwHt6MvOFxjDfIrXP0EkxmS2ZyDeaKA6GMNt9iGqNC8xvojWiww7hbIpgOsFtMYfcbxCtV1BnF7GvUo9MWrkcz2S+yuMsS43YRyIUREp7+ham8fx39VUqNqwiCq0OubYmc7/eeAR58mAICVCIBCkXCs4LDMMwvwY1+0goyNOGco+WdJ2CPDkGlNKkdZB0JN6Z+wHcAQAA//9iYZWUpkkogvZ+/f/zm+HPxTOaP29cDfl1/7bt/z+/uUAV2WgFNgpGAZ0BaFP4v/8MzPwCDKzS8uCDQrhsnRlY5ZUgyw5HAX3Av3/gE2a/nz/F8GX3FoZvxw4w/H39Anz6L+iaE9BMExMP2qmpox1NMgDkICxQvxI0S/z37Rvw7B0zHz94CdEoAK1uEGPgdnBnYPj1i+HPh3cMf9+A9nD+Aw9MMY4u1R4Fo2AUjIJhCkBlO+hgONAOnd+//r5+KfDr3m1xBhaWF6BT8KkOGBgYAAAAAP//7N3LDsFAFAbgv9pR7UqkiYiE8AQsbLDAu9vYYEFcokVIhGhXoqamZKaP4LJozvcAk8zqTObMnN+Q0SS/oGVNaGZOju93HvNpg3teXhZ92b6lIkbIvyTPZuXzdcgM92IJdqcHu9sHq9aSP4Dk54R/xfN0AN9uwNcLhLMJwvEI0XaP1x3QLJ582jd0Ouh/k5y8HIYQ/gVx4COTs6AZLD37+0RGV9FkVquNWDzByhU18Zi7K4jzCSK4qcVVJjajTichhKRKchnLouOuyd3lgFXqQ73g7FQeZyQDvL8EwBsAAP//YgHvDaIBAHU2Gf7+BTWyOP48ecD17817BkYuZgZG5tFR5VEwCugG/kHv02RlYmBkZ2dgV9Nk4LR2AC+jZRxdyk4XAOrk/Lx+heH7hRMM38+eYPh15zrDn5cvwHvlmLjZGBi4qL9kZRRAKlLwyC3kNHTwvk1mEVEGBobRE5eRAbOENAOvVxADh6Yuw48rFxi+HdkDpv//ugVpcPyHXrEzmkZHwSgYBaNgeADQdgrQAPf//2x/Xj4z/P3k4TtWeeU3bIqqDxk52Bn+fYUMNlIFMDAwAAAAAP//7J09CsJAEIVfYjAhGBXExkKwVlAD4hnsvLEnsLHwLwEVbAwKNmJ+3ERms7lBFJH5YIttt5jdmXmzz4iPfrnnVvxC22rToBjpgBviFtg0h1SxNLY8YZgvkkUvZAKo9rqw3Cmc2RzWcCJtEJjPIq4BIn+LeLdGuFoi8jageCuCC9IwT4R024D0tmKpbPloqrOZxDLRJHlQ2dXaf4Ak3LTM/gh6vSml9uZgjNjfS0/O5ODJ4oi4q8dHUS9WV7kcgdXyOSCNNtyZZxiG+W2U/V2WpuRK0knOJzd7PhZ6zVGKtxJjOIA3AAAA///s3TEKwjAUBuC/pLYUQRAcRNwFb+Aiggdw9aAugoMXcCpIFy8gWhArTYe8J02jdbcFkfddIGRKHnl5v1+2dTXKXZrULe2AaGwu5wEbMnh368khJET7XJ6mqRYKJ1P0Vmt058vWRluLGmmN4hgj223sa2ZxSsB5AU958MIAKnDFZXkpl0KzXcaAdRkhkwNk/nmn32GGPxzZCKRotrCttDo+INtv7aRk0glguGq9YjdDAnVR//onK4QQ4vfZVBAijx8ZU3rtU3aPbO6yij7ylxsA4AkAAP//7J2xCsIwGISvpVZULM6ODi5uCro5+OgO4uAuCg4qVDpZpdqGNIn8iYiLWxWH/4MMeYAMx+XuAipMqBLKdVDJgM6ynowPM3ncj4yUITgaxjA/w0gaztPwOxGCbhfNyRSN4Rh+u9r3zryhtd3MLJMYYrtGvlogX84hdhuoc2kdIL/lnKSX+8NC87t4T7EpClfprlhsfsRW4of2EORw+u3INtfW+wPrytOcjMkz6EJA3zMn4m90z6HvN/s13BQCRuJV0OSalXkflmEY5q+gWKMxUOnVK5NTpC5pjUSmF4Zufq0qADwAAAD//+ydvQ/BUBTFT6mgJmFkZLAYWHQQkz+dgcRiNxD6kdJWfDTtu5X3GolVUo3h/v6A9952333vnHv0am+Q64KaYQBRJAdg9MXxMCeC+rAAACAASURBVJdaYKkJVtpgLjQMUwwJqctepdNFfTJFbTiCZrBX7ZcI6c3cbnBfL/FYLRDvdxCeo3bUm1lgMj69b9xoFohs7Ln+fEu51UbDnMEYm5CZ3ORfkLgWKPSRuA5E4CG2LdDZRWyfIFw7i5kRkVJVpO8BQwzDMMwfoWU/mymBnjEo8InCoCQfDyV0u+Z3VgAv9s5eh4AgisLH2NiQLShVGo2QeAWVF1dpJSJCRFAQxsbazWLnR+7sKnQKVPd7iDs3c849xxP17/ZsimoNyDLqNGtmu01fH/cN95vMDw7D/B6jYW3ubxNBAL/TQzAYwu/2UWZV8yfQcv1YLXCfT5GOR7jNJngs5zBJmlsNKfyU1CJWMv9LYfV0t4QuHd3P72OZj3lTOimHgUbMNYJNYleXYq4XqLOEiUIoeYIJJainjdKXqTPWVc5cQuhQwqY3WFXU0bwct6JQVAXfejIMw/wVN4ytayvQceTp06Gltut2qVLZK3mM3b7yjZkM4AkAAP//7J09C8IwEIbfxlRtoVTcxFkc9B/4x53cxM3BCh0U3Fz8QlD7laSS6yBuDtXFe35CQi73Xi73yrr7cuH5MEVuJxm5+nppm+ROyS8paL5IGOarkFejjQ++B9nrozUYoTUcQ4RdPn9fwCQPEpm32RTJcoE8XlNrod0E0XbxFqxZaP4eY5+VJUQQoGEHH0j5bytQO47nk61ZM+yQJ2dTaUArmvoLpWHyFPp0qAowcYQsXiGNI+hsDyigdF9fyilWiRKlU8KpMbFhGIZhPoM0py4a+nQYFrvNBELM1fm4rfKXGhxEADwBAAD//+ydvQrCMBSFT9tEa0BxVmopBUEHZxHEF/CdXQQnZ0HEUbEVFH9qtTWVhIIuTv5M94M8QbiBk8s5h+Hb1SdpAiixedjze7gR8nAGGKXQEsRPeREyRslGsdWB6PYhegPwhkcbnS8jT0ekwVpXRFymE0TjEa6LGeRW+R2U2DefPjXi/6h5UP8ud8C0BVjNAas3YNiCLuNDnoK98D4PyPXBHU+fgt/U71EarCB3Ox08ofydMo603zO7RHpbqj2fcV5Zo72eeecsyIJDEATxM5jK+UjYbTlvW5XqkDtuaJYrC8PiyJSm+xQADwAAAP//7J2xCsJADIZjr6cV0VYQBEVKQRzEQQcnH10QOvkOIhRRVASntlC41kpyFXE/dcn3CuEIyeX/f1tv4c1RZk5lGhDXqIFkCqyWfDcNhmGMgz8MGDuAgfWi24PmQsecNCYzHni+AOox020IabiGPNqDOh/JIMjyLJ1JyCeB/wMHzdfyBUvRdkEOfZCDERkfML9BuF3K7qwHYyhXKRRJrM9q7zfSfeKpLUar5NcLqGgHDzRxSirJjY3Pp/jUODMMwzBmobxNkvgIdTr0RcdbSj/YONM5+XyUJrSbAPAEAAD//+ydwQsBQRTGP2tkV0rYKClyclEcOCg5uPmzlXJRclRSSrJJLLFrZ2c1Y5WDm43L+9Wc511eM6/33vcxd7mIKPCnvybLm0bgOkW+t0riYsfhhQ9/RK1YgiA+ZN9dAHEBVq7AaHWQ6g2gN9uIMfpcR0XAOfhmrdRlr+MRnNkEt/kUgX1W6puxJJ57gaCR2b8ghFJCV+JYMh0KJoxqDenBEMl6gyx/fows7OXRQsX7RHi9OB7AD3v4Umxot1F+tN56BW7t1LSAb5/gy2JUChJdbEC8Zm7f/Dy1sP1JhShBEMR3ME1ZoPCtpbv6opLq9nPSBkvLZNUe/tcAeAAAAP//7J27CsJAEEVvcGOCr8qQRgwRLCytrGwtxda/tLS2kaA/YGEpVipEMQ/NRmZdv8CIgnNgf2CbZZa55woqGi8EnbfITk4TMu9nx0OHdoC5d4thPs+rasBseagMhrC6PbZvFgwZOKP1Euf5DNdghTwJVWzAKAvA1Ll0HjK/hx40ZfLMatptH43JFLXRGKWm+6+38nMY1TqEZUM4Lsqejzy9qQ5UUu3f9zuk2w2iYPEUbV1CJRWiA222VRlPIVVnLQ+bDMMw70FbcfR+yjinSMNNRnGm/B/0gVtEXRiABwAAAP//7J27CgIxEEWvZqOIK/goRBthQQtrK1vt9GvttPM/LMRiFx+ISNRljUYyq9hYCD4QnAP5gYTAXGbuHSch3xSYIBzaYabnfl0Hfj+aTppnfZTgPAaG+RhGn6jeErkMnGoFmVabxKb1adqdt8xrWL+CFZnH2ZSKYDUcYDceIZpskXTtiGbszSR/JgvN73Idl41DsQwSUkJkXch8ASJfhNvtI9vpQda8f7qVn8e+kz2PSDeaSHkNiGIJ0qvTnzsrRYm2Jgwpjp9sOire8WnCKO52iuQ90ZZhGIZ5nltSvtWXh505bdZlvQg8s1eBXi1f91oCuAAAAP//7J1bBwJBGIbftbNMddmRpItuEkVdRCz99e6imyii6CSV6KKTtLuzM5lp/0Bakr7nJ8z4hpl5D4xX67HsiJVKGaP/Yzio+IupG2zXRUhlWw69PhJE7ESHg/JC429ySnkjn+WNFrT8wVx+aOw+Rl6veExGuPd78CYjeOOhrnWCndZBKVFZPVWafAcjmw1foTJSBwExsEIRXM9BrYFE2wXL5P5xZX4als0h2emC11tGaqtrU4T2dmq57WqOYL+Dv5xB7G4IL9EcJuRLXUAeT4IgiPcx3k3zy2mF51M5WC2awnGEOB42kEp9FPIK4AkAAP//YmGVkqFKrDAJCkGWmZ04LP7rzg21P0+fMzCys0DWAo+CUTAKqAtASwZBhQMzEwOzAB8Dh6EJeLkgp74pA/NoA5tiADoxE3SYyffTxxi+nT7M8O3oAYbfj+4x/H33hYGRnZGBiZsNsY9sFNAhQv5DOpfg2cx/YCHQ0h8mdk4GZnFBBmbQkkwlVQZWBRUGTiMLBnYNHcgpzKNgyAHQ3loW0P5apJXP4L2coOtUHt5j+APvbD5h+PP8CfiuT9D+zr+fPzL8/w4dhIdetcYI29c52gEdBaNgFIwC/ACy4ITpz4unWj9vXXNlEZd6z8jK/hh0Ajn4aityAQMDAwAAAP//7J29awJBEMXfOqeunyiHCZguYCOiiIJY+GfbWQVESZUiAbtYBIIkohbnHe65G3bVWpAjjfNrth+Yhd15815iOruL26yJwvi428Z6rz1K69NlzzBMotjGtzJZkZfwHuuQrS5y/SE83k1LBL3bYD9/QTAZI1q8Qy0/YVQEIa05CfFD8z+xE3z7uaKOLsrEHM4us1kNqhTcJDM3GEG2e6CqD/JroFL5fupzB1hZdCpfAPkPZ7f7kTvV19Ll3IavU0Qfb1C/oZOCiawByABut5M4+olhGOYKLm8TEPH650mtvjuZ58ZMNttCFEvGBMHt5QPwBwAA///snb1KA0EUhc8s+5fsamG0MNmooEVaiwVhIeBD20kaSZEXSJE6JCEqiq4b9m+uzLXJti5ahPvBvMBlmjnnzjl2uVm1nP9PCi2VhVd/fpxV7289naWaU2gh/ViC8BdQSRyW4URD+HGCTpzAGV7JrNtAxP2ZtdnQmD0hfXxANp2gfnmGzjSUD6nO+C/2nUxjTLGwEvCDwzhfVhDCPjmFM7hAN7lH524s9/+AUa7HxwqbIoJ/G8O9GXHdk92PUCzm3N2pzX/O3Y67PCnPOUka2Ft7FwRBEJoYTY5I1a/bsFovR0rh3L28ttTRsaav9PfDAvANAAD//+yduwrCQBBFbzQRJSBYCAFLsfEv/HIbsbC1EEQUEVtRIsY8dkfupLKO2jjnA6Yclr2PCfPNutEAEU9VM6iGyUDKcurT24ieX5VjbakbxldgTk2iSttnqWhaCcoHEEFx2CFbLfBYzsGmbne96FxVNENTR36COmU98HTwVa1itvvM8iXojCdaIMObmbTJ0j5LZd+ymf9KoJ8M8aynp56odNJeW+y3ek6lOO5Qnk/wd4Z6gVaM2pkAe58YhmG8UTfqB5KzhC3t+iyLxDndlI1aaQG8AAAA///snbkKwkAQhv+su8EDRVIpeFQK2oogWPrWVr6BjYWigp1oggd4JnEjGRUbG69CnO8FdpsdWGb+b+S702BGRJGkITQX+fa85c2mFbryY9kcwzDvED54ISBSUahiHrFaA/F6k6RAt/VDzPOclgu4oz42nTZ1M4+9LvR+h8DXEKaEodg2+zWuVlkal6UzAhhSQVgJqFQawrKgsnnKZJrlKq31UbkCZOYzvgHmtwm7nSZ1PEtUD73wsznowZ2M4I77cMfDyyfUsUliGHjeRSQE3POcXDcZhvl3rnFIvT1ALxyl1ysZHPYG/CTFFl4GwBkAAP//7J1NCwFRFIbfy52YLFAkkWZiZ4EiP9vSxs7GSrGQhZSFiLLQ0DBz7+geysbKx8p5fsAsZnHrnN73OdJutD/6gLBTiM6euCzmjtpPO+qwdyJwVZNhvsrDeKp9BZHQsEpl2uQn6k3IQvG5rWfeIlgt4fV78IYDqN2W4ncGIWNsm/0V5r/SHa+QYuEI7qUM08uUWQ1ZcWG3ukjWm7DcGp3DiJvhM52hOC3DvELm8hBWC5ZTJUN3sFnDn01I8uWPR9BHTdZFUDzXSDFi9/eTB06GYf4YGtzM0tdXVCfSJ09F4TUwJ+Ci0MgS3gTADQAA///snU8LAVEUxc8bPOPPZBakKCkLG4spJTsbK59XWVj4FErZWGjIvwWjeMzQvWQt7NzfR7iL2zv3dc6Jk9/hG8g7Ex32ysym5evCb4TbtctGG3n7CsLveKbP8q+m68L2msh2exwMZGUdGfQHcIfmMUC4WSEYDXAY9nEeT6CSePkEwSJehOZPYeFO/ZiPADmlbcScJFRCc4UWdAK6VIHttZBud0AHUUo7F4R3IG9nvFAECo+wNNsDdK2OmJODlcrgOp/hZk5caxRdDHs6QUmLtGMtS0SnIAj/yXP30fE3OgYq3G3yl6VfjYzxw+36/PFMANwBAAD//+ydOQrCUBCGf+UlkGgrEo241TaKhaWdtxYLCQheQeOCuDViUDDPNzJPPICYzvkOMcww/6KyWaSIzfiuuV584o8AUU4GtiBkB+vlOX4677lwylV4nS783kBqTn6Akivu8wi3aILbdAx92ts0tndtwmfplEMzU8hYPyY9DEzCBf8GquTBqbehKjW4jRZUULVeZBU24ASh/WQKwi+w7LowHNkwoXSzgt4srSebpbZpvIBJtO1qzRWNnbNSUiwIwt/CexAR10k1023c1+fjTB92azyf5iO1/QoALwAAAP//7J29CsJAEIQn5hITtRMCIiiIhWAh2PgSvqulYOkLGPCnF43aiGJQT2PuxD0LW38694N9gSu2mNuZEVrK757Tz0FLmUkPeyfdbV11PJs9/WUBKMMwLyQK8AScUhl+u0PeJKfCoUAfoTVumwhyPELc7+E4HCCZR7A8m4ZrEn7M8yfTBJdbRjTJ+xCBCxGUKODFa7boVDZbb0BUa5Q0yzC/IpMrkNf3Mep0Ii+nOw2p1ugyGyNdLUhsUtcrcLsYsYlgPyfDMP+FsRloK1kvG3ISdkUxiLXWkWXbii5A3hXhAdwBAAD//2IBLWWiBIDPdfj778+/b9/+//30kenf998MTJwso5s2R8EooBYA79UELVn/Bz6BE3SvIIvs6IX1ZANGRoafN68wfN6xnuHb8UMMf9+9RZhE5qjdKMAB/v5l+P/nL8N/0H5MUBueHZSOWRhYZRUZuEwsGTiMLBhYxMTBd2My8QmA71Nk5uMfDc1RQDPAxMXFwKagzMDEy8fApqbN8MfUiuH3/bsMX4/uY/h++hjD75f/wPviQVdLgQ46BM90QrcwjO7dHgWjYBQMd8DIAjmV9vfzxxLMdwQtmAVETrFr6u4FlZn/v38lva/JwMAAAAAA///snc8KAVEUxr/5w52puaYQYmMxykYpYcHazvuymoewUUoW6haNJhpqzKB78QATGzq/N7hnc+85537fZ6bB7rOy3W9GetgX0/Dg3E5H9T0KNtmKE8RXeOmI5AAnV63D6vRU1IlZqVF9syBF79KI5hIhXq8Q+XNE/gzXjYDuGKq+1Gh+kbfDrNxiMgsaY+pOkHmIRqkMuz8Gn0xhD0Z/c2Tid9C5izx3gaYHYIhEbKHxgtpk6suFFAbhfo6AJHlmdL5yX+ldQxDE3yObTQCJEE5sspbVHTbyXluXZpRpGGQfugF4AAAA///snbsKwkAQRe/mLVai+CAiBhIV/QUrv9tKQRsbQcTawiCKoBhDTExk10ftqzHM+YPd4jLDzJ2rBIvZZ9/GhVeWmFI2M8nJqyeHfSGJQvbseEmUCeI7eIN05tdnGeR8DprdhN5oQzFrt+KdeBlePF52G/iTEbxBH/54KOJObt4EWvv/GdyTySeZQYLY5/mYEeRqCXqrI7IxNcsR15NVy4Fm2Sl5NPHvyMUKst0e1LIpvJzhaolgPhV+ztB1gXveq2RIgKLShJMgiNTySDeIj2dE2zVi3wPT1AszDHGA7W39A3AFAAD//+zdTQsBQRgH8P/urMW6kXKQxIHi6uLiE7s5uPkALkpSzsq7XSyxzIxm2HL0VkrPr+YLzGHen/9Ywt++1V/qmayUwjwHp7xYLRuX+aSoMuvDSHFCyOckl2BOArFKVS+G7HIVTP8pR54mBC7TMY69LnatJvxOG3zm6eecpkM3ml8RTj46XZbBdCJgaQt2rgC7VEG8Voeta+bKsFLph5o4Qn7PYEwn1qqmbttPowEOmSwCVdc57EO4S/DN5pZHIe6lR3SgTgj5R+HYFgBy70NuvSj33KThJBbcXYuXN5sArgAAAP//YgHNlJAMQIc8cHCCjsZl+nX/tu6vOzc8/zx/rAK6i5tx9GyNUTAKKAf//0GG0v+C9rjxgu/U5LZzBc9qjgISARMTA2gFx5cdGxm+nz7O8O/jB+ieg/+jHU2KACP0dFnQTOY/8L5M0B43Jh4OBnYNHQYOIzMGTn0z8InJrNKy4H2ZzILCQ9i/o2AkAFAaZVfTBpe7f3UMGDhuXGH4ceUcw/czJxh+P3nI8PfDfwYmdsj+Y0ZWFsiBYqMznaNgFIyC4QZAzaN//xj+fvks9PfFM/n/P398+/vi2df/4FNpSRhsY2BgAAAAAP//YmHT1CU9dEB7b3j5Gf68fc3069Y1jZ+3r9v8fv6MDSzHOprcRsEooBT8//OPgZGDnYFZiA0y2m5sycCupT8arkSD/wwMf/+Br4z5/eA2w/ej+xm+HtzN8PvZCwYmTlYGRp7Rjibl4D/0dFlWyIoW6J5MFkkpBh5HDwYer0AGdk29oe7JUTACAajDCRsYYdc1YmCRU2RgZGFj+H75LPgwIUYmRvAVPuBBq9G9nKNgFIyCYQjA9TozM8O/9+/kft2/ZcryWezjv6/f7jEwMpA2u8nAwAAAAAD//+zdOwvCMBAH8H9DGht1ExEEHxXdHOqifnid3EVQXJyKDxRKEaVCja3S+MDRuin3+wbJcORydxxnMpv+hh6BlVlWFB8PQq1cEflHGBZ79foSQr6UzGqqGCx/b0NMqpq8UqfbTMXAZe8jnI4RjAY4jYaIfE9XinWQpBnNLz12j14UYnXVP59MZsDLVYiqrZNLs2ZDOl2IRusnT0jIO14sQXZ6YJZEpu0gnE2gNkucF3Oo7Q7XADCyyXvIpKSTEPI3np2qke811HrZ54WiK+ymy3I5pddEfZpwArgBAAD//+zdsQ6CMBQF0ItFhOBgHHVwNCFRQUL4ayfj5B+4uDC4Go06iEQJakKLacUdw0beGbu3Tdv7XnXZQfZv8ga714d43Ds8iTV+u0JkOZhp0GsBIbWUk1eU8dnJXNUQySgiqUjGPpJY/aOZrhZI10vwy+nbGdVmtEbV8qvNZNCMQu0D8iXTnAWwpj4sP4Q+HKlxQppCxsDbshOjF+LtuHhFW2R2F9ouQn7Yo2hRDSchpGHKdY0n8SA/Hz24wcYYO0ymPsQzq37YBPABAAD//2L584aMq08YGcHHgf9584r776eP7P9//USyc7TAHQWjgGwAmtUE4T8M4CsjWJVUGdi19Ucb76QA0B7NW9cZvu7ewvD91BGGPy+eM/z/8Z+Bifv/6ME05ALo1Q//fv4FHxoAmslhERVj4DSxYuAwtmDg0DFkYJWWY2CVkWNg5CBjtcwoGAWDHbCwgK/tYdfRB9MsktIMvx/eY/h+9jjDj8vnGH7ffwJZWc4KuTqAkXV0T9EoGAWjYAgDaHPp37evrH/fv5X+9+O7ECMrK1iUpFNpGRgYAAAAAP//7J2xCsIwFEVvkqZCKQ46idWqH+Kkk1/sJjj5FYq4iIu1SiotqbxU6GpwKrwDWUOS4ZHkXt4NyvPRfwFCSJvdVXW7zm2eDSAVRFD5z8MwTIvLgrQQYQg17EGnC2dF1KOED8kDUjHNYY/XbovycmoufbJiRfMfSLVRpGZS4L1EMJ64JirxaoNouYZO0u7ujWE8oI8/GhRFZR8Z9HTmaox95qgL03arZRiG6TJft0b9LqjWReRmtcZIGfebWvfrYxPABwAA///snLkKwlAQRW/2BLRzqSyCAbFSMI1+gZ1fbJfGWkEUREQClmoWn0nei+ThB7hU4pxyyqlm5jJHv6+X73WismSqmqY3Wx6P44mII1fWaY4jiO+okqNUwKjbUkpRm85IsPIGgjFkmxVuiwBJMEceHiCSDKqjU6L5KbyQB5CSV4mNCqPjwur2YA99mF4fzmBEiybxlyiGKQ3Ljj+Whyyt0UZ+3CPfbVGcQvArk4INxaJfToIgfpCn20KwFPxyNkUSWWWRy1rJi9eXTQAPAAAA///snTEKwkAQRf+GDcHkAIqFoK21Nkmj2Aie1c7KRixsAyJWAT2CrJFkwWxk1qQWtxPnHeEzDJ+Z3T/SqJuLAvJpqnF1V4nJ1dAmEnIuEMO4UzfJnuIdSBEmc0SLFfxen0X9RKMdbTEf+y3yzRr6mgGmhgiENYJs9VwR9gahFwbwyFhPE0TxDJ1JbGuTTmAxzD8ju5S+vIQ/GEGfjygOO5SnFLhkaI1Z26MYhmF+BUFDevo2qTVMruj1hqzLQlJf+2qzCeAFAAD//+ydMQvCMBSEzzbWDIJFcXN00EJ18f/Pgg4uDi4dqlAXcSlto20q7wWcbSeH982ZQhJy5HKnOtUpDJxP1xa5V9+zRZ3doub5mAPycCAIveE/mhbeiIrwQwTLFXS0QSAJtL9BQjNN+JJH9llzOaPJS7Z7ysHUA1qP5s0mFpo+fzaF3u5YYFJgFXUzk8VbEAS46p/xEHodw5+EUNTTGcUojnuY0wGv5OoCsDWNpQ2lnPCUbk5BEP6Zr40W/GWAAmVtWbRtVaEtO4hNAB8AAAD//2LhtLAj3qugU2j5+Bn+vHrO9PXQHt4/796I/P30AXK/5mibbhSMAvIA+KqTvwyMfHwMrEqKDOzaBgwsEtKjo+FEAlAB+P38afCs5q87N8CzCeDla6BG3SggHYDSHCPkoBNmfiEGdhUNBh5XHwY+r2AGJiFhxCX2o2lzFIwCOADt22SVVWBgEZNk4DAyY2CWlgdvjQAdwvjv+08GBhZmRJ4Z7WiOglEwCgY7gHU2/4CW0n5n+Pv5E8e/Dx8E/vK+fff343tG8GmWxAAGBgYAAAAA///snb0KwkAQhOcuCjER8Z7AXgutBEErn9vOzsLCVhSRkBDQxv/c5SJ7Clb+Vhb7PcIWx+zN7mzJU1+kXArhEjJlrS4Krat2u1H2sL8f3WThwTA/Qc0mJXz6vnONSKhQ1D6L+feYNMZlNsVxPMJ5OoFJE5eU/aideJzrYF5TFLCZdqWTSt3uZjbb8FsdhIMhPB7pZpjnCAnhSYigBBmECLp90AA/rUVkyzn0egETR8h3mVs7kpXyTTfx88QwzD9DMiq35G42dLTq2dPBmDSJkdPP/gdOI4ArAAAA//9i+ff1C/FeBO0pAy2j/fqF8d+XLyz/vn1l+v/7F3QkfLRhPApGAekA2tIAXY7Px8/ApqjGwKaszsDEwzsalgQAaA/BzxuXGb7s38Hw/cIZ8AwCqKMJOs0XAUZbcsQBxEwlqKEMWsrNbWHHwGXtwMCmqs3AIiY++L0wCkbBIAIswqIM3K7eDGyq6gzfz51k+HpwF8P3v38Z/n1/BL5HeXQcbBSMglEwFAB4pRgLM8O/zx+Ufj2448z8/s37vx8/vGH4+xcyOk0IMDAwAAAAAP//7J2/S8NQEMe/l7w8NQ2IuBhbCh1EIiVDnQLiny4o6OTQJbXtVOggTiLyWn3mR7k0uEnjlsJ94NYHBzfcO77fO4U8b54rP8prvbOMCvPpFh/vVK4tSCv5bArCf6m9mqRdqNMAenABfXkFFfa2N4yEPymNgZ2/YPV0D/Nwh5/lopKq/Q7ZxBPVDK7BIkdpCkAB3vkZDuNrHCW38EcJdDSEe3yyD5kIQqtgWS0HbxQnP6gGiOx1/ho/w04ntQqDFS0Eclw5zSQIQjthRxIRsrfX0M7Sm4MoTr1u/9HpBCjt9+5eC8AGAAD//+zdsQrCMBQF0Ju01SribrUUV4dOXfxpN0cnJwXxB0RBBEEQEVtaUtPICw5O2rHCO3/QQEOTNPe6NlGoLkolKnLqXPFMljo6S2EUfSy/U4sYY/VVlb2rKfs9tMKxDQWiYnzpchn4N0YpPM8n5Ns1is0Kar+DKUtI/2PceKFZm4BApelEU6I9iW3lDv0C6AUh4Pt/8hSMNZQx8IKR7eak94s2FR/zGfRyYecycFY2Y6zBBG2ECQF9vXTU8RD5cTLoJlPHHUbQ99vvbmEALwAAAP//7J0xC8IwEIWfiba2VkXFQZwEJ51dCg6Kg3/fycHJyUFqlSqlYhq5pjiWjBXuW5PlIARy9/JeU8WRfYmNYnypVRz1VPJwdZYC6rfGZ4VhrNFmqqQAORjBW4Xw1zuTWcgd7krU/Yb0YAyBSEabVaRRJgAAIABJREFUJ1kh80CbXR6t0UbHR2ZKwg/gTidwF0sE2z38cANnNv+TQhim5tD3I8rk7DuFWy35XtD1L7wO3qcjPtcLZdiRYqzc22KJLcMw9UGWj804ERpnJ389u3I4Bk02BcWfUbe6CgBf9u6fh2AgDAP4094rGmpTbb+DpYvFQiQS35qJyWQwWCQGIQbSP0F7r1y7o4PE8P7G2268e+7eh4rz8fsNmfjyeaficgo5jTumx04u5YSoiauDZtn/2NAgL4QTDcp6CaspSdJbDOSHfZVqbtblv03l2jLlsSbWGpZNsIigegFawzHcyQxOPwJ1fZk2K8QvMIP8EO3RFMoLkK0WSJdz8G4LHcdAwYA8bBFC/JEy2TSP8R4MmPqT2zXXacLKrGXJ52QTwAsAAP//7N09C8IwEAbgl37Sqq1VQZ0ddHBycioI+oMdXXXpKCq6C3W01o9ioUkl6SzWQXC45x8EsuTuzZ32PGzKHSnPxXJvXW20BuwSTfgt7hXlOboShHxFrjrhUGo29LYnJ34a/aGsEpH32DVGulvjsZgjCZbITmEx18bQqehVlohucw6ecCjVXE4/rvhT2P4M1mgsOy+EkB8RnUvTKr5LOHWorgut00USrJDut8jCo4zWiuCBImZhUMqFEPIvmNjBnYHfY5NFZ0f1mpFMx356bAJ4AQAA//9i+f3gHnHeAJV+LCyszB8/Gv77/s3l39cvKuDeLjMJBwyNglEwCsCNffDBQKDli2raDOygy8D5+EcDhgD4++o5w5edGxk+b1jO8PfTJwZGVhbIUrPRGTgiACN86Ta4LP8FWsbHycBpbMHA6xvKwK6iycDIxT3ofTEKRsFwAUycXOBrhdiU1MCrCb6wsDF8//mD4feLp+CrsBjYRqN6FIyCUTB4AOjKJhD+/+M7199Xz0X/cHI9/PvhHRPDPwK9TQYGBgAAAAD//+yduwrCQBBFr0mKCJttRMFerASVoJ9g6Vdro42NIAipRGOINoKrkU1kxrS+Gm3mfMIWwywz94xHR4jfUuYIcmM8m+7bWbTu2yQOuIFxpdEThK/gySbgKM2mQr8bwq3V5Q2fQPIfe0hg5lOcZxNcVzHgA64WC/bHUDi4/HCyqKTVhB8OoUZjVHsDgGyYgiD8DFphr6iALbWUk+ZFMa1xWS6QRREKc+Ip5yPDKXVOEIQ/Q4sWDuj8ZeO223SKPN/aY5oW1mYvaxSAOwAAAP//YuF2cCfsekZGBiZeftAJkIxf9m7j+v30Eeeft68hndDRzuYoGAXEgf+oe5yZuLkZWKVlGFhl5MCj3KMAOwDty/xx6RzDt9NHwSefMfJCRtdGl5gRCcAHUf1lYASdcszCysAiLcfA4+TJwOPqw8CmrDHakB0Fo2CAAbOQMPi6ISYBAQZmMXEGRpb9kMPPvv5mYGT9P7qCYxSMglEw8ADa5Pr344fY3/dvtf4z/L/z9+3rj////PkFPj8WVxnFwMAAAAAA///snT0LwkAMhtO767V+FVErOIvo6iD+AJ30bwsOTi4ObkoVxEUKPcR+nFzatdhNlDz/IFtCkucVRsP9Ec5wC2MJYekkceNrILJQAavb1PARRFWw6de5mdCXaPyUwzGIXp/092XoDOLgjD+aaruB9H4DSzL6Fa9KMWhqpYF1bJCjCTQWK2gu11Cbzn+jBoL4c0yusoka4i0P7eTca6NI6LnfYR5nFr2AuSy/QKChkyCIb1BsNtPwMYgvp5ntyCPv+gfmuJE2Nu0yhTYAvAEAAP//7N29CsIwEAfwf9rYWqQUB/EDBKko6KQgDj6Bo+/q6IM4OBVxESdrSdPiVZrutZsO93uCDMmRg/uQlKXfj2xVySbpVBQqoUJps4y4Cnoc+BhrwvRq5gUsv20+Fs50Dtkb8BuqQUohu0bQlzPy6AagXHPCJZ+Nla0U5b1TMJOOvc0O/v4AZ8KrTRj7N8LrwJ0tYAddyHFoSm3j0xH0yiAkQbQsTjYZYz9RpXwCFD+D9+MeusvV0FtvbdkfgZKaqbQAPgAAAP//7J29CsIwFEY/2lhULEVKkVL0DVxcFAQXN1/Y0UcodPAhxD+skapNIjeDulSdRPCeJwgZAoFz7xFq+0Fn03FIpDVqvwm0zD0K0eP98iGGYZ4hjVYZiDBCk7qawwlEnPAVVUCLMs7LDHIxt0qZOpzgkm1MWxrBmZOX3NMlNKPZhtcL0RiN0ZrOUO8PfvjgDPO/2DlOP4DnB3CjDnApoMsrijSFljsYmT/ePf50MgzzTaxR5kAf81q5XiVG60jEXUF2nqEUZlVvE8ANAAD//+zdKw/CMBAH8P+tS3hsmGWCD4DAodBIMHxaDMEQJB+BAJpkWYIBuu5VcmWO8FAEcT9T2YqmufauOb9MTp+X6imyuaEyTaI6yzrEE0pyQYjvNb01eVBRjPZo7IJ+rhgQz7j0szjucVktcF0vUZ1TqB49+j3JJfM93md15fpoctacHzSCyQzhdI7WYPjPKxdCNLxu6CoRKAjhx33cthvkhx3I1i6wIyUltUKIXyLw30xbFbBae1Zr35rMHULWmNeXTQB3AAAA///s3asKwmAUB/D/rm4M3TB4CZosYtBiMtgMJh9ZEATfwDAYqBgEQdic7MI++Q5iETaDwXB+T3DiuXGOngZ+eaSUHWuG5jbb+eU8Lu5RhwpNnmwy9h1aZRS0xqh7FszBELXRhIpO9kk+Cc5OR8S7DeLtGun+AMWRrwIMQHByVYXWtR8FVM+E0evDmS9QX65gT2f/HThj7E1OOeW3AK3VpcJTdRuILRtZ4CO/3ug1CjXfKg5zMMbYT7xu9Ig0QRGGShGFpkgSlRrcaUmxCeAJAAD//+zdvwrCMBAG8K//YqE4FFxcBB06OAhdfAI3371LX0DoKKK00DamTeQSR6sugsP9nuCmcJcL+UJVnd7XYAwdepHpukzX19xIuXTTLW8XGPuGy9Wk54wJxGoN+pTLn/NGc4puGvRlAVkWFB4Mb/b8fZYHzc9oga5GjA0QLELE+R7J4Yhok/175YyxF3whEG93CNIU1HbVlzN0dYNvs8+1yxvmFx+MsR+zHRhdbA0Kum9h+jaAuns2u3tQ08MmgAcAAAD//+ydrQ4CMRCEp73LHXCCH8cTYBAIAhrJS2NQGAQSgyMokhZKucu1Jd0EBAnkDIJkv6QvMKrtzO6k6bd+P0ER2thzl4WbGdWn49Rf9fC5kYhhmAZEZ7MGzc5FRzMfTyB7A1buHeofrVAd9rCbNexuC68URCZoIzbTQD9XQxZtJP0uOvMZisWSongyb7F6DPOPCEEpmHiCMXBaAfkKQWt4dabPTDjHDifDML/l5Wy6OLcJby5JKG0S722hvH9+bAJ4AAAA//9i4bJ2wO04Ribw/X9/3rxi/nHlgtDf928l/335zA3uhY7ObI6CUUAA/IeM2PwH3+ABXgrFKiMPxkwcnKOBhwZA+zT/fnjH8Pv+LchSsVevGEC99NG9ScSA/+AG5//v/xlYxAQZuEztGHg9fBg4dA0ZmNjYB7/zR8EoGAUEAZuqJgN/aBwDi4QUw/eTR8BXo/z/+oXh/8/fDIygg9NGy8lRMApGAa0AtHz5/5eB4f+PHwz/f3xn+P/rF2hCkuH/n1+QQS9sgIGBAQAAAP//7N2xCsIwEAbgP2ljjailVkUQH8DFQQd3NwdfWRxdXESki5uCUFoFKWppijRdK05C0fue4Eim3J/kTGs4el8WN/SbAG47xtPbtVTgd9LoZuaJJ20nIR9lXWeDgUsOs9vT39qL/oCSpgLJ+YT7Zo1otUR88JBGD/AqA4QoXa2loq9pKzCrAqNZgxxP0ZgvUJ/NwWzn31eHkJ+RzeCUEzefxem4gDAR77f6jbvuaKaghJMQ8l3ZYTNOsnRTqkvYTgL/qK6hglLFKSSAFwAAAP//7J09CgJBDIXfxNlZRC/gCRTE3kY7j2xpJXgJy+1U/AHXWTBmJbNWotvZSL5DhMmb91682q6+onlNCqiZnVQxSIwBzE0bkd0GNIx2RNtnpRFtspAeB6pIO/3VJFNr3tH8+HW1RLneQG4HUE5wZp9tR2cx69AHfD8gH03Qnc4QhmM4azo2jL8kNUzPF8k2L+oGKQrUd0ENAWUdwHvLcBqG8Rte659Uscfn44D2u+3jcioh8nmhBPAEAAD//+zdsQrCMBAG4L9pUrHFSR0KDlU6uDmIk7go+OBOxcW1qwhdVFpUakGSytVBB+0gCA73PUEI4Ui4u5ykVOhHgoKWQnnNBc1VMZezoNrcRxktPzYZq1X10hjY3Q5UMEBzNIbye7Bsyfv2gmKKzlIUmzXyaIUi3kK1Actt8IWpDu0NnTEpIVoSTjiEN1vAnc6hgpB+Ef/ftTPGvkbtTU4/hGeWMOmxKmOjMXb6sH/GBfAsTsbYD1AOwAL1bPq3ZDdBiUSfshiGspdvYg6AOwAAAP//7N2xCsIwEAbgv7HYFi0O4iIIvkEHheIgro4+sZu4SEEXBxdXleKkDT2bSJq6qN2c5L41S9Zc7v5zQVR/E6FskiaR0DJzlenPNYlDjt21whj7xi7T1w8FlQNet4fWZIYgnqLBbY0fimsKuUsg91uzuwnCe7Xp80OzVvWjqaWCCP3yp8OPRvCjMZqDIUTAM8GM/TtTvGzPFxBhB/fVEtlmXaZ5mzkquIILm4yxn3OqkFgtZb9IzzEoP9DldATlN3v4BsATAAD//+zdPQvCMBAG4PfSVmKDiqCDiAiCo0vBqZv/WydXoZO4CBb6A8QPtPRLLh10sJuDwz2QPRxkCHfc69ogzibc2cxzIH065e3Kx87pkisLO4RoVudq8gZV1XbQms1hwhX0IpB380WWxLhv13hEO5vVpLoE4lEw+Ws2484F1XXyJlP4y9DmaWredNzp/euthRA/pHwDzZnN/QGUMajKAulhjzyJ6w4nnzqvQMouhPgNHpoiQnE5D7PTMahG44hcb0Nav6cqPgF4AQAA///s3bEKwjAQBuA/aSpaFBSRSqUgCD6CIIg4+P6z4KBFXKsoijWYyF0XB+vk1vvWrAkkd9wf4ysWGF2MqbNJKYfU1bzfeC6A/3USQnzFZ8p5DmzRnR5MkiKIE1RVfOrudcrx3G5g90coXUAZLY/yH8r95bhrodpNNCZTRMs1dzU5NEQIUStmECOar+CKB9zlCptlgPXwgYUONY9DyUiCEOIfKDiWCljunCt72HXDdNxvzRaBGY5o7LK8o3wC8AYAAP//7N27CsIwFAbgv6YJUotVN8FBFHV0cBAH8f0nFzcHRykUpTfw0iSStIKInURwON8LJFPI7T/HVVlSPzZjUJw7Kkt9nedCX262CpFFm0FCPpPlYZO1A3sQEOMZWJf6ar4zfZmK8Ijrbov7YQ91StEInOoyi9aXWs8scK9js8DeagNvuYbbH/zphAkhv+RwDjGaoqU1ZBRBJTFkFKKIz2UcofoJQQghX6seTmQcm0r4pueS35wvGmI4gYlmKhO3fAXgAQAA///s3U0KwjAQBeCXxlSCoQcQf9AjCILg3p0XFheKG7vxJlIQk1BoOzLtTlEEl853iswk76XHTWZvaa1qQlLfiqwpYyqLMSG+wC20XELrMpjpHGY0gepLhu4Zt8/6ww7+tEdVXIGU34UpGTQ/UV0WmDygZg52sYJdrtsP34UQ/80Mx3CbLRI7QDwfES45KNzbfDcfEKXdWwjxM77ZJAKVhLoKaGIkJLqbEI157fQB8AAAAP//7N29CsIwEAfwf2ISKxJQAo4ODm6CDr63o0/gILi4OLkJ0a0SqhJLKkkVXAoOIg73e4GETLnjPsTdHprP5VwG50x5suPqUvRpvyYhH3gmZVo9k5Zwy+EITCl6uZdUml/itt3ALRe4rlcpyORdBsZpgmqjVJpSgWUSQitkk1maPBt7tqDaf3ppQsivxCm1nekcwgzAtUbwHn6/Q3m09SZ2CjYJId8QhxTGStfYZlk4hHMu4h8luLxObr0D8AAAAP//Yvnz+hVua5mY2P9//676991rg38/voszjk46jIJRQBCAZjVBZwSBDmxgk5YDnxTKONoZgIN/374w/H72mOHXrWsMf54+ZPj38RcDEy8TpKM5utQLE0DD5N8v0OmzDAysskIMnEbmDDzOPgzsoPs02TkGl3tHwSgYBQMKQHUOl5Uj6NJ1hr+f3jP8uvsMPFHAzPgHMisxes/zKBgFo4BSALl4AXSwI9O/zx/Z/37+COp0YnY2GRgYAAAAAP//wjOzCTrFjJnjLxen9p/XL03/ff8mMTqrOQpGAR4AXWfOyMrIwMTOzsAiJsHAKiXDwMwnMBpqSODv61cMP86eZPhx7RLDv88foaslGEcPUMIFYPsXQJ1ONiYGNhV1Bh53fwZue3cGFuHRA4FGwSgYBaiAkYWFgV1NE3y6N2hA78/TRwzg8zn+/R89KGgUjIJRQBUAa7L9//WT4+/b10J/Xr1g+vfh3T/QobIogIGBAQAAAP//Yvl58woWSyEbyhlZ2dmYBYXk/n3/rvr/5w9eyH6q0YJqFIwCrOAfJIOBljIxi4gxsEjLMTALiY6GFRr4++Edw49rFxl+3bkBWusPOUZ7FOAEoOsMwDPlXFwMzAKiDOxa+gwc2vrgwQxImTwKRsEoGAWYgE1eiYHXMxB8jd3300cZft64Al72Br8OZXQlySgYBaOAXADqbIK6iz9/cv39+EH077s3PP8+vv/2/+9f1KlNBgYGAAAAAP//7N0xC8IwEAXgZxpoKUqX1klcXBzEQXARHP3/k6CLUBDRoiINLa02OWkjDoIdXL3vPwTuvYSc/NZy1V/bkn44+noOjUojk2c2xoqWVSmM/THS9mzIMGp2arrjCUTAt5pvZEuse7xDuVmjOuxB9bzj8rOuVtqGTRn14U1n8OcLyMGQgyZjrJXo9uAvV83uXeF5MJlClZxARQ4iQsfhpo8x9qPXCEJlEejbZaST41arNIb5CJsAngAAAP//YuFx8sS0hZGJgYmLk+HPyxeM3y+e4fz9+D7D30+fIScMjS51GwWjAA1AZvz//4KcwQC684zT0o6BQ8949IJ9JPDv61eGP08eMPy6cRm8tOvv5x8MTNwskBMSR0fYcQLQPk0QZubhZeAwMmfgMDQDHz41CkbBKBgFeAG0XAVdvwXqdP799BF8+vfP6/chezj5Rjubo2AUjALyAOwcn/+/fwn/+/RB68+Lpzf+vHvz4v/vX19R2nQMDAwAAAAA///s3b8LgkAUB/DvK8/UrRobEmxpCyLo/29pqSBahLaKigidwtOTi9PKKBraHN5nvOmmd/B+nWVmfz6Zz8KbnS6SzYrkNiR1PkErjYYjeEMQY1+q7gCyANHrwx1PiweeVdRxj9t8hmS9RB5H5bkGVzV/ec0AA2QDwg+KBIbtD+p4W8ZYTZHnwRlNYDrU1PWC7LCDlo/ig4kznOxjjP3rWdlMZTuPoyG13EBn6aLcnP8GwB0AAP//7N2xCsIwEAbgP2kOaitopxZFxdXFV3DzrZ18g+Lg0M1BsODU0jaWk0YLgjp0v+8RMhw5kvvP/Fo2rzyCDsLuVUaBWXP5vkyPpCAJ8cXNairowIc3iUCLNSiZyzl9YGvRZGcUxwOqNHWJtMrIzNB/Ctw0LtmY4th9yQ53e7e4XQghBlUTQ/CmkVuX1N5zcF2jOqVor5dXFqQvq7mEEAP1zWZZjB/5bUmzVeJvtqS7UMzWgvumE8ATAAD//+yduwrCMBSG/5jUGmuhLyA4eFldnHTr5OiLO3VxL4LgBRxMbxo5KV5AHZx0ON8TBAInJH/Od9Q9YXiCTGY0j4lUtijyBoeZDPMZZ94SwplB/f4QXrfnDnemhnqDqu0G2SpBlixRpGvIUEH4ii+b73BJw00IDjQHI3TmCwSzGCp6fRxkmH/Fkv20KmHL3PUe0wgo0dK8Xz+CpGLBNK7boaSEOe5wOZl6MZxwMgzzDa5eWKoh3vmwj4Ruh3o8kfQLy2bmMQIFwBUAAP//7J29CsJAEITnLqeG5AjaSUAEwULB938OsQgIPoCYIDEWmr+T3RSKBuzEYr9qq+OqY2922DGUifKOMp5SWru2uESuKjvJS94gQeiFg221A7kEhssVBvOFNFQvNNmJtyBSribV7u4A67qAcVlu/QmpgTT09X14kzFG6w3bsg2LGObfbisIvZCQfUu2KJMd6jRj4UTbCGYad+6PeMa18Dsok5fEUFoy1p5TtOkR5WGPJs+fE05qICUeRRCEb/BfU7GY6K5FgLqyKgw1bb9WgSV/VncCgAcAAAD//+ydPQuCQBjH/54nYmtQJC1SRARBL1D0rVuiqW/QJA2NkeAg2ZKCaefFqYNQRFMQPL8PcNMNz93zf+EiDF6O03SdIUu5uIZN1Z9C1QQE8YG8jIBWoS2G0wfv2JTyV+Phe0jcPTLvVPgzWaP6EaN55i2yqiZQ9TnmYARzOC5K2ulOEf+CCqJJjgdE2zXi3QbZ2QezOJiyGTg9WPMVrMkCZj4Fb7WhcZJx/gymgdtdWLMlxCUo5Pri5kKmstwp0EOTIIhvqJQQSi4r00R5wo08jooQDnmvbTYBPAEAAP//7J0/T8MwEMWfE6cgClIpoMqiOwsDEx+djQWJgQGQYENFMCAQImnqUBrSnBN0NpkQMHW73wfwcLrh/rx71i7Pfjypoli3VA8bOzXtsurLVlMQ/uBblh4Ntr2JS2LGUIkUTx30+ozq9hrLxwm7loVbTeFX2NWY0Tu7WD869qZAbNgmErfVwrIfZ3NQ+gZnZ2hsjuZ9hrYs/QBAJdrL49lhOh6ZsJnbG3lpqNA1KS1clmJxdYGP0xMszs9Q3U3gUt6q8V+xBVyRoyks6od79G4uQyzNPuLBENqMfa5HG5sS0VWhFKL+FtYODuHmc3ANWL88gbIp4AjccspgSxCEf+luNomCbPaz7KGm4PhIDuiaTQBfAAAA///snc1KAzEUhc9kxmlQ0W2hFYooKEWcRcHXdunKRaGLvoAFCxXHVu3CKqhTmxsSuQmioFI33cj9IC9wIQn375yMH/1vqHTNe1d3r88NT2ZTkk1B+IGPCnDKaqE51NZ26EbxqJjcmYh7m8NO70Dja7jZA5CJ1cmvfN2ZShFEpnS7CCOH0gVeLX5ewZQjUHmFxXAAmpSgmxJ2OoF7eoxFEq2DV2FWb6J2eARdnEAXHeQ7rf8cmr/jPbwl0O0YVe8cL2ensPczqPUcquGiL2wSha8Mx3g0RNXvQvH6QWsvHH3cCSJY+e4+1IYknKuEu8y1gzbY2o69j3F5gbBWxZMVkmwKgrCEJOz7RJFMZwycWSSeSMW/wH52NgG8AwAA///snU1Lw0AQht9kNy6WHqySxg8EUbCHgnjz5J/26NmLVy8K1o/ETa0WwbY0JdlNVmZTsYd6FEH3+QELGZjNzs677/BCxgvLmVq3HwSCra3vlaNRxxRFyx2cHY4lkFUopZuonf7IfIGHm26Ux5xy/I6id4P8+gr6OUWVlfCbfv1W07EkYCVNa4XfbIBFIUT32LrQstaGk7b9ADQGQqUx1EPPFkgqvoMeDqD7KfTbq5UYUtenmtItLQ0rBPyAZOESWqZQMoHJM/pfgre34P33vDem7lhKiukt1NPAxo63+VfOmwomV6hyA6No+xzDW+2jHL5AJY9QyT14tAPRPYLY72Dl4BAsjH77y/4mjIFv76JxckpqNkzOzzC7vEA1mcL73G/cpaDD4fiWebFJJnCzjDqbzGjlWVntYrEJ4AMAAP//7J07SwNBFIXP3B03CWStQgyksUgh9v4BO/+zIAha2AabPEAMQUR8kMTHmN1ZOTMbSTBlOu9XTLnFFDN77rn3jPWL2eZneMZY9gpJ1y/mh+Vyua/njaL8peSTJyaBZFlo/7KdLqSp1fgV+XSCz5sruMFtcDix+hfXA2UrZe7j7G+7HRweik065bECqHu2a+jofFxf4P3yHN93YxSPDyiLGM4UhH+VnprYqk/exIUVXDccIX+aQhp1JK0DSL0Bxr3/Z8HJ1OliPkPx9hJmeCRLY0/4+p4YgdkTGLtWPKHbSeF/Pw5i0xhB2j8OM4XN0zPUaidIGKWv7ByKzLR3BNvqIH99DmFB3kUDgvcb31xXFEXZyu/MJp1NB+++jKfIZDt+dYcGAPwAAAD//+ydvUsDQRDF355rcsbYqTE2dhLED9AEFAQLO//nFEIgIFpEUCslgjYGP1CyudxedmVmvVioXWx0fnBccxwctwy7O++91fHGzuc7IsXFx5l+YfT4UM2eeit+YOaksykIX6GdeRWNoCtVzGzvIl7bYi+MwIf8shyx32pieHnFZnGlpaP5Lbl8NqhKUFytoXx4hHizzj420WRPAO/YSxj8afd81uDwooPk/AxJ5xRZ75m7cJSYSt5CukOHyfh4sUT/ieRB1sK9Udx7AtNuAdNF3hAoNfah/r300wXFRz6mfxq6+eYJPUcTFZNyqrcfhPWpMydwry/cfY671yjU1qHnF6AXlxGVpcZODKU4oXaqsoTS3gHsXRemfQx7e8Op4Wr2j3ynIAi/wEcdzzy8T0O+gU2j0NW0fDEA3gEAAP//7J2/S8NAFMe/d7k06VnoqBQHwUIFKYJdxEVcxD9Z6ODi6FAEK9ihUptFUEGMaS7XO7kf1aqDi7j0PssNWZJ3kNx73/d9YY3j088bYBFILYXMJjS/6DfUy3NTFQVbVHQDgcAS0h1IjaJpJivWtjuhEuxR5lA/HkHc3kA+GN8WsYpGUOh+YhQhG5WYOh9Vewe8d4C4tRni9UfMnx5RDq9QjoYoBpeQ0zvbBqvyV+jZDJTHoHXl24KWYv4l/sRfJoiazoNYTTO8nZ+BrW8g7XRX2mdo4kLq3HrXzWoVy9+6v21CGjm10/yaONEfiaqYjO3+lNcDJN19pLt7SHuHSLbaIJz/01OtCFpkbzGFAAAgAElEQVTbSeprRyeuIJPdQ+d+UpltdwvvoUAg8I1FzdB8OudmIq2gWgiGSgBSAJVPNgG8s3cGLQ0DQRR+SZrEar1ZhCL1JkgtUvDi//8DHvTQqLVYbUOxB1NS3Nl2V2ZSQZBKQW+d77ynhV12Zt57W+NI/R8QRfBouKJoePr4pT2pKDvIt649/0uWnJxi76InE04FIqMz/TsYLjTzMdzCIqzH6mXdgMhno0BSONOzDtLOZfVXq6ac/glvDGz+Chpk4ss0tzeglyfQQx+raQ43X1XTywRV+qY0irbwxvLZjyNZ6mYGtBjBPmZYTieIjpqSWLuTTQIuwg8OZRof1tfF4LZW46/9CkK5VzlEyJcWVDzDjkdYzt5ghwPYfAJ73kXa7SFutUUJoPwP8XELuLoWfz37kim7h6NSHpFBovusKMoGuNh0nj2bNV8W+6JKmb+LCkgA8AkAAP//7J3BSsNAEIb/tEkMVKVWCqUUehcRH6G3PnNv4sknkCJ46KGloVWqTWIbdndkZrOIF0GhYMl+1+whCckkO//MP6H0UlXwwHD+UJoiC+hjF/FCkgHjfrPp8TicEhWcsBLVlp6t5mXXHq37u0IkPyo7NgVKFxJTGknp78tPaBtj2WQmubpBNBgCxvzf8z0S1CpF8XCP/G4ivWjcQ0xG2WwrP5fnboPj1MxfmDA5/5TYlt3SvoRepzB5Lj3ctaxwYGUzaaF5dlFtNv8yS7cyKRTXarJ57qABvVqiWL+IO3D59IhWtsXpaIyw1z/MtdQNKeMnhJ0ukutbqPlMFP/989TO34y/1ng8Hs83WEfg0KDK2GTvbb15jcz2TZPiTDoAAJ8AAAD//+ydMW+CUBSFDzzQUgebFJsmTYxxaRenOtTfb2Ki/8A/oNjQRME+GHhq7r2YmA4dYPR+MzAwEM47554b3Nqc/CEJQrZCT6XtnMvCw82Ap6IotTgwPky/j85ozOKARKcKKoHWRtAsHJV9sGjSZPH/UBzbnBG+DRF9fvHqB3VsGkBtqHmGKt2xu25XCxSrOexyDvctrbK86/FBmjh5BU/b1E59OxXtsYuf7eH3HmuX9M4gsRkGMM+xzK57TcTm9b164nJSPsvJTKcrIG23u0SaDn9zRNMZzOAVQfyiSYC28GFBhO7HRAo/CguXH1BtEnkw/QtqOkVRlL/woSCtuiuf3E/6XiWb9emYb+Eqy5cCuAAAAP//7J09D4JADIZfOEJw8CPEH+HiYuLk/3cyDjq4aGQzMZqIHkZPD017SIhxMbjZZ2eBQlraexpUD3C+ruGDnTR7ezPOSCZJtCCUsLGSrKGdmMcdaXTODa0LZB+zhz13N9lKSSvClXw/PlIVA6mAu+McT3HXJdrCV5BMhqyy58kYZjHDZT7llRoPreFHAbzQOhtqmTD/IC6LepVGdu0xRa41jxP9M36zxZ1NL1A1b3HxfigfXuRBhTk/u4c+4TqbwG43MMkSjeGI5UwkuWGhk1AvpFttRP0BTLLGdbVEntFKg8zZmaXYFAThDU5j6N/gzbRtmvbsfrfIz/qAu3XFJoAnAAAA///snT9rAkEQxd/d4eWSIIjXBQyIWGghQkjh98fCDxBJpQn+SVQuGsTcnnu7G2a8ImiaxHSZX7vFNrsLO2/mvZPPJuejaFI208AqBVE2BeGIwkeE8t8umm2UbmpS8S2KVDnNVD2PoCdPMJstB7pLrub3OG3YoTeIywjrDTZAKd3WRaH5IS5TrCrS55JMgHaDPvT4EXo2h0ddmR7gh2RCE/59GyAdbd+n0ROY5QLmff3vW6D9q2sE1SoXTexWFSXvc1Qx7+CUT3O1pHKqPfRkCj2bIk9WyF9eYddviLr3CJst3l/4PXRPgkqMy7sezzY79cFZyU65Q2SNiA+CIHyleNptlsUmWXV0FA1tmj54xiS8AOATAAD//+xduwrCQBCcC0ZFP0BQ0wiCha02+XUb8RNshIgoWgWf8W1ynuxdNIJWEqvsfMJy7B6zszO59xwUYn0pHwVRZMWuQobN4ubCYCSbKJgPJjH4ZApEofvM+EJvdcLZWMtopT4Ofy4nuDbfoMI7hFCw6w6KHReFVptdNn9AtPJxGvTMbebEw22+oKkHK2+krMZM/T/3ZvppC0HyIchgjftxrwnbTE9My7gq0z2l3Gx17FEqW7G4/1qFRKIslz6Ogz7kyte1J/mu3WhyP04Bds1BqesinHq4jYZQVwBZT/ZhMBifiG0PVBSW5SGoit2moi5n+0W8AngAAAD//+ydvQrCQBCExxgPwULLVFaCiqTwDax8ZhttxMYHsBVs/UOSXILJ3ckuiT+NhWjlTp/mIAm3+82Mj6J4erBGF03YPPdclnr0k6j8aSKRqBRjjw34hD12S+yx/uf4ljGc+qmXc94uWa0fCJ0Mq171jM+SR2oYojWZQvVHjxRP0fsjzK9c0WBOB+4F1IsZ9HrFlxubAl4L7B/8OXFQTXSTiNNoCR3/980mnTkN4VRvAHPcc8UM9bDhGzZkem+8ystpYaMY5hLD6RMHtznreMNJ9UGU7iyUwOeqtztohmNGlfPdFhk2cCaBuxaoKTHii0SiUvxddtRkouzlHBRwgU1idSdjAdwAAAD//+ydvQvCMBDF79qKxeIXbg7OIg5uLnbzTxcUwUFEEHQRBTfpYm1rk8hdijg4iIiL9/ZsIeQ+3u957D97HNCWPqsVMjiIslIY8CE+CJHoWeQNoi46wTDQ9/9+ekfAjmy7YRhLtt/xNoRTlibVKxlDE01a60TAWp0bFn63D269KXl2b4pAPNfFDOL5BJLFlEmztMpKeY2OZ+zK5S+mWwRVoTzJNAYVRTa388+LTbrBDvnZ2x3Imi3Ijwf+RnztZpsi99Gx2Zxuw35o0vWKvYUEJlPhGCrDEROeRZ8LgyqUewOohCfQ6Q3SzRJMogFLpij6hU4rEomK113lYOKLp5UKVHR2iWXAhSgi3AEAAP//7J1Pa8JAEMUf2U2KVgpaqqSkKEgr9gv05Cf30LMHQ0EPHgotVIiVggT/Z9dYZlKhFA/ioZfM774sbGB5m5k3T+OPZzOrbCZOmmyQJjlvBxKE35BiUop9iPrGh/YD6OtqPmMODlA1wRqYaMy+ns3wBfZrDnXlsfAXjkDTwD0FVSnDa7bgPTzCDRri+z0Basc0769Yhz0sn7tYh+TPfOOFJHupdZYfmv8lgumbURvtYgX7GSGlymbeBTjF+NRuearpdjTgfFOYE9adsQ9PFdaadYudzLCL+xx5QxE06SJG8anDdzVZHoQzjth1cXHfzmy38xi72RRm9ZGdvcTiCYJA/Px4oiF9dho52r8ruPWm41yWsrk/+z2+AQAA///snbsOAVEQhv8j61JsKShEJBK3hMY70Im31HoNjRBRKjQirglh7c3IzCEaiYrCnu8FdqtJZv755ljiaD7hCa12NvktMiXOFR+UMwXFYJArtOwCcQIVzxdgZXJQEV975NW18HSEt5gj2KxAnitHWQRTN95CIUER6QNTpQqsdFannTDN5ifocsZ1NMRp0IczmYK8I2Cp12bBj98CVI+p7c3xERx20uRE3hfkZpOTzUJRfHY9kPri90inbDH7JoeEwu0GDqfd66Uk3na7i1Sz9cUf+G/YI+ehWLLexHU2RrjfgwIX5Pq60Td13mCINEqkTdZJzhI+JKqNmN3pqWS5pp19P8AdAAD//+ydvQvCQAzFX2r1KrSDqygIgpMggv+5k5OTu4ubqDiIgrhUi9fWKskpLuImgua3dbpycJCP9xKf94M9IL9MKHlUJMewSK0vpWJVSSiKcM3dND6/3kDQG6DS7sAzwX9fziWXSaB2NkW2Wcv3Uw6hQchL7oE3ywx5xUC52dK7egN3MznJzHcb8QPHoyGSyRjZ1qJUgwt4WVL5jaXz90D7mrJ/MJaEk72kFIYuAf7TQJxMIPuHuZAivkk6f/hAApmKdNuKxCJdLpyc9rAHjIEXRa7DGUaf/Y8fhN8X+zdNt4/qai4Sdl4xVMQWpNZNRVHcFD4puuKU8URrYr83J5sCgBsAAAD//+ydwQqCQBiEZ201JeoWFRR1DIog6Nyxx65L9ARdOkREBAVBRhm1Whv/qtHJUxLkfi8g6KK7/4wznEqwYxinETHMp3cpIQgs9oXOa43mXyClX5oPpUhZ7Q54vamnutSredjD36zxcI/hpp/rztEklMpDyiapP40WclRIn/V1lAD99yGWC3jTMa6zCW7zuTqAGkWEltn43v3Cvvrx3BjFHZxd+LstcpUaYOYz3TFLFiqDDt22A8ZPUSFpitbLKHiLWYaakktfKmszhZbROikMR7C7/XSunQF4uQq7N1CJz/56FabTOroKRaPJPPE74Bntb8QdUtzeH2QpBF4AAAD//+ydTQsBQRjH/2t2Nwd5SykllJsD5bu7cHHlICWEcpALJbXa3Vl2V88MuezFQal9fl9gTvPyTP8Xk9Li3hhC2LH0K9H10ogDmQMPmwzzgdRatq1+7LOdng6fSLlkTvk1jwfIzRLh+aS7ICw+NBIhjxPJ/WyhA1TqTVitNkS+wAqSJMgD4rlKuueOh3BGA8j5FKEDmCVTd7j+CYbQdyVVccj1Qvm5rWoNEOlNQ6W+xky+oKS04fn1znj53n+7rqUHz0eg0oG92QSxe0Ps+ZSWqPdcscxD0pdQum+220ew3yHYrhBePf0+5MYChmHe0MAppRHdHFWtqaS1d4knAAAA///snb8KwjAQh39N/VddBHURXDr0id19ATdxc3DRxRcQB7FQcGxrq63aNnJJEURcBEVJPsiW+S7h7r5jxSHE/URhLQ/9Po/jAc+uYqOSjsca5SntktQyZFi0sLwn1P4PVRVVYUw86OjDmQeyS0L5mbVX0GJ7qry06mLel/YQmp2evKzj7DNFgcxzkSzniGZTnNcbKSFt/l5iEp9NBhRhgKu7Rb73gPwTVpz/gjUs0YLJLEs6IfgXuh7KCrdRLeNzmuKy2yKajOGPhkhWC+UdTu9AIjzKfXXbQc12YHbbck7rksmKtQ5iGo3aCBW5GH0xeHKq8DQBJ0P7McYNAAD//+ydP0vDQBjGn0suaRMltIWQhkIdRCK4Ojm4+Z07+Qk6RErndii0lBRjiTHecUl5Lx0EEZxEyP0+QIY7Mrz3Pn+49jScYbblsY/yWuWvCYQYmM2mwfBlI3XpwhlP4EQx7MGw2ydDoR9S6CFTbtZQ+y2a90+wwDWv3D9Asj7mMjhXU3j3D+gld7CNh+wbrUez0HI96tAsnmeo0jnqAuAjp5VJ/rdpgeSyNms3m8sXneBJ98s6Xpuq66HCCFYQtEm9qgH+yufHuQ7iosBDdcggVxkk1TLRABzG6N3cwvIvOq9O+TVUZ9X3dHq2//iEuipRLVLU5e78BTNwGgydhn5/cksoyVVx9NUxZ/Vb3jRS4AQAAP//7F27CgIxEJzkVDAW54GNCFaCP2CjCIK9vytW+gUWFoK9InYinu+Yld1T7Ox84GW+YAlkYWd2ZzLX7eb5NEGQ09aW3T6usrKplO8dHh4cFC6ETVhEplyBDiNxYU3113BOXB9Psynsci6ZvOSNgV7CHYHAkKgCptVBtlb/4Wq/B2ZDedCMRwPshn1RNCUzOv8o6fdkKaWVrJDz3TLnzPLdprM29f7CMtiFEZQpQG3W97xN+kyPeBASOrnhRJbgziccJ2PoqAS69mAazffX8WfgrZ5CuyvmS3a5gF2tnlEo2meye3ikFok5OxPGAR32huKtol1MdDnjBgAA///sncFrwjAYxV/aYtEic6x0B/Ey5mF/gCf9qz0NdttV8CYT6W6KYzCmW5vSNmnGl0TYYVfnmPn9BSGHwMv73vsCXepxwGOh4rwvP3YDVVcRnNh0OMxvPNX5x9do3QwRxInNHp3v3dCKk3K1AH98QPWc6vtggXssfsQ64+T4+t0LvX+wPZqYTJ9yBRvfof3OVAZEQjO7n6KYz6BIpF+2wEKrM//iCKTNIcqsQCPWENuNzqogPvnJTop2Nq8Ss+fyhRnz67eh0jKaTIlqMM9HlS7RlKYdl/kewts743AeOUv6X6DiJ/owa4/GqNInyLdXSMpl8fysG5gdDofVjEKETZ715P6902Sfhapr+QUAAP//7J09C8IwEIavH4GKaBG04Ojg4uLfdfY/uLno1MnFQaibKK5C22tLbU8uaRXBxalK80CmLJflyOXey2tSFMJrRWyF4hLigCtTVWzqxKFpN1So41uuKzub/LnE09evpbDUMQsOgP4W8tNFXehE2/s4n6HK/NzsCrBGnpzVtIf1rKbOr2/kOaT7HUQ8oxkc5Y7xD3/sVH6bbGtDSQ5FFEIZhz8QWLMYHUdKaLnDqfRVzT0WcKEpQ8hSuF/PEK9XcFsuAP2NMh7XfIXwxuDM5iAmU7bNgzKrcp1Go2kltRqWikJQmvYJsUeINiUIDwAAAP//7J0/D4IwEMUPioVETQgQFwdXEycXv72bg5MxDobo4qALcVChBuRPzR2Ii4OLMYT+PkGTtml77/qekV8rZVNSBZBpnPfzKDRlmr4PUIWizchSuWCOB53hqAwqb+2+kKVxyzmAx34Lie9Te6jhcNB05brxEXRr5DoYA5sUASxYUPagogaVcnwEoHOoWMwhXi3pjyYqmvXrpCnLKweQIiTFh0yhyNWonYUYbJ9ltgus26v6q/44mNccaJIKAfF6A+lhRzmSmMFpjieUD6ruPN+B56E1ndG//ex0hCy4NGHYCoXil5BDdWYV8d3Lo5tbCBHKLE2eAAAA///snbEOgjAQhq8IiEYjJj6Bi6uDb85kXJ1cHNxNSHwDC7YCV3NXmzi4A2m/tQxNaQOX/vf/8bu8WykX9aBNMzHJ89S0LX8kRSg2AwGrQ48TiBZk47+xweC+nosOASsJzaPk8Hr6sf5JGux1aoOEjJQ629NHckLO1Vx7rq38A+2l+nIGeSxAUVQFrVninhvRvnKRn1oBUo+ifHptQhOlGUtoxWzOazAIX6dv0UsGqlgp0LcryFPBQ9n+0Pv0xgK913S74ygwLtI71yeL1pIyEAj4hbvZREyM1it81Uuj6ti0DXwAAAD//+ydzwqCQBDGZ3FdSahIyK6BEdLDR6ceo0N0iaKzZR0yMdFRY2f16ikscH9PsJcd5u/3cSnBr7LpWq42z3kRPclIW082Nb2muadjyjPOGE2AT13q1vf1X8iggbcAsuOBCgRacdQhop1C2QZIJWPh+cCd6T+/tlNkY5OmTPsdvLZrutMs47fy0OzCJuPb1AruUuQIwyvgIwRTWNSs6iOyyDTGDjB7+PvJZkNzw2ln6obzcoIKN/RHpUWLOffU5oHOfVphQpBYkFj4YC1XgPeAzNtlo4UZOnfUaHoL4qBMk1kZR26VJucKET4AAAD//+ydPQrCQBCFXxKV+AeiEEQ8h41YiJ1HsPaWgoVYW1gIFqIELP2PWdZks7K70VJbJfPdYYeZeW/n5WqjsTkR7jiI9r4VzqfWY7vRBYOGTYJIe16l/JdKsOsNbbvKrrIpdFOh406uZ5Mb6ZB99hOvCDplv8632iZQntCotxSlESd8vYIMmFFI8J//Wa102FQHaMTpiOR2hfREZvcxKirDrlZhu65Rd3+oVOicZFgQ9wDwdwhmEwgeotIfotjpGmcX8RV1NK/cG0AEF/DlAtGBwa7EekFLgaYEkSHeyqZwJefNhIWeZKwgRYwnAAAA///snbEOgjAQhq+kBBQkOkk0DD6Ik6/g6Mu6MJk4uDsQAyYaogmxRCg1PcpmjJsI/fYmHa7X3l3vfuqtN7VTAEB9sPywhyq9Y4aW2P3Mxmo0iKpsEpMAcUdgjCcof9LnBIzMXBfJCZ7REQXsa00K/aB4C9qP+jhi2TjF2JwHYLheCzf7AyqOvb9sF8Ij3KKMArGp7PdQe/nDc9ZctoxBeb0obcnyi4XdRNq99JnEcdpT2WxoZDoqjtV12S9cxBEOf6O+D2awUEOFdND5CToLYLhcQXlLgZ9jKBIlp6cDTY2mf9Q9mwPBmC+ybCpyZgnO4QUAAP//7F09D4IwED0KAT8iuBiNf8DB/787OaiDzC4kxEVjQiS2VeFi7gAnB0dN7y3d2+Zyr+/6nuqIJnAmVo/NP9hVrAZRNgVuo25dROMRBJMZK1LKcWMXKhoUkE7EAMuCx9FASY34iE7SJD4eRmyoEUzn4IXyiEeoziew+w2YdAuP7AB4bZpU758jKFqyidYAFheoSdl02OmUztJPxjye6hH5+KmtaOuWpzg3Gcs7VMccbLoDvV7BM8+k//kCqj/gf5vRYsmrnwybsXG690I4BQJ38M7ZxBCtGaO+xWh0gEbDCwAA///snc8LAUEUx7+7s5s2v3IhkoOUXPz1DlL+CEUObkpsol2h2c3M6D3ixkGKdj4192maqTev9/1+KeqE9Qm0VBw5JpHO37j+WSxfxCjNo1RetYZcp8v6FGQ88kSfDlDbECrc3HIEnew6bb7DaMM5fqIcwK83IWoNuOWKLWDpHsUR5GyC43gIOZ1A00g2fUR87wd29wHOU7OpdluoeH93pM0o1KwrljibkTR+D9+Yn8iXvRU63NwQAq5OucGYLuY4jgZcE7lBHuxrYd/sSyjaxm+1kev1ka6WuIRr6CjiqSB7dhZLVqD3TokFyjNSFsz5lNdJIqAVrgAAAP//7J27CsIwFIZPknrHzQsWfAAHFydfX9BJxN3FxQuKaIvQtI1pJCdxUXBWer4nCKFpk/Tn+wMjU3zB2riISVNuJUH0XBCElZe4vWPQ7bvKCjxslnR5eGO1jiMvPrmCkQ9gzar7u0l8zJdR1vDNoTII3a1/OKSNl3EaUHXcg1wuIJnPQB12XmD5mhv2Rz0nb3CGoy8yCfp2ASvbg5J3DzJrpG218eDGqj4x5btnfwrBXa3T+QRmvcIuXJtmaUymmEogviM6PaiNxpBtN3iZpPMIQBT0fSCIsoBpWKzHEzZKWyT3uo5jblQOTwAAAP//7J1NCsIwEIUn0STgD55CEd14/xu4ceGmFrqtulQRYw1NZJ4V3XTjypJ8R5gwIS/MvNfnXQXhNIwagr0pqmv5dtRLJGLmFVkhMfqop3Ps3MUKXEOvF+KoJHaj9dZ+Yk9iF1BtsNhUCh8VnEfH+Zqxw27G/BCtsi2yNKs8g66UI/1VmQ6P1jSTD+HeGASdT+idmIHz63gCMSKPJe4Lrsm/iRAYv+HsHuT2JdnNmgSL5MGQzHJFPZ5KSLTCddKzBZliR67IydGh272cSCR+w3sRXKWC91oYI4RS9AQAAP//7J2xDoJADIZ74Q4ZjKOjhhBD4sLi8/sITi4OBDRhcGGUwAFn2nJOxlml3ztc0//av792zYMOGIzhAlzbsNgUBOHlW9ZrPO+ecrMx48iTrsyhPZ+gv1fcQ0il+ABONvG7X1OUQpQdeB1v7gw9dPmFhKa9FeAwYctvzpLZ48eb0ykqCQXLUE9ic8aeTQ/WTjwkE1RXnvYODuDbNqZ9bVccV9SVBbjxSH5TMCFE+4z8iWIbeA+KTbOJwWwTyqLGl4xDDvKuKyUTDEH4d7yNxFrMYw9MvDNhkqpguYInAAAA///snc0KwjAQhCdJG4XiD4IHRa2gL+HN96eggooXD171aH8spVF2tSCIZ4vJ9wQJhJDdzMx6JPcR5CnRGibPG3dTSrh7wWEzVQqtrFJE++y5I1+KrdAopPywQ7aOUF7OEFpaLw/8ChdMgotxfoANJ/Cnc/at2Q4VGrftCtkm4vAc2X5LKP2DMBFRFZuFQRknvF8TX2uwst9CclQdzlCcjjBxDFPen4FBdWrevc6faGieH2zSFPl+CxU0OUFatTrwxyFLgh2f0M8wNRVovJM3GEP19kBRPH+xSaLsFDAOhxWQbNYkiVDdngoWS+mPQjwAAAD//+ydOwvCQBCEJ6cSxSf4bEStLaxs/OVWtlZ2ERIRS7UQNKCJiXFPbjU/QYjefXD9Vcuws7sj1CED9SgMhIzvRZ61NTXBoDOfTqxVynM2onq6x1WoGhHvNojWDpLTmUfgfvpq6DfhfTQBUbaRb7aR6/S406+72FIOX3LYI3YdxJ6L58VnEcpC9F9IHRy1mvqQIP+M5LgHBTetHU7OmB2MkGt13+OzWZ4sTq/wk4QMCdHWw3UxR7haKp2UgQ9mGMtCoT9EaTqDPZ7AKldAIRl332DQCEnEMXmqBSWqNSHqDbwAAAD//+ydsQrCMBCGL0kLttAWLYIoPoXgoI/v5O4iODiJLUWEqpjUJHKJ4iA4S3vfIySBcP/d/T83UmIANbfyHtqmiazRgiYeiC7jPkbGQKSxLxQSykXELpQuDtAcSzBX6UfJqNj8Bo2BtPaRD/0EgtEYBL0fp3TqqgS53bhx7MfpDFY1aAX6yTtsE9yvb2JnU+13oKvCnUFX4WkGwWQKIh+6+7b/XHu8zNB4LwSRBU4owIie23oFCuNQiJ+gwBbNlxDPFiAGuRcWDO1uEkT7eYutziQIrJLC1DUzl5o9AQAA///snT0LwjAURW/TKk5WdHBwcejgj3cTNxdxEHFxchAFcS12Ea1p8yHvpauzweb8gkdaCLflnUsh01loqXizkj1rTBKCZqDNuHrECHGaojOeQPQH7T0No0kcxmXdushhS+32rRDEQF9hs6pAPBqygVYEsQj/4St3GzxXS8jLCVCmkYf8aTVCI9mjrs3qfER9u8JK6cFgv4EEQd1pxjVSLAjisOl5AKH3Mo6ASkEXJd6HPR6LOV7bNdQ992BAP+Fnnc14T92tnyTu4yRdrKF3MxD4c5qwqRWgagGrI1iLDwAAAP//7J09D4IwEIbftiAKfqGuDPx93YyrcdF/YTQhIU7GBD8SihRzbdx0VZQ+a5em7aXXu+t7XMkcSuaU4WxXhexAlTrMbP1ISzMxjccZlUH2Q0dCl8MAACAASURBVK2gKPzm/rWj/zbl6YgiTagCAtwDmPsctI7DK7QjTY/N4VhnxoXv12+SH4ZKSW+bFa7rpc7y8UCAe46xtz88R4xaoAhAnTPI/RYy2VGUtwYz+w7c84wthCOAVF9/ZssZWMsBDxjuhxSXxQzZfKp7cVreLRmD6PbgRjFaUQxnMgAnAUrSBrF3hsXyt5juBCZjQ/ZOGkBU6VWpEg/2ziUFYRgIw3+a2C58FVEoeABdeAav7w0sWHAhgqDioxW0NiYyI27VZW3z7QNJCCQzSb6hwpuA1MpK1bH5PYQxLwe9CzYddYW9N3SzGXJtzTo/oyULrd5uUKyWMOmZD9COL3NG64dkGb0+VDSs9X9fttJdMjbQ5skcxfrAyQqv1fih9f8ilMcHa308wcYxgvECdnqr9Jg/QgFIsw3Z7bE0ixNWb/tw2TPb1D/PwyPNoPcZZDjjMkZqELEwSPhBCTpZIvjPq+S90x9N4CcxJ1zs7gqhjLP5OhxVhoNNyxcVVmtBr+NgDJ4AAAD//+ydTQrCMBCF38S2WgVFPIGLLrz/KXTTAwiCoJaKuqv9SzsyafeCq9bkO0FIssibyXuj5GsPV6XHRbnkul6B2XdC02Et3ItNCQiaL0y6HoUWp9CK2HzcUacJ+J3BJVV/wXgV5K3ldbMF1xvQzN7Optg09OWM6nQ0olOG+nejTv78IokPVSm0WQ59TaDTm9kL26FpaLpekvYqplYeQ6K1SSafgDwyIll+ehTxAXm8R/N6DmCBw4SCAP42QhDtuoKtxjjO2+Fw/EZfOGQJV5OOpm4Ut0xgpg8AAAD//+ydsQoCMQyG07se53DTFTzwARx8/9eQO0TwCQRFUdfSppGkIri5OJzNN3bt0CZ/8v9Z2bS2oap25L0DxFY/k0rxsDLFdve9k6KzVLgZFS9niKcjW1lrtuY30CsGoHdghxWYrtyoBN73FRfjww7i7ZoPS3hfRN2pgEKE5JMUJfi4z0PJ+yGsanIMSt0t8kTlnMYq5U5Jmm80bcUIp1kOYn4k+Zu6e/QBNxXa9QYCTzXsR1kvMFprKsr/81Y2gwFEAwnNEwAA///sXcsKwjAQbNaYg1S9iPr/X+SlH1A8iSCih8YmZWV2W7z4AdXsQO4hLGEfM7MEHQmnl+c+bjj3WwaN1v5MQ4mYEkGnxQL2aiI5ohCKDQehQT4fQqHlBBdap8fw5bE+ibNMNuu1TMap6P2sneh907mVwlPok4sC4kccTdVsF5NcdHmH+w2d3pFnXSbwl6I4c6tad5L+kGkMppsUvLI9rhehhcfmVGXo2WM3gxvOC6AXL3f7yh+OumOYpkbTf+q0DQaDqNxHhhfMJDMxD8TM7g0AAP//7J1BCsIwEEV/SF0oBYPo/W/houBJROtaKCItTU2dKDPBLl25qEneCWaZmcn8Fzybti+87devx2BAlO7LOpMBpmYzNAsm7W+QrKy4NaKtEMecijQ99JdMacYb6O0OahH3feI3qG3h6iPcuQa1XdDlpKTM+STBDxbUXEHdXSa+qaKWK9n48xdzud37p76bXTZSs4e3Ixz7N6sK3WGP8XKaQYEzQ2uosgQL3fnGVRu+1S0Ayqm0mUzU8BBR0mifYbNJHm8AAAD//+xduwoCMRDcvRijnlh7CBaC//8bFn6ICCLhDmxyiewsBzbWPrID6VMsm+xjZmaYVmTXUOOW8NksxRkvy1AnJisG7WLLZFNMqasWgEiJ8jDAZ1OUq9kKzffgl6a9pNS2xakZOUZK1wulWxQhOlWgrSmEdJtWmzbxDgsYmXSzr7OnyyEQrzfKgwdn85fCQQsk2Vpwq4Jtj8fpDNEbEQKbH47EYfHxW34bhLfud3vy2w4ryLnvkR/tJTEY/gzT/1DUaIWzOY4M/mYp/AQAAP//7J29CsIwFIVPejtYlC4WfJMO4tM76aSCvoA4iDj4S9OmSeQmdHMVo833BJcMIZyTe07CdQamlmRkNbKqzmGisxmJsCqbDP03SJH215kyz7t3Ni9X2Kb1L2cRFzffwoo9ESgfuKRKFw5EaYCDfh7OAuBuyWq1gDrsYaXyxe5J0i8lU/jOTedsnk/Q3M+oVACDfQcW8Hhnk+/Wn3M2O1z/JsHKFup4hdyuUS3nkLsNzOMWxowBQcUEWTlDVk5B4wK2sUCr+34skcj/0vVsak6i1QLGiBcAAAD//+ydQQrCQAxF/3RqnUI3Cq7EKwiCC++PuqkrN95CqaJVOmlkUlFcCG7L5J1gNoFkfn5+EvwH7BvLvnFMlIPZGlU2ldgJw2bukBRFnLUgnjPq/JrXC/jhJX9U12h/EAzx1MpwmU5GSKezqCNz6HxCvVujLjeg6ggThKzURLc+J5XyVjYrqSemiNdoB1mn+Dv38mwCPQrd/MAMkyWw4+7198Met3Iryp3yTfBrDudL5IuVHFVij35+MiiK8hfSPraStSmXaMFsngAAAP//7J2xCsJAEEQnF+MlhwiCIKKIjYVg4/93goXaWaQVLJWghRBMzEZ2E1t7vX3/cHDs7Lzt8JSViEwYmASv0oHIz1G8onDywnp72/Q1uVdkEj/XIOuCP8cZyvNJkk1J7TTQ/ALb12rpZ0aTKexiKXc2faW6XpDvt8gPe1SPu3zMvRRLtW+Gz55IsnnLRLrlK8bGjTTL9X432fzAncS4Sa2faYpwMER3NpetBuOcboC0yAmU0Rh2tUa02yDsH4GqkO6rDi8V5R9hQVArCSIKUFPwBgAA///sncEKgkAURe9TgqR1CAX9/w+1aFPYRK2iok3OczTum4KWLa2ZAy7cicI4cp/nFiYr6DoZQpjYgeG1QuYFIJMSQ+wAE7FEs6TOnpUnRUIykw9oqdaDg9/v7J9Nm55N81Z8hyWbUSxlZe/Llan/UyXcrvCugZ7O6B8thBvzFDff7Gjkq9SrjViyazTlZBO00VazaGgW+dlg0+Cz5TitKsLlDm22aDdr6NGh934EFzguKNsr6wXKeg6ppkw9cu9mJvNv2MTK+2Oz54kAkCcAAAD//+ydsQrCQAyGf47abrVuIuJihb7/5qTgKzgIgjgI4iI6tNLeXU6SCjq56+WDe4AbEkL+/InhRBmsNaHrMliXgUhLSiVOXp4yUxRIxhOY4Sjariuv8pf7iLst6HYFOCvoyZMvBAQWrJIBkukMaVmJZzM6vAc1tRTc7nKGv7eA9b2KFWMsmf5R+5ARS5kScHErm5xXf9qz+Qn/gRtNrYM7HdFsVqjXS3SHvSzIUN6wop3OK2TlAibPAR96dVNRlP+CG4i8dFo8mwQQ4QkAAP//7J1NCsIwEIXfhKQKbgTFH3Tj/U/TM1ioFTeiWIq1I2/SleABNPnOEAgz83480yYxqFNxvGwW0FiTkg+bmaTQmNbsxJl8lhJIK+pOFeuSO6Gvjxge99iNmOVOXzEr4mvs4psv4FdbSzJODe069OcG/aUxCY1Mxot4olUH/Ey516VnU29XKP3PKQ8hIUSJKVNpqRr59WdB76aFyXGh0KEtS8i0gF+uTVIrs3TVDZ8waC9sdgj7A55VBR1qiOQKlEzmbxgT+YlVKNO3yWUcFG8AAAD//+ydMQvCMBCFX0tsNxEREUEQ//8/6eQgONpSnWxX03gkJZc4u/fugyN7yGW4e/eOZbSBKJ4VYgSvgwaKTHyqVJvtDuZ44uXjYq/CfkB9B/doWUbLFfxSv4Z/xDU5Zn/gkOhizO/m1YGeLYKzKFaQPeub88ZPDvQeQeMAfOXKaKMxULneJOO1pfwnRZrzBzlQP8BeGzbGmu43Xo+iZOoa1fnC3U1WDQU1ClKURfLL7dzVhPeYAQAA///snU0KwkAMhV/SorRUEKXe/0Cu3LjxChVFEBGHKUlmxI0H0OTbznJamJD3wyUxSCbQJsugmetWM7YYgS+08008m8MK7XrrerNpPqQJabppxD8xR8fmV4ocRJSiy4V6NSUUwyOaunqRqpyzhkyZz9fxd6OeTdbaoHS9W8dg9vvCtjTaQeW0xPT7m82KvpsY3AH5lfA8HfE47COd9gMJT+PNiHbcgfvODur9O1U+BMF/URRw72Ezyb9NAGgGAAD//+ydQQoCMQxFf9MWOiAighvRhfe/j+AFdBYKIoKonVaSwujGC0zydu26pfQnPz/IgneLp+bXtEtvKGVolQj22oX1Rmlls8rDX27XFkJ/f4ES4DobUv0XVu7Y69tVOTM0m6sdLCWVzf6I3J84v3n0LOrFtb/2UFEeWT7h+XJGzO+WwapNwOE2c57yzS3mU2ij/cURXKoiuDwPe/jlCnG7Q+R2WsVZzSMxwi9aLBTnbVIKqOznFvHFhEzDmBTfyqZDKfQBAAD//+xdyw6CQAxsxQdwMAb//99MlATjgZMYpaGk0/XIWcN2vmDT3ex22tlp6mwqu7Z2Yo0KUyBHYAitdyLMvKJozm7PnxmgrxeBm6iO4p2pUM8uw+L1NZaq9yCavMuYmI9vnB0rVphcFC7GkUh6HMwP5zWQ3FuXpkueclr7s8mHEjwTPGMtOUdyp7V9lUdPn+uFpLuRDs8/WNzvYfcAw4CvoeJ4Iq4q4u3G35zIOwOB1QBzNjGqPfFKnWgGAAD//+ydMQ7CMAxFv0wUVFRUcQaQev8bsIA4AgMLM8wtrUyCbGdnAlWt3wkcy0MS2/+T+aC8RUWQTKbWcRZKKj/vOxN4oapaXh6YddRPPAExDkDwx+ZX5LEpIiHbWi9SiOuJB/w78qv4ST4fap+jtePj15aHALU/GW9X3WvNQz+BwP6PdPnUx3hTg2LZBZ+DKqnU+crOknuxjrqju5zQnY/a7XcM9SPdt4iHFtQ0ACdXpXWcuaGjtInATGAOHwAAAP//7J27DsIwDEVtNSqvoSviAxi68P8zfApCYmtaxNK0Rr7JxMRWVPtI2TNkiX0fRUYrWHNq8aZr5x2rSAmJ1O1UpZ8Gg72A2GoOkaY+Zs+d0caKnykjPHhatzvi/cG0ZE4wrIg0Dx2JSkWtVp58wzmVF5vNxx0naOegPfEEUD981aicNsC7OetbkZUkXiMwiElePb1vV6Ip5RyA4+kPLrc8OsStzy1t2gsClNIzV2uxOzUcZz0gmVZYUgoyjuEDAAD//2JCnBb0F8Ie7WyOgpEKWBjAl40z8/KBOw4jEoAOBnr3Boz/w/bcjfYV8IP/0Blxbh5I2hmhhwOBAKgz9ffDe4a/n76A09KIvV8THYAGI1gYGf59/sTw6/YNhl93bjL8+/plcLmRjgB0Ii2rJGjvngB4VQD4zsXhAsCdTVZw+fnj2gOGr4f2MHy/cBoc9/9H8B2rMMDEwcXArqbNwGlixcAiKQMR/Tfa7hwFo2D4gX+QzubvXywAAAAA///snT0OgzAMhe1GgjJXSMwM3P8uLEwMqIdwG+FUfgFGVirib8mKUIQS834euQElcV43vGfTKYi0B7w8CRcGrguWQariEGxyv+Ng5N+CU2w+By9S3WQ/Wsl/NkXQy6qyeVnZ+1mJ8v7gwHg33/dMETJa+YMnuwZTAIS2g4LEgpLSmm456IbnPX4oLjPJNMLPXDqWShteLVX9gD5rDDQ9ldZx7ocF9ZtiVpV/AAAA///snU0KwjAQhZ9OBH8QLS4ECxXvfww33kBwK/4spbSWUpsRZ1rcCC6VZr4TBJIMmSTvPY06YX3utI1uBEnbbE4INIvEvCJY6uYbZHpTzZ31Cd9hNAZB43BjT8RYSuNyfJ6Dq/bgaAtIED0fgYtXDukV1fmIOkv/YGC/gaZzuGQDWsaAc2rO1jWkJkAKRHnY477b4nE5hTXRn5CL3REG8RpulYAWEXpDemfyGYbREVh1m973nwAAAP//7J1BC8IwDIWftbKNnocI/v9/5MGb4FUcbOBBTSPJ6nbR+zT5Tj2WtpS0eXkJk21Q5nnsOFZ419yJ9KluEFIyLYMEkQbE4qDI9ByTUv5e+I7enSjnp0ZobNZsan9NkV93F/+k+ETJ8EoGL98AGnrTMtpVSojtVg21xMF1bD36Z7GH3AlR9pzwOJ9wPx6Qu+sCJrYMQlWpEd9mt1dFUemIYH1ZHOfnmeJGqdlkXjPn+AIAAP//gu7ZBHc2GUev2BwFIxL8hyz3Y+TgBh/kwDiSTxMFHfDy7QvD36/QqxlGO5uEwX/IejnwAUGc3AwMI7GzCbpf89ljhj8vn4M7m+DDPkbTDSb4D7nPFzSYA7pzE9QRGYkDvMw8fAyssvIMLGLiw3dmE5QBWCGdzT8vX4BnN3/dvw3OK6BBvREPWFgYWKVkIMtpBQQh9+AMp727o2AUjALQilkmhn//mQAAAAD//+ydPQ7CMAyFHQey0A0WJO5/JTpUzJWqlg2pLU4qP362XiD2J+UCGezYec9meU6QzcGfxe6vcQxSvl3olD4FQ7Q7Fk+LTX0M4civ2PSYsMf/acSBwjGhUYFde8bIy0wyjZDRlnX1H/EdcCVMyLeQq6s3Wuzt21QFSbre6ADPXsQk8Bp3LQaOKKLK600y9LQ8Wpq7Oxp61tE8G88XTOkNpwbB1IV1jlMPmAWkFpucaQMAAP//YmGVloU0mECzm58/Qm9ZHgWjYAQBWGeTnYOBEXTAC+tIvrriN/hEURD+D5vZHO01EAbwwQoOyOmaIwz8//mT4c+b1wx/3r4BX5kzer8mDgAKEmbIfbagjvmft68ZWEGDFCNsNhw0KMMiIsbAIizKwMjKPuxW0MIBKA9Ae1CgffDfL51nYBaTYGC0Z2Zg19Ib2XmEhQWSBqRkGZj4+CFio53NUTAKhg+AnAfEwPD/PyMAAAD//2LhC4wCV3o/Lp9j+PP0IQPD75E3yjoKRjb4D+1sMoFmpdhH9mmioAOC4DOboDt4R2c2CYL/0AOCQI1m8Mwm0wjsbP7+BVkh8xkyU8c42tnEDhgh1/eCw+vjR/A9g/9FxAajS2kP2DkYmHj5wHv3IPf5MsK3NAw3wMjGDI7zn5dvgO8VZZWUY2DX0GZgGMGraEArQJgFhRlYREQZmEHbDxhGO5ujYBQMGwDZswnaqsnC8PcvCwAAAP//YuLx8GfgsrJnYBYSRSydGwWjYCSB/5CcAZ7ZBFV6I3hmkwFpGS0DeBntaIeBKADaggCa2QRdmzMCZzZBd2qC7hEELQtlAG/JYBidEccGoMuLQbO/oD2b/z68ZWAAzQSPUAAqbyHXTTGizAIOKwBeNQMpE34/fsnw/dwphp/XLjL8ef1iZJ++CrqbmJcfPLvJxMOH2vEeXU87CkbB0Aegq0/+/WNl+PePFQAAAP//7F1bCoAwDFvLxMf9Tyd4CB+gCOukGQ4/BP9tw3qDUpq1TZhiQ1hjYSq7tVWu3hsFhwVkPHqsQVI0fLMpKcixI3KS0ig54fwGMfJGp+IWbzaLsNQaZN/qRNzz5gU32VSbmGVGWDb615qrZJP7iO0AeB7/kWc8iLR60aqY1jmN+HCwSqy0TnLbYdDB/RBcodLh+Buykk3OInwBAAD//2L69+0r6Ah2Rsj+rNHGwSgYgQB+QBDH6KX8oKtPfv6EXDgPPjFxtEwgCoDSDzMLZKCCiWkIOJi6ALQiBlyXfP8GSTejyQY7ANWxsAOCPn1g+PfxA/hApZEKwAM0vHwMjNyc4JkuSMdrGHY6oMuDmbgZGJg4ORn+vHjG8PPSOYY/z5+M3Fk86N2zoOtvmASFwUuqGdkYGUav4BsFo2AYAdBS2v//mAAAAAD//+xdyw6AIAzbQD2I3v3/b/PiH/gIxKwLiRfvhK1fwAES2m5t/RWJrcn+wB3mUP82HLA7FKwHBAnZvC8lnDmrO+Ui1C/qDAh/yCazPbKJftbzhEihjngDZ2oRck+ws/lgXxPOpmWyOU4U5oSSf4g0vZJNqr2bhC7J59iRSiuhWhbFqS9iWmjYtG8zplVDKi2PFzscvUB4ZSmRSo4vAAAA//9CLuVGO5ujYGQC+Gm07JDlPCP5gCDQxdq/f0MawKMVPtEA0tlkhuw7Gomdc3i6+TNsD3mhDoDMbDJAO5vwa8dGKAAN7DFx8TAwcnBBBmmGexOEGTLLCTq1+dfDe5B7aX/+HAQOGzgAqnfZ5JQY2NS1GZiFRcFLqcEDVqNgFIyCYQD+MzL8/88IAAAA///snTEOgzAMRX9goOyVeoEOSCy9/2kY2FOVDZJ8ZCMkxm5Eid8JPObZzvdVNmkPBKNKrnc2u77qP5vSVU7bCq4BTNZ8+p9DNvVGa42TTRFMWZ+N8Yx3zqCoDHFHmJSIeVy8CicqnmxKGJsGBEmTrylfNrUhRSL5BWGedI02/r4ZVHYfKpvvAY/xg/b5AgNBy6k0jDJwjnANdwAAAP//grWK/kMERhsIo2DkAXD7BnSaKOhwF1a2kXmaKBSA9t6BTsr8//s/5O7d0TIBD4C2jP/D9uIxQdIO0wgMs9Ez5YgCsGXp4AOCPn9m+Aua2fw9gk+jZYUdEMQJPSBomF9/Ad2X+v/nX4a/798x/Hp8n+H3/dsM/758Gbn7FFlYGVhl5BnYNXUYWETFIWf2/R0E7hoFo2AUUAZA/Uom5r8MzMx/AQAAAP//YgLvl+Dm+Q+ezRldRjsKRiqAHlYwYmemYAB09QloZhM0svxv9K5EogGss8nENILDbLTHSRBA0wloufHfD98Z/oIOCPo7clvWoC0LsJlNBtgy2uHcDIGVDYwM4BO/f968wvD12AGG3w/vjthyA3QvMSgNsCqogJfRMjIj1b+jbdJRMAqGNmBk+sfAyPQPAAAA//9i+v/n9///v3+CZzEY4dccDPcSfxSMAiiAn/DCBLmMHzQzNYI7WKBZTfA9iX+RioDRDid2gFxEMkLDCYwHkyPpBED5BzxYwwy+tH60kYgLMIL3JoL2pP3/9pfh35fP4E7HSAXgziYn8gFBDMO77QHNF4zskDzz+/4dhm/HDzH8vHV95A46QOsXZgEhBmY+AQYmbk7wQUqjp9KOglEwhAFkxReoY/mPkYnpHwAAAP//7J2xDsIwDETPaUlhQq34/39g4z9YWdhAakFCDUNLUmQHJAaExAj2+wRPudzZV/abNeK5Qzy1oPkiOzuGoQ1xHFhsKnWmpiRui1RXPHfITGN+Cel191goVBXgPcC1OfZZ+RkeD6+3XgNie0QKIXf8aovwzzxInM1Xsfn/UJnjtLdDB7gthv0Oqb+gWNY6BvAGfn+6ukHRrJCGR7RGctW6r/Uaxg8zwdEI58Y7AAAA///snb0OwjAMhM9OK5WlYwXvPzDyXBQhIcKPhEhAtkX3iqm1PykPkAyOfJecm+thb/VdnE1RFz2HowTOsCCTaXQF87TcnUQp6rDU590Gq3M0m8EMxNEUsbLrgMdt/Q7Vn8iLUWqhY4Y0JOY8Ig1bUNosel9zobax0ScSzKb/GX9VeeWwiQqfF1DzRQWHcjpas+k1zbkWcN8jDTvUnLX5lruI/EYoBMGyIapgLkj8/gIAAP//7J0xDoAgDABLYXUwLsb/v8sBCU/QKCKmRR0d3Ex7CQkzQ6Gk7WGKEwe5ktZSh1voL5IikEddIbSMlsbNkyORXIl510TzM0L7rpxjbRAtuJIG5e3AqgajLDOk4CHFwHtpmGsaLSunrKC3x33HHIVjLilQNj9yD6/Y0lFEsG0Hrh8Am6YOUlIDiqL8GS6jBYP5BAAA///snU0KwkAMhV8yVYsiUun9ryYUCsWdbjs2kszoQnDlqibfEYbwmPy8hFPXWTWJNs3y1weVg+CTtyexbqNlKtV1jwUX3Tw7Z0jO4ZP5CZ9vp/YLSzb1XiIn+yRKxNF3VGsSsGhn8zohT2MZYXeGeTZ1fHLXli29XkLm5d3clu7u437DPFwsFsRrhkUMPp7QnHvQ/gBRLY1kMwjWR9XxOjEoxCRPAAAA///snVEKgCAMhqf2ZFE9Bd3/WkFFRNAFipKMbfYa9BjbdwSRifv1m6UTzySLosYZilSSjVZssoldZBSFoSBIB2p/Jz5Ci0vkZR0TKlfVJPhgs7n2LV+hegMQ9w3CPMI5DfR/Uxpso83BeM+1V9qeoSeihpwZR99BWBeeVSsR60gSlDUtuKLkBdAaoij/BiVBxsYbAAD//+ydsQqAMAxEcxFEXPT/P9FBwVlTuVSKizhL8qB079D2mt5FW4KiPOYkCQZoUtQ7TTOg2GQVyntsMonWPUMZQvvJc324ZnbWEVJs9qLTLOAvmSY286b4BlDfedlm6FgX9+wVD1aKBYNy3Ovrlc0unNfXu2wB7k9kVdP2TYrFFJs8d/mlmoITw1gPoNxCkuR3tG0cKGAarapdAAAA///snTEKwzAMRX8sj3YJJJje/2aFpktJS7akWHWRMyRTIGOR3hE8CAlZ72/DplZlv2Fgt9n0SnM2C9fYExGWyP2mcfb9yhpdIPeuCr/BybDg+yuoS2jESGuh7MfUeuNQ5gV5eOIz3PDVuNkUG22INWdTnYlXoLXp4umN/LiDX6Pe+is3m5cWvk9wIcLMQIbx7zQF5BhE/AMAAP//7F27DoAgDKRIwEX//y91wDgQqGlBEgcTF2NMewk7C4/r3bWu8UsEA9i5plqgFNJAtRZrRWc2MaW6sKjJ4RGgX5XYyCbPT5SobPrAzT1IlTDOM98GVTbvATUfTuetbJlJRtnlKZuGsr6U8w1jm896KYt/v7+XcbpoqDlUXhdTYhRro+V8F+V3p5lH4dB73G8QqR16FYo/g//VQwZr8wEAAP//7J1LCoAwDERj2grqRnBR0PtfUBHx01QSxa0LV5I8CL1AW0I6nUFprKUcyWoH2lCL4r/L7Ea7b1KgVMb1jXw1iZxRqvBlgiNPfOwhxOEye0k2sHyF7xrKQEsCmkaRUqqTHrN0kqNPqkZVzubDPdikeZX4G848Z3dalSAC1jW4tpM9YckIhvFzCiTw/oBQ7icAAAD//+xdOQ6AMAxreqgr/P+VqAIWQpF7iZENUGKpe4eoqmM7xsYFXAAAIABJREFUseiuknUZnloimXk1hWIQTKEf5JHZxAFZ0mfgOajPBuJqpZVINjHoZZrLQnaonDdJ4t2LfRkoGvR322rrvK/Vhi0MGC5FMdb4Qi8XKWXTCFXZt7klc6bFMNRNIzDzDGXThzKJFlZ80symQvFvgFc6z+TDcbF3hjoAwjAQ7dj8Av//aRgcCRIwhBVy3YIlwZHes5MzvfZ67Z4EzhgLHvi1hDgFIon7mt+4tNmQnab5olBEIm0/2L4VTjrUgA9Wi69Ab5TThIbuW232eKJNtDAdN+HtMg1c6r3NZZZjGkXX1afDJASJOdtk04LG2PQk5L+YazappKQ3AAAA///snTEOgDAMA+sy8f/fMfAJ2KAEOY1AYkGMKD6pP2irunLssNHCXGjW2mSjFTmxx0oGIiGTSyfgO+wp3WPmNbNgZ0k/hcM4eEm/KZX2Fdfk7fCezbYuPRE6GZzZpJUWDKWt6HPPifYNRTbvXs7ubvPkvauW7dMq3p4Mi6IVn0nF5XLS6g4R4i/cubOeQQuUghMAAP//7J29CoAwDISPVJAiFKmC7/9CLs4OPoI/g4hUaWpXwVGSb+wTXHJ3zeNsFuBcLdGpSlNRhJL729CuzGdC4AP9IZ6vEBiFzJC1IN/C1I6dTnbKddh8Jzub24qwzOnWrTDioGl8A3JV0iPSFjaPoxuHzH3ocUyj2O58XDzwZ2NtB6rK9KiJG0X5FywlWVNeILpuAAAA///snbEOgzAMRJ2oa6H8/9fRsVIRG4pKanSXgJiYg+wnsWciiS5+F6uBk8kmjEFU1RrrunKMc9YwWz0Y1yqGIglrYD034ZD2amayKZAsWRYsYXaze/ETXjbVd5IrdhspBF0piaalzP1agz2tA6svAi+bxpLNWKKAPE/ye4+yfj+0glsF898PyMaefamV+vtfxHGaZ3+Rgm0NzUUIM0NUkaAbAAAA///snTsKgEAMBZ9x11bwB5YW3v9AgpVgJ1Yqi4pkV7ATLCWZM4SQMPmQX8i29iRrHYxxurepiEashYkes6mj9N9hs7ltfhQSu2CzyVdpiwqGrQQfCuIiUa3EO3THz7qEX5sC48fHTV6C0iz8OpbWXMQh7x7TDNd32MfB/z0WCRFMVSNpWsRZeV/61mZTUX4Dl5CP2QSIcAEAAP//7J29CoAwDIQTm0nwZ9L3fz+RrlbaSlIDjl0l+SAv0CHQXu9ukMVOVJDoxhASABbv2XTM8fWWWexJ1P/1etn0HdAHahptldqTehlXNlmhmmYZVjkNizN9vN4WCZhKqU0x+FjBirhUoIytX9GY11f3Ltfg5POAHKP4vy3CZzEsK4Rtl7CxpmyaPArH+S0cLi5tJ2zaBIAHAAD//+ydSwqAMAxEYzWodC0oLlx4/6uJC/9IlaTmALqT5MFcoLRQMknG8dpxxJBgvkOGKy8JMgyNqF5mQs5mGmW8Q5ypZea5O40zd4IrSsialjM3ya2CAPpcqi9I9NCpNKdVihTex9YrbUcg3STHBWHaIIwDK94FZe+HnM2qBux6jlJi7FdqGP/hcTa5iEZyDm4AAAD//+xdQQ6DMAyzm4nLdpjG+P8P2QmhaWib3BSJG1xR4iekSVsrcVzotidfmn1YykKylXV+EBJB0EhmHTdHUMLJZl+xrhFLHA8cnVBVvd08hdwmukJ+idYPsP4JdF3rSORbso9tjOLVnzYXK3fk0aoJC0TNGkmcTL6bbyyvsd4l0fSKOn+7P3BRZ/N683c5yWYicQ5UzabvnwXpM3LA7w8AAP//7J3BCsJADERnU9IgCvWqtPj/PyZ4Eyu9aLcyu9K7vUnyIJe95bCzsBMmAjWIWobZBNWpJNIGgUsy3M7rcHSJgS4siTTanyjO5lxczXm8l6AXr9DN1FMP7S9ItsPygj+XahMJ687r5PD+se+2rfrD/r3+TzS1uG/1fbsiPx/+Umn5Fu0P0POApjvWs9CQIPgjvhkg1HWm0YosHwAAAP//7J3BCsMwDEOtpC1l//+bpdDB2kMXF8XJ6K67Dft9QjAmTmSpyWinKqPFMB4CvMOMNnDJJ9vN486mhfJTzsaXZWcxd7/TQqToHMnYE0pp1bFBEOuHsQU0CGJN6S6i5y14K/imqylYR9xvyYM5k3qj1kcbtNFbsMM+nOwsyvGSsi5Snps/WXXrE/zdTPPDVCMxbAbBH2A9u94nc65JJwAUgF4AAAD//+ydPQ6AMAiFEYyWxM3NeP+7mTj4EyetNVDdHFwNfEdoAqE84KHs2GDgA5nnoqonQNr9o+nYI+UOstgOWLyeKYVuYDXU1m6U54DvqE9ihHNdIS6TjsCZBUmPvIgqUXY9UMsAFeWY8qu076T73ULIxbVYfzg2uUXtc9sgjoNaoViNG9Id3iYr3j5s4zj/4VE1ZVKFKAFiugAAAP//7J29DsIwDITPRrWhIHgDhoqB93+0UIQqSIOckBGJEcn+xsz50fliH5MISCWT6o2GIRHTMyZRBn5oG91y7pDXGjtQPFp6JjZ12/qmutiMO+A3zAm26vtjRrnPrns2O3w8QS5XyHQGH/Yor+x7Su9XSvsiaHnXumsFnxCbH5w64ebsLQvWlGocjsv3yE6GuSOi4HEES1+MglUQ/C19yGZ3NqvQ3ABM5Q0AAP//7J3LCsIwEEVvJtI6AR8L+ymC4v//jWgFIdjSRCaGrgtulJmzzCKQkDCZR+YSMYOYR+Jwc217hfcve2Qa6sjV0ZQSyEmhQRMHkwOIazdIYzkSxZPM5jNi6u9IMarfPCml5eMF4XzC6tABQ9J5r5aQUBxMv9nBi85k03w/578hZ2McinzQLAqukbpuaTY2Pfryd1NtRUDOcMzw2z3cmuYxwzB+HAmYfWQ1c8lskscbAAD//+ydQQoCMQxFk9S2ozKgcw83s/L+R1KUQm0jSQuzFzdD+m5QKIG0efmEPgL6+KE4PcmHByKNn82BDbob0vxE1nw7jR8w+HoqM/YUgkZX6Lpqgxv3f6Jv8GUuUN+gjhXntMOD/BeJsZhuKxzXO7jLFWrq7qYy3E1F6k+RxqJF59A8g1sWdaetwaXo+LlkS2r9RZu3pKnNCDVnqOkFnJLdZlNqq0zanM6A/QHG2mbewWBvMPDmbLpDRaSKiPwFAAD//+ydSwrDMAxER7ZLnC6SAxR6/8uVhH4SEmpSRq4P0F1BehvvvTCSZ6QJatvJ/VvyeZYuz6psOo412Gw2ZdOi3U8fhwRhNmJyG99P1A1BOHbOWj1QplsNZDf8C09LNuc22XCeLleEPgExfG1wXjAqvAsuA+oC4jBoXAybdLHoLGDEBy3o66vOzVtXNvcN5XlHWXgfhheOZSqbo56KK5uO8/+0erIpmxKPDwAAAP//7J1BC8IwDIWTUK2XMYaIgv//twmDncQxNG2kWet9JwfJd+yp9FCavrw80lyrYyyezReGwxOR2N8Cjhmaip8zSMr6w266SCh+Me2xdwFqC3pUpZZihjRNwOPD9qCgCnU9hNsdwvUCdIp1UJB7N/WOyUkLS+oC0HAG6ocdbOxPpI/6E/OyaJeJxfQXpeYdC79B5nnN7jWsbNJP2YzrmhebjrNfWpoDUpuuXpRNAUL5AgAA///snbEKAjEMhv+GUhWPcxJcFc/Fxfd/EsFNcJZDXXJXK0l1cHMUku8NWpqm5E/zkw4FUWVz9kBKdxD5dAvHHhIkomqKImW5VSfGaoES3w8fT+4/IsMsoGdouJzBpyOy2BYYR4bepPUWqetAixZlrEUd84gSPjwR5g0muw2m+wPicmV2Vwozcn9FvvX1Hg6waZXzWTOzemwWsVLKdoszomhS02qnhOLpyHH+G4nR7z+bQCC8AAAA///snTEOAiEQRT+wYJTeUpM9wjYmVt7/EBYWxs5CE1ldZs0MaG1pMvwjEGD4Yea/kkYbApmwSMaHBGsz2pluUiQp72yqcpnZhObizn32PgBdBYw3s/mbTFkvTqKdLmc8T0cQP5yVSzAomx5+28s8MLcaz1n5nuKfq9cEugMuRiyHHVb7A9xar9mkcRTMB92u5Q62SrmslUfL5pvxJ3N6KEYG1TTaGCVPQNallaOmpr/VF4/84UbbjjgDxDiHNwAAAP//gsxssnP8Z+Tg/MXIxv4T3NkcPSBoFIwkwAjbs/kbckjFSF7mB76CAVQmIF0uP1rDEwagwpWVAbxX8/fTxwy/7t5k+Pv2zWB3Nc0BaA8wm7wSA7u6FgOLkAikEzHSkxMsPzEyMrCISzJwmtqCO5zMgkID7bIBA6BO1d/3bxj+ffwE2aM4EjuaDEiH1v36Bd3D+n1ELztnZONgYOLkQVpGO9AuGgWjYBQQBKByDLQli4XlH3jPJiMjAwAAAP//7J0xDsIwDEVtl4SKFqmMldgYev/7IDFVPQEDlMjIDpY6Mlay35QTJPlO/v9EMjnKLeOxLZjyW8Qmh9gMvGB3GgsIkvh95y+bdU/IumYOsfkXaognHViUZYb1cddvgd6RwYV4NvNtAhoutTOQN94Ob5hXMyVohhM041XFOEm9A/mtHFKxKb2Sz1W/WWsitkPBiSY2P+XnYX059mwC4CHVRFoLrYujKAh2jHk2UQfLkgdE/Zmp6/kLAAD//+yduw7CMAxFr1P1QYtgZkAgkDrA//8REhNUlIGqpA5yTHdW5NxPsJQbx48TR4sapP/rBSqqgVzG6UAnmdLc2XyPMekJhul/AgeSajKVtYKCkhn8KH1sSqFiunfw1wu4u5mPnySJbrVGvj+ibM8odhu4ZfUFBRlMogVE5idQ0yA/bFG0J2SGdzVnsewmChBn1BiZ72z6AH4NChkzO0ar/iH3UeySwLydJiX9heLobJxGCJ6fPXP/wAcAAP//7J1NCsIwEIWfSS3WWgR1I17BjYdw55Fd6MoTuPMQIhiblkxlJhVcurOQ+SD7LMLk7817memdvkxZwRSFH1mrMlolIWKgm+Rsei+yJYmtSBSxq+aXZB7eyU+d1oIf4YMiEcjHvM3wuIOcA9fY1BmvNyj3B1BTw52P8NcbkAOm/BwiE1hk0qsZELhXc5WLtHiy3cEulgOY3P+g+hX7E9uvWpP8ZZPzVxt0bdqO1qwAEEfarM+e1b1IUQYPewGZ6YzVXeF5OXW2muMNAAD//+ydOw6DQAxEHQiEleAcNNBx/zINN0DpOUJYBQwaO0jQUiHZ7w6r9Wc885ScTTSbIaDAjJSmbhXo2GLfbMZJJ+yQ0loFBkH/ZlM2m+tqt/C7ykND6tFsInMTd4uWJZIAjpIwwUEzPo8jxeFzkNMaQd4SidMzbjWLtqNX3YiJkll4kcEMnFflNtEjlxRWKa38RbPV4ac6Wp5ktI7j3JddRZvllJQVtpq/b/9mYqYNAAD//+yduwoCMRBFbxKTFS0UH83iAyy0EBv//49EFBQfa0xkJsJuYWGrmQP5hFzmMnNntBmMYIZjqMLB9PpetWwgoYNYTiEXGmaTV81n3Nn8aDaF72iYcioSn8cD/H6XlnzkzvvullssUazWsLM5dLfDOem/z0jz3USPcKu4U2MnJdqbLT9bTuuD9RlC/4RGrML5lOILYjRrYloURNMRTHZarFJm04nZFISfgWTK6EjNS2X0PT6qEK8XvAAAAP//7J0xDsIwDEWd1K1oERNqy8pQsbBUIBbufxfEVhGkDk1cOS7d2RDxu0PixP7+3waWerGRhScIzgXynmJ3MdVQZSU5YoA4EYR1spmyjDYTpQMXeM5HIpEYK19gIT6cOcphej5kaqNEWEFTnM6w6a+AbbPuMP410RRJjJGwbqG89FDe7lAcO7BVJecsUcI4Sr6mG6TxoJ9NwSwKCW5avQbJ2kztHjbLWkeeS2afKmwU5bf5GAAaOxlEl213b9zXHpsDzAAAAP//YvmwfC5kEzYHF8Pvh3cZ/rx6zsDEC9rYOYKvfxgFIwvAZjZBe4e+fRnRy2jBlTtoaT1otmUEN4IpArDO5ts34Ds3/ymqMDCID2H/UBGATl3lNDBh+Pf5A8Pfl08Yfl5/ADacmeUv+Nqd4dagBM/W/fkHLmOYeLgZ2DV1GXhcfRi4TK0ZWCSkRnwDGlzmvnvDABr0ZhjtbCIA7Napnz8Y/oJmfr9/Y2AGlclMI2sWAHJAEPtoZ3MUjIIhAaADYkzMvxk5OD8ycvF8YmJm+fP/718GAAAAAP//7J1LCsIwEIYnCSqpQt27KHgFN8Wdt1cQbyK+WszCaWR+U1y7UGo73wkmgSHz+DODZBOIIzNjx6CbTymG8O7wqJMrfQbJZvPqbN7TUJyBgtUnKdlsO5sqpf0ALDOWWl2DIJol2axuf2P+txFZ3KhYkq9LCvsthcMOA5V6+8Yk37F5TuNFQX5VUrbeYDrv0P/xUtvZFD+5nBF/GMxr03gD92CSjLa6oggKtUkHbPsVOKsobURKK2+RxqGK0m2SiMc4F+zEH202O0VrH5GZngAAAP//7J09DsIwDIXdNFXVEhVxAgbEwgGYYGJh4+pIzCCBhAq9ADT9CfJLuzMhCv5OkESJ7OT5xZobKSOhbFv2aTmVjV0QaWr54mk7hUcOufDLIKp7ZZMbaZP9Y2VTR6RGBr9To3wJubJcNt8GzYy9R6++X6k6n/ABitCBfqQhSkjNdkeutvQ87Km6HLFmHHv8fhu2gtMrmphJHFM8X1C6XFG63lA0naGCQCB45Ksip4a9zfzIJ/YdT19GW5bwtCIuZZNvGNlH4QcZxKFQlE1BGATwbOpHkCQ3ZUzhQmVdU9MLAAD//+ydMQ7CMAxFHTeiJRU7AxILEwsSExtMPS0jN2JAAhZESwuEGtlpB0YkllK/E8SRIud/O44dTGfN+lmOIhlrX1QWUOcFENXqMir/TWMhU00AnNhvpU6jdakIThae4lKp1vwKg0Yqm1yx8Yd9qNooH2CSQLrJ5A/OaLeFa36BYHxSyDtdbxfkt6gEEI1SsOMJDJcrcOsM4vmi+7H9EO4k8eejDNPiC4mJ1NwWWrHpn2FoXVVJ902v4D3gs8KCk//t61f0itI92mm0iHeM4xM6dyZDD/Ie3gAAAP//7J3JCsJADIb/zKRudPFBPHgRBMFH9+RLeCwWFRQED6KdaSsTcbl6rM33BhNIyPJnwjYdfx5kqCGOfBV0YHx+f9WuKH/Ne7LpRLLUZRktOIJNUtgsA6Ie9Obu75A1csahupRwuwJ+X8h008SJJtIvmGE4FllpOO1Quzuu6xXKTS45tUndc/rXJnuFGFI6NBWkaOJxhsF0huFsgdF8if5kKk0c5ctkodjc5vD7g8RdsqQ+gq+dTe9FcRMaoZ1cZzBPJQSRNmgUpRWEMMX2RoPR0cTJqSbj4B0eAAAA///snTELwjAQhV9iW9taxV0EEf0DLm5O4ur/d6soYhexBbFJk0gSKhVc3NTmWzMml7vj8e48EjeSH6WK+H5JOLejpnXydGuvHH+OURq0Z5NJqPsNiletvXLj2dSqZjKwf4B0k6k/xrwnBcUBWVxRHffghxTBZAYStXfNxTuoHyBcLCFZCZGdwXYpYMLvN7OObjR1zNBhH8F0jt5qjWSzhTca23VCjhf09G+RnSAvOUhkVSzXbDZQ0jacUrSzFqvNq6SWeusDV5k6HF/HU9nsMNoNcxLFBRWqUhXHAwAA///snbEKwjAQhv80aW0RrS76BII46OADuPniTo4uboIOnYQKQmtp0iB3QXATnEqb7wnCDUmO/+7/FSsYHwJpRBQ9YUxpQhWDQ1C8rOHpOPSQ0dhbDTRlAfsq2Gq+l5EESkHSaGM6cS6AXtn8n8B9pqvzCep44GaDciY9X4QhZDplhdM+cm7U68sVJs94V43GkamOFBLtjLxaVjxSm+juoGgKISDTEeRsjni1QbLeYrjbI1osW3DQdkGfDzLO0tmN9zVt2UAO0Du31Z+Qd4bWLhamj8omvc0ddKn2eDqL29msRELK5vhuITS0xhsAAP//YmHiQZ7ZZP7DxM7x/v/3r68ZmVnEGf4xcIzOaoyCEQP+QRtBXz+Dly4xjsAlb+AlS+ADgnjgBwSNrqYnAzAyMjBxgILvP8PPezcZmE8dBZ/COtrZxA5AgxvcLj4MLFIyDF8P7WP4enAHw+97txj+ffkGmelkHYyuRrpDExTlHBwMbArKDOwGJgzc1o4M7NoGDGyyCqOzMFgAqIz9de8Ww6/7t8En0jIww/YpjoYTGMAm8kArJEAdzpF4zyYsEMAzm9AOJyx5jGapUTAKBh0AF1GQ02h/M3Kwf2Dk4v7I+O/vP4bfvxkAAAAA//9iYRYURjiYifknEyfXw/8/vt9lZGXjZvjPwDE6qzEKRgwAVV6/f4MPq/jz9hUDK+ioedbB2sqlEQDPbAoygMoF0GwSbP/ZKCAdMLIygWcmfj99xvCD+wIDx31Lhn/mXxiYuEb37aEDRlZ2BhYRUQZmKwcGJtABVfx84GtRft68yvDnySOGf99/gQeDGNkgJ1QOyGwHtGMJWtLI8Oc/pGIFTbxysTKwKasxcGjqMXDomzKwqWsxcGjrM7BISNPXfUMIgO6f/XZ0PziO/377zMDAyjjaecAGYLcC/BmhWztGZzZHwSgYOgDW2WRh+cXIzfORWUDwL+jAxP+/fjEAAAAA///snT8PwUAYxp+31yrtoRGRiBhsEpEYLL6C1Yc2GS0mBkNDwiCkqJN7q7roJiHp/T7BJfcO9+aeP7YlMxktCRGRL7d0PGzILvWUQtMkURoKAWVLlZbvxbsQImhAOEGh7p+j5j0folpniSN7NgsWgvg1KPECI3pwaX28D3HfhXA6FZBtNvhP6Plz+0OIVhulThcnX+KsuwbXeuFMGhAUKRB/t//gAcqy2cSPmza06ERdbzyBnM5QHozYl6sXZkM+OjTrspgjWi3ZI2+5r98rA5OOtmKJ9i2p0imgjJZ0VdLbt/kHBzIYDPlkPZuxVfEiIWtAfIdyrngCAAD//+ydUUvDMBSFT3KzVNdWimH6N/wDe9r/Z0+TIboxhPqoQ8E2tum4t24gyB6Egaz5HgulkJbQ5OScY8hNDjcqok+V5U9h+7pU1t5Fv1ZkUFBfWcAeoq/yWZSJH2nNQ0B6IkmUTeKuTcs7y3ES+BPiP+tEBeM0Wg4J8utH6LyAuXYneOAZoLWk9tosh75IoJJLkLtBtZijKV/QVR8I2zcEDvLyTb8+4VqEU5S+i5LJP/sBaPuz5Cqx4jHVaQoqHGhy2wcBTWcYf6uykeNjyu/Ob1aoH+7RlO+gwkAZHc9F/oZ4Nr0kNg+SvbKp47cRifx79mvG0ajV2VUlCfx8ydfYAQAA///snb8KwjAQxr9r01Rb9Qn8C6JQEHF08v1XsSAu4iQWXaQUWmwj19jJQQQFsfm9QIaE5L677y6CvzmoIFtk1O6ccr91JCES069lqA+kC1FKIY+vyC9nFElc2/0v/9psd0Ce0IFOlVU3dqb3KYuYpJMYhz1kdwAYsfkSFnPecgWnN4Q7WyAN18h2IbLtBkWUQqW3speT7EIHo1/we3NliYWmSgFIwGr6cPojyPEUjUkAGcwhR2NtO3cbH1//3+BhN+wauUURwPbQ6joxVc1n6JHwYMHJ57D2A4LM22Mw/DSP1hKybGV5Xs6tWOXsE8fBHQAA///snUkLwkAMhV/tqqiIFsUVKlYE//+v8ORRUHGleCguYNXWVpmplrkpeJLmg9zDDMNA8vKiyGUzyV1S1btcKO3DneNA0z0un6P3TaQFsbO5XSE6HlN79axzo9QaUOs1hK4bzw0x0ujQ+yOSIsWzm4sZruMR9K4NrUcOpZ9gbshymYUJpdmB1rHg2wP4/SECZ437Zolw73Jp8uNy5nOdSS1EEuL9iSV/mWBrK65SEJQ8fFaZrfnUdcjVSpxDowW13n4ZPdnQLJs7zfJ9oMRXhKcDbtMJgtUckefRoX0DSUgJgvgHWM2QFYCzOWTyxYgrlYwsYBh4AgAA///snTELwjAUhC80oVak4CCi4qxDF0EoCP5+BycHcXCWDi10qqUSE8lrbesg6KY03z8oJZDLu7vHyVNbwYTQju+bi+aVcSHtVNPSJehxXSmyPJaTzayz/585Anw0Bp/MofICKk+qXKsVm9/BSGxqrSCjC27nE2Qa/9MH/ARmHY+7CEhwqnALmSYojgcS7/l+V4qX7N4MyJzqPJPo1C3hiddsSDsqUuWTyT1bmAcXgA8HcJcBvPUGvVUIMZ1RwRNN/r1+WVZk+Riz3sZYaGUcUdGSEfTWLfEG3VjEWZf3j9Zn1MY5LJaf5Om6MI531zSze9TOXgOGBwAAAP//7J1NCwFRFIZf45rrI9lIoSwsLC2U8v//gAULCzQKCSv5Gvea0TnX2EmxUXOemu4fuFO33nOeV1GCkUDmTa9Upr2Tc0Zr+9KRC0Ia8FzfZkRpyWbJhfxphRIdHhdsd2D3O9y3O0gN0pfQPhol5ocrbsEU4WQM21+xgIpkMsJnaBwnW/GBituh9tGB32whV29C1RowixnMesnVRfHl7Lovzc31E5KgIHJ9mCxsSnoTniN6id02o5Q7dZ4f+Kpa40RVd3so9AYs/xF+w27XCMdDmGDO5m/eCRfew/fSZ0t4KqF/NvkEQfhPnqZ2r6h5Ki62NgpHwzg6ngASnBmDBwAAAP//7J27CgIxEEXvmqziA0QRLbSz8P+xsrbzAywEwVJW8e2qi9mRmayIYCUWonOKsHUC2XnczLVPJsr8bTg1NQRrKQh9UVjfayk/D0+94xHNbG0QH+C2a6SnP5Z5hVlns9WGKZWRZP96vQHeIHjIOOl8RjIZIx4NJYEJxYdReQeWtvIe5rs9KQxdFxHcZgW3jPy76/UKFB+RHg/eGD+5SDIKti7JkksO5KUKWyhkhdYibL0J2+Sufge5esNPpa7W9Iw+gNhKzaZw0dx3Nk2gccUL7qoyUZLY0Eu1/3Cf6G41RKSNTUXbcKJHAAAgAElEQVT5UthPnFdTqkjcmO62bj/oE6t/xC6MUtzYO2MdBGEgDF/hCgSNg1EiDr7/izi56WyMrsRgDBFiaTV3JSQODkYHE+5LGFkKbe+/Xv/Dl4wZLWi8uKEN4uQRxJod/wRhELDjnQNXGy6lddWVg9TB9dqkoYgSwOWKA/l6s5b2J1/RBYmowN0baHZbdlmlckzMchY6wufQCWRIzyzr36V5254LXwpfnsHVXmyCab3YJGfPXmxqP7dJbNL9UHLATVMIp3PQixzUaCJf5UdQksWWBbc6MacD2MsNgrH2yW3hPXTnKYr4Xx2kKJeTTUH4fzoDM9o/McutCrEyx72jPZfjH6XgCQAA///snb8KwjAQxr80bVR0sOokPoKTTr7/Jg4uDj6AIIKbUNCmkbukJIiL6CD0flMf4Mr9yX335anmxOsCWCPg2GOvMEBt5WVT6Agq6kPqmgskKla75rWJsFKvy5LXFLPhyE/a02Mq8sb5MarQpODE43SGKnboL1cYrDfQ0mz+DLIeyWmAOp3BzRdwdMmTVmldKFitjfFLwyXKeayJ880nf5vei95E+BZ7vaDab3E/HmDTK99SU7ynNUenGCVP3k425SHhNE008GtzkISNIPwR4d/UOd0yqLLx5KaMsSRhYaDwBAAA///snUEKwjAQRT8TktKuSkERb+HpXfUO0o2IiKBHkNBaNchPi+jCjW4KmQcDucBkmJnk/8/NJs8Ma4NkOQMPqlCmKLmtpAuHNPcbgr9EM/4ooiWJFfvx75qZzSFlBcltbMC12P/O4CXIp4Qe/XGP67ZBf9ghK1YQNpxq//A/xkThHmU68C6lp6av12ibTRzgwbzLBitfEQ4/3LCB182moihTZBTXE+e8lNXJLpbn0LXdK28BPAEAAP//7J29CgIxEIQniZfKC4i9he//LBZXCtociGB5SvCHRGbJgWIjVnLZr0u7gc2E3Z39qGyK85mbZeN9YoLjWVoJ9YaVqfPymLMikmJEOg8illjtqBHOCtl5gAutxEKW3EuoNCP8ijhwWofH6SginB96v1qr7lYmCccRbrstYrfBvT/AuAzjK3ZX/YaxmYyarMxsVhet4hfCHaN5NPZ6W1+kKMpfUBoP0DSDbcPeLpa9iZcrdbQA4AkAAP//7J3LCsIwEEVvHrUN7owPRPH/f8Od225UFJR+gIooQRrbygRfOzcuxMz5g5BZJNwzMxrv/WihL0DS5L9aGuNpP0p4bHvPF8pEBdU81X59PASdNtbPJoJO24GyXeBavoYmxZb0fhGRiqBt+mILN5tC9QdIRhMI2fqbMzIMQf2y5XqJyzxHuVmh2jtomzxTfuYDtCHAtIE0i9N8CPp7xckmw/wy92RTpNlO2V6uh+NFcz655qHRArgBAAD//+ydMQvCMBSEr8SGOrQO4v//SZ06dBIsKqLg4KK0IfLuNa4OLtK87y8EQu7l3d2KPpWZYl6plb7NwleB3hXxCsRoLi1j+ciknZNUWf0KFFZSPK4m5zyRtE4JTnF1g3C/sTzf+I300B6PZ6Bs2eGIDEOojOUzXS949R2m00DhoL2advBfSZ5NSUxea1qyBtjlhTYqpKxLs3MZxj/CX03eV/7hms3ebXeHWPrnR2wCeAMAAP//QpvZhO7fZAPNbHL9YuTk/M/AzMI4eiDIKBhx4O8fyImW794y/Pv2lWGkXt0OPqVTSBiyd/P1S/B1EqOAwjBlgaSmv++/MPz/d4vhx6WzDD8unWNgV1IFn1A7Oms8CoYF+PuX4dfdGwzfTx1l+PXgLngsj5FjtB1BFIA13tg4GJj4BRiYeHghh1mNNACa1QTflft39OqTUTAKBjMAlVccHJ+ZBUUesIpJvvzLwcHw/ze0s8nAwAAAAAD//+ydTQrCMBCFXxKrLZqp3v8KLj2IC0HwAP7shG7a0nRkEgIuXbhQMh/kBIGZ4WXynrWrGvnELCfZkGvWbOomyDptLHDMahKklINJxgTyihe6J3joi718Udatb2Fpl9R1hjb9L2GWaZiSkPvusEd/OuJdCVSUf0b+uk+3K4bLGdP9AZ4ZZmFUuP6APHKJOZAY1IkIZQoToWKrmQNYQuGlLmrWpqL8Jlkcq6rRbnxnaQvnWzgSvw+CI8ILAAD//+ydsQrCQBBE5zaSIyQRLWwM+v/fYhWwsrCwkohFOAgmJpvInhhLGwsl+77gmoOBYfbNuuI8Pt6P0W0IvhYMYxyl89JYKzZr0l+uTAU/jekZ7ErwpQDLYZyJ4sPOSgT3GeiQqG/zi/jtZkA+jEt77r2b6w3CbPv0HSvKPzIM6CuHep+jzndoT0f0rgKl4djqKx94HQiyEYLFEhRF04xgoiBrGqBrtfBQlF9FMjMZSElJcXwLkgTg+/veD4AHAAAA///snT0LwjAQht+0sVVEBRH//+rm7iZuDg6uDkUEt1I1tWpsTpJ+gJugg6X3bNky5IYjd+8j0+WiPriESc+30eS5UZeTPxrHXrfXB4GlY0w7EKLMYSBQqpAnMagKxWkhdtrBSu7lZOp2h6hsNvlv4nuEaygFjMqgjwfoaAe9jyCtamYw5LROppkIgft2g/N8hut6BXPLgNqwxm/6I6qfgjBwnuNCjN6Ae/8Su6uZP0H68e57ZxjmX4q09AEX60FeEBJkx7iVTDspW9UsgBcAAAD//2L5eeUCqkawKMsvZj6BJywiovcYubj4Rjubo2BEAWZIRff343uGPy+fMfz9/HHkxj8LCwOLiCgDq4w8AzMfP0RstM6nDoCdLgk6kOrrV4afd64z/DhzFBzO7GqaoFHCIe/FUTCywP8/fxj+vn/L8O3YQYYvOzYw/H76goGJm42BkX10RpMkAOpYMjOCty4wjuB7Y0EzI6DT4EFLssFgdKxiFIyCwQNgS9tZmBgYOTlAZdV/RhbW/6CVWeBtmbDOJgMDAwAAAP//7J0/C8IwEMVf7KWCUHQruAj9/p/DxdVBcFBBFwWhCC2tmpNcA+7iIN79IJkvW979ezQqinfgnC7K79l0duK22TmfVxxQakysGUpxTjbghVuN5+UMbjRXNjPJrFM5h4tNDsHE5tdJVZ/H8YB2tYRfVMij2PynNxoqCPUV3WaNbr8dukJ6ABOG02jb8RGpUhBtSD2Jx6ZKyxOBRWTGbfA2y24YP0gSm8MI5jgedkQsvsCycDZ9FgG8AAAA//9iYZWWx/QBM/NPZl7eB3+/fb3FyMpmNNq4HAUjCjBBrvv59/kb+Oj+vx/fQe75GomnhDIxge9/ZAHt2xSTZGDm52T49/0nYsRqdKknxQB0wT2oMf7nzWuGH5fPMrAqKjOwKqkxcGjqgu48Hg3jUTAkAGi54697txm+Ht7D8Ov2TXBDA3wI1mj6JR78h5z8D7oihgk0U8DKPrKn88Azm98Re79Gk9IoGAWDB8D6hqArmji4QKux/kAOlmViYEC6VpOBgYEBAAAA///snb8KwjAQh39JcynSWl9AfAknX9+pi6+gi+Ba/1BrwFTuSosuopvS+5ZMWUIIOe6XL8720bhnkiTYYnaw+XRviM5qoFTGhOmLzQaIpwrxWCHWF9i8GO0+MFkmkiCaL8Qw2TZ1dzFy7oPZytu1lQcPRt4lcXT7uimli4xbg8lypbIg5S8wRPLFSV2uEbY7gO2zpHv3GzhRw+4MFofZNIX1fnQW2oG2i2XHEGQUtNhUlJ9h6DlwAs57PrPuhkjMHi+dTQAPAAAA///snb0KwkAQhCd3yeVEIahdEBvRQqx8/0ew0CJgJUQQRRHFIuTnksgmsbISm0D2e4LjYJdZlp2xxWj89XAhZS684UvcrhdLuREPmkynIOFPVZQDRUzbzTOyUwh3vuxm1lnliqihZgvo1RqxMUjDA5CXdUg78+fnNgpKiipPLtkHKJ4PSK1h+1M4/oSzN5n2QkYuxiA7HhDvNkiCLYp7BOEpWA6Lh5/4RJorB1Z/UN9td7j2Sxo0yWCKN5sM00Lq/k6DJfUqS/dS0M0mQVpZNP0fwBsAAP//YmERFsPwAGjNLbOgCAPLqxcfGNnYfv7/O7oSZhSMQACa4Pz3D7xv8/eDuwzMQmLg5aQjEYAuF2dTUmNg19Zn+P34HsP/u3fBnfHRYoGKADyj/o/h3+fvDL//PGT4efMKw8/rl8CFOAtoUHC0wzkKBiEALZ/9ceksw9eDuxm+nzsJ2eMOKxhGGw6kAehUAWiWmImTm4EJ3NkcubPD4D2boGW00KtPRpPTKBgFgwlAyyvQnk029n9MnNx/mLi4ITObkD2cEMcyMDAAAAAA//9iYeYXxHA5qJfKLCAEupTzOyMb+5/RFuUoGHEAtJSJFUL/ef6U4ee1ywws4tLgK0BGYo0HKhNYpeUY2NS1GZjPnoDcqzR6ZgNVAWS5HBMDAzPofqo/DL/u32X4evQAAxM3LwOTriHkOpRRMAoGC4B2jH4/ecjw5dBuhs8bljP8efoY3FFiYPo7Gk3kAPCBG//Be7WZeHgZGLm4ICseRiT4Dz4cCHQHMfj6E4bRmc1RMAoGFYAPjrGDtpl9YWRl+/L/29d/oDNOwKdIww72YmBgAAAAAP//7J27CsIwGIVP0kYheAEt6AMIDi6+P/gEokhnkfYBxM0mbU0kF0cXcSjk/8ZkC7lw/pzkfBGbwi/qbDbvuft2m4PC3InkYCLYaV0GortlGu/2yVbqnSefTabe0pkXhQ8Zt68mdLoNh0rOf4PxMO/auoIxB+SrNUabLYlNYljEQlxzOUKXZ3T1DebZgUvh3xwSP+AsyR+xKcPNZrpjaWG1CmJT69BExwxBDIfokuVSqmyxvFutHk156tvqCuuzcaNwBPAGAAD//+ydPQvCMBCGT1KsVpxqddYf4OD/x829gw46dHMoVpTUj/hxqVyugjiKQyH3TJnvkvAmB+8bkD35NxzkHgOWmtZW9UOojDhQCp6hWPTjfueML55F7q8rbX3mKQNSxQnfD5jznUA1ERObv0GRBySq8HAE1ClcxxPoTGegBkNug8RICA3Ank9gVilcFnO4ZxuoEF1kR71JpUW/8JZY7ZAnm93IffR5CQ15jQFbavfo5ML4WQpBaCS1eWwr6ukgGWWVxe1tvXw4TfgJALwAAAD//+yduwrCQBBFbx6oIGJQEMH/x1Kw8we0UbAQsdBeRFJIsmMk2ZUZE0EsFRQy5w+W3YW587phMpu+n8H3pXKRn47OGlOEwxGK+AxH5QZKDSyVGlBVmKwhef+WfeMohdfu1Pb6Odse9Hl2dQCXJhJwqtj8Ml5paizBFpBt1rhMxjILx6KTPU8V5ZdYMrgddqDlHLRaSPvsIxGnauAjnmKzIf7GnnSW1Xhm80qwCYvNsotGCx2K8j9UYrPZioOotw260d4VecaLvV7+KoA7AAAA///snT0LwjAURW+bxMWPqiAo6uD/x1Fwc3Hp5OjooOBUKaZIP0wqL0FBcHKxmJxfkCXJe8nhXZ5t1h8XbgZyAjpgXLbmC1VqxSoqLEnx8IWlxwnsZiETgHK+tJRQaQpOzaar6ihj4MMRxGQGlSRQ2dVGHDRgaX9FTTl7dtTv/XxCtloCRWGskzAamJ8PZyMRPD9FFzmq4wG3eIt8Fxt9ts5L0yC97CfPV5hrhWosajY7PYQuN5v00EsabSah6ezjwsZEeTyeRvC0ZAMhLmHU3/Px9BC0uwVN1X8DwAMAAP//7J29DoIwFIUP1B8YDCoJhMTBR3DyvZ0cXZycnEzc8F8TB5WIUIGaixJi4mZMVPo9QTs07b3nnNvSq7ObZtSThB40V9Y0N6quL6L91oYQurxMJIUhKybJeh4GiL0jyHbOLPueay4glCVitoNyqw0+d4HVDEJOpf0M6qPj53PEB45gPAJrmFANA1qn+487lvwA0XqJ83AAr98Dn04g/DBftFSe3iNTNqsa6A90cpIU1TZPhWWqbJ6OEBcBpQY5kVsi+SZyZfPE6qbLLGenVDROkYonANwAAAD//2JhU9fB4XTQ0DrzLyYurvt/Xj2/wsjOzgbubI4eFDQKRiAAX4Hy5TNkOe23r6CTmkfmqbSg/dwiYgws0nLg/Zvgwma0TKARgCynZWRnAt9X+Pfda4ZvJw4wMItLMLDKyI8upx0FdAWgAx/+f/7I8PPaRYZvh/cyfD91jOH/rz8MTJxsoxFBLfAfMtrPyMHBwMwvAFlKO0KXJoMarOA9m99Bp9FCBUcHM0bBKBg8ANrZZGJj/8nML/CBRVDkx18Gpv/Ip9CCAQMDAwAAAP//YmGVksXtcCamH0w8vFcYGBlPMXJySzH8Y5AabViOghEDkCo20D1f/z5+YPjz+iUD6+dPDMw8I/NkUNC1BqzikuA7N0HLOUGNAHhDYBTQKNAhnc6/Hz+A9w9/O3aAAXSKOKepFQOrrCJk9mMUjAIag3+fP4Jn17/u38nw8+oFhn8ffkGuh+KE7bsZXfVEMQC3r/6D79gEDeoxCQiOwOXy/8EDbeC9muCO5m/4jO8oGAWjYPAA8DLaf+ADzX4yC4m+ZxYW+Q9qI2J0NhkYGAAAAAD//2JhFsFzST0T4y9mfsH7/75/u8LEzmn9HzqLMTq2NApGFAAl+L//wKP6f1+/BDe6/ktIj8x8wMwMHnFnkZJjYBYQhjQ2YZ3N0StQaAJAFyaDrp/6/+cP+AqAnzeugmfa//36ycBjx8LApqIxDH09CgYTAFX9oOPsvx7dz/Dt5CGGv+/fMjALMCE6AaMdTaoAUOON8T/4KgEGZkERyKDmSNuzCa1HYKuIwHXK6OrZUTAKBh8AFftMoNVX7P+YePl+gfaYMzIygtsqKICBgQEAAAD//+ydsQrCMBRF74spramo4CAiKP7/6OYPOHTxCwoOQqFTG0HRpEhe1UXcLAh9ZwlkSyA3ueHlRuv54vsABsrp6axuzjYnk1avhERB6BWKa3p48wvBGKHtL8SHn6Ab0XqDaLmCK8rghNiQQ0t4WCe83w83HBjkawuVGKg44cRKrlARoy90QDCW10MGu9viku1xO+aAcyCtZbp/jW+llIYpayyZUf/eKXICvMW9OMHXVdsn0iYI/8PzcjH8RU9xzFVuajzxQavIpJ/LFcADAAD//+ydQQrCMBBFfxsrhhJpewHBlQuPrrtexI0L91IUxWLBijUZmbQrF+6KYufdICGQzPz8P6Nw+uE7oFKtSd2YOpjoJlBcsXbVpqgYwkDw+QwE2GuJptjDlpfBd/IDrRHN5hgvliC7gT0d2jl7Umz2A/u4+HGvyO8zJyM/dlvc4hgqzby3SyXZP65c+DKsaFb5ClW+hqvvvnMNPoty//cGN5DCJGuT/we2z+TYn37G81j4JFrvIhBlUxB+BiLnC8pQR1BJCmWMA1E3voG1mTdlE8ALAAD//+ydvQ7CMAyEL0lRKf+8AOwMiIWHZ2JiYWFhRajiV0VFiIFWpCnIZoCFCQZE/T2Bt9jOnc/TtDl7hzbcxOhKLTHVWkYNJlzydIXKukkoAubx0rn4CBsukMVR4YdNyuH1e30Euw17a7LDnr2byv+B4v4Z+uUgiYrNYdchcmuhymyaQzAYgmwRHEEhCB9Ckm2Wzo5HuEwnuC5PUGXANIxcBf02rJ/VUL6B16rCIwltvVHMgT53cHEEuwr5+jsjO0xB+B0caf0B027eSp1uCqXP6Xzmsv0WnLFJEQWvALgDAAD//+ydTQrCMBCFX5riz0LEn41YETyAIC48vK66UURB3HiD1oAoXZTSmjQyoSK4cKUiNt8Nspm8mTfMc1/mFtGHQgXQ4YwEDR2iyNOsyEbRtte0lIL7gYY8TiBPwjibOktLLeoZGCqDEWrjKdLDHtitHwXGzqE+R+FwMk76VEKGAZLtymTzEfXJDG6v/59vt3wVKQLE/hyxv4CKzuCtQvTbnO23o1UO2hzjjSrcngfe6ZrL36VEa6joAiVCM8ikhts6mxbLD6HJyAScZjtzvaHQ8npMNktpapbRIk9mDIAbAAAA///snb0LwjAQxR+mraAVRBFchIKF/g9O/uVuujqLiCCIX7hYq/1IE7mLLoKbgtD8xozhhuTu3nsO7dt+hITpwqEMFSX8Vil8HzqJjfjTGgJYqsLrs5kp7rSSZk5uN3CDIYfrV7L7zFsPTdTDCN4g4BXOMn1qWTl40z5If8ZrqlQUUPcS+WoBndz4iPJgG6MxRK9fQRdLyzdQ8YVriiaayXRinGezFHCFyX61fB/Su9dqEN0OvDBiDTa5OlYSrSGPe+TrJeT5ZG5A2LqzWP4G0pZr2nJp77xgOBPtzlyeDneVXY3M4n3aAOABAAD//+ydwQoBURSGz8y97owRCRMLNeUdrDywpey8ASsbD6CUWUhhKDRydX7sWFiQuud7hHs73frvf/5fc0n7W3yFjifPGOuFxYsXRCiz5yhqywq7XL3gEFBXeZ9kvcJDiIJ9VxXox/D7JsA56EaL7IFj6s9ISvVcS1D8Jc/lfFUgVbLYn8jTlI7Tyf1TuVyhqNtDPYogfEq+mFM26NN+NKRrtoUtCuMOp5Mc5zeAPqctEr510iEVN521KqPTerfBzzonv8NHIyKHIPwNqDzhyQzDparHY9NOZqpaO7EF/iVEdAMAAP//7J2xCsIwEIb/hoZGtIKKohSh6K4gPruLOPgEDm4ODiKCS1Voa1vklItddROE3vcGGUKSu++/uI5nPi+gvDA6pkaq4eeq0Xw42nNxT6WzKVQP3g70zsrxdEa314fXalc6T8JqvR4E0OEIdItsRdr6/DKo8vfYLwEUUOSglDucO1CWA1xALAqY6Rxup1tmOgXhO5TGeJyOiFcLJOslsu0eisWNGt4FNdZn5dz/CTyBFt7TKrRmMoMehpXVldnOoEtku5qU5FBGS0ZYEP6J8hhQdf+sB8FGh+ODul7o42MTwAsAAP//7J2xCsIwFEVvYmKNqGCti3RQcNOh4OCXCw6Ck5Mf4KCDICoiiEOxra1G0lZwURwchOR8QQhJXvJy333so315vsEJ43dSEiEV5QCcVaUJOAYNISy74KufzWi5gNX3YPU8vZeCkn7ZDnjLRbxeAYd95nXxB0PTgrSGk4NWslRjvNsimM+AKEoVKGIwBHfbus+S4QuS7Qb+ZAR/OkZyOoKqrhvqzGM8S2yYuP97nq7+ygaDEhQaTRQ7XTBl9KWpOkQGF8gwhIyTvP7fRBOD4S947UKihC4lcaW1+pnazl0SInF789gE8AAAAP//7J29CsJAEIQnlxiDaIKF+ADWFtZ2PridtSBB0EJQC9EEib94RnOyayohKYMk973BcSwsO7szllz42W9gdzQHyTF8Q6mD2eluxW7TQ7CvI9F/r6kYlsGF9goDyOUc8XqF5HaFmbcdUHZMi6fwTn/Aypqcz6AkOdXo4igMMtCgoSHfcMYciaKi01chuERoDEech8r3xRrND5QbLNMbzftkjIc/ZWWcMtRQweiNQkmbN6MmIJouZ2vaVKt5XhplJTWeTM4nVtlpWKb7TI3m/yBLDsOxIZqtp3C9i/DaikzOMpVNAB8AAAD//+ydvQrCMBSFT5IqtQWFChZdXXwQRx/T1UcQHFzExWdws4M/Q63appF7Q0fFRRGS7wnyx01ucnNOUGzW73siJUxVaqN1ppL+XsbdPmBSL0brcQ0h7MHL3O5WLe90ZDENetlzFRKhCQZDtMcT/rtJ9iecbAL+NeSX8G99BRkJjstVdkCx2/KhjeYhns7QSkfujIfnY+ji7LKYI18tUedna61DCRCVzvpN/qs02hcyVFC9hBNOqlRwEmPYn09fc9Tlw649v/48nv+h0YsIBGQYQYYdjlfkB2w9gV80FcATAAD//+ydsQrCMBRFb9NoRWknoYqjH+Hmb7v5BU5u4iCIFARLQGgtbfoqL21Hu6lDcv4ghITk3fvuk7VKBxdihnfKUenP45Ncrg4ijGIQYldxclhHZytvSgI9ebbk3YQY8KgJ80Cwsa9ECNMTyNavYM0pigvoRLWmfpOw6F4LP6NXOHUFygtUlzNIPdq98DxMN1tj0+PkYIfdNLpCrRR0cjXW2Wy/Q3G8wY/44+N1SfSuR/PrELVFonBmVE0uXFrrQCACvXKQSkFZNqiSOByOP9CrjGNu3YlY2axFMCHhSzR8b306swDeAAAA///snT0LwjAQht9r+mGxoHYWHZxcHAQHcfKHO4iL4FRER1cRdZBU40ebSlJwUycp2Dz5A4GQI3f35l7bbra+79hid9YIN8jSNXneIA8M5qQNJUbJfc4x0sNey36selhqqwlSg4LaHVS6PVzTJVJ+hHwksLySVumLQptfsXyoCxFkzHFbRfoRl+y2qI7G8PtD4NNffcPfIzmHiBYQ8ykus4m2NGM1gFzS0nj9oDCJ5u+RuScd+UE+3TwIyjuFVi2VbPITMiG09+gLI+U2GApH3VHKVFHbAfm+ajQk5DqZbjooqyb5JnYBeAIAAP//7J27CsIwGIVPQ2+KtuooODgIIuhDuPnOTi7i0kHQUVCcrEgrtMSaRslfV3ErQvK9QYaQ/Jdzju0MR78PwJiwO70YFtuxZitWGSswTSeDrqh3T5akdSqOB8rbdIMQOluwMq8BfzJDOV/gJQrk0QZQq1BGJlg/pAFzoMT68iHwPJ+o0JTJDTJNIDmHN56Sm7JBL2SeUbQJ32+RrZbg0ZpinNTyteWzypTGfOzr41NPsbALuz+oJBmautDSZPOeQlwv1CSjqa/BYPgfaBNDxWF6YO2AUkos16eLarnu98kmgDcAAAD//+ydvQrCQBCE5+JhEn8R9VVsfAhf1koraxtFsEotdoliSFQ2kd1ErMROhdvvGY67m7vZGcvWjY94XmkHQ1CaxiYIco7pLlVsKo4ifZt1kAFf4imJURI5P17CLolwMsU12sNs1lWcv/IbnsEjzUa1LolEdF6Wc9ApQW9WqNh0DS7LPx4kBChdLQEzu0cAACAASURBVJBvdyiyWISmrBWjQvPbSHI3j1u3O7CjMbxuvz5g3IP7NfkxhM4cbpa9yvwURfmfPYt/N63lmc2bCVt34/tigRH7/zuxCeDB3hnzIAgDUfiBFIIh6KL4BxwYNP53N2cnJjcXooNGognECIlAoZi2Mpo4qZF+Y8cO7d3lvXvGW8tN9B50u89lHqnuDkrNJmhYW0k2ysWt6BZPH2IVX1CEW1izhchG6zpcw2/6c1hTH8bIA0sP8kb4NEzlpH2e1sPJG09KUScx6DFGnaViy7hGTBAeIO8OoTlOZ6MW/p2GlsIDR/ch8k2AbLXEPViDRrmUzlpENZnfopJDAF6HiciTkdfdt5Ix1NdEqjCymzxT34ZC8Tvw+Q+39DtuYYwnO80gUXU+VQ2rhQT+pfUCwAMAAP//7J29CsIwFEa/JiqhUCsIgoIv4aCT7+0mTuKiSKGuHVy0akultX9pJWkdBTfF5jzCJdwk5OZ8La3zQWxD3fwIY4QaJiWmgZL7lT1MCITUIUXRIDRKqrzNwEN+dFBcXXVYqxH/Vkmvj/ZoDH7zUSQRSp41+j/rV3k1/1r2QhiXBuVwuQB3T2CTKfTZXGbGakxvapX+GjGBER8sROsVkt0Gib2X1k9iQEZuKL5AbeqW9u48B+2aMp5ICoKaupeIl817AO5dUDzCqg5qeSoUP4OcxCClmMA408HQLtPUia1tJu6RYk95C4AnAAAA///snTsLwjAQx/+mLyjE6uqrjg4ufv/JrYvgJohW1KrgAxRfrS2NXNRRHBWT30e4DHeXS35nkrHwI1RAcg/ZMqJR6dFqNGMgtMXpzB5TC91sahTCeGTA/HhFupgjXcyQ7TawSAPNmNqNJ2Owqj6cdkfeUifhCOImUNCeoO9CH/jxXGWVxEgGE2TRFDe6LDns5Vk5rTaMEklKuMKB+h+kFGo1R9zvyTU4l6CLdDxEvj+j4Jpgrq16iL4H1U2UJ2wGVuQwKzW5r5hekCkrZhJCNppUZ5LtXcZH28w1mt+BJpu5gOGVI6vuBwbng2y7Tl7rst4C4A4AAP//Yvl6cDdRHgEtufr349u/f9+/vWWVln/x78tnyT+fv7Az/P0/ks9FGQUjEcAyFWjv8rdv4AMN/jx/Al4CBVqeOJI7m+B7NyUkGdhU1Bl+3rzCwHD7BsP/XwwMDFz/ISskRk+4HFgAWloLvq7mH3hVyu8Hdxm+/N/B8OvebfBScG57NwYOfZORHELDBoCuNfm8fQPDtxOHwQ34308fMvz/9ZOBgW30dM8BB6C9TcwsDEzcrOB6g1lEnIGJVwDiqpEaN0xM4IOB/r59Db8feHRFzCgYBYMIgDqboOMgODjesggK32KRkH7MyML6BzSriXdFBgMDAwAAAP//Yvn95AFhn/yHLsdiYfnNLCh8lU1V8+jfd6+t/zy4qzB6Ku0oGMng/x/QwSsPGH6cPwU+up5NTgmUEUduiDAygg+e4dAxBC/dY7p0juHv5/cQuf//Rvd3DwYAWqnCxQ49Ufkjw98PFxh+3bgKPpUUJAba6M8iIQW5sBk0eDLa4BsaALQs8+cP8CEr/799ZfiybzvD523rGX5cOgsup0B1NRM7M+TUwFEwoOD/73/gi9FZpSUZOPRNGdiU1BiYuLhHdKSA9hX/ffsGchrtt18MTBwj9O7qUTAKBiuAnZ7NzfOWVUL6Dquswse/oJsYCJ0czcDAAAAAAP//7J1NCsIwEIVfmmpbRRRaFTfStaAbBc/uyq0K/i28hZaqaKm1qczkALqsNN8VEpJ5eTMvNn3b8BNFASFlJv3gmEeXXtpsDQqlQkqlNeWjoZJQa6gEJzwm+w1qw5BnFQUqLDbpIPIaHDxDM0hWuwNxjrTIpFAxy7RBlIJCB7sJWz8mqjRjJ+yxXHBarTuZwRmNuQgWlhEnf4EQ7F4m2zXS0wHJbsXfnOCda7PMNo5mWVApIB3Fd4Y3naNOdVhl10afReoeI7/FUM9EJ5mbvWowlAr2C0jzud7LCvpX6XcBepD+JjYBfAAAAP//7J3LSsNAGIXPZCbm1mBNyUpcCdoqiNB2UXxxl921iz6B4J1AbIJVF6YkE1L+iXRrlwOZ7w1mYBj+yzlHuJfXhx+GsYqfRG9V8r7k4fFduxZn7KkN3YTMNWh1QGYfanrgXIzg3k5hBWG3OzBcgEcxnKsbeOMZUEvIPEfzW4KZ3E19UNEof4UkudX+fKumCWmQy9dn+GmCevOptGRiENMH0/Ub0xLSZtIks3x5bN1m5/fYrhaQ2ReYY4EJS71Jg0Y0ynARzvkQ3mQG+/RsH1fUOSgPuNiifHqAXKdoKtnWnwaDQQ9aZyDAZrB6R6TZrHg/KpgfgAv7/2ITwA4AAP//7J0xC8IwEIVfWms1LioiOjiLIP4DJ938yy7i4urgUKiDo1CsWIJtMKlcKLg6BpLvLyTcJY9371pk/fsbxmpKS9NCPBnvlRSrXzPpb4PHSYxHnTHUZQX1yKCyO1SeI5rOGrHWbWW2M19CbXbQosDnsIcWQNj2s5tW0pwJJWOSlY0+LXSf5TVBvFiBr7dGTPHYBz3S36cjqssZ8pZCUghQ8foJXo7ubbQRk97PAuMoCGi35nhi+gWLu872C6o55KqQaWLWM5m1rz5z0uOxhlqTs5XS7COEgxGC/jAMODcF66+xDABfAAAA///snUtLw0AQx//JbkqD9GVFRFSo9Gv01O/bWy+9+Qk8eFC0IFgjirQ92JYk+5KZNOf2VALZ33V3LrvsMDtPKcqi9GMIAtB+2+pmotXRVGNgd6oQrKtXzlNfSiNOW7jthiOcOlnA3t0jjGOqca718cjrW5yNxtAf70ifHmGWabFQdmL0VIZA7K07/nDmUIsE6jNBPn9BNn/lgevkXJQXl0AUccM4lvH3eHqMgdMKTimony9sH2b4m0647tZQYxXKVm9St1kfzawcxgKRgOjErB/l1Q1E97zW78ilKfK3Z84OMr/fRWq/VyseT3UgvRUGkP2eaQyGWdhur8x66cgW4PmahyKbAP4BAAD//+ydTQuCQBRFr+MXZMtamEEQLQr67y37D21qEwQlQQRBUQoGoc5M8Z7uo00Iztm6cSVv5p53dSz/B6+NtCvfpwIUZQWBFp0uhJfxIx5GbHMdZWgR9YDAIZ1UrCHK6wUqvcPywuqH+i2HTAgnjOCGEdQtAYQEysJofQ2mXufkdF6lCR84s+WCC4Ro7cKbTOHP5qxKG/6PLnJuD6YBPd+uq93M4wEqe/K7mCCzubyVhvAEHzDdwZBL5dr+LaSLk/J8QhHv2BAyDbQGQ7OgZJMGA7vXf7ij8R5axa/NSlKoQmbCV1MNwAcAAP//7J3NCoJAFIXP6FhJWLQxBKFFVGCLatXDt4+ggsAXKAuEhKxNP/hT3NEHyEUgOR/4Cs7hnHvv4YXSF9F7pFBikypNI1banTe7Xhg5rHIsTlJZWPbRfhsJcqr9IBFRyMj5U0g4kKhqjKeiy5GOKaX3pygGlqlYCSFDUVXB9Nw4TBIkYYDH6oznbo3XeAJ9Nkd6C1Hrj8DtXpZy0jsiReLvSBOxyxYHPiJvL3ZrH5slXu5WTFSQ88w0OvgkC21LTX74hls2agMH3Ozmdy+qa9RT3UlE1TzHQzb+zVVAkXpSIikN9N/S3uCm5dWHzkI1Wm7sn6JvEk0BgA8AAAD//+ydTwsBURTFj2cGMUppJjtFVhYk5ePbWVlZyp8ZimyUMoN5M+/qPfMBWKiR+/sMd3H/nXOsj+y2s+ZQVGskak4qqo4q2KUixTEPm8z/IjKz1csZ0l8hOR1A/QEXRIbWJJX7A8TbpTGfURFrN38KRcYdkmRk9IB0uyEO1rCaHiqjCSrDsdF18urge2it330xRzibmqumDDaQe9/oaukhX+H3HICfYwpmqNSZw5Sm0C6OpU4PRbf1v0ua7IVCfwQZF9rwCiUJwuY6Zpg8oVNH9EJT1Bs7u92dWa63SU5Hqc0f3zoaAHgCAAD//+ydwUrEMBCG/6TduGBrZRUWpAo+gBdf3MNexKdQF1foVRYWqdrWFG0XU5lJH6B7K3Q+yKHkVJpMJ5n8+cO/8mv4O7FmM4Grqk7NTKkX5+/qOF6itlqSRmGqqMBfFOSKgpNxshvo6hqIExkTtGdPvps3t2izDRrSlX00vkNixvihKic147+X+y7x+1qge37kf8w8e0H0mfMxG5NeQUcxJ89K93pOqV4fDs0L53iBSZVlev7ZPME+rGDv77DfvrHOje3ISD97JNY046ePdYoN0fn2WTqOztYBU50jNMbblivzzla8CPdIzBCEsaHCAPok2YUX6dpcXufB6dnwHA7APwAAAP//7J3NCoJAFIXPOBoUabaoIOj//V+jTbsWtYnaCJIQBemkaGPcGWsdbSqc7w3mD+4dzj3Hvq2W76+pssqXQkgpksju9Q+F323eo9CHSUAx1JTnrPI9FkAQoAgDyDg216GC1BPOZAGHZJeDIYroArCqkKZffdOQ/A2lMqcpUWZa/UfznDGzUBxDNCZzNGYLdcbOeA7ud+u+XZ9BcUrnk1JI5Pudys5MN2tk27VWBlxT3btwXbAz84Z+HxVIztU8LWu2wOmNjKYqk7i2UORJcoU8nyBFonw/Xpj7bDB8n8r4lTlUx7XBXS+32l5iuR2U5L3xbrMJ4AEAAP//7J0/C8IwEMVfm8Sq4F8UFOsgDg6C4OL3H7soLhVUUBAHQRxUUFsblbt2Ft2U5n2DkHDH3eV+TwaL2fcHsqDtQmktW+2J2KwIZ1vmWGrehlEalRA5qEurwyOi7Qb39RLKbcdYaDvl4CwheIeVdpRywxF/l4r2OzxOZ1gZs+f3N+KkozjxILHcpH2r29hDuJpDNVw4/QF7B5LfrOp0oZpuQq01BdFbPWMAg76coQ8HBHOfC/nr2EPgT9n31KJJZkbBzptJ5r+JwEB0d6JehNPtxc2Yai3VNKenJpulPTeqKI6wTIgwMvodUQNICNhZImhX+OeSJaXkIQHl9U+LTQAvAAAA///snTGLAjEQhZ/ZXVK4hisOtRbFVe/+gtVh6f+1sRIEwcbCQkFYRBDESt1d93YzktH2QLtT83Up0iQp8uYN89xHq8/XvBUnc8vVhSj647SkaiBqU37HZovllSnc3J5NiGgyMpO7IIMvrmRbAFlvgnp96PiE43AAHR3geHT7YNhfxlNi3Anjcu72QBKDkhOycIXzcs4FBlkP4NUakK1vuJ+Vdz+tP9HnBOl8hng25c6I1EyX3W2RrkNe04EAozGd3EbOPBPmnrSGjgiOB86qLXZ/IIPO248NNmIzY7G54TZaxj5ri+XfwLnAJNg0Eb4ioT5+RUnl3FLrq/vFJoALAAAA//9iYdfQJd1jjIx/mQWEHv959fw8Ew+fPVhsdBntKBjhgBF6sMGfVy8Yvp04CL6wG3yX2mhnEwxAyyu5BITBjecfVy4x/Hn2GtIYG72jd8gCUCXEDJ1oAx2BDrrCAIQZLp4BNyZBnU1OM2uG/z++M3Dom4BOsxvpQYYV/Lx+meHrnq0MX/ZuA+cP0MnW4LWyoP2vLCwMzMKD0NGjgDCANcZAd59ycjFw6JkwcNu7MbApKI/4wAPdYgC6Kuz3k4fgveCMjKOdzVEwCgYVgJZf4CW0AoLfGFlYv///+uXffx4+yAARsZ1NBgYGAAAAAP//7J1LawJBEIRrxhkliFmNj0UQQgLJ//8ROcWLOXhQUDzFQGSVXRIfuL2h2iTXkJuy8132uMxhoHu6q8r5we3/z2ZMwZ1d4/2rbUSZ/jBMNgMlh9opXj1JN7pWeJhPka9XcHEosH+wtRo8tX33jzgu31DsM8huD+OCmcxFQ6dNBj8fReVpJ/da4DCbaNMpWYbtaIgqdWqtNnyvDxs14dpd/ZalymRDLulaH6SYYcoooDx5x278og0nV2cl/dBpMcPtaczEV2SEDOvLRKhLdzBXHpVOjOrdg0ZjsXgrPYWcdMmLmd4Jw0lvUFUEAufD9xDRXkdSad6k+Sb53D4/Fbbe0G2cX+OzvwDwBQAA///snc1qwlAQhc/tvfGnSEUIgj9ISoVuROj7P0I3rhRFxBY0gq5KmmBvkiszWjdu7M7Y+V5iZjhzzjHsG/grSh2N7Xlm9VOdiz3PgSiiUgj/FVIh2LtpOc7dbje8TFIfodLSQ/iLafioDN+Qbtf4mU3gvhIoLZ6+QqNIgaMO5suz0S4XSMP1MYWz3YPXe0b5dQCv00Up6MO0u6x43vW7OSX5xhH3CZJyuZ+Oka4+OfjHfsyRbkI4darsfSxByzNE8XFUGZThoVqG8WvwgheYVge0qAmAS2L2a9pwhZzS22U+CsJtcTo2db0RGb+5dN/RLhm95+dd7dpbE8ABAAD//+ydSQ6CQBBFPw0R54UmRByWJl7Bnbf3CK6NIQ7ghDFG7MFUoe51pdjvBIRUQ//+Vb89Ufv8hE3UGze3HUhybvRlkT/ZY6DUYvk7nguQnJ1MQSUxp0eqXQKKiXZ839YEic1uH9XxhN8NiU2dkoMj4QgbfFI0yMkzVw2T3gCcoNMjZLKGXEZwWy14QZdTa+kfQjPOXjjgC+85WKj0+/VAzo1cRRzw82oZPO5ZdOptjIy+D8ke+kwppYAoO/m1MXbjXQAMu/uoOvA6IfzhiGv77w/VSIQrBblZ8/pQuwPPfpP7a7FYvggSm8ZANJpzN+xNRbkyM9tYccfGO33vAO4AAAD//+ydP4sCMRDFX7IJqxyCLiii1whnIQha6Ke3tt1mOwsRrGT11uPwuGXdrMwE7e38M79PEJJJ4JGZ94z/Cr0Xxe1wLs910Ip+7eArLU+ndpkd+BFRIjaFd4bun/ZOnZS5SdEFbHcvYpMJmhHC8RRhEuOvuQB0JrObLwrNG1I76A2lUH4f4I6ZF1TG8rkbEpzdHtdFbTJHNZlxu7UOa0+5MZUruashT2L8JzG7yhbbDYp050ucYn8oZ9A5dpfVdan9V4Rd+q2F/RwgHI4QRDJ8W50LuJ8jcjLB2qeozv77REn9C8JDcU0Z0R+Nten1lybqrIJ2l4Zk7lsngAsAAAD//+ydQUvDMBzFX0JsQwQRGcr0tMPQwzzoUfDoh/a2syepIGM4BKeIECIyNps1aeSf7Au4g8iW3ydIS1qa/3t9T9A/IuvAdgoE+90yKavydHDrjb7yRvdCA8ayQJHZZng6OLWfGnZUoeifxZ7JzArOU1jG4ALq+gbBDeHNFO1sAVZmu/HGEm2FDvAtWpemppTeTOEppO5RHY4j1e/1BfbxAaJ7DHHQAVO7MXKd7Ie0b7hS0SXApAIrSrBSxkPtX0Efy2FpEaxFqGuEehFtgJSy7GdfCPM5nNHxeprJGM30GXYyhjcrBVPEysU4kKIamWyx30RSlU1YpuonCgSS55cQncNtvzHxubFPI9T3d2g+3tKQMesTmcy/g7IXaDDK9/bfi16/Ekcn2htNL7ffrRXADwAAAP//7J1BS8NAEIXfJnFTNDG0loKBSvDgT/HkL/boxUMvRSoIhYqUUkiNjSXEtu52ZSY9VG9FBEn3O+11D8Pu7Ox7zyMDh/3ZikuM0aJx3JeXVyfr52GAx4cE2vqJWQ6bKmTdQBcLrEdDfL6MWJ9i+Q5p94LrG768l3e30PMSQho74awrlNNJTSEb3/w4rITgKZ+iqI/JGB+9e9Z40sSTjFXoG6LbOedsQu+sDTKoc5stOEEE9zTixtMNwz/VfZrVsmoqi3d24iNdts5zbPIMapZCZSnUdAxNazIAKhYwZbn9NqjgNCQcf2ffNvKnvtArCumYfQ2n2cLRRVJN6n8hW6oLVBOrpwGWgz428zcIKWwZWCz/FcrZDKPC68SvXtw1QvpmHxdaBsAXAAAA///sXb9PhDAU/q6UAEFPvahxMK4OLje5GBf/fePiYOKdxkHjJZoY7hAKhbbmPTCX6KSTkX4TAwMpgfa978eTIv7N5twfCIVw8uBw4cZbl/L66ryTRNXre/wfxGOICIjZHMG+F2iqJ+j7OQeAkB/NS8zXkHv7iKenaF+e0TzM0SxeAdH7voUPDPrX+PpuSVJK8rqmAupOvkPbR5s8Qow3WH5I8msuMqm4TFO+FknKyZ7EdHaMZ8zsJzOeccIKHCpaRzJkOSNE8H1OpevkrNTBpbliNJIBuoZVigtMZjB1BatKOKVgywKOWMyygM1XcPkKZpnB5BnPDSRPplnW7NdjV0vUp8p6BnMYcDRX00BshoiOj5CeXSA6mZLvaegrwzDZG/TdLfTshr8fcDjcH3gwDw+PDp/NslhyUzeY7LYUEiTC0GF7B7A/LDYBfAAAAP//7F1NawIxFJxN3AVXDSroVRTbH9BT7z32/x8LehH8QhRLbdZnyrzdyt5KKfSyGcglpyUkm/fe5M20sun8L6sb7HCUyH57Srq9D170sFGVNqLh4CGll7cvcLtcUKxX8Is3tfuwzpV9ahEa+DOBSCdzpNNHtJYLlcC/vZ/L/p34/2gOqOTMYQNQb9Mk4ymiIltS9XmqgA4DVGNhmDh+C+ok1dlrt2HyDqzrq/G06Q/AoipZJSafhsJDtWIGWUd9GsukUkRVY9lvLfsd5HhQD8DgfVkEuQ9qJAgg1zJJrc3zQ2wvqzzIqqJr3MvNAZnsT8CMc+RPz+i+vCKbPTR9Ve6gHZjsNlqUCYUgyf7vCXxERMTPUO2dlPFZrl7xxjkJhSdTcuU9+WtmE8AXAAAA///sXcEKgkAQHVvBRAI16lAf0CWigqhLH98tOvQDCR0jjIJIpXBnY2bNoFt1idx3URC96Dq8fW/m2SL4rmFdBKECmZ+FH2ai4SMeT3rrlsmmeasGFQbnzyqOOMiWCxCtNriDMYjgg7ihf0Rhq6TsOXc2BxnvIFuvAOML1Dyp7cgGlfsmStD6QclKo0Kl1U58GmtAPbo5ihuKa0ACpkPT0j221VKvJyuepHSywmkzKS3JJmrSSJFFdK6upF6mPDmX7LKY6gnTZT17OfJjHj2Y4kmctYppimClUCoCFsec1IcTcEdTEE3zz+cNnSThScxMNpNcrxezEWNg8FvIFdVRZXe6B6fXjyzH3dy2Ecp4zw6ftwEAdwAAAP//7J27CsJAEEVvkklitAiChWASEQtLwZ/3G6wEKx/BTxAsjImSjcwm4qMJaiM6p1nYYqthmTtPwqeDFfijIDKMZkuZvp8bnkvaQVCqjEALwp9i2iYKS0HtdzjOZ6BeCCeIRGw+YflteOMJzts1snjF02LeipwJP4bOblvlsvcH2VYzn6DKinN0FskBeZqWd9Ue3Jtzez1L5VoU1bta5CotPLkc1yJVb4/3DrM4z/9JtdLDdD1QpwEnGoDCvs6si01AVwdwLzOvO1FZonu3JRYjCN8HDwbiZjC7G8TOcDQ1iBanzbLQFUVcwfMqAC4AAAD//+yduwrCMBSG/yS1lVZEwdVBnVxcxEF8dJ/CRZCig4MIboKUxmokJ1WK1qUuoud7h1xO/ks88Wm1vFUngrpRzZZW7U4ioyggH34FTy/D/BRKkoBi14OOV0iXC5zHU9S6PZcfE6zcgWq1G07dnMzo1ducUlyOB5hEQ/jOLsn8MS8X9WKhSMngeR8WM6eI5rOka77Fm4+oC/Pn4/swKXKFssQGy+U+zDM275sYIPTg9weUR7cxJdrrGco96+0GtpSSLPFwbgCGYb4LchFJad0ZcTAczUUYrrP97ur6NCqcewBuAAAA//9ioUp9CRo05uD6wcTH/4mJk0vg35fP/xn+j9bEo2CEA2hnEjTaDbryAXRyJeigINDyPCZ+AfD+sVEAAYwsbOA9rVw2jgz/Pn1i+H72GMOf968YGJj/Qg5WGZ3pHAVYAZaTLKEdQ8b/TChXKjASnBHFYIzOSI0C4gD0NGXQVSfgezUVVBnYNHXBe9JHAQSAZzZfPmP4/fQRZF8+02j+GgWjYFAB2Fk7oHqSmQW0V/M1i6TUfWYh0W/M/AL/yD6Lh4GBAQAAAP//Yvl1/w5FfgWd/Pfv21fQApIHrNKyp/48uc/2580rsdErUEbBKIB2OEGXCv78z/D39QuGX7evMfxWUQffvTna2UQCTEwMrNJyDFxMtuALv/+8ecnw9xXoQJi/8ENXRhsmo4AkgHdGdBSMAioB6Ew6eJUXGyMDi5gE+A5hDi390c4mEgBdG/T7/h3wSbT/Pn2AnNo+WqaPglEweAC0MwlaUcbMw/efWVD4E4uo+EtmETHIWQfkAgYGBgAAAAD//+ydTQrCYAxEk3wppSBYsVorRZddeP8beAsXgivxDP2RCRTdd9PFvFOEZDLPEe1bBCJuwzCJ6sNPzT3tj5WKVuOIYyv1J4TMxSFQJkSM6PUUby+hbiA/UBbk9Vny7hbxMwwmaAZF/Cr+vzmYEELWBlbtPf57M7FdLll7DaemH2ouFP/ANTN+Nj/vKP1ipwch6wK9BTABWOGStuVkxcY0JVezfpG2T0S+AAAA//9iAS9RowSARvRAjUQxyYfMwqL7f92+oc7w/78VaDnJKBgFowAya8fA8h+8T+XHpUsMrDIKDOyaeqA8Mxo6yICJCXxiKLu6DgO3jTPD33evGX5cPMPw+913BibOPwyM7KMNt1EwCkbBIAOgzuav/wwsooIM7LoGDDxufuDyneLzMIYJAO2dBm0h+Xn9EsPvR/cZ/n38wcAI2sbKOVqej4JRMKgA9PAfJm4u0N2aP5j4+X8zsnFATtgG0eQCBgYGAAAAAP//YmHX0KXQr+DZy/8somI//n78+ICZl/8teO/Cb6gUaDPp6H6rUTCCAXgEl+U/5Nj3L0/AM3Z/QcuIRgFWAJrx5TAyh8wC377B8O/LGwZG0G0VHNCZzdHyZBSMglEw0ABWDoHoPwwMzELCDNy2rgw8rt4MTKPLZ+EAtKLn540rDD8unQXflwveRz06qTkKRsHgA6ADz1m+eAAAIABJREFU9UDLaEHXhPHyfWPi5PrJwMwEKegomdlkYGAAiIVVQooqHmYSEPrLyMb+iUVY5BOzgCDD34+vIUtooXsZRsEoGLEAtG+T+T/4dNW/n78y/Lp3i+HHuRMMrNKyoNEj8GzeKEAqS7i4GNhVNBi4LOwgHfMPPxn+/wRdAP4L6f7CUTAKRsEoGEAAvurkPwMjGxsDiwQnA7u2PgOniRUDi6TMaKwggb9vXjN8P3uc4fupIwx/Xr9gYGBhHD2FdhSMgsEIwMdjMP5jFpH4wCojf4aBienB7yeP/oPuqv73/Sv5LmZgYAAAAAD//+zdPQ8BQRAG4HfnFnGEykVcolFINHoNjT9+legoSIjIFUo5FPclbuT2NJQUJOb5DVvs7sy882EP7QtmUL1hWU7botMFUMVC7nyRthD/6/EDrhXIZtzOAcKZZx6a9mgCcrtyNl4pmLmn2ngKDiPEyzlS/wCUM3O5KxLTpMIphPgO08GVMKhZRanXR2UwNCnj4lkWHHHdb5D6O3AcgTRJAUKIn8NmPRhBZbrlrHXH9ThNtslqwXkybRHU+CYAdwAAAP//7N27CsIwFAbgP2lriw7FQREVHBVE3HQoDr63u0NnR6V4QVy8gS2maSKNIriKoML53iDJEELO+Y+dbjcfWTI/H6GSGLxUWnndfqivcTtdr30tNWeffdIS8p8sC8zNoE4HJOEUll+G02iZUBzTfE0X8Aun3gQLxtCZgEovkPs9tBR5INn9d5P2ixDyDc9ZrkBeyVUcBCgOR7ArVTqOBzPyS1whlhFENIfcncBcgLsOBUcS8oNM+yOg7Fpz5nV6E1YoLPJAL0j59nxNA8ANAAD//+zdwQqCQBAG4N/WVsgQAunYxSIJuvbmvYoFRqdwUQ91KVFXjVnBB6iIiPlOe93DwswO+69dxYfPbFmIvgiEFTlBuNeZ0nWS7LoaEs7rf7Mw9i8o5YvOSUvT/usNWl2gM4WuKGC5kz6ylg0ovMz255DrLeQxQnWK0eQp2vvDvIGl9FrGGPsqajRNs9kXZyN3CrnaQC5Ds2a9rizRUPpsqswgwhpaTK4FGfspVJu2FHRGl0QawvPy8SI4C88rxMzv3vlf0wDwBAAA//9i+ffrJ3X8DHUMi6j4bWZh0S2/nj2SYrpwxvDvP4bRI8dGwShggGZoEP79m+Hf1z/gzuavm1cZfoEaKvKKDEw8vKPBhAygG9XZlTUY/lrYMfx5+5rh5/lTDL/u3oGemjZ6tdIoGAWjgM4AvFfzLwOTAD8Di4IAA5elAwOHnvHonZpoAHRt1c871xl+3rrK8O/TR8g+zdHiehSMgsEHwO0pyP2aTHz8DCzCIh9ZxCTeM/MLMDCysVPuXgYGBgAAAAD//+zduwrCMBQG4D9pUsVLRWwVN8HZxcdw8/3jrRQRX0AlbY8kmkHBrYjg+dZMGU7CgXNRejZv5uIh2RylF7pdd9FgeBZxi97PGft7Lg4kPfdubmAPBirLONn8QHa6aC+WKE9HlEUOMsY3sovQs8nvCmPsKwio6seqk/HU95T3V2s/7I29ciW0ttjD5lv/17nCHcHD3Rj7OVRXEJGGTDRUOollL9EhVhuJWQB3AAAA///s3bEKwjAQBuA/jUmhYqkoiEihq4O4OLj5/rMKooOCILgUSqMUbVK5OopTFUTumzImQ264XO5aKk4+enAZda27mEz2+qkXRtbzz89a39I2bp3L2F+gy6sr2DxHsVpCDWPoOOG5m29QQyCKU8F8AZulqIor7sdDvRaULudyWsbYt1H23zpAa8gwgD+d1TM16WWTvbJUibJZ47bbwpkcUII7iTP2i0qKa9Kp0cD448letDsn+uIlTIbKmOY7BvAAAAD//+zdvQrCMBQF4JPb3lCk9QmKiFDQxedw9D0dXX0L69DFQRFd/MGpmmikyayLCoL3e4dAQu65J6YPFw9T8+VqLKiVgrI2VKL96IRzJlwMZY5C/Dmf3WTyOZbrco1LtQj9Y+IlzjvIRmMoZpynE5jtASq6g+StKYT4JqXgrIWrgSjV0L0CyWAIlpqTp26nI8xmBbvbA7EJfdMyhSLEb2liAcYfTct5t9RFfwaFeV2Vfm+Gs2Fr0FsAPAAAAP//7N09CsIwHAXwlw9bu1QXiw6iIIKDiItDF8/sPcShTqJDoV5AS4WktUbS4uKcQeT/O0KmEPLek0w6jlQy3kydiLCvZTS6P3tpWD8K1oyFEkLaLKIUMLpEfStRXk5QyR7ebAExiMAcPwD9C5sl8MNV80PCtmhX1wwmzz/FZICgV3NCiGumHTvnNtMk0BlPEMRbBJsYIhrSaX8xSsE2WOrjAVWW4lUocNubFPg0V0XIL7KxJM+vvOk86S7XO3Bxth0ZbfzRwb0KwBsAAP//7N2/CsIwEAbwL9emwf4RbNFFQQWdndxcfHBBQeji4gNIJxctVgRbQRulteAiTh0c7vcIgYQcyX1nCln/s0BRbJLjZUbLT8jxesV/fa0hBOd5MPZBBFIa+eWMa7gCtdqwZ3NYwzEv0g9m0EFjMsU92uG23eCxjwFZpEJWjex8oWGM1aSYp/luAyII14YcjMrzR3H67Fd5fEC6XiANl9DJqRx3Igyei8zY36n2ZFmaKfU0/OAou/1IWCojt1lf1g6AFwAAAP//7J29CsIwFIVP2lJqHASVFroIgoObm+C7O4lgQZ9AFMRRBCXUamxTuTWIg2MGh/u9QTLdm5yfwCjl9Pxe+e5WErJ9DAfDTO+3nfJ8SlFxKi3DfKit8VrWMEWOYpNBRBJ+nDT+RJIvsOToNxSkFE2mqOhXs3zippYwWttENQ4MYhjGIXYgI099OBpDzmz6bLfPt/wNyfGMgT7skC/mKNYrmMcdokWqE/Y6MMzfQTMT9b9HHvW+V34vvgZJeqFHtGbZdAWAFwAAAP//7J0xC8IwEIUfoWkJUidF0MnBX+Di4uSv9m84KHQSLa3iIIIVq7lGLgEH3aSDw31LtoxH8nj3XvQs9q1e6LvviPjM9Hiy1Nm6V29WffdADCOJtILwhu20bP20FnStQ+9mmftdFy4KZ4eA8A1HcevhCGY6A53KYKndbdHc7iHxMInDnBElXRCEX+HPE6uCHJ5B8CJgyoFA8wWigdhnP+GPpqsq2GMBe8hB54t3nHhRVd59gvBf8HxzDZSKoEzCq49OpV1SpuNXubgFoDUAvAAAAP//Yvn7+gVVDfwPvfuOWVD4KaukzEEWcUkdRjZ2J4bRdt8oGAWoAFwBM0FGl/78h5zed/Mq+IJwdk1dBpbRkXPsgJERPLvJrqHN8O/Te4Z/nz8yfD91lOHnresM/39DN7ODwnS0gTMKRsEoIBeAypD//xmYuLjAd2hyGlsycDt6gA8HGgWY4P/3bwy/nzxk+Hn3FvhO5P8//4EH/xhGB01HwSgYnOAvaAKQmYGZn/8fi4T0W2Z+gW/g0/1BbSdq5lsGBgYAAAAA//9iAR3jTU0Au/sOfBHov7/vGFnZvjCwMLMxMMMa16MbN0fBKIADUJ6A9Tm/fGH4eeMKA6uCKuTettHOJl7AxMnFwK6pB54ZBnUy/7x/C94vBObDVlmMglEwCkYBKQDaTPn34y/Dv+8MDMzKvAwcJlYMnGbWDMwiYqNBiQOAzuYA3an5+/E9hn9fvzD8Z4SevD466DcKRsGgBODuGhPjP2Ze/p8sIqKvmHj4PsPaTVQ9z4eBgQEAAAD//+zduwrCQBAF0Jt1YxaMpRpECIiFlYIgWFnY+eciImIhKhYi2ifxkYdJVjYWdoqQdHN+YGC7YWbvcBmGhTxC6rmQcSTB2JXXLDf1HIFUMqjJA93bJORDJTgbCWQYIDrsECxnEJ0u9JZNfzd/4HULbDRG8rghcR0E6wXi8+kd6EG9JiHkX9lEU63jl8DNMkRvgMpkCtEfUlL4F9lmzmaFaL+F9O/QysgtyZIQUoBYNZv8yRvNo26358ysXtRJPs0wIH0/v4IAXgAAAP//7N25CsJAFAXQaxKjEQsLFwiKIAHttBA/wc7v9TNsRHAJWkQExQWUhIyTjMzTWhsFi3f+YJrHbJdrieXsJ2vQlSoqTaDu4mI3W4GKo5LcBrk0ig3KqfHrJmNPlN00qc8oOZwg/AXi+RS214ZZc2HkeYPzjg6zO70BVBgiOR8hlmsooWeoREZvdrhInDH2yetSL40kzY9svQKn20dxOILT68MqV/m3xBvp7UoxELHaQMmQ6r0yPHsZ+086synoKHa33MbE9jpjI1/w5X731X5NAuABAAD//2IBHUZCS8DMK/CMWcfoKMO/f7x/37xW+P/hCwcj2+hBQaNgFKAA0IXXoMGZH38Z/j5/wvD93EkGFgkZBg5jCwY2OYXR/EIAgA7v4LZxYfj18B7Dr3s3Gf6+egm5d/Pvv0Ht7lEwCkbBIAGwA8VAg38cTAzsmjoMPJ4BDDwObgwsopIMDKyjew+xgn//GP79+cvw884tMP7z4g0DEz/j6KqcUTAKBjsAdcXY2H+zSEhdYpGWO8TAwvodtEKBmleegAEDAwMAAAD//2JhU1KjTWhAC24mQeF7jMwsG/+8fSXAyMoq8f83AwfEI7SxdhSMgiEJwBmbkYGRhQG83+XHxbMMzPxCDMzCouBLxBlHK22CAHRCJI+zFwPDvz8MX4/sZ/h5/SLDvx+/GJhAp9P+/ze6pGsUjIJRgAVANmn+//WbgeHff/BecBYJaQYOQzMGDn0TBhZJmdGrO/CAP69fMHy/dJ7h27F9kD3z8KM5RuusUTAKBiUAt4dAhwCB79fkYuLk+sHEyfUdvAoMtM2R2p1NBgYGAAAAAP//7N09C8IwEAbgN2nS0qrooChCB3ddhE79A/5cV1cXnZwcBMGvRUeHYjXaRhKdHHSxoHDPmC2BC1wulwiv1y90KXilukd2O1wW8y4LyoNHkskKmQwhf8vEA+fgvrDPUV+3G6Szib1Ka07YRaNJ8fKJcGwl2KnVwDzf9g2p3RpQCjrLwQQlm4SQV8+Kpt2DGWQYwo9iBFEMGXYo0XxHa6jVEsloiHQ6Rn5KwEuwbSGEkN9kvili0oVTd7VotY8Q8mxe9Tdj5uvKrwNwBwAA///snb0OgkAQhOfgACOJGIg1iUYLbHwCrfSBLX0IY+NfQmWMCTUxgHieWdDCho7EYr83uC2m2NuZkTIYtDoMo+cB6qmlH6TU4yI6svZQ0YNYkBjmF0PUZ0kZbYwTFPERRXyqgilMr8/DakRUuywrHMGdL/HKM2CzRr7bQxeA6bPmMAzz5fOjSd4kpaEVYHRt2JMI7mIFZzpjzW1CKah7WiXQPs4HlNcbBPVqSu7VZJi/pfJq0gWHLK1wmDjjaCuEuFA4Jdm5dNlCaCyANwAAAP//YmGk8tUn6IARtM8BNGPDywfaYP+DmZ8H7BnQVQWjl/2OglGADiBXoTCyM4AbQaBRY9D+TWZ+wdGGD5GAkYmZgUPbAKz435tXDL8f3GX4++7HaEdzFIyCUYAEEJd/gw6zYRLgAc9kchpbMHCZWjGwSMmOBhYeAL7q5PEDcB31981rhv8/fkNmNEHnD4y260bBKBicALSC489/0ATGD3Y17WscesbbGZmY7v959YJ2zmVgYAAAAAD//+zdzwsBQRQH8O+OZQYrJ0lKpBQuysFBLuTmn/YPOJBErpywWmWtHzOaWVeclNr3uc5tDq/e6/2w9YrbX7L0YdCYrZNNP5bLH1k2q6S7h5KKohEhb+jqsDmFslqaJJOXq+C1etjmQD5jDJYQ4LUGnOHIFLb8yQS3zRrqfIElEnTvl5Cok2G7mJ6HZ04Got1BqjtAuteHXShG/Xe+kicPwWKGYDXHw3MBCRqPIuSfvXbpmJFNkbzGS5Upb7bGuN+298POvP9kPwiAJwAAAP//Yvn/6xdNQ+Y/8w/I+mAOzncsktK3WETFZX9//sT//y8DK+NowTQKRgEmAJ2GyAY5nfbPq1fga1BAlTqHlj4DC+iwoNEOJ1EAfCWKhS14VQVoOf+XPd8gd3CCypw/o0tqR8EoGMng/9+/4Jk4ZgFBBlZFVfDSWV6vYAZWKZnRgSgiwO9Xzxl+Xr3A8Ov+XfAqHEYOhtFrpkbBKBjMANrnAh1EycTL+4tZROwem5ziTQYWlv8snz7SzuEMDAwAAAAA///s3TsLwjAQB/B/E9OKig+qm+AgiII4Obm5iJMf10kQHJwdXLUWFx+r79qcJI4uXQTB+32BQAiBe3CXio/7rx6glQKZaNl1116jNY7CVf4ZBj16oECehgP+nBj7YAIi0qAnIT7scJlPbfY92x/Ca7b5vpIQArLoI93p2sEVdLviPJvgEWxAV0AU6T2enzH2P7S2O8D1GRBuDNWpIzcY2dVJqlrjh5CA6bqJwhVuywWiYAs4d9uKzMUDxn6YKWlKBZFJQ5bKJP3KSfoVbRLvXy1iAHgBAAD//+zdvQrCMBQF4JOb/vkXUSgICnXooCAoiO//Fg4uUqSDk4qolTRWEnfpUhC83zNkCNx7z/FsgWezPkf41Opk/mT68MdJIsJgCYM+v0nGvhAEapPbDLBVKDZRVQ5jhOkM4HLx2uyEM1qs3TTTXE4ojznKu4bgKhTG/pLNixC+gRwoRKuNW7cP0jmvgdZQFQV0nuG520If9jDnK6QilwbOGPtRNhjIvEChBKkevHh0k11VuTtrN+1s8E8J4A0AAP//7N09C8IwEAbgNzH9wmKdVVx06C7Sf+DmT3YQB0dBBxFUBEG3IiKtlrSV1LaTg0tByj1zpgzhjrvLCcSy2otJ03x/oIi50bw2Ws6FGZZQZdzPo64a/SnoI+Qb1uCAlJA3CXbY4bVdIzqOIbr9LIkiP+A8m8EymYf4cc/OP1cbxP4ZSRCC6RrKlUyEkHpK8t1yqn3WtmG6Q1gjD/ZkCn3gVh5s1UV02iNYzBAu55Bqr2bx0RJj5UwYIeQPqXRLCKkqmlqnt+dO2y9a3yutbAJ4AwAA//9iodsdUn//MPz//o+RgZHxF5OA4G8mfnbIdZt/f0M2pI6OJo6CUYAJQLNvsNNp//9l+PXoLsP386cZONnYGNi4VUYDjFjw/z8Ds4gYA5eVIwMzHz8DM+8Whq9H9zH8e/wAUvaADgthGh2ZHwWjYLgC0NJZ0LJ5Rg5OBhYpOQYeZ08GXq9ABnY1bcjJ+KOAIPj/6yd4wPPLvu0MPy6fB3fcmXgYIXs1Rzuao2AUDF4AntkEH9r6i1lU/AGLpOx5Zi6el6CVc6D8CyofaQYYGBgAAAAA///snbEKwjAURW8am0qwCA66KgiK2Mk/EBfBL3Z1FFy6ODhWwUmk2qitiaRxli6CyDsfEfK4575XK47f1mgdT3sChTED5h1Ef7gx6srzfdLS54dggtQVgvgE4wxGKdzjGF5dgrc7EF0aNivz1kR8mwhL6VIO30e2sh3OHfTF3gQ2lG4QxL9RdjQ1dGrgyRzBYAw5naMxW6AeTejvURGtMhRWn926DbTFMQVvctfVJCuEIH4a+waaW2l6KdHrr4NRtPTCMNHnkxs28y8uiwXwAgAA///s3TsKwkAQBuB/JbuuSsADCApioWCRFNHKC9h5YC9gp2ArPkiViI9C8xwxGkvRIiAy3xEWdviZHXaMonervOQFXSpXd/tTCoNavPdteCdFkrhUMfZG9jstEaLNDsIQ0JaDdDhCqVLlY/sGEUpmHdoaAEojPR8RuVuQH3BnnrF/lN9rQtZo0rYDczxBudN77gDgiYZPJL6H63KBaL3KgqmQea7jV2HGfh+B4nuWVBfZaM5Vqz0ThhEmB//RLCoy/wC4AQAA//9iYRGToE8QQT3CJCD8nJmLe9+/b98kf14+r/7n30sB5MuVR8EoGAVYAGiZEmh0/ttvht9PHzF8P3GIgVVKloFD3wQ8Wzc6Ok8kgM5wskhIM3CyszP8+/gB3HD6fvYSw7+Pz8AXlTOyju7hHAWjYMiDf38hLYt//8B3FXOoyTFwGBmDT57l0NYfPYmaRPDn2SOG76eOMPy4dpHh/9cvDKPnq42CUTAUwH9I/4uJmYGRm5GBWUiEkVlE7DUzP/+3/z9/MjD8/g3xAy3bkAwMDAAAAAD//2Jh19Sja2AxcfN9ZmJhvvPz9vVbTNw8PxiYIZcqw3vVo43mUTAKsAPQ5ePcDOBC48eV85BOEWgvorDo6AwnGYCJl5+B09SKgZGLi4GZfxv4eplfD+5CBvlAdwOD98uOlkejYBQMRQC6RxN0JgUjOzsDq7QsA4+rLwOPux8Dm7IazS4uH64AtJ/r95OHDD+uXWL4/fghuAHLyMbEMNrjHAWjYJAD8F7NvwxM7JwMTOLcDKySsr8Y2diYQNuywP0uemwdYmBgAAAAAP//7N0xCsJAEAXQn9msGhOjEIKVIIKCiIWNtZ2eWbDwDBaiEEkrwUKLGI1JZNcDSApFYd4RphiGGfavafrtrxaK7EZmCBELzz8Kz0/JUUFBhU7c5IAOxt6QpDf2aRjqi5wKupC9ASq9PqhmcfVKMEwJ2emC3BaoIkFuE/F6iVuwR35JQfUMhjR5oGLsjxQqYV8NWDdAeBaqwzGc2Rz2bKG/OWHlZKcIyXajl3FpsEN+voIcCQjui4z9PNULkwJG04qro9GhNpmuhOMGj1P0OnreP/tWUwPwBAAA///snbEKwjAURW/TYAtFWh0VP8BBFAcXN2dXv9HRTfwCJz/AoWtBXBxsqSQ1kbwiuLgUFIV3IHsgvCX33XulfUqoX8KlmZGcK6Xwk64WSQe2uMIoTflBrCQwzHs8r+5EclYjk+dUrO3SAUUco9XnQvImiChCOJlRhym0gj5lqLIbEADwbX3Il8Tr/gzzs9CGlAHuhm7optXNdDRfoL1cQfYG/HYNUOkR+W6D8rCHLYvaqwnwJxzD/AHWWFgFl8J9CYbjbTiarkUQptXZ1Ra9eNo/CYAHAAAA///snTkLwkAUhGdjDjzQJAREUbFJEQtbGxtLf7ZVOgmk8kDs7CImGo+YRHbFVkgTFN73E94282aZeXKy35Y6LaZqgMR4NipQOj1f7Q/bj91GR3hRIZGYI4ivfCrmcyCLz6KwgTWakFo6ZNOCVK3T/ArCfzi5KK2YFrIwBM8xxIaL9HRAegyEeM2Rvc8jkBlGEL+FONedQxjnTNyRg9zuQOkOUJtMUZ/NodoOPVpB8meCLIpw85eI3QXu65VoRYdMSyZB/AVcK4qeCoaKYV412/G00djjmes04MVAJZlGAF4AAAD//+ydPQrCQBCFX7KGIBsSLUQkhY0gForeQCwET2xpK4ggYqOFjQTB2oCJWUd2E1tBi5BiviMs7DBvft7UkuOh3Ccr7gaSUjfRaq+dsNt5RpcxKZiLopzKMcwXPkZbrjDCM7tGeOw2cHt91Acj2CGLzb8hwB1OjJmIHk++r5ZQ+63pdiJTgGMVgZmLYgxTHfKOJiV6jxCwA9/czvRmC8jp3AhP5ndecYz0fDJ77DoxpZRgSZHX27joxjDVRo/Pau8JoY2BbC02SfhBJhpNQHqwisZEKV8ZwBsAAP//YmHk5qFveEEbyyx8gi+ZePkO/f/2VeLHxdMq/38wCDKygTb0j+7bHAWjgCAAjy4zMvz7/J3h1/1bDN+O7mdg5uVn4LJzYWCTU6Lbpu9hBRhBo3/CYMzIwcHAyM0NPnjp1+3rDL+fPmb4D95X/peBkQnS0R8Fo2AUDDAA3R33+w94xo2Jh4OBVU6BgV1Lj4Hb1oWB28aJgVVBeTSGyASgU8+/Ht4LHsz8++EdePYYDGCra0bBKBgFgxeA8iioswlqy/Bzgk7g/8osKPyNiYsHst2AnqdxMzAwAAAAAP//7J0xC8IwEIVf2mhabS0iiAqCv8GhiAhuDo7+cRcHXQoFQXDVDrFtIklwdVEqyH0/4UIel5d7HA/ni5/Uyot7BRNBVubZEZxLM1MM9cpdkJARxHucHeUJd2fkYQ88JJgIwIcTeFHDJtKfwaczxNudHfu/K4XqeoGWFXSpwYRyppiVKdIqgvgJNrteQxWAF2m0RmOE6RLd9QaddAU/6dO5fEB1zu2qE5mdbE/GBGtkHx9BEN/B5DXNx4OfDExM6MbaorYGnVLuwdkUAJ4AAAD//+zdPQrCQBAF4KfZzQ/E1kICClEiFhYiFjZ23trW1spOiKgI0aCoKDHJJjLxApJCEeaDvcB2uzPzRkjnN6EiFcNMAdxEw9lIp3mKV3tARu/hfm7TYOwzVMHMMiS7EOoyh3BakK4Hs9dH1a7xJZZEv390qA0PKqXheiS7NZKtD4oMz6MnILSiRYUx9mW0QzNRqAgNol6D3mnDHIxgT6awhuNiHRQrR10vUOEBD9qpuVwgDc7QbP2dhM4Y+w/0qIypIGHdddfzDbc7g5B7dQyQU4sthbV+C4AXAAAA//+i+2m0cMDCCm6oMXFx/2dTUn3/+8Gj/3/ePWP89/kLeIkg+NTNUTAKRgF+ABqUAW8AB11g/h/cIfpx7gQDM58AA7uG9mjgUQhYxCQYeFx9QEtQGL6dPsrw7eBOhp93bzL8/fCXgYkb1NiFLkUZHe0fBaOAPgDUUPrzl+HfZwYGFmEmBnZVNQYuZw8GLjNrBnYtffAVRqOAfPDr4V2Gb0f3gZfP/v/2FX5+COPo6bOjYBQMGfAfNHMJOoWWnf0dm5LaTjZF5Y0M//89+PXkAcQLoNlNegEGBgYAAAAA///sndsKQUEUhn8z22Fnk+0sKZciF8oNufTEbqTk3qEociNP4FS2wyaGZrYHECK1vkdYU9OsWf//L03srZ/UziW7atlsGoGFXq62r9tN4NA95i8rK8SYoJ2bBPEUDwWA5sibzvMZdp0mmBEEN01osST5C99AejZZJgseT4FHomAeL3higNNkDGGtVXKtrK+acKqjIEUGQXwclcB9cx5QV6FsAu50GL5iCXq5Ar1Why9XUDYTAtwuAAAgAElEQVQC4jXk4nexWsIe9rBrNXCaTiBs20mgVdDdRhD/wePzW8ZL+I2jO5Xu83hiJNOlVcK+5JvqUQB39s5uhYAoisJrDmdPfhKRCyUlpngOruRhvYE711MupabGhZL8pcFwdPZ4AT+R2t8jnIvT3muvvVf6utv85OlYJbMTGU0hed2RuwjUaepXcEERJFMCQXgGRyf5m/FqDXP1ETXbcL0O7y1ZC6jwHoqIL1wqTaBmC4dCCcfJGOfZEsrucGbNo+GUgkwQPgufr2fbrInB1jBdLyPXGyDfH4LqDaSqtSRWTXgZc4pwDgPO1bwEc9y2ezjkAFqEf0H4J1iUsyK4e7P/YgbGxNYNkvRcj6Dcb9YqAO4AAAD//+ydsYrCUBBFb3wxCS5RVxAE0UVQ9A8stHFbO/1hsdFCQVsLIbCF2iyiRBNe8pYZf2BBUYQ5nzAwMDBzz9ivGo0o2E+ofOFkV2sn/RPM7HJlZHkbgDabaSobGUH4LyysMTBhBH2JcFnMSHXNFwJOqyOyjHthU20J6rOL7FeDchC3E1o1gQnPPKhRtpOGYljyj1MQHgIbFTX3VMZzkckXOYue6w/gD8f46H1LnR+B1oiDLcL5FNf1EslhBxMlsFyH/6KLB00Q3gTKauoUyvdjVS8fnWZ7hayzT46/3OcmJhvrkwHwBwAA///snU0KwjAQhV+itqESanXjBVwU/KPoyb2C4EJcKQiCCnUhrlyJgWgr09S9gijCfBcIzCKTl3kzU5Vh84cBzCHrGlIFlECkjFoVqQPgboqFwiIX/GhjmFcoewaFcnZam+5xITstDbppRKXYzNkK9QFkGEENRgBZanUIs1rArJfIaGgQac0a/SZ67iDu5WSY93nmfWuRmRxCZTTBHn7chxqOC7Hpd2IO7KcQAna7wXU+hU13Lv7lFcZCk2H+Byrk0c5h2dZn1UtmfjeZCM873E5HV8T7cq9mAYAHAAAA///snU8LAVEUxc+b9x5mSojQ5E/ExpISZeFbW9vazEpZWFgoLGiw8Cdv6F2fQIno/r7DrXvPPZ2j5LcTK+MufTCdZPqqK/WlLvkts1nHTRhKqIh7NxnmBUTsaZEw2wPOYQAnmaLeSMfzoAo+xIe7lf4RoTR0rQGZL0JlslClMqxod13McVstSTkkscwe9tLhA59hXsE6NIyhXkfrHlC5BHS1Dl1rwusP4XYHlLbNQvQbuEeIjgdcZlMKBToFE/pqCq0gYrx7MczPQeKQgMzld267N050+qPouN/aOf9argSABwAAAP//7J0xC8IwEIVfY1qluqm0VSqCQlHQwT/g5v91ExQHRSdxcfAPuIpaaxFKG7ng7CAFEe4bQ6YMR+7eS5789dBK6KwXQcGjoel6R+l4QXa9+CpFBQXF1zSG+QZy1RrQCme8XkA6HkzP56PMEWGXYQV9iGoNZqOFx2aJeDXXYehZRAon7XmHoHMlY5jPUPNIFrA0hYoznZ8pXQGrE8AeT1AcjFDqDSHrDjeauWHgedjjPpsi3m2RhTfd5NO6wc+YGOav0PmZJN5ZitxsiXSaJ6vdPasoTFL9GeyP6iaAFwAAAP//7J29CsJAEIQnd2eS4mIhkaCChWCh5C0sfVpLS1HQ1sZOENRAxEYQozH+sGesrERBhP3gHuCaZdndmVH4VfRJDuW94KKocds6zfYoXcyDLFppZLE2m02GYd7mOZWm04nDZAgZVEGZuoV6A4IMg/hi4HNIx1nyzSvU6rC0NluZ02xq4gNuyfERnGxOafOxHjfJDPOK0WZeHwYWtg3hSkjfhRO2jC5Td7qwW6GR3DDfgWLvsniNw3iAfb+Hc7SERWVKsPssw/wdeQ0lozRRdKEq1Z0sBxvll9Ob50Ekye9+BOAOAAD//+ydXwsBQRTFzyz2Hx4kb55ki8SLF/LmO/sCSikPEmlrC+VRG0rtGuxoLuVZqU3d3zeYprnN3HPumSwFW6SIkgYVN2HZZ7PeWJjboBpNx32dOKdnBrjcMcz3UFeaPu6VeBxDxMs5LpUR3MEQdrMN4fCl7ZcY+QLsTlena5MSE80muPor3PY7KJmQykl7om3MQvAsJ8Pg03wh63n8dgMUX2fI9Fpwe6+/M3M1jx+aPyY5nyD9NeQmwD08QMUJhJOBACuaDPNvkKqpFCXnG6WyboJHhmXdaRk6tDBNpwKAJwAAAP//7J3BCgFRGIXPNXNvxEKpSZjQNE1WSrHz4HZewEJRZi3sNMQ00zBX916SnYWS/N9DnL+/czrH/lYz0QtSgpUriVVzNqLrz3mrvStUVwFYxpDn5hpRpIMg3oc9y7VkmunHRyaJNtiUsyn8nmlTJaftY/B6E7ZTh+j6OrZsN1y9WXfZrpEfI9MCp92bu/gTxD/zcDOVKHGVbhLgTgPcbaM0GqM4GKHUH+p9W+Kz5PEJabjAeTpBGi7NbVCSRPvmBPGbKC3NpCqFjIUXbEXHm8GyDtdor1MMMvvirwfgBgAA///snb0KwkAQhCfm8lcLRhGDBgwINhaCIPjYgp2dnUUaQWxSBQRFECWa3EVu4wsIQhD3e4Q9WJa9mVlR/9BTVtIZveiXUstpMysYnO0gkMUpFep6r34+eTZjmM+h24+KvDjPwx5ZvIXV68NstiD8Nhf0yxgNE1anC0znFGrihBF5ZrVUTV7eslr9JG6D73Iy/wt5MwvyZZY5IHwXjvZmzhZwxhNKndX9ic43Md/n+cBjF+O2WSNPElqAGYKHLIb5TQxAllBaHeJ5R2c4WtlhtIRSqV52U7+tKYWWAPACAAD//+yduwrCQBBF7ybmIQQ1ICIWCqZTwYCFhZWlP22VQhtBC8FGbCVKVJQ8MIlsFtMLgopzYD9gYYqZncvZQtb8fAFpFCK5nrko6Kb17MX9sG/7i5kVe7syU5gwnhAE8RLZQCPLSIMI9+MJwXoJyTQhGSXo/QEK1RqlBt4M03SorbY4TSvbJPOXxWi7QXzykAR+LkPJ47Q0dBL/wLPeJRmSooBpwqCtd2wUhyMY4wm0rp39pUm8H77d4L0Wt876cwfheoU0FNFlLmQkCOIX4ZE1br9nkCumq7asqVJvOPHljNjdi/t8ssUA8AAAAP//7J1LCsJQDEXv65fWQUtFV+CnII4cdeJCXKUzcRMiKBYUxJlgESwo1GJbefGDY6EUJWcHgUd4Se5NtLxiz+YL8jOlCYRpRabfn2bHSE+3mxHynfPYjsYwzNdIdYBa4HbYk59QdT0ojisTExnKmXLQGk1YwZBunV7DBZLVHOk6pGUc+SUl6ZpUbdDxdPZyMv/K821LSb+cZMoiU/HqNPk32j6sQQCz04PR6nKhWSJZfKJbmufJGMlyhiL77ONzw4thfg76M+QQqgJhaxB2zRK6HlMY7+WEMv9WGBiAOwAAAP//7J29CsIwFIWPaVIahyoixU5VLIjo4OjoG+skvoIg4qKbD+G/VZpI0qJ7QSxyP8gL5JJLuD/ncP1MSnG17wK/Jw+8Ga3duC94EE4q0ul9FB2pA0AQRbC+aQLQdldnZwVtjPcmk9Iq1Dp+jd7WN2CZdYM53mAEseri1lpaxVojHmS8r2yn0+Q3rSkGxH+Sj3Ax6QKNKkQQQkSdfDdzDG84guPXKfjfIk2hng/ctxuc5lOcFzOo0xnME/j5L5QgiOIobUdkmV9L3SBMRDveg7tHdb1kebcM3uoAXgAAAP//7J0/D8FgEMafaouGxGiRWDqYpAklPoDRhzWYTGLqwiTxZ5BI7KQN2r6vyh0Rq0GQ3O8j3HR3zz33WBRQ/hNQr4UMBp3W2AXybp5IdaEmmIumUmTk7TTknFYQ3uZ1iNFAut0gGo/4zLbcH8CsNKWmH8aq1eEY4Aia1PNxngW4zAMe/q/HmFUGzuW0c+z9xOOjsCD8JeQTUoqVTMqdJRW/4FZRbPfgeP7d0+w2+JGWDJofxjSRLNe4BFMkqwX0ISIxBEZeFviC8M9kSuMaZ7Brlb3T6k4crzPMlco7HYaAVs9F31cBcAMAAP//7J1NCwFBGMf/sztYKyWFrELyCdgUyt3NF3XwCRzkwGdQHGxeo9A6zI7VjAN3KVvPr+YrTDP/l+f5j2m0H4TwIVXcRgjwgrONlWtCrFemPB0N6pYRxHcocYlxQJ7PCA5z7Xia2dxrX2Qmq/uGxG9QQlq8WtcnbLbBSxXtMCvlUSwXkJcbmMXfXU76aBJRxjDALCUcm2CJAEbKguV2kO4PYLd74HlH79Qkfoi+Rx4I9jvcZxP40zHExoOeg0FJCoKIPvqdwGAWip7tdofJRmskrxeEKjGlXM1/MDYBPAEAAP//7J3LCwFRFMY/417DivJaeEwzCwqxsbDylytlZ2MrFooMQ15RHs0wundM2atp1Pn9BafO5jvPjzmbVQjC+EJ60XG4t+uBa0Zf3W1zr/Op4Vi7fIS96E8QQfyCLy5EPfMA7PkM10EP0WQKiU4XLEsfaoNAiOx4rQklxqXVg7jnfEwneG6WsM0Fnhdb5khMOkWRSqKQCDX+TaZ4se+43l1mDGCZtJxgcq0CVTcQb7WhVuvghTLZ/wSAKwrNtYn7aOh5/07HcnVf5oua9wTxv3wa0hEWhcI4WCZv86Jm8ZIO5bj3NkLDohsAvAEAAP//7N0/D8FAGAbwp71qtam/VdLEQsJiMYhEGPjSNrFZkAgGH0BCDDVoUn/KSa82K1LJ+/sEl9wtlzfv8yjBYR+DY7yTEupRKTpjtVJLXTYrCxwlWi0g5DMklUFmDzy8E/zZJOy5BQwTZncQTTfpc/N1LG9Bb/fEPue10YS/mOKyXkDSDQS7LcIkOdGFSkjcvabw4XuVtCgBW7FsqNU6ks0WjE5fJM6ygk1X+SuciyTK83IGbzTEeTXH3XWjmhONJsqE/DUe1plwkbvB0jmuOGVPzmRvImCNMcjXeOTxCACeAAAA///snTsLwkAQhOeS3AUrERHxhYKtaGFh46+3sbCxUUELi6AEbCxiEk2isqsBawsfsN8vuOPg2Nu9mXFuWfYDy3glf607sdLaU8YsYakUualS7qwkCML7KMp5VLidY6QHn/WDlHuHKERhNJYJ5wexyxW4xpDAn4tztz9E4m0Rz2e4rBdI/ePjyqMikYaczlPPyZMh6cAJX+KageoH1mRGnGYCq6hh2l3OyXR7A+hmB7rR4oaKXSrLSX2Q6ynAebNCOJ1wzEni7x4/Z61n/STu14Lwv3BWMUetJU61FuhqfU9eN7QfblL/SKwlA+AOAAD//+ydvwrCMBDGL2mstDZ2cBBEEIcigrsOouDog7sIboKDUnERHMXaNKWt5Iq+gFAr3O8Zksv9+76I2nbOGctzFSdFll259G9WxwPUlxo9EyNRO0F8hbk/mGyUn/2mlxCnaYVSwGUbxJKKzSrh0ofmaAJ2MAYninD1Ler24ME5FOmuNFrRunxEPrGPEkXih3ALjayYMOcwBctzcGXWnS2gtVqDO51jA6V0RCT9S5WYQlOfjxBvN7i5osMTxgt0A35DhSZB/C1mqolSG+nf7WFwaPQHeybEE//STRTmDLUBAF4AAAD//+ydTQuCQBCGJz9W7ZARBR1DSDTSQ3++Q3hIgv5C0L0vCk9q5erGjnToXmIwz09Y9rAzO/O8Gmr3W0iduykfV/rJ8IIIqsp+7ncuPx5GKB7QabyMIL6C3LVKcyjvOUZyZJsIlP4ADHcGitWlM24KadtWNTRw4ygMLzCfk3lzLD7lfm2Z3IBfzyCyCmvNdyg+Nd+InyLvl+ykF3VOJpqTLUCpmC5tssMx6BMHmDMF0w+BeQHm+CJUaDaO3PvOtmtI4xXKx8RDfJpnqdAkiL9G8Nq7ofbsixkuloYfxB1mJLiTXXL8RGgNAPACAAD//+ydQUvDQBCF32xW10BY9FAbgqT1IpVILPrzPRQ8eRAhFAKhh57SgxClBiVENpVd4k+QxjLfX1iG3Z15856kwV4E5LKhPH36KcPowdNnflfXwXe5GZEdDw8ksYVh/jVWTisFIAwEGZjtO76eHkGBdkvnKrnl890DRAQ1SyAnlzhJ79AWudvpbNcroMhhqlfXIHCSWv5oMn9N71xq3wskCTvhQY7GOLqI4af3UDdzKJsjG8UQWoPY/Gcv2KmGeavQZM/OebZZvrimvQgky2YZ5hD4reF+rUaeh6W6ul4cx9PM1B+d9eEYXJ0D+AEAAP//7J1NS0JBGIXPvTPjZG4MrxVkV0v8auG/8Ae3a9mqTW2ijUSJIPixCFT8xOka73tduGkRgim8zy8YGAbeM3POGW3yxQNYxi+s1/Btcq6y5x++PXlZvD43WBxH31sWMhm0BGFnuJ3QQzQecWMhbBKec4jmM9jKHds8hT1C+0GvnCT6a3WodAb68gpu0MOy9c6W52XzDav2J9zgi+MZ7Iymu0NNosCPQ3SC8Fc2xRN02cut1ZTJXAB+CtDZDBLlGkx4C1uqQgUXSFwXYMIb6FwY/w8r/Buu28H06RGTh3sWmtFwGue8yf0gs5IgHD/kMKFioNQpVDpwJl/sq7Og5xkbF/BQ9wYr0QM67wB+AAAA///snU0LAVEUht97Z8yMEfKRkuWURFLKxtbOv7UUG5Z+hoUshDQTQ+PqHCxtWJDO8wfmdud26ny857WdoP4Dx3iNslOJzhfiZLdZWeXKQeeyMBEZEj+STS0BVBA+hjqcjuZARpUxMv4OD3uYcwzluvDaXbnjL0GSArtaowomJwDp7QZkWRXNpzwmZ44LXE8xTGLYGooTTeksCW+jHs/HgtEGCleoCy3/yXCimRkM4ff6cJsdaMe9f8RKcTde+A6GOhnxXQYRjkeIZhNe+Kb95wiY/BtB+Ad4qSvJ4Iulk9fqrJ2gsaTgm4Q0Pkv6hh8s+AG4AQAA///sncEKAVEUhn/XNcYwkhENVqLsbCxsPLWNjTzCbDyBSIaMpIxw6dwhLOyUSefb37qd5en8/ydF1o7BNz5DhRjCMJTIF7Ypt76Ubi08L+bmlQYLsCuKYb7F48zqpHBZ+wiDQGs4kk4JIpvTzZIsYf8BujlYRIJmQDsKZdklPRRkxcWRMp0rH6fFDGoX4LLytTblelAvDbbP9wzzBmW2aRtOfkxaiktAmGkknaI+iZWlMoTtwGg0YLTakSuz2UbCzPAcY4LabXGceNiPhwgnHs5+GDl6Lc5zM8xfcY9ipqr1qdXrD8xOdyQse6NLgSinGcdTeQA3AAAA///snT0LwkAMhlO8nh0KIggiRfFoRXFwcvJH+y9cHEQEnURs0aWTSP3q10miBRc3hyJ5fkE4SI6Q5H0FBlhmdPqW+ddai5YTmMoL8mvUTs8n+um4jDLMj8AihTdZFuUb5HEG8cEn6XxcoyXj4I7i1y4BeE6A5vhS9SAZT0hN+L5ekojQY7MCOPqQheGHUxRXSuY7BhivKSb2JrYNot4AqVwS/0ELE+kNQXp91FAAw7LY/7VkJPstTTNv8xkp0VZqxYYD5z3D/AVFE4nzNVOAaDq76mA0NbvuQl+iOEe3jrLeZAPAEwAA///snUtrwkAUhU8zTaJoq5RqVRQLpRSF0n1X/gL/rTt3roRCuxKEUl/4KkVFEDXjaLk3gjtXgkHuB4EsMxCSYc4951xD6wA8xhEoVYl6N21nHiq+1cx0cmOG/bLX7LyQP8lPWJMWAEE4GXS4Q0rHdssq2fLzgzeXlEQZfi+xsiYptWeGErkdly/3uQA7leExWz0ewC28YvP3i02vDTMeQnd/oEcDmJl3UDotnpL0VVPLOlThCJcJbULI60Pm3n1kPqcZUk9bCFDRKPdh2uksKMdB3SXg5PJQ90nYj098fxWOyMsRMMx0glXjC4tqBct6DV7r2+/XY8+2TH0JwsWw780kW5OKxWmqaa4SDy11G1sZb43dmj7m9C8P4IIB/AMAAP//7J0xDwFBEIWf2yXOhYSOkLiQSFQiERqdP6tU6SQqBY1GoiEKrYg45O7sycw1olZcmK/ccpOZ3X0780aTe1nSoflyllJXXW8un+eTf1vM2zBoQcbNCcL3oYuppWDZceKih8t9vYKhhAbAGY6QcZuy8UmBxDjbYcOWtNtA1OnxWnDYw9+s+cfDBCHM+RifV5m3j055X/4PH6Isi+BkMmtnoStV5PpD2N0B92dzJUO+wCITlc6ntNi/J5Fgt8VlMoY3m3KvfWSe7AQcTxmQ4BaEX4Fim2JaFfLQ5RpUsfSIwiBnPC/u40yyWAzgBQAA///snUFrwkAUhCdxkxTUIoioFSoFQaGnXvzx0kt78upNSqGIBaFQWiV2MSabMm/bU68eYnkf5B8s7L7MvBmDinWx/IE3Ir8kcWG9uY+6/WV8M1pF1/3MbT9jOErHgf+TpyjK6fhROJ0tcHxdwaV7X+ReM/IINd0r3eGsAqykoK3RGBEr0fDJwabTk3qK8LKFeHyL7HmJfPshicMu3YF9XLTclfYL5SH3ibZi0Ql8qqgqI+cJdzD5MMmdKJcyYP7uYTbrMkRyB5vngn2u0WAoqiaHTJ4TWmeValNai2z9gvRhBjt/xOFpjTDxrgXUAh8SojUnivJvYCo4XSmm3dlc3E0X8Whyj6LY5e9vAIWAKs9yAL4BAAD//2IZ9EunoO77Dz4l8xOoB8/OJq/0hkNP98XPm1cl/7x4ygrqbDKOdjZHwSigLoDOcDJzQZZY/n3/geHn9csMjFzcDEzc3OCZEBZJmdFAH6zg/38GFgkpBi4HN/DyZ9AJtqC9nT9vXgUPHvx5cp/hz/NnDH9ev2T4++EDA8Mf6HWKLKON1CEP/kMPkvgHu4+NhYFZQAh8sBT4mhJJSQY2FU0GNhkFBlZZBQZGPn4GZm5e8BKtUTD4AegwsK8HdzJ8O34QfDgQMycojqEDRKP3aY6CUTD8wF/oCnlh0VvsWvpLWeWUtv//+f3z39cvoJNyg9jHDAwMAAAAAP//7J3BasJAFEVvMglOxCK2GrQgQjcu3Qjddd0v76KbLvwDUVRQdBGaEWcceW+if1CJ5Z0vyCITMtx73ksep2nhcT4aRFlW6Mn063wybV8Wn3a1HMPJh1UQ/gyqZDnH6ddpMYe3LjTyjgbN94+QcGYymbJ2UOLZ0FANzU9GTif5d+lwBLtewa4XXJEmL5cdz+0Gji6e+x3cYQ9f2nBZSarEM8LN7Yx45VQkrue9qZo+7F6yh1n9ZPjgYF6dXEou1esLT5KmhDvudJD0BlDPXfYyVS9HOnpDSme3ej+E+kNVWRoCRokmrT0ysx94U4YVcHIWBeH/cXU1U4VYa6i8v03ywXfcetrZ34LX09V+1RmACwAAAP//7J09awJBEIZfx7vLHkeKBAQ7A4KKoGBvlf+bMmBpp4WFENJZ2IjWcnreubmRnfPEHxBEZR7YZttlZ3e+3rn/zOYVbI/uYdz7zdY0zA7b9Gf+UfG8NtsyJK+GVlH+HclwEijy5I7ZzQbJbCJGjm2OaPgJv6EqtY8AhRGCZkeG8nPqzs9KxYhzMLPlAul8Jv25nPzCxnsp3SEDcDm6k1gW53R+39Tm3oyLo3l2MkuhHy6i3q6jxInmUVhFtVaH6Q3w0hvAdPsSaHCZTSmDNyEo8FEJjPZiPhhOHTz+/kI8HsGuV8XMcScW5nv6/1GUJ6Qsj6XXqLDjb+8Wx+wvT3ayXyiD3/ndB3ACAAD//+ydsQ/BQBTGv1a1R7qIRaJBIhHCwGb3b0sMRoNYhUgM0kRIDKpKj7z32EwmlfuWS3NLh+bS7773fi9TZpMdvuumuVL55FRri3y1viNaXno4CFaP9n90oKmRUeb1Sjj1+Ypku4GOIkk5LaBoj/ggNCnJb4uBL47/8R059awEnHgl6yXu+1ASzlsCTTeo8YV7xfg5jnlFcpN7PryQ7PTjSx+EbcYufC02lRoPLQRZLp96d5Q4ZCzysFVBaMS0KsV0aDKPtu8LQTZowGv34LY68Jot3jPKrnR8QRruEE3HOFOf5nwG6w14ch05m03prJHR/+lOvobmawehGgxXXrc/sVThSOBUqWbIgOcB8AQAAP//7J3PasJAEMa/7K6K5CISDcY/Vy8ePLRQeumT+ipCofde7BtUUIQEowhx3WyZGaH3Qg9p94M8wA6E5Tez3zfNgs27F4EDLa42Vr3+rZVNnb9a7cqCL+YowGZQ0O+IJ5wRVKx5XYbLC1Qf7/y0A+024qcXmMksFL+hMv0EavnAgFKfz6iPOXs67e5TPJ6HPfs+fVmCQgkcBQ1RsJD9DqGJTA2vIgFOIADnj+Slm+28PI21d46g+nY0h/qYZAhFHsxBCpOk0GmG1mgsne9BKvswyVtNEBqml40XNX4ub2v+brutQKbR8n/JHvL/XqKgoL8pGmwSbGazTffxedWZL159VZ2o8S9ryxpwagBfAAAA///snctuwjAQRa/jgCCFkArBDqkVYssGFu2/w4Zuqi76FW1Vkb4CIuYRGzQTE8oHsAjyka04UnZRFI9n7h2f6/3LBBmVkM1vtttU7wcv9dFD36zVOPuKu/RShOs17XBcEOt8SoZdastBCJVi8lQKwWOu4STHS0e5oEyZpEnllhajUt7c7j7eoL/nyOaf7GKrf2LoRV5+a1ZLmOQX+zSFXiZ5BpSz3iZ3uBU261m0WxF2Lez4pzUTOD1Y1kC12PgfTRv2dpzfF9ej5tKc+p+KesCBogxbELUbeGEIL2jAa0UcSPrtDrzoloNO2e5w2SzpL0mj6bge6FtjM6CnCdLZBOvXZ+jkzxo/CZfRdDiuFTpwJC22LyGbDep//F4bjqeV3l1MPgtcWVSWfySAAwAAAP//7F09a8JAGH7ucrkTkWJpBUEIpYsgDv4GQei/7dZJt25OLg5SWmjp1oof1Wg+GnnfiyjuDgn3LJc1HLzJc/d8KBpmhYP8o1Ta0A8ehlm4ifezqY8IAx7AVbg0NgeHayL3R8uqx0Ex6e8PwskY5CrThtAAACAASURBVCFIl3PU+k8wnZ7bghJAagPVbMG7veO+YwqFoo8c+3XjhPebCGf88cbS6mg2ZXKabDf431FHck6glCWcNmjI6m6FtGsmzgioyG9FeYYXkHAeyyvZW5lbP7ILUnlMis1wqiZJ7TOF+4gKmGTqVgDd7kIHjyxtpnAfri0xFQhfs2Sd0mO5B1MbV0NUQkSf71i/PGP7OkLy/YV0teCXFEa5/xwHhxKD1C3UmcuVVXSgeN+Q3k1dUfgbHdDa3s2CAMCBvbNZaRiIovCZPyMSdaEuioNBUFHBhW/QjY/sTnHhul30CRooRZAW/KFak0zLvRObWCi4cZE6H4RMQiAQGJibc+cc7ZqmbM7KEHNjMrV38GRs8qBt0lb7Ozfu9aNy6JOhfSsQ+EsWCudkCpemcOMR3NuL3xdoNqFbh9zyF2gwSrHCBjpWQOonRapkgz6+Ts651fZ7YUxKJ/LC/4Utcl+w0jnLfBA1mbu53I/J8ZjbRwt/XRrgMKKujKJywkVVkAosFad1lfRXLNvHz2q3VqiS5fDHO6XPKaU4LqEi/oY8V6jliTJqpd93CW0gqUDUhotHek7FMcRWDGOP2DV24+wSxh5zPAnFDQX+BzSnitEzJo/3eL+7xbTXWajfMtIQQdEMBNYa6gyiCa9bdhxdXQ+j04uu3N795PUVratKl9pGAGAOAAD//+xdPU/CQBh+7lo4SbGC6UgCA4MODP4BF/+xswMu+htcDMGBEAgJgcOm8XrmfV8sdWJyAO+ZLunYpnfv83WxOrU2wR8mnLOblhj2Mr7OiiaVWnxM4e1aGAEdcioBAX+KvcJJOTLwAekTxeQd9mUM6BjJ/QPMzSi8gzMHKW2NXp/ZVzO8ZfXT7Sz8bgu3WrLtzy0XVettabeS9ySrrd3A5xYlK6E5fJ7zsImCrrqS6zx4h4oOVlyx5fqDQqpq+4LCL4tu9fAojlhca+tKlaytuRUWEuPQTQ8YL0Mk5Sap/ZXYaFIhyQprDKKrLlQ7RZxl0O1UmOu0g6jThWolXPTDJUDJJQ/7nIsO+Df4ms8ko/n6DEc5aUff1b6PIiiaAQFnDB5wJKtfgjL5bxeju8fGYPiktGJ1kAjbk/oHAPgGAAD//+xdwUrDQBScZhsttdCKpl4KBcGTF/14L+qhh4IIUijo3aP00NKYxEi6u/JmN7SKV4WUHXi87DGwy+Zl3ptpN1E9sv6WYFHZ6RSHl1czW1W3eJhcf77ME7uxbEcKCAj4h/PoGU5bVtCLN3zMHjmzZ8oCJk1xcH7BFkAyOwH7B9ri9Bg4HX5/PWuoaCszJiZbQ6+W0Nm7LzZz2CyFlUKzyKi4aWrF29KFeCtjU1H1mBes9nl3Le1Esv+EFfXh7EHkWW8v5d9acmvLrB8h7UtU1iUb6czyySaRsdxm7n0q/MZAHLOdNaJKbNepxB65olEYfirHylq8TwfHiHp9Fpst5gSqP2iEX1rA30GvV7Q0yaf3yCd3KOdPnIcmPGMeCs2AgD1GLXSgIkTdNtTw7DUejW/USfIMpVq7P0EbAwBfAAAA///sXbFKBDEUfEnu1jXL7SkI4t/YaSH4GX6fnZ2VlZWFCoogCHZyerdyJtlLZCZna+25mWbJFmHZXZIMM+/NSG2sNUfxIKDbHVfv7V9qa9/C68uZu7s5kf4PPF5BwVDwo3BWhupS6hbiH+8ZQN4/P8nk+FTs4REP4gUDA2pOJtP87fsDSSFne8JGGxmd4mmlTb1fN5oKmUCGwPvRLWW1mEt8n/F/Ql0wr58dm6fA3ULSivkYy+JyfijmgFLqv7JV97faT9aPGpJGWl5BGqFKMo+yykoj6iObhiRSW8u8Um0bMWjc005Ft7ts4KO260xC17ZYNdpi11COMf+4Ek2beR5D5aQCivdTiObg4R5upbs4l+X1FZtyxfkHXwnW1qJoFhT8f6S0EiUoXxlnp0tdx+TdDHubMiZxv8JesklrgYh8AwAA///sncEKgkAQhkfcWjNBKCKCOgQRVFAv0CP0sN2iU0/QGwhBIkiEUtFB04qZNQ8dIjxE0XyXFQ/iSeffmf9focnKF7xGQdC7KY1UNFtb0IVb7vamer0xuyV79TxKc+IfOMN8BCyicbw9iiDxfbh4PiTuRhXfpgVyOKaAEyq0mb/h1dme75Bi2m0YkLikDiiueO94UAm4eAZoHJPPLRebKFxRbGad0bxz+QxtlGRdS/RRPsQmBvCQ2JRKbNIobFVd44pC07RAt23qSGp2TXlbGaYA6HW/eC6cV0s4LeYQO44aG6eQrtJPFpcMwxQAvZpCB9Fph8ZgspP90VqTRkDTYqcjaOkVADdqf+l7AAB3AAAA//9iGWpbNlEAeLkT6B4y8Gg4K2gEHXTtwr/vP8D7hcBLqEY7m6NgFNAHwAo/8DJDyDJG0CzU9wunGf6zsDLwfP/GwGVswcAoNHo9wyggHoA6dUwsrAz/BYQgM5+gZbW/IRh86BCoYwk+WOgP4oAhUFqEHjqEOEgBW2WHvIyWCX5vIWz5LGzGE75kFnTADxINPgkW1DEdPQl2FFAAft65yfDt8G6G7ycPM/x99xaSLJmZEGlztKM5CkbBiACgE9wZmP8xsCmoXOC2c17DqqCyF3QwNWhbCei+XUZmFkg9N5QAAwMDAAAA//9iAS9jGsIAtGwPtCfo/4/vTKwycrc5Dc2O/v/9S+fXzWv8/379B51TMgpGwSigIwDPEoHAf9BSyd8MP29fZ/jz8QNkH97nTwwcxhYMzKBL6bnJn+0aBSMIgA+h4mAYiucLjIJRgAuAlnqD9mP+vHWN4euBnQzfDu1m+HXnBng5OOigKfCgxigYBaNgZADYSkxWZvDWDDYF5WscOoYrWEQl3v15/RKyegd0ewjolPahdiUYAwMDAAAA//9iAe19GfIAdILhr9+/WWUVDv7/+eP/r0f3o39cvOz0/8fovZujYBQMFIAfzw/ae/fuNcO3YwfAV2LwvHvDwO3kCT44aBSMglEwCkYiAC3x/nbiIMPnbRsYfl45x/DnzSvwicyQ05eZR9PEKBgFIwmAVmKC7y/ngNypzMXz//+/vz/BB+GBAGjFDZgegmHCwMAAAAAA//9i+T/U7tnEBiD7bv6yiEvcYVBWf8cmr6LOIsRn9+fdN8jQ4L9/Q3IkYBSMgiENYEvYwXdxfmP48+Y+w69798HLHhnYWMGrGkFXPjBx8yJmQ0fBKBgFo2C4AuiedtDe4x9XLjB82bmJ4cv2dQx/Xn9jYOJmgCzfBs1ojg6Qj4JRMKIA+BYNpv8MrJKSX9i1DZ6ySEjd/v/jx1/Qye3ge6qHcnnAwMAAAAAA//9iGYprfzHAf8ida5DDIP58YRYW+cSqqPrzP8MDlv/fPzL8//uPgZF1dEnKKBgFAwIYISdHM7L8Bdv+6+4Nhi/b14MPcOE0tWZg19Qb7WyOglEwCoY/YGRk+PPmJcOPC6cZvh7ey/Dj4llIu4UFcrUJfIButKM5CkbByADQgaV/P0CTln8YWCSlL3Mamm1llVM88P/37z+gw8PAA/RD7a4TZMDAwAAAAAD//2IBXTQ9XAAoQhgZmf6yqajf5vr29QAj6yGzH9cuiTD8/M7IMHrv5igYBQMDwHdGMTMwcTGBC0zQJve/x0CX+38FX/gP6nSyyisysIiKj55UOwpGwSgYfuDvX/Cpyn+ePQHfQ/z10G7w9SZ/X7+EXA/ExTg64DYKRsFIBLCVl6C9mrwcDKxyihfZVDVXsggK3/nz5iUj6IT1Ib8yk4GBAQAAAP//YmHm4RsEzqASAJ8YyPqXQ0DwDDM37++/b178/3nzms+/P7BzCP/jOJFwFIyCUUBzAB7Bg1gCOkkUfBgG6OL+Tx8YOIwtGbgsbBlYJaRH42EUjIJRMKwA6E5ZUHn37ehBhq9H9jD8unOL4e/7t5ABctA9rKN3rI6CUTAiwf9/f8GnnjNzczCwiEqAthV9Y/j79+X/X+D7ov9DVm4O8ZBhYGAAAAAA///s3b0OAUEUBeAzZnL9hCjERjWFUhQ03sAzSyQaFY1CRcIWOsnaRmYKGUbuEq8g1v3eYnLPnGN4/648IlBTMJ0krbTaKe22A91dTaP3r/PtPQJaHptCfA1Havl6GR8IWY5wzovB/nDJihhZYzSBSXqfUXwhhPhJ/D+Ty9HcFbfDHm45h1vM4DdrcHmhbr5ndKRPQoj/xbuadQJZ66vD8Yls/wgFz8VAikqSPAXwBAAA//8a2vdsogPYkub//8F7xJgFhD6ySMl8+vfxvei/r59BJzsxgu+uGgWjYBQMMGAEX2v4/y8Dw5+Xzxl+nDkG3nf999VzBi4TawY2FXUGpuG06mIUjIJRMLIAIyPD37evwQcBfTt1hOH78QMMP+/eZGD4A7nSFTJjMdrRHAWjYEQCaP7//5uBgYmbmYFNVfM4t53rOjZ5pcMMzMx/GVlYh891XwwMDAAAAAD//2JhGA4HBCED0Ebbr19Ay/MYWcSln3EamB75/+2r1c8bl0X///7PyDi6d3MUjIKBB+C7E9kYGNlBlxj/ZPh1/wH4hMY/Tx4x/Pv4kYHr0wcGdn0TBiZubgZGltF9nKNgFIyCIQL+gWY0fzP8eniP4df1S+CDgL6dPsrw6/Z18CwGExfbaEdzFIyCkQ6gZQAjKxMDs6DQb3Y1rWOcRhZzmQUFf4JXeoEmzYbLbCADAwMAAAD//+zdsQrCMBAG4D9XI5SCCKLugi/Ryd0ndnJ30Q4BUZBSxLEditQYzEky+Axa73uFkCN3yV0G3MOpZz68dQZYL5ZFquDdtRx2+93atwCl4ePURKa9CfEt4qGL8WpqPM/HuDdddUHW1MjyFZLpXJZKCPEbSMGeDO7bDR7mAGsKuFsFdh6f1kxJNIX4b+GijygW1GkyIxqNO6W1DUEi9HAzuD9hAsAbAAD//xqW94GARhVBgEVC+i4TJ/fdnypn1FiERBx+f33HCV7AMtrRHAWjYNAARlZWBvCKA9CJje/fMXy/cIbh5/XL4Ls5mdjYGbjt3RgYQGpAezhB1wOMHvI1CkbBKBhMALQ/E9R4/PeX4fezJwxfD+5m+Lx1LcOvh3cY/n74AG40MnGOrtAYBaNgFEDA/z//GBjZmP6zyMj8ZdfUucYsKPL237evoJ7mP9B+TbCa4RJWDAwMAAAAAP//7N2xCsIwEAbg/6ptxc0XkEqHgogugpvv65toUaTgpEMHHcTNDk1JTCpXqLtbKfe9Qsjx3x0hwz42XrytJa7u1jYh1Z/ObqPVOiO6JLZ4Terq41E4kOmiEF3R3kUObUrDKo0qOzYBzjwfCJMFwvmS32HLkQkhuoUI5p43QzJ1TlGd9tD5Fe5dAPy98G+sTz2LkEKIv3AJcDVcCXiBIT+K0/Fmuwui+FBb65wq0TabvQHgCwAA//9iGY4dLkaon/59+wreD8Yqp/iIx8F9BwMjA/P3MycM/339wAbubI6CUTAKBgcADXqBri4CYRD7/3+GP8+fMPx++pDh1/3bDNzWTuDrUtg1tMH3cYLXo40OFo2CUTAKBhKAB8e+Mvx+9YLh29EDDF8P7GT4dvIQw/9Pnxj+//nFwMjKzIDa1hjtaI6CUTCiwT/ofm1Wxv/MAsI/2FW19nLoGS1i5uX/AL4O6SdodGqYAQYGBgAAAAD//+zdsQrCMBgE4Gs0bSZdFUERp+rg6KM7OjmKCCqFDBVciiB0qklrEonGZ1DK/71ClvvhyHVZ3OJqR5hZiCezC0vEuimuU52dVuZehs0/C9C+FSF/ydVPWAU0uUQVQl2dpe+Pg8R8Cdbr08MRQn7Gh0N13EMddqi2G2h5hilun5vSr5rQfBMh5MvnGG0QiY7jw8EjSRc5H41lxOPSV/B9G9M5277dXQAvAAAA//9iAd9nN5wBMzMDM7/AWyZOzndsSuqXWaVk3v19/1YI1NEENWYZWUY7m6NgFAwqABoIAg0UcbAxMLP/BxfA4Ebc21fgpbVcL56BVy9wmtuOxtsoGAWjYEAA+FqTqxcYvuzZwvDt+CHwElrwCZIcrNBt5aMrL0bBKBgFqAC0V5OJjesPu4b6Ey5L+8OsUrJP/v/4zvAP1NkErexiGIYDVAwMDAAAAAD//+zcvQrCMBiF4ZO0tdXqqrgougki6ObiJXsVIhQ6FAcHQfFnUkRsOxjbJpEqCl6AIOV7LiGBb3o5hcxoP97z4vm6k1PWVquzdAajuYyuw+ywbai7MplBE+SE/C8GLVNooZEdT5BhCBgmdJogu5zzagFWuwvuVukPCSE/p+IIyX4DEfgQCx83b4Zkt4aKJVgJYA6jYooQ8i0vKfG6C9ytGXavH1TGk6lZb66eKQTnYJZdzEcD8AAAAP//GpYHBKEA0L2boA23v38xMPMLPmRX1976+/ED9r8vngkx/Ps+LE/jHQWjYNgAULsNdLkxD3QJCuj+uru3GP68ecHw+8lDBi4zGwYuK3sGNgVlBiYB4dF4HwWjYBTQDICW8oNmML+dOsrw9dAuhl93bzL8ef6MgYGZkYFZYPS02VEwCkYBdgA67JCRhYWBiZuVgUVc6gubsuYZdjWt/UzcvP/+fnw/vM8OY2BgAAAAAP//7J09CsJAEEa/JctuiL2CWAhiGgsbr+DBPYFVFA3YCQHxB9OEyWYjs7G0FonzbjBM9Wb4ZvRfZAq4Rh/xi4WzsvEG1i6g9bprbtt1WCaRgvDDvDPWjQ+bhaZ8AnUN/7jBXYpwqTZermCmc6g+59AFQfg6LRHouEOVbYNo0ikHHTK4+xWoeJsJwEg+UxCED/CgnFg24aPhqDSzdK/Hk1wlA8cfM4KjsIr0VUMAvAAAAP//Yvk/Au6chJ1u+f/3r6//f/64w8jKdotZVPzzv58/eRn+/AHPeo7u3RwFo2AwA+gyE3ZIRxKUp/9+/sjw/dwphl/PHjNw3LvF8O/LZ/AsKJuS2mhMjoJRMAqoAkAn2v9+/JDh6+E94P2ZoHuAwePUf/8wgA9YZB3dijMKRsEoIAD+gu8U/80mr/yIQ1P3GLOA0Kt/X78yMP75w8AAuqMXBIZrd4yBgQEAAAD//2L5++7tIHAGbQFo6vr/v7+gqxP+MQsI/eM0NDvKKiU398f5k1Y/rlzU//flB/vo3s1RMAqGAICdIg064Ov7b/BdVf9+PmT4//Ur+GoU0OmQnEYWDKyyCgys0nKgvdqjsToKRsEoIBn8+/SR4c+r5ww/b11j+HnjCsPXQ3sYfl49z/Dn+VcGJk4GyP5MFhborMTolSajYBSMAizgP6Qj+f8vAwMTFxc7u5b+RU5L+80s0gr3wO2Zv5CDgYY1YGBgAAAAAP//Yvnz7vWw9yR8KfS/fwzMQqIMLFJyV////jWZkYHhy+9HD5T+vv4A2ZX7f7TDOQpGwaAG4EYdIwMDEzMDIxszAzN0VuHfx/cMPy6chtzLee8WA6eFPQO3uS14LyfDcD9xexSMglFAVfDvy1eGn3duMPy4co7h27ED4M7m74f3wQ1HFmEW+InZYDDa0RwFo2AUYAX/oXs1WRmYuP8ysEhIf2dT1z7Ppq57komT69e/r5/BmhiZh/nxMQwMDAAAAAD//+zdsQrCMBAG4L8hbR1aUAdR6ODgYKEOPoKjr+2kmyIIghQEUapQl4qNJqk0Tg5uClrue4AQyJLkP+54kec/sI3vKvC8oJqB8Y4LVm8Iy2Ix7wQxb7XvMjkBlgSkAkw5LT04CfkLjJmfQS0UimMKdU6hs8wknOqwgxsO4PT6sIMumOfTmRJC3ipHEIjN2jQByucz3LYxxGoBmeyhL2UyAVR+XBwh5DNMg1IN3rSFG0ZLbzSe1qLhhPn+9WX9qodcAB4AAAD//2IBLwMZQQC0zwJ0wAh4apuF5SertPyHP29eS/5985Lh389fDIzMjKOzm6NgFAwV8B+yl5OJkxXiYEYG8Czn99PHGH7dv8fAdvUiA5eFHQOPrQsDu7b+aLSOglEwCrCC/3//Mvx+8ojh69F9DF/372D4efUC5JL179/AHUxm3n8MDEyjbYNRMApGATEAclYMw2/QVSc8XzhNrHdwO3nOY5WSeQEaEEcpS4b76ggGBgYAAAAA///s3b8KwjAQBvCvTULBwUFBVGqlT+Du4iv4lr6Gm5tTUXARQVCwWkHjH9omcsHdUaX3e4JMIbn7cpGeUj+wjO9QYX/hDUcTW+Tj22w6sKkWnjSA4GFBjP0V6nDShu26nBrmDhSnC8osdcUlc85Q224goxiy1YFoNLmoxFjF0SyH8piiPOxd/P65TKApNpvMke+u8AN6lwkX2af/fTkyyxj7zLrJ+bRn+PUAsh0+VBSvZLe3poSVNXQRfZ9bqgDACwAA//9iGZFLQsCHjDAysErJ3mQRFX/95/VL5h+Xzij9//deYBC4bhSMglFAKoA1AkFL5ZmYEHs5v31l+HX9MqQxefMKA6eRJQOHsQUDh6YuA5Og0Ggwj4JRMILB33dvGH5evcjw4+Jphu9njjP8BN3h++I5A8O/PwwsgszQASnoaqfRjuYoGAWjgBgAuv3i7z/wiisWQVEGVjnFj4ysrH9B92kysbMzMHCA1uOPoMFuBgYGAAAAAP//7N3NDsFAFAXg01+NpLUUCyFNWDREYsvGE3sJexsi9RcJkkY1EaHa6VCZ4gXs6P1eYXb33jknXze0H1k6lATZMG6wSnvdbowMp9N/hKz7CE9mGieqpCm0+SDkF2XhHfIrsTZi4NcA/BjgfvBwD3wk3hbJeg6tZkNvOlDLFXpmQnJCdGZybwe2WYEtXUSTMdhihlj0ZvpngAOyKSHPV1+EkC+JuZToA7+kkC2FF1rtabE3GGrVuitCSsUAPEugzf78vCtP/h2AJwAAAP//7N3NCgFRGAbg98xMp1EHG7dAlJUkl8DODboHtyBRVtRgYU2EmpLOmZ/TjOYMC3sb5nvu4vvpfZ13LG+hmAVlikRKQClY5crV7fTmiZLVwFs19d0XsPNAIULIL8ovmxZ/7dMYM3154X4LfT4i3KzB6y2I4QiiNihE9DghBNC3C+RyBrmYItx5iE8HQEdAHMEWDrLucVag9zZCyDflQ2QamGqkB2+0J6Vuf8y462ed/mbYVJ/5QH8PwBMAAP//7N29C4JAGAbwx/wIMhpMkGiIPoga+v9pjZZqcOkfiFQQIm3JU+/OOCXa28r3t954cLwHL89jdOwWJzR2mgHTmsyvuuNuq4I5ZRxN+S3p1wdUhULIb3sPjZWEZAxVmoHHDxTBBWUUNIFhaQJztoQxdGG4HrSeTZdOyL+QEiK911sNKq068494HnZg/gk8DOuuXk31ZpqoKwo06s0khHxDrc9yoQLFhDkeZN315mwtVnvdGwUoCogkh8zzz/vSlu8FgBcAAAD//2JhEhjJ+5YgMc3EwfGZWVz66q8Hdy+ziEsG/X5wDzIV/u8PAyMDy+hNKKNgFAx1wMjEwMjCyMDIBV3JwcQIvh7l26E9DL9uXGVg1zVk4DQ0Z+A0s2ZgVVAeEfdejYJRMBLAv6+fwEtkf1w4xfDj8nnw0tk/r18w/P3wnoGRnZWBifUvZCaTcXRv5igYBaOAAgDauvPzLwMTL+8vdlWNJ5zGlueY+QQ+/Pv4AVKugFaSIt/RO1IAAwMDAAAA///s3b8OwVAUBvCv7dX6kxjQshmaMBhMEgaxeWar0cAgHSxCtEGaSiqpaNpb5Go9goGe3zvcO5xzvnOYLIKqOZXe3xRriasxFOmqmt1VsT+YJ955zB3b4H6kSlpCI3aE/APxwX/esuhoBgG4FyDaOojd0zvTyd0jCm0TaqcHpjfBGnqa/ySE/IzH/QbunhHbO/DDHuHGQrheItpY4BcfEDUnBZA1hrydfyOEfMHzmS0TA5jRCkvD0aIymc6UWt2RsilKlMr57F0BeAEAAP//7N2xCsIwEAbgv5doK6IdRPAFBKEuLrp00id27qRrfQRBQbGii2gxtIZU0uIbuGjve4GsueS/O2lHf9edyVQZnREdP/HGk6U+7KW+XuZGpT3HvnpKHnnO2F8hAadBIFE16pv7DcpeRndbUNdHaxaiHS5A0xDEsVrGfoo+n5CuIjzXEXRyLNcf2Z9Mk2cgV6D45Jp4byZj7AtsLWUTUeQ1IfuD3B0GG3cUxCDxKF5ZdUBd6wgAbwAAAP//7J29CsIwFIVP+mcXRVSoUgpODk66+PIOggr1RRxa/1ptCwYT5aZ9BAex91szZLpJ7j3kHAfcQ9XBzW8N4fuJE0w2bjQdO0G4UJdqCFvWzlEtlb4Z5i9p6lk0+ZykcqpbASmPgEWRCCfoLIPKM7Itp0kl6H+71e2xcRjD/BKmfh/QZYFXfoVKExNlUm7XqA576FxC2LWSKTxhHoSC73KGYb4F9RBPDavfkW4Ypf5ytfNm89gejM60poq72ai15w6ADwAAAP//7NxBDsFAFMbxb9qpIsRSJFZIdEE3vbYT2HEDGwmiiyYVjU1VmtJ2ZmRKnMBC9P1uMe+9+XP6j/j6z6UnnCrPhbwlMRgL+WCYyfiKMr5ApRkYN+iclpB/pB+d+nrBlGCWrFYeZXRGulqiCANYowlarofGeArbmYN1ahxVI+TH6MJjEfh4+AfctxsUxx1yfw8RncCgYLTfobBquERDY0LIF+nSvRRVaIz37cR2Zuum6y3Mbi9UOgYkys9GU5euawnAEwAA///snTELwjAQhV+bWFIogiiitYKo6P8fHZycHFw6tIg6FCmFIgiloLUWJVd/gjjY++ZMSSBc3t17kjai4dDxVwZdBUPZD2u6CEWvvxKOY99223GZRQri9VnJDxXD/B2mqZN3Sf0gpSTLUaU5OdbKQ4BnfIY1X9bFp+tBDjyIThcmF54M83N0fAA5zKYJyiRGEfoojnsUgY8yOqG63knNNG3dLi957pphmO+ji0edlanH8NoW5HB0aU1mG+l6a0OpPZpOHAAAIABJREFUXH+E1cZADW8hBfAWC+juuREPGH+DQwB07DnogncWUfFHDIyMixmYmT79enAv49e9h9KMDKOdzVEwCkYEAM2AsIJWO0BmOf99eMfw4/I5ht8P7jD8vHKegUlQmIHDyJyB28qRgUPbYDRNjIJRQGfw+9kjhu8nDjN8O32U4e+blwx/Xr0E77v+++kjA8OfPwxMnNCqevS+zFEwCkYBrQDoPk3QVSdcnAzMYuIMrFKyXxmYmF/8+/Lp6//fv/7BV1GM9NUUDAwMAAAAAP//7J3NDsFQEIVP/9sQKhHvwaZenh0bO0IkdoSVNLS9TfXnXpnbPgIb5nuE2UzOzJw5tqp5s6lFJOlImk4MR+TLSs1ef9c8YrPcb+f19RxKkfqyKCzt/eAGxjC/jU1fKttmIoVA8xSoyLp9PACeg+p2gUoSKJHBGk9gDUIYng8jCPTQimGYz6DKUn+XVa8CFCHQxHctMvPVEvlmDZUJyKqzYVNWJl0puC5Xn2GY7yNBC6oimEVnfxotzHB0MhynaTM3uxNa+vvyzwB4AwAA//8aPfMbDCDHFYMTx7+/kEoNJMrJ9ZVdU+/S72ePFX9cuyj3/8N3HgaOPwyMTKMV2SgYBSMCgGY5QXu1GUE1yn9IOfH3L8Pv+3cYPn/9yvDr/i0GNjllBnZNXQZWWQUGNiVVBkY+gdG0MQpGAZXAv08fGX7euc7w6/EDhl83rzL8efKQ4dfdW+C7MsErs0CLENig1TjoioHRWYRRMApGAY0B+FBR6PJYFhHxd5zGlku4rJ02/Wf4/xjUZgCdA/H/x3eII0D3a45kwMDAAAAAAP//7J29CsIwFIVPNSYOFUEEh2pFQQrq4Lv7Ar5CHVwU/KsgxUWrSNOklVTp4OTk0vs9xCWXnPNdRoP5C/MtLiWy1MhC+I05vUXNHbaTYN9U54sNitMSRHn43OYsDLSfjoYOQ6ggzEUk3OlD7jbgg1G+dLKuC9ZxULXt3GBLSQiC+B2zQBq7rH5EUKcDVHDMxT/xdg25Wr5PmVwTWBywRAUwSQJ6xxAE8S9MT1OnQF1o1mrEwhv7YjKbC2/q6+cdWRQh0wpFTbHs8wnACwAA///snL0KwkAQhOcSk0MLyQPYBBFsbMRGX8A3t1EEg4JiKQgKMQjGXM54kd3CysLKxv3aa5djZn+mIULoA9QdJXHpnldn7kltTQeeP1WhzzNzNqLKkwIShH+EDSjdddaAtahOR7iHhd1vUawW8KMIYX+A1miC5nAMFcofKwjfUmUpzHwGs16i3G1Q5zmq9Mz3mC67sIhTmsYJkOAfQRB+C6XPkpEsAK+tTRB3D0HcS5TWN1r3R1nyOxvSdzDQnwcEAXgBAAD//+ydMQrCQBBF/27WjWmUVBIQ8QIiiFaWXtpOREQbwUJBC8FCJEVEUdBoNhvJRsUbGHDeCaYYdhjm//0CUZSDMvKF6Q8dp81yZ0L4VsWbFButEXOcntrv3PgY2OawSVEoBPFffOdzvjydaYaWOp2NdwNyDiYsyNUS+hAgCUPIWh2sVAaTNri0U8UEvR0EkWgkkUKiImNdSX9uVP4e4XqB66CP22yKx2ZrZLJ475UWz6SyDi2ZBEH8AP2SxAqOglc9Op3uuNhsD3nZveh7CKg4O1hxmvEfADwBAAD//2IB98RHASqAzVr+/8/AIizGwGlo8YRBz3QOy6XTz7/u3R7y58VrBQbWv5AG5+js5igYBSMXMELKC0ZmyMm1///9Z2D4/Qe8/O/r/h3g+/9YpWUZWBVVGVjlFBnYFFQYWKXlGBiZOUcTzSgY0eA/IyP4+hJQB/PXnevga4VAe6D/PH3K8Ov+bYa/b19B9mEywk6WhV6KPlrnjoJRMAoGAvyDrGwE1/kcrAwsUjI/OPSMT7Br6l5kZOf4CC6omFkYGP+PHhKIAhgYGAAAAAD//+yduwrCQBBFb+KahBQGogEtgggSVESwsvLfrVJZ2dlEYyEKgqBgHisbmQSx8QOCzvmCbXYvs8ycEUWS1Og4daIofyZ0x4Xo+fdGy1lplpk8491UxpGv8kyHUloZfNyKzDD/CYWO+Nz/tzCA1jCk52spNNFdF8ZwBDOYwBzPYAwCCikIt0MSsspi2+RwYn4cEvDlGWjRORWZ8nKC3EeQhz2yzRpZtIWMIxQPakOr5jF1m2V8DMPUBCo0lUKj7eVNv3+zF8vQms5D4XWPBb1vKddTXwHwAgAA//9i+T96JC8OALmIFdx4/P2LATQ9zsjC+oFVSvYpq6zCt99PH3H9ff+JmZEVuqRuFIyCUTAK4AB0iu1/cKMZdJrmr3u3Gf6+fw+mmfkEwXdysSkoM7CpazNw6JkwsIiIjQbdKBjegJERPOP//cpFhl83LjH8fvGU4c+zJwx/P39m+PvqOcPfj+8Y/n//CVmOzjx6Bt8oGAWjYDABUH3+D3zNEruE1AseZ6/l3A7uO5lFxB6DHTnal8INGBgYAAAAAP//7J29CsIwFIVP7V+guvkAIg4OVUqhi5sP65M4dLCL+gwOIhVKW6uQRsltSxcfoOL99kCGDEm45zuWIcRQ9zYYqA6lKjHSVSh+kNRFPn8ruaqzfNoHgBmG+XvaET+tPUdXLKVznfcUdXqjcUHoSMfYgz1bQIQRVF5ABBGJhfQ6w7R6Ay6LyJhfg0bNarp80We2lPTjL68XVEmMMt7jdTo00p+shNFGm6guwGnMsnziGYYZDJ3sx7GVOXGlu/SP3ma7E+vwrHQP8PPRFlXwe+ArAD4AAAD//+ydvQrCQBCEh0uMQVAJKvEHfwoLbXz/WjsfQNKISDAJETRNRJOcJ3vRRrCPsN8TXHMsO7s7Yxptp4LPqhjafVJA2I2L6Q7XSko7O+4nD8/rkgpbutPyLQnDMF98io+OTCkDoPW0M02R+weoIkMRBrhtN7DGM9QoNmU0hdnpwXAHEHUWA5n/gpwYZZKgOIcoTr6OKqGJJk0yaU02jwLIOMKTTnjkO0hM0BdR3GQyDFM5FAlmOWD2nbs1X8T15Wonmq2rIjMg8mnQZZ4bzZ8AeAEAAP//7J25CsJAEIb/3ehutBVELBRFiKil798KPoAHxiLgQSAoXhHGRGQ2FjaCpcV8zzALO7v/UdJSQP4DxRApY1Ndqc58uhOFi3G2iRp5Ets8vZWKJANJnxIE4YPP9No37kLN/o706upSaDEHfONktbY/ggkGMM02yp2ek9d6tTq0tUDZQHla6h6E/4HnmH8vuQrg8UB+PiLbbZHFe1C0Bq1moHDp5OPZIQEIUL5254F9ysrIeikIwp/DK4BW/Aic2GA4Ma3ulA12z8upSJdnJZMsnN8B8AIAAP//7J09CgIxEIXfalbQRglaLrqF57Cz8ZiewkbwAhaChYWFP4iyP2ihsD/JyGSxEAQtLeY7QjIkzPDeG8UHKHyBvLciquveoTUaTynPo/tiNilW6yGnHHtNaTYFQfgFqpJrDYem8HLBHMVx5+SGnMqZdTRqugvV1vD7IfwgdI2oCgYioBD+B/ZhnvZuaJJtNyijM2ySoLwmlXQ8vsCkMUyagl77zY11SbRVHUsxC4Lwp/B6Jv6n+b1qsL1FPWDsnMpiCcKNw0Gd3YWtL6xeIis3+QkATwAAAP//7J0/C8JADMXT/0gnHcRJSlVcFF388M666FJcHUSopeIXqF6vjSS9ugji4iDkt9x8EJLjeO/FFVPr91CSXqVL+sl4dBarNZQq1/llqE7HESptAaIxbMkAFQThA5Ri69kAZFFrlbK0ZzBLocxSs1bJZhmtF8UQTOf8aA9mS/DjCViOx9J+HoKtr1Ok/MIvwCYsD83JDyqTLEv1WiQ7KPZbKJI96NuVd8vW6v6SkFN9khfTCaQ2BUH4I7iHITjdXuX2B9qPxgc7DDdY12f2cZIvXevmPm1/FN4BgCcAAAD//+ydvQrCMBRGv9YUhyqKOgj+jw4+gpMPrW/g5AsoKFRtEUVBUwVbE7kJ6OQgKAjeA5mzhJDc5HxX8LPvG2g8KxeOA9fPbbxGe+U1OzKNwpyS0jGVDk98Zj6GYf4DbZPuQK8+5LEZsRO2DYSeQUmJdL+FmIxNv05RLEFUa8iUKxDkduYLYP+e+QYmgfEscTvsoE5H41tSuA9dLNNojet8iiRYIAmX0PHFrF/jJ7vWLNEZZUOvHg0z+czBMMwvY/cocjLp/ujVW4HfHwyz3d4IQgSktlCYn4qlbX1Ig7/RvgbAHQAA//9iGV3GQgIAzxwwMTD8+c3w7/tHBvA2ThWNW5xvrC5/P3tc89ftm0Lg0Y5RMApGwSggsWyBnWCLXiL///kDfJgQCIMqNWZBYXAHk11VE9zxBN3hySIqwcAiLcvALCDEwMzHD74jGD7LOTrbOQqIBUgHWoH2YIL2JP15+QJyL+bTBwx/X70Edy5/PboHPuzn74f3DP+/fYXoYWFmYORgI9CiGG2MjYJRMAoGOYCVg6CDQTm5/rNpaF/ksnedza6pf+Hfp/cM/3//AZdl4M7mKCAMGBgYAAAAAP//7J1JCsJAEEV/THd2xiiCQ8D5at7UG7hQEFGCKNGA2hGkNYP0sJaAK6HeAWpTi091//rFtN+YqIi1qalXWrUT3A2FG7QWDudeFh/ncq2GTcDhBVnaCIL4DSt4OoDlXaLMbJLt84Q8FSjEDXK3AVst4TYCHSTk1n2wXgjW7oCNJuD9gRJLagRRCRXh/9pvjZ37ECFXu5fJGcUjNT+b4o7sEiO/mp3MQgKO1jxT3di/SfsIgvhf9DCpTpQ1fekNp4k3nq1qfhDpUDPGjXVWu5Bye5Ofmv0VAB8AAAD//+zduwrCMBQG4L9pelF8AUERHBR18jLo++OkS4tFcXGyuNTihdJam0riBUQo6Cjne4QQAsk55w9XL+Dky1XjqgrBy5VIsy0XTD/FnjOMPbcjwuCx+QSl0xJCfvf6s9P4rHheU6T+Ftj5SFYeNK6r+U6ZjMdrDZVsa48msHt9WK2ubPmnCwAplIV7XDZrRLMpkoWDZOkiO4QQ5yOgIv4z9c3XczZJM03oJq0pIeTPiHttyajWg9JgPDeb7QXynMkODzmrrs5Axt5S5kkBADcAAAD//xpdRksSgA5fwBptoGVvDIz/WcQk7nPZuqz6++XL9+8nDzv+un1NGXTKJCMHM1TPaBiPglEwCqgEYJfm//kP2UIOXbn/j+kTuKj5++UTw9/XLxj+vHnF8PPyeQZWeSXw0ltmIREGZl4B0GEHDEw8vAxMPHwMTNzcDIyjd3mOCABqJP37/o3h/5fPYBrckQTtwXyHmLEE3Y0JuqbkN/R+zH8/foLvl2OEVWOwG75Aq7RBq6Jgh1ONglEwCkbBUAeguhXUkWRkYGDi4gZtUXnGZeWwjV3X8AwjG/tn8Kwm6Bqy0ZlM0gADAwMAAAD//xo9IIgcAFveBhrh+As5iYrT0HQbAwPDg3/fvvD/efZYGTwaDDudavR6mVEwCkYBtQBsRBXHUOH/nz8Zfj97wvDnxTOG76ATbfn4wR1NVjklBlYJacgBQ2ISYAw6YAjcCRUUHu10DlMAWhoLWnINvoLkw3vwvkvQMljQFTugQ35+378DTisg+f/g2UvECfVM7GwMDOwjPQRHwSgYBSMBgMs+RkYGZgEB8DVjHPrGlzj0jPeyyine//fr57/R2zvIBAwMDAAAAAD//+ydwWrCQBRFbyYJWqURG0l1qbb4D+JKV/3bfoFf0W6kkC5Lgxkj0YVJXuTNBFwXdGF5h1kNs57HcOfeK7Gp18BRtdN+KL1BtGlNZx/F5HV++v4aUJaZMe3wwJYUPkEQbkUT0W5WZVVPYo8nq1L6gJL7DrcJil4f7ubTBglxl2cQQPHeYwC3x92eIfxoBPd5BO8ptP504W6g48E+KvXWKNuUaZSsXOZ70E6bQAvSKSr2YKaJVTR/f0BZDjo2CbJ+48H01MWDCQmaEgThv2K/btRFDcer4Y9f4u7ybd1ZrN7daBhDKWLrnDkl9+DfAXAGAAD//+ydTQrCMBCFX5G0VbxBUSl0IRapIB7AnafzYuJe0IooiOCm7co0NZHpj7gWXYjznWFIJnnvzXAn8QHoN0QnGS1kd0RvsHUns7XJ5VSmqUcDParS5IcmwzBfolkrYdVDWsTruVMNbLlnSalwkaJV5c7tMutJiiatpiB7rfADuMMxnDCC8QMIrw8IDub9AjpNoI57SLLBHmLI3QbF+YTieoHJc7qf6mFTqvrBJ1dOab7RsDo2Wm1TFw03UwzD/BHaPCMCFC9xR9GqO18snTCKoZTR8oZG1eRO/g0APAAAAP//7J09C8IwEIYv/TLpYhEtfoB/wKWT/98/4NjBRUFRcSlSKUY0kbuk4F5x8Z6xc+HyktzzctjsijG+tiCGcJg3sp+tA6nU61oNHvvdzNY395Pi/GYZE8MwP0X4Dk9nz8PbTvCOl/athfCOgyCN4Xk5kYlUb0qIxhOIcuzwzNxup0ppj0VIRcIhEhKplKREFFgxwCYcTL+GNWC0duFQa7BYuYWBUd/pBtM2DZimpg5W6sHEG018Fns++g7Mg/tGM8g76+BDIxC0+5fC7V+y7IJhmH/CD0Gr3TpcmI8quSi2sliuoum8DJIeGDzjc6VhNwDgDQAA///snb1OAkEQx/+73IVdyGnQCA0FCa8AjfG5fQobGiw0aGwkfIVblPWS3TszczGiJSY2zK/aR9j/x8yI2PwL9ImjrXw0Q2UMfb6CMmamm9YXT4/j4uH+JrzMUPnaUVYiNgVB+G/IDKM6LO1zSQ982d91IKVrcZJvUUwnnH5qa6HaZ0h4wdAlz3mq8wsk3R4aVL/tXEG3W1zF1aYFnWXQLEYzCciOJZaIbzkq/47oHN+xjC5Hud8jug0nmGG1RLle1ObA/JVrszSbyZ+iEDitJJOTtsdq2/y+Gwf8fEslTBCEU+XrrDBpzQRI+4NnO7q+TQfDu+rD27hznptCZMZVkmkeDYBPAAAA///snTFuAjEQRb+NwdqFwEY0EUrFMZCQuHSaKE1OkCINEh0HCCC02tWCbfTHAdEnUorMa2ZX9gVmvv98bTZ/C9vjZD+Zfv/knmbbcrF6iU1dNO+vy/bzY44uyNM23U6rKMqfcd9c3AX4S4lnpDaKzzN1EDWMDSozhXsjD0tfZ/WYN9nS81mOYMcVbFnAcLMtm0wqnwMvyifVTlFAqYg+jOWMTajxPqukXEj0z3Ke04nPWVuE+iiVHkoqlYleyraRPEs+d411roHnTf6PvE/vJe9y4c9hj7j/QtgxniRnsBr3rVa6/C2q5XXIqd5LRVGUG+kcYEyCGRZw0wnc7Hljq+rNeL8G0MnwTrODfw6ACwAAAP//7J1PC4JAEMXfum5ZlwKR/h2CDlGXvv+1z2HgKSLCgiLC1DVmh0qiWx2C5gcyoAcvssyMM+9JsfktKkrScu4oF4UKZoulgkqqNDXXZDUpsz2/SPw3BUH4BV6KD+7gkn8igHbN5okuT7k/bUV2AXYeFzA0f+sb3vukUVqygtKanxkDzxi2XAkj+KMx/Kjn1HC9Ttfd0xRJBTdo/cXnQEUj7U+Sn2W+XbtYbDewxwNKUoM9pE4t1pLKOe1YOqGn3I1AVy6WvJJxt74pOaqgCd2wz+ZBPSmSBEkQBOE9dJ5qBb8foTmdp2YwjKssi+3peEYY2YcWgvAZAG4AAAD//+xdsU7DMBB9dhK1TQMMKFIlhASIgaFbF2Y2vpeFjS9gqdSxS4cKITrQUAnJwa7uzia0SwcYGO4tTqIMiYeznu69e0o2/xQh+jNNsGXZFBdXs/7k9tEtF9ef0+fL9vWlpm6BGWQ6nFahUPw/7He/iMAQuSFpJntX0GV7+qjTSGdxsvyF6Ae0gD0assQ2r0c8/TY/rWGGlXRIqet5fCIdz7KCKQoeRsTeT7rOcpb/sp+QSGwmZDYR2kRuOQqGSbGNWZDdahJZ/q61h4pu4GERIa38z0LwhOTJPa+R/O2QQSfkkKWs9Nw5eYdyLSnTkuSuzRotTYLljMsV/GaNr9UbfPMO/7GRDqXf++TwY69Nt78sjbbRb6meS4VCoTgMHlog54LpDdC7Gc+ru/uH4uz8KQBLsowYztOket8CzquM9jcAsAUAAP//7J05DsIwEEXH2ZcroEiUFBwAGg7B5bgBV6HgHPQBIpTFGP2xk0gRogAaxLzGjlM4iqLY3575FrH5bfABa83W8vfq6kXF/JitNnt9OW8hNhGepv5jIV8QhF/HiTXe9XSD7eBy24+9zxxMnQKFAMPxG011dQKxF0Y+Kd4ZxXVAHnLek5QUcj7TnFSekxenPBHwkphDc1GHARHnx4cIxU1sO9qUFaGswHx3ZAcLVH90QOqf+xX3MdeRBXaHiUbt6i2ZtrOhsF1Dpm6sWQ9Me24Vh7kOJQx8cK9CaU19ELIFB1gz9KGHvrgdef1x5Ex8zOSNmkkGhuxeCoIgvAP+uRgbVBTwOdPxYnnI1ptdOCtOuiyV8gPDi5naLTAKn0FEDwAAAP//7J09DoJAEIVnF3ZJ4A4q0QtYGAvjlT2Pxtao8QICYcHMDyCxMRoLk3kNlAsF4Zs380Zh81fCn5SmbUyaHTHR0c3mi/pyWtbXWwah4MJKrO20KpXqTzSCGjPwzqjiK1Akez/Z8WvJrSMnNAjvSTpq59rhjKFNMBE3orZag2FDWFl2CViESe/ontp1vQeL61hw9tM5SgI3ArB0xkhANrK98/m2s0ngJy5mYHeS3cowOJb4TB14VgUnxSJMViXPW8oVygpC0fL8a91voOE52I6B7VMqrDV8bmNeAb5za1UqlUr1maSjsLkHsC6Am+bndL3dp6vNzk/yg8EOm9jzSBx+76mrRd/11wKABwAAAP//7JyxCsJADECTOymisziLYicXP8DF7/Rn/AFxF4cOfoHSQiGRS/AMVQdFByEP2qG5oVOOd5fEZfPb2DI05lQaRXQ5n3qj8aG/WFZN3M/b6hi5JZdNx3H+n1cSKqGgYpWFlO+Xop2pqBhQhFFuANME1jRdNU3ITbFcJqv9o7IezeAGK2f2e3jT0JifPJQFmuExLiffUm6la/UkHKVvNUYCHrDpp9QXgt0r7L+7UTqO4/wG1BzdaEovJrPdcLXeFNNyS3UNAVB75m/5vbOfOR8CAFcAAAD//2IZXYdMZQDatwNbbgYagefh+8cqLfuRRVr2+F9ldT4GJsbgv+/e6P199wFiL2zt+CgYBaNgFAw3gOMEVIwSD9Zx+/Mb2oGDnZQL7Z/+R5qU/I+GYVLoVRklxSqsnQFbugozCwsN30cJx4yI5cewJcijZfwoGAWjYBQMKPj/6zd4kodFQvgLm5zkaw59k4Nsiio7mQUEvjGA5X+N3qlJC8DAwAAAAAD//2IBH2owCqgPQHtuODgZWCSkwGvCmXj5rv99+/rV72ePpX9cu6wH2tMDaoCApurBB1+MglEwCkbBSAWwztl/aKcMvugDMg2KsX8RjaJ1V44RKwd9nyo2sdFO5igYBaNgFAwK8Osf+P5odnXVZ1wWNofYlNQu/fv+7c+/Tx8ZmHj5IVsu/o32iagOGBgYAAAAAP//YhntxdMAwK4SAO0n4uAAn6rIxMHxiYmH9xOnqfWWP69fyXw/ulfv5/3bMv+//WNg5Bmd3RwFo2AUjALMcpDwMqbRknMUjIJRMApGAU4AmlQDnVrOzga+dotVVvYqm7zSemZ+wUsMf//+As9oIq1IGQVUBgwMDAAAAAD//2IZDVgaAtDR+f//gBP6P1Aw//rNwKasdoLHyePT3zcvMn7cvhEBuoybifsf+ETG0SXNo2AUjIJRMApGwSgYBaNgFFAHgM8BYGVkYBYUZGCRlP7LyM5x5++nj6eZuHk+MbGzoW33GO0TUR0wMDAAAAAA//8aXb9JU4A4mRF0WiGo88ksKPyaTV37IKeJlezvp4/Uft18IP//7ydh0OlX4KOWR8EoGAWjYBSMglEwCkbBKBgFFADogXSgiU0e0H2a2k85TK2OsIpJHGTi4nkNWjrLyMUNnvUEX3PF+BNyCu0ooC5gYGAAAAAA//8a7d3QC4DPuf/L8O/LJ/AdbGxKahd4PQNXfOXa7/Pj4nHbf59/MjJyjy6nHQWjYBSMglEwCkbBKBgFo4ASAL5PEzRTCVo8yMnFwKauc4jb3m0ii4Dw/X/fv0G2urGygre6ga+u+v0beifXKKAqYGBgAAAAAP//Gu1s0hn8/wG5j41FWOQmo7b+z79vXor/ef1U5/+ve0Kg4RfQdP/olSijYBSMglEwCkbBKBgFo2AUkAf+//7LwMjFycCmLP2cw9jyDpe57Tp2de2TTJzcDH8/vAXfqQy+qurfX8jM5n+M0+hGATUAAwMDAAAA//8a7WzSCyDNWIIS9/8vn//8+/jhGSMH1wNWeaV3/799Ffrz4inD/19/GRhBl5GDLyIf3cM5CkbBKBgFo2AUjIJRMApGAXEAunwWdFUzHwsDh4nVfj7fkIVsShpX/n//xvAPdCDQ798M/5HvTGYYPT2cZoCBgQEAAAD//2LBvJxsFNAEgE/9/Q8+dpmJg5Ph368f/5m4eb+ya+icZxaV2MLExub57cc31X8vXjOBrQepH034o2AUjIJRMApGwSgYBaNgFBAFwJM2bCwMzMK839jVdZ5ymdvu4jC23MXExsHw98M7hv8MP0evqaInYGBgAAAAAP//7N2xCYAwEAXQL4lJpyBYiAPEuV3FJQIWDpBOSEDQRJLCzjbVfzsc3HEfvuT3rJLSZ5rQyBai60t+PA0jlNI2Br9Gf+prt+Z2rmTGS9Y8929yAIiIiIiI/uV9Obc/+AghHqjF5ENzk9N8pBAQv6pH7tVVAXgBAAD//xrtbNIN/AMncPCJs6xsDExMjOClskw8fG8Z/v9/++fd601/X71UY2Bk0P374qno3w8fGRlGt26OglEwCkYyO4j4AAAgAElEQVTBKBgFo2AUjIJRgB/8hawIZOJiZ2ARF33Prqp2mk1FYyMzL99d0IFATOCVnNC7NEf7PvQDDAwMAI3u2aQbQB5J+Q8+8IqR4R/D/x/fwWkefDqtV1DX/39/o77s2hz//+VHBkbWf6C5UMhpWqMznKNgFIyCUTAKRsEoGAWjYBQgAKh9/O8fw7+fvxkY2VkYWMRFGFjklD4wsnNe+Pf505l/3768Y+QTZPj//x8D4//RzibdAQMDAwAAAP//Gu1s0hsgbUYGdTghJ2AxMLCIiL1gERJ58ffDO7Y/z59p/f/2Tf3fj+98DD9+MDCATqcd7WyOglEwCkbBKBgFo2AUjIJRgACw5bGMjKC77H9zGJk84zAw283ExX2UiZfvGSMbBwMTGzsDEwsbA2xyc/S4GjoCBgYGAAAAAP//Gu1sDgbAyMjw/+dPcIZhlZG7ym3nsvj/968B304fdfr76T8Di8BfBgbQCbWjmWMUjIJRMApGwSgYBaNgFIwCyOTNv78MDEzM4JscWETFmTgNzXbyOHkuYmBhu8Xw5zcDEzc3AyMnN+Rawf8MozOb9AYMDAwAAAAA//8a7WwONAAnegbIctpfPxmYefkfcugarv779hXr3w9vJRj+3FJgYPzNwfDnHxO4wzkKRsEoGAWjYBSMglEwCkbBSAf//zP8+/WPgZmf+z+rvNRHLnPbC1ymNuvYdQyPgkLm//fvkHs0QbOfox3MgQEMDAwAAAAA//8a7b0MJgBadv7797//v3+9ZpWWP87t6LGO09j0IiMr68+/n/9AltyOLqcdBaNgFIyCUTAKRsEoGAUjHIDaxX8/gMOAkdPIYjuPq+8EVkWViwzwzuVoB3PAAQMDAwAAAP//Gp3ZHCwA3IlkBM9w/vv86S8Tv+BFTmPLL////GX58+a51N9Pd+UZmEbv3xwFo2AUjIJRMApGwSgYBSMcgK4IZGf/xyLK8o1NQ+cWl5XDCk4Tq01MbGwM/758gszgjM5mDjxgYGAAAAAA//8avfpkMABwFEAODvr/9w94Oe3/X7++Mfxlu8/IwXGDVUb+w9+PX+T/fXrN8O/HbwYmVmbw+vTREZtRMApGwSgYBaNgFIyCUTBywH/wNSf/vv9lYJES/M2hY7aP28F5E5uS6lnQHs3/0O1po9dpDhLAwMAAAAAA//9iGZ0lG2CAHP5MTAyMoBOzuHgY/v3/DOp8fmERk7zOaWZ9ipGNXfTHpTPC/54+Zx9dGjAKRsEoGAWjYBSMglEwCkYUAB8I9I+BgZn5PxMPyz82JbV73I5Om7ltXRczsLH9+vvxPbgNzcjBMXoQ0GABDAwMAAAAAP//YmFkZh7pYTCwADYCAyIY2UDHNjMwsbMz/P/9CyzExsR09//v3ysY2dj//H50P/73/ecM/xn/gu9NAccd4+i221EwCkbBKBgFo2AUjIJRMIwB6OaG378Y/n9hYGAWZmNgU9N8yWlkcZZFQvomAyPjL/B9ggyjfZpBBxgYGAAAAAD//+zcTQpAUBQF4OPvkZ9CyRIMFBPbZwfmMjbDkFfKo2dgDdL5VnCnp9O5Nhg2P0OHRyt2gSR9TzL9cAXQXVKqYxyqc50btW+OkhtTJhERERH9n24p9YRM4LKzfPHKuneLsjWENz2NZhACkeBfk68BcAMAAP//Gl1GO9AAlHnAUQCJB0YmJkhmQosXNkXly7w+IdMZ2Vg9v504FPjz9k0uBsZ/0IlNxtHMNQpGwSgYBaNgFIyCUTAKhhcAzWj++cPw//dfBiZOdgZmaTFGFnnFx4zsXPsYfvw49v/nj1fgGU/QjQ2jV5wMPsDAwAAAAAD//xo9IGgwANgyWhD59y8DAwhDAXg5LWiGk0/gLZety1IGZqaXf79/V/j78b3lv69fGP//+MEI7qCOdjZHwSgYBaNgFIyCUTAKRsFwArB+CiMDA7Oo+A92XaM37KpaJ5jY2A/+//f3FhP0vBNGFhbw2Sej7eFBBhgYGAAAAAD//xq9+mSwA3gmY2RgZGVlYFNUOcfj4j2T4ffPV9+O7HP/9fQbFzPvPwZGLraRHlKjYBSMglEwCkbBKBgFo2C4gH//GP7/+cvAwMzIwMTBwcCmoPye28ZxPaeeycb/f/7eYWRihBwIxMPLwMjKBj7zBETDO52jHc+BBwwMDAAAAAD//xrtbA52AM0o/358Z/j/8QMDIyv7Oy4jiyX/P3/8+ufRfdk/T96ajO6HHgWjYBSMglEwCkbBKBgFwwr8h1wLyMzLx8AiLs3AaWB6nsvYajWHnvGR/3///v//8wf+DuVoZ3PgAQMDAwAAAP//Yq6vqhzpYTC4ASyjgJbWgtajg7Z4srKA7uP8Ch69YWRk///rm/Dfj5/ZIXs4R3ueo2AUjIJRMApGwSgYBaNgiALQvfOg/Zegtu8/8Lkln7ltXTbxuHivZFPRPMrEyfUDvIWMlZWBkZmJgZERgkfv1hyEgIGBAQAAAP//Gp3ZHCoAuhwANIrz9/tXBiZ2jtecVg5rGTk4/n3e81v47/s3OuBchrTsdhSMglEwCkbBKBgFo2AUjIIhBaAzmkwcnAyMXNwM7FoGV7lsXOax65nsZWRm+Qta7QdTMwoGOWBgYAAAAAD//xrtbA41AMpYoJEeZubvzGwc91ll5U5w6hvr/P/6RfTXo3si/95+YWYETXiyj+7hHAWjYBSMglEwCkbBKBgFQwSAO4//IafP/mFgYFGQ+chpZrOHx8lrB5uK+gkmdo7f4BnP/6Onzg4ZwMDAAAAAAP//Gu1sDjUAmrFkYmL4/+sXw78fHxkZ/v5/yqasfvzf1y+y/759Nfj59osI42j+GwWjYBSMglEwCkbBKBgFQwlAO5uMLMwMjOwsDOwaOtd5PQNncZpYH/7//cuvv29fMTCCDgRiZ4d4arTDOfgBAwMDAAAA//8a7WwOZfDv338GJqYXTJycR1nEJLnYNXTZGP4zWf9985z535cv4NO7GFlYR3oojYJRMApGwSgYBaNgFIyCQQ7+/wLdp8nAwCIt+p1dS+80l63LGjYVjZPMfPzf//z6ycDw5xdkVnMUDB3AwMAAAAAA//8a7WwOZQC56Pb3308f74B2RrOpqMsysbIp/7jyT/zX5y+jd6iOglEwCkbBKBgFo2AUjILBDaDtVTDJwsDAKqd0j9vWdRWnvsl6BgbG73/evASv6APNeI6eSTLEAAMDAwAAAP//YhmNtEEO0OMHlCFB9w79/Qs6kZbh/+9f//7/+P7r/59fNxiZ2bYy8fExsYhJePz7+EHz75fPIHnwsltG5tFxhVEwCkbBKBgFo2AUjIJRMLjA/1+/IXs0JcXes6trXeSysN/GpqKxm4mH7xkjMzPkNgbQXs3Ru/6GHmBgYAAAAAD//xqd/RrsAMdgACNsBAjEAh33/Pffv38/vpxi+PfvM4uEjNj/f/81/z+4y/D35UvIkoPR/DkKRsEoGAWjYBSMglEwCgYN+A9pzP5lgFxxoqR6l9czcAm7hu7Wf9++fvzz7jUDi7AYAyMr9+iM5lAFDAwMAAAAAP//7N0xCsJAFATQ2XVNXFYsDEgwYGdjayXe2SNYKJbeQdAibZBg9CdZ2ahnUGHeFX43w2fMKymgn/W5TwgFlIKKImg4QCtoN4QaWPTGCdp02qKuS980Rx3bjZxP/fKwXd+uRearqmtBuw2isEtERERERPQN78bE3wU+DCyMnJhsltvlah/PFzuTTHJ5XAAR/mj+OwBPAAAA///s3TEKg0AQBdDvIqwkmAt4ghSewCYnt9UrCKkCghISxdLd2Qmr3iEI/5VTzAVm+D+N8cJ0AqqIBbZJlkGthbnm2ywNshffhiMG2hiY/Favz26UZbKufxV+6Ld+TsW+g4iIiIjon4IHEonvs8XnUj1aey8bFT/L9w317kid5UXz1AD8AAAA//8andkcKgC2fICFhYGJEbp0FnoNCrgDyQTlMzP/Z2Rh/cCmqnGU29FD4f/ff2zfTx4y+HH9siTDz98MDMzQ+B7tdI6CUTAKRsEoGAWjYBSMAjoD0IwmaIKEWYDvJ6uE5BsOA+PDbPLKW5n5BU4xMDK9A3U0R7f5DRPAwMAAAAAA//8aPSBoqAHQ4UAgJzMiBgn+I8chaKktqCP5/x8jh77pLgZWtsf/f3wv//30seTfd2/g+kdnOEfBKBgFo2AUjIJRMApGAd0AqL36/z/D/1+QvZrs0jLvOC3sz7DKK+xk+P//6L+PH14yC4v+Y2BmG42T4QIYGBgAAAAA//8aPaJ0qALkER+00Z//oDXubGz/mfkFXnNo6b/+9+6N0r/PH3l+XDyr+fvxfVGGX38YGJj+QTL96GDDKBgFo2AUjIJRMApGwSigMQC3T///Z2Di4WJgERb6xaahfYlNUWULk4DgwX8f3t0H36AwOqM5vAADAwMAAAD//xrtbA5HAJq1/PuX4R/06hN2bcMd/3//es/w52/en9cvnP7/+gwZWQLtA2UePaZ2FIyCUTAKRsEoGAWjYBTQCEBnNBl+QlbXscqIMXDoGL5llVc+///P7yP/Pn98/h90EBDj6Kq7YQcYGBgAAAAA//8a7WwOVwDqTP78AfYcs7DoC3Ztg63/v3+XZGBkYPlx5bz676cPxUFr5uHLaUdnOEfBKBgFo2AUjIJRMApGAbUB+DDS/wyMHKwMTLw8DCxSMtdYxCT2M3Fy7fn/+/eN///+guVBNycwgNig82T+/kUcfomMR8HQAgwMDAAAAAD//xrtbA5nwMTIwPD7L8Pf928Z/v/585fTyGIrs6DwPUZWtvw/r557MXxD2oA92tkcBaNgFIyCUTAKRsEoGAXUArA9mr//gg1kERVmYJFTYGAWFDr179uXRYwf3t9h5ORiYGBlhVxx8vs3w/8/oLtQ/oA7nv+xdTgZRjucQwowMDAAAAAA//8a7WwOawDN5D++g+j/LFIyj5mFhB//+/he5s+719I/r12S+/vujeD/338YGNlYRzuco2AUjIJRMApGwSgYBaOAOuAvpJPJwMzIwMzLx8Cub/SU08TqFDO/4Ob/P3+cYuTgZmDi4gLftAA+nZaXn4FZUJiBkZWVgZGLm4GJk4sB3BllY4OsxGNhhiy1HZ3hHDqAgYEBAAAA//8a7WyOBAAdWfr74T34tiJ2Td3dvN+/gsQSvx7ZZ/PvBwMDM+voDOcoGAWjYBSMglEwCkbBKKAQwGc0/4BX2TGyc4CWzjJwGpkf4HHymsksLHr737evkA4k6OwQsHoGBkYWVnBHE3z2CGg5LRMzAyMrGwMjMxPD/3+gu+IZwWKIWc5RMOgBAwMDAAAA//8a7WyOBADL9N+/gUeHmEXEHnPoGq/9++Uz//8/f3h+3roq8+/DexHQKWHgTD7a4RwFo2AUjIJRMApGwSgYBeQA2IzmfwbwzCWbmtYrLiv7s1y2Lus4dAwPMyAfTonUafwPWjIL6mT+h7Vd/0HEQAdawhT9G+1oDinAwMAAAAAA//8a7WyOJACb4fz0keH/r19fOPRNNrMIiz77vGND4td9O9z/f2VgYOQfneEcBaNgFIyCUTAKRsEoGAUkAtjkBvhAIEhnk5mHDzSjeZzXzX8Sm5r2jf9/fjMwMjJCDgP6/x+6BfM/YusXbF8m7ARbjI7laEdzSAEGBgYAAAAA//8a7WyOJADtQP7/9hV8YBCrtNwdNmm5O38/fxL58/ql8q/bt8T///zOC7ouZXSGcxSMglEwCkbBKBgFo2AUEA1As5AMkAMqmXj4GFjFpV5xGpo95HH0WMdpZLaPgYWNAbR89v/vr6NtzJECGBgYAAAAAP//Gr3QZiQCcAb/D76H89/PHwzsalqHeN3953Jo6d0EjTT9+8IAORVsdPRoFIyCUTAKRsEoGAWjYBQQAUAzmqBrTBgZmRiYhUQZuGydD/IFR9dx6BofBO3fBE1mjC6BHWGAgYEBAAAA//8andkciQA2wwnaw/mPnYFFVOwyh6HZ5/8/frD+//Ob69edm5L/fn4TBM9wsrCO9NAaBaNgFIyCUTAKRsEoGAW4AKwD+fc/AxMXNwOrrPxbTlObGzxufms5rRx2gNqS/z59ZGD48xtywM/orObIAQwMDAAAAAD//xqd2RwFDP++fgXt4XzBrqW3gS8wspvTxPIUaFLz36f/kI3aozOco2AUjIJRMApGwSgYBaMAGcAmL0Azmr9/M4BuN2BkY2fgNLI4zOsT3MauqXscdHcmw6+fo23JkQoYGBgAAAAA//8andkcyQBaSIDXz//4/oNFWvYym6rW5f9//nD/efNS6efNm1IMDL+5GUDLHkZnOEfBKBgFo2AUjIJRMApGAQyA9miC2pKMkD2aLFJ87zgMTJ5yO3qu5TS33cbEzsHw990b8IFA8CtORsHIAgwMDAAAAAD//xrtbI4COPj/4wfDf1Y2BjYltRPcLt5ijKzsvj8unjL8++k/AxP/XwZG5KOqR8EoGAWjYBSMglEwCkbByATQU2fBd2X++8fALCTMwGXjtJfX1Wclm6buWYY/fxj+/fs2mjhGOmBgYAAAAAD//xrtbI4ClBlO0EW6zMIiVziMzb////mD6f/P79y/7t6W+v/vDw94rf1oh3MUjIJRMApGwSgYBaNg5ALY9ST//jMwcXMzMIuKf+Q0t7nF6xm4htvWeS0DMxPD33fvwMHDODqjObIBAwMDAAAA//8a7WyOAgzw/+ePnwx//j5gV9PcyMTH9/L70YMB308dcf774S/4Hk5GltFkMwpGwSgYBaNgFIyCUTCiAKjT+O8f5B7Nf/8ZQBOXzCLsDJzmNnt5fUOXs6vrnP7/9y8DeJ/mKBgFIMDAwAAAAAD//xrtNYwCBECa4fz35fM3FnGpM6yqGtcYmZmZ/r57Lfvz9005BpZ/HAyggoRp9GypUTAKRsEoGAWjYBSMghEDwHs0GcBtQCYe7n/MouxfOY0sHnA7e6/isnJcwwia0Xz/FnIWEKidODqjOeIBAwMDAwAAAP//Gu1sjgLsALQW//dvBsZ//76xKagc43byFGZk5/b+cfWc8d+PPxmYeBgZGFlByWe0IBkFo2AUjIJRMApGwSgY1gC+R5MRPKvJLCrBxGVus43H2Wszu6b+CciM5+iM5ihAAwwMDAAAAAD//xrtbI4CTAA9Wezfd8geTiYBwaucptZf/zMwMP3/84Pv582rsgz//7Mz/P3DCL4vaRSMglEwCkbBKBgFo2AUDG/w/z8DIzfvfxYh0R9cZjZX+HxCV3BZO24ArXj7++kDZB/n6IzmKEAGDAwMAAAAAP//Gu1sjgLc4D90E/jfv98Z/v+/z66qsZmZl+85s6i4z/fTxzz/PP/AwMT9lwF0We9owTIKRsEoGAWjYBSMglEwjAB8j+Zvhv9/QbcWMDCwSPMzctk4beX1DNzIrqF9GqQGvE8T1F4cbQqOAnTAwMAAAAAA//8a7WyOAtwANsMJ3sP55QezsNgpDg29s0w8fD//fngn/+/LGVVGZkYWhn//GUc7m6NgFIyCUTAKRsEoGAXDCIBPnQXtv2RmYObi/McowvGHw8D0Oo+r91JuG6cNoE4mZI/mf2ibcTTyRwEaYGBgAAAAAP//Gu1sjgLCAFSIwDAz8182BeXjPI4eSxmZWb1/Xr1g9ffVZwZGLgYGRtbRGc5RMApGwSgYBaNgFIyCoQ1AM5p/IafOMkI6m6yyCj84TSw3cTt57ubQ1DsNXi776xeifTja/hsF2AADAwMAAAD//xrtbI4CwgA6w/n/2zeGv+/eMDBx89zjNLVeBtor/v/nD7Gfvy4qgUumf/8gJc1ogTMKRsEoGAWjYBSMglEwRMF/uLOZePn+MwuL/ee0sD3P6x26iMvCZvv/Xz/B7UGwstE23yjABxgYGAAAAAD//xrtbI4C4gFs9IqB4QcjM8sDdmX1ncwcHJ+/i0l4fDt/0u33o1esTBwMkFNqoR3UUTAKRsEoGAWjYBSMglEwBACo3fb3L8P/33+gHUkGBlYp2e9cNs5beNx8t3Jo6pwBndPxHz6jOdrZHAUEAAMDAwAAAP//Gu1sjgLiAfyU2m8Mfz9+YGDmFzjPoa51nkVY9O3fr59l/759o8c4ev/mKBgFo2AUjIJRMApGwdAD8D2aDAxMXDwMzAKCDJxGlpd43QPmcVrY7mL48/v/37evGf6D79sc7WSOAiIAAwMDAAAA//8a7WyOAtIBeDTrH+h46/+MnJwMbMpqx3icveYxMLP4/Lp+yf7301esjKDtm6zMDAyMo0dgj4JRMApGwSgYBaNgFAxaANoqBboj89c/BgYWRgYmTm4Gdk2955zG5ge47d33sqlrn2FkYfn//+8f5FVuo2AUEAYMDAwAAAAA//8a7WyOAtIBeIaTieHf9+8Mf16/YmBi53jKaW67iIGF9duXf3+l/n75pMXw5y+kQzoKRsEoGAWjYBSMglEwCgYvQOo8MvHxM7DJKjBwWTue5nHzncWhZ3zs/69ff/6+f4d06izjaIdzFBAHGBgYAAAAAP//Gu1sjgLyAaig+fcXdErZHyYOtvfsalr7GdnYOFhExB2+nz/l8uvePT5GJtA9nEzQS35Hl9iOglEwCkbBKBgFo2AUDAoAmtH89ZPh/y8GBiZOFgZmKQkGDn3ju5yGZse4bJw3g+7RZGRh+QW+RxOER1eqjQJSAQMDAwAAAP//Gu1sjgLyAXSG8/+P7wx/v35hYOLgeMBj7z6XRVz6zr/fv6X/vH5h/v/nT6RN5KNhPQpGwSgYBaNgFIyCUTAoANqMJquC8mdOM+sj3PZuM9nVtc8z/Pv769+XTwz///yDTBowMIzOaI4C0gADAwMAAAD//xrtbI4CygGo4AGNeDGz/GHiE/jDrqFzjMfVZwEDE+Orn5cv2Px+cEeQ4Q9kHwAjEzOiwBoFo2AUjIJRMApGwSgYBfQD0IH//z9/Mfz/ycDAxM/BwCov+4tVWuYKs4DgKSZevq0sohJnGFnZfjP8/8vw/+eP0Q7mKCAfMDAwAAAAAP//Gu1sjgLKAWiGk4mJATSL+efVcwYmLq6vXOY2y5jYOR5/YWQW+vfxnfW/z58Z/v/9zcDw799oZ3MUjIJRMApGwSgYBaNgIACs3/gPwmYWFvvLYWD0mFlYdPe/t29W/X3//ubfD+/+sohLMvz/8wd60OO/0Q7nKCAPMDAwAAAAAP//Gu1sjgLqAVBHElQwgWY4ebg+sWvqHmZgZJRm4uN/9ePiacuft65J/P/xk4Hh3y8GBmZmBkZm5tHAHwWjYBSMglEwCkbBKKATAM9o/gZ1Mvl+s8oqPWBX07zEIiNzmeE/455/TEznwGdxjHYsRwG1AAMDAwAAAP//7NkxCoNAFIThecHFYHoxLOQeabRJk7NaegRvYOcNNiISQohk2cdKitxgsZrvFv8MY5PS+T+c3kPfL4gcPsW1brOyGiXPj/pc7jo56PqF/FYyxiYRERHRbqICUMDYy+PU3Hpztl1YpiHMs4shCERYmpQOgA0AAP//Gu1sjgLqA9AM5+/fDAycXH+YhUXfs3NwHfr/84cCAxPTn5/XLur/vH1D7t+H9+AT0ECdU0YWFsgegtHibRSMglEwCkbBKBgFo4C64P9/hv+/foNvpGMW4PvDKiN/j9PU6gCbkuoORjb2Qwwf370Dr0wbbYiNAmoDBgYGAAAAAP//Gu1sjgLqA9gM55/fDH9fv2RgZONg5NAz3sLIyX2PWUA45/+v33K//t5k+PPmJwPD338MjKOpcBSMglEwCkbBKBgFo4D6AHwjwH/IjOZ/BgZWecVX3Haue9mU1Tcz/Pt76e/7t5/BezNHz9MYBbQADAwMAAAAAP//Gm3mjwLaAfBI2i8GRi6ef8x8/G/ZlNQO/7p7U5xZSISB9d9fHSZ+AZW/r16w/fv0hYEBtP+clXX0DqdRMApGwSgYBaNgFIwCSgGsk/nrD3j1GKu0xDs2ZY3LHIamR9lUNA8w8/Cd+vvx/cf/v3+N7tEcBbQDDAwMAAAAAP//Gu1sjgLaAtBI2d+/4BPN/n56z/D3w7v9DAz/H7LJK4cySMtH/bh8Vvrn2ztgJzCyjsbFKBgFo2AUjIJRMApGAeUA2tn8zcDAyMbAwK6lf5PPO3gGs4TUsT+vXn7+8+71V7AVozOao4CWgIGBAQAAAP//Gu1sjgL6ANA+TtBdnL9/v2VgZHzLzMPLxsjFzcL2+6f5fwYGzb+vXwv++/YZXDCCZzhHwSgYBaNgFIyCUTAKRgFp4D/kmpL/f/6Cz8RglZN8x6akepvbznUlh57xzv9MjO//vH3D8P/rTwZGVrbRwB0FtAUMDAwAAAAA//8a7WyOAvoC0DLZf/8Y/n39fJWJg+MTm7LGC2ZBEeafF88Y/bh6kZXhD2hDwWicjIJRMApGwSgYBaNgFJAK/v+F3on5l4GBkZudgUPP6Ca3g8ccdi39Xf9//fr29+snyOD/6IzmKKAHYGBgAAAAAP//Gu1sjoIBAf9///7AwMDwgZlf8B+zgOAfRjbWu4ycXDq/79+W//PmNT+4kORgGS0MR8EoGAWjYBSMglEwCgiA/38hJwD9//ePgZmTi4FVVuE5u5buLS4rhw0c2oabmPgF3/z78I7h/48fo3s0RwH9AAMDAwAAAP//Gu1sjoKBAbAZzs8fHzJycm7g0DY4wSojb/F195aoX49fG///ycDAzPaPgRGkbvTQoFEwCkbBKBgFo2AUjAIsgBGydPbPX7gUE58AA6eVw0leN58pLOLSd/59/vTp7/s3UMnRNtUooCNgYGAAAAAA//8a7WyOggEF/3/9+MLIwfGFWVjsHqus/Iv/376y/fv+jeH34+dy/358EAXdxcnIxAxx4mincxSMglEwCkbBKBgFowAO/v/9DR6YZ2RnZ2AWFGJgkZR5zK6p94jH1Wctp5nN3v+//zD8unGF4f/37wyMHByQzukoGLKngzkAACAASURBVAX0AgwMDACNdjZHwcACRkaG////M/z9+J6BkZnpBaeR+WpmUYkH348djP96dK/H36/fGf6zQg5VA210HwWjYBSMglEwCkbBKBgFEPD/5z/wWRcsAsIM7Oo6f7ks7fdymFguYVdRvwFaMvv300dwO2t0wH4UDAhgYGAAAAAA//8abb2PggEGkMLv//dvDP//CnxjlZG/yyIl95CJm5uXgYWZ78els0p/nj+V+PvlKwMD41/IstrRfZyjYBSMglEwCkbBKBipAHylyR8GRmZGBmYBHgYWUfFPzILCr1gkpS6wa+qu5TSy2MvExcXw59VzcPuKYbSzOQoGCjAwMAAAAAD//xrtbI6CwQFAheD//wz/Pn5gYGDn+MOupbebWVDkARMXT9rn7etD/r/5ClorwvCfiYGBiY0V0uEc3eA+CkbBKBgFo2AUjIKRBkBnXnz5z8DI/p+BQ0WegUPX8N7/X782M/z+vf3f54/3/33/ysDEzjbayRwFAw8YGBgAAAAA//8a7WyOgsEBoIXhv29fwXOdrLLyD9jklB8w/P0r/O/bV+mfV8/L/v34Ufzvh7esoCO7///+zcDIzDxaiI6CUTAKRsEoGAWjYGQAUOcRdG85CwsDizjvNxZx0Tfs2vp32BRVD/958WzN308froDOvfj/8yfD/z9/IEEy2k4aBQMJGBgYAAAAAP//Gu1sjoLBBWCdzs+fwIUqu5beUQFu3jc/Lpzy+37mWNT386eEfz9/wQA+rZaXEVzgjs5wjoJRMApGwSgYBaNgWIP//8B7L/9/+8vAJMDOwKFv9JRDz3A7M5/Aif8/f1z69/3bI7D3R/uWo2AwAQYGBgAAAAD//xrtbI6CwQWgnc3/374w/AeN3MkoPmaVVXjMyMHx48+blwJ/3r22YOTm5v7z6rUAw6/vXJA9C0yjI3ejYBSMglEwCkbBKBh+ADSgDupk/vkDPk2WRVbsLZuq5lMuS7s9bMrq6/9//nT214M73////AE902K0PTQKBhFgYGAAAAAA//8a7WyOgkEKoIUl6JLi/4wM/75+uf7/189ZrPLKx9h1jXV/Xr3k8uPsMbW/H/4yMPP/ZWBkYR3tcI6CUTAKRsEoGAWjYHgA6H3k///+Yfj/G3RqPwMDq8R/Bk5Tq6PcDu4rmAUEb/379uXBv29fv4/G+CgYtICBgQEAAAD//xrtbI6CwQlgM5y/f4EL2n+fP779//PnERZhsbPsWnpmzJzcf/99+fiP4d59aYb/v3gZfv9GnFI72ukcBaNgFIyCUTAKRsFQBqDBdtD9mcwsDEw8XH+ZRdg+cGjrPuR28lzHZW6z/O+b1ww/b1xiAO3RBIPRts8oGIyAgYEBAAAA//8a7WyOgiEF/v/8AVoqcpVVQYmBx93vyY9zp31+XDhh++f9DwZGjr+QJbXgg4OYIJdzjoJRMApGwSgYBaNgFAwVAOo0/vnD8O/7XwYG0An8nKwMbHKKfzhNbTdyWtpuZpNXuvjv5w9EJ3MUjILBDBgYGAAAAAD//xrtbI6CoQFgM50/vjP8+/L5DaucwkFmSZm7zDx8/xhYmLh+Xbmg9PfrZ77/374xQw4M+jc6yjcKRsEoGAWjYBSMgqEDYKfNMjEzMHGz/GUWEf3OKiXzncvC/hyPu99Kdj3DXf8+fWT4de82aHsRxFujbZ1RMJgBAwMDAAAA//8a7WyOgiEJ/v36xcDIxPyCVVl9B7+E9MPvsgpeXw/ujv558zYz+MpO0GggKzNklnMUjIJRMApGwSgYBaNgUIP/4Gvd/n1mYGDiZ2JgU1L9wWlmc5pDx/AYh67RCVY5xYv/f/1i+P/z12g0joKhAxgYGAAAAAD//xrtbI6CoQVAPUlGRob/376C7pH6w66qeYXNxOoKi5j4x/8/fyn8//fP8N/nD5z/Pn9iAx8yNHqh8SgYBaNgFIyCUTAKBjsANVfY2f4zsTD/ZJWRfsumrnWD09hyM5e1wyY2eeX7/3/9ZPjz4hnDv+/f4W2hUTAKBj1gYGAAAAAA//8a7WyOgiEN/v/5zcDw5zcDm4LyBV7fkEks0jIOP69d9vxx6awqqFD+++U3AxMHIwMjGysDvPM5CkbBKBgFo2AUjIJRMKCAEXx3JsO/vwz/f/9j+P+LgYFFQpCRXdv4Cru6xj4GFpZL///+Oc/w7/9jsCtHO5ejYCgCBgYGAAAAAP//Gu1sjoKhCWAznN+/Mvx994aBRVr2FZeN03pmEbH7jCxsbH8/vudmYGHlZnj5jJPh7x9Whr9/GUdHAkfBKBgFo2AUjIJRMDjAP4grGBkZmHi5/zJxcP1k1zG4x2nluJ1NVm7Vrwd3b//7+OHnv4/vwctrQXi0HTMKhhxgYGAAAAAA//8a7WyOgqENoBOVjExM4Ls2GZmZb/3/928li6jEHTYlVZlfD+5Z/Dh7zOL3s58MTDwMDEzc0JNqRwvrUTAKRsEoGAWjYBQMBACdNvvnHwPjP8gEJ6ui3HcuS4e1nIamBxi5ea7+//H9LsOfPz8ZWNlHV2SNgqENGBgYAAAAAP//Gu1sjoKhDWAznKBRv69fGP5+ePft36cPB5h4+Y5zGpoqs0rLv/n36T3nvy+XNBlY/rIwMLMwjRbco2AUjIJRMApGwSgYMMDMzMDIxMjAzMX7h4mf/y+Xue1JvsCIBeyKqgd+3LzK8PPZY4Z/P74zMHPxjA6Oj4KhDRgYGAAAAAD//xrtbI6C4QVAHUkw/vfz/9+/d1hl5Hfwegc/Z5VRcf15/bz7r/u3Bf//+gceSWRiZWJgYGWFzo6OdkBHwSgYBaNgFIyCUUA78P/3L/DeTCYedgZWcWkGDm3Du2xqWvu4TK0PsMkrX4R0LKHtkdGB8VEwHAADAwMAAAD//xrtbI6C4QVgM50/f4L2cv5iVhU9y23ndpZNWf3Fl/38wv///nX6++4107+vX6AXd44W5qNgFIyCUTAKRsEooCGAtjUYWdn+M7Iz/2eRkPrNKqvwidPEah+XrfMMNhWNS/9/fGP48+wJw//R02ZHwXACDAwMAAAAAP//Gu1sjoLhCeAXIzOC9nEysMkrneF1853HKiF16+fNq9Y/r5w3+PP0EcPfDz8ZGNgYGJg4WEcL9lEwCkbBKBgFo2AUUA/8/8/w/+9fhv9f/zH8/8nAwCov8JfD0PwUi6T0+f8/fzxnYGY+wcTNc52Jk5Ph3+9fkNNpRwfBR8FwAgwMDAAAAAD//xrtbI6C4QlAHUcmJvAM559XzxlYpWRecZnbrGRTVjvz7diBz/+/fxP8/+unxL8fj9gZmEaPFB8Fo2AUjIJRMApGAZUBIyMDIwsLAwP7LwZGFgYGNhWNa9z2rhuZeHg3/bhw+snfd2++/n335v8/cSnIVW6jBxiOguEGGBgYAAAAAP//Gu1sjoJhDiAznKDCnomX/z/znz93GNnZtzALiXziMLFUYZFV1P9994be72cvQRdxMjCyMYFPtgV1VEfBKBgFo2AUjIJRMAqIBoyQ+7z///rF8B/UdwQdgM/NxcCurfmUXVVrH4e+4XFWWYXjfz++vwE2EjSTOXpmxCgYzoCBgQEAAAD//xrtbI6CYQ6gM5ygY8a/fALt42T8++b1SUYW5hscaoaq/7X+eX/n4OD89/241r9v30YHFEfBKBgFo2AUjIJRQB6ALYEFz2j+Z2Di42VgkZRj4HZwPcnt4DaDRVTizO/HD/7+ffOK8f+vX//BM5kMow2PUTCMAQMDAwAAAP//Gu1sjoKRBv4z/P37h4GR6S0DC+sXVglxBmYX3zesMgqGPy6ecfh544r8v68/IeU/aESSdXQv5ygYBaNgFIyCUTAK8ADIKfgM/77/ZWD4x8DALMzDwCqv/IJDS+8qq4rGHS5jyz2sCspnGf7+/QW69oTh79/RvZmjYGQABgYGAAAAAP//Gu1sjoKRB6AznX/fvPrNIiR6jsvS7hKHvrEyM78A27+P7+V/P3/K8P/Xz9GEMQpGwSgYBaNgFIwCwgA8KA0apf7LwMjKADon4g2nsfk5HkfPteza+nuYBYRe/X3z+vef1y/BS2zBW3VGB7JHwUgADAwMAAAAAP//Gu1sjoKRC/7+/cfAzPyLiZvnF4uE9GUeJ8/VjGxs337evq7x+85N3V9PH/P9+/QBPErJyMYyehT5KBgFo2AUjIJRMAogK19Bk5l//oDPhQBtvWRiZ2VgU1Z8w6aocp5VRv4si5jENWYBwSMsktKPGFnYGP59eA+Z0RwFo2AkAQYGBgAAAAD//xrtbI6CkQtAI4t//jD8efWCgZWVjZFdx3AXs7jk+e+XzwV+P7iH7T8jo/7vB7/Z/n37Ct/0P9rZHAWjYBSMglEwCkY4gK2AhbYLQIcLMguLMHCaWF7msrBfyMDIcPjP88effr989o31/VsGZj5B8BUoo4cPjoIRBxgYGAAAAAD//xrtbI6CUQAamWRi+s/Ey/eVlYvr6+/nT3Yyi4n/4TK3PfpPXVvux9ULJj/v3JD7/+0/AyMHA+S0WtCei9GO5ygYBaNgFIyCUTCCAOSE+/8//jL8B50/yMPFwCol+5dNSeUyq7LaVQ5tw/0sEtL7/7568Qx8+AOofQHezzm6P3MUjFDAwMAAAAAA//8a7WyOglEA6jyCKo8/vxn+fnjH8OfFs3v/f/9+wWFgysosKKLIyMNb+PvFU7m/3z9Bggp8VDnziA+2UTAKRsEoGAWjYCSC/38YGBhYGRiYBYQZ2DV1n/O4eG1i1zdZzMjM8ub3w7tf/7x9NTqTOQpGAQgwMDAAAAAA//8a7WyOglEAA/8hI5YMv3//YGBk/MHEw8fApqz2kvuv12pGFpa/v+7dUvn9/JnWn+ePuf99/AzuczKyM0NmOkdnOUfBKBgFo2AUjILhBWB7M/+C9mb+B2NGDnYGViXpj6zS0neY+QQfMQuJXGGRkNrCpqx+5/+3rwy/H90DtSNGE8IoGAUgwMDAAAAAAP//Gu1sjoJRgA6gM51/375i+PvlEyOHnvFeNkXlcz+vXgj+cmhPwvffv7T+ff7M8P8nqLM5ujRmFIyCUTAKRsEoGNYANBANBUx8AgycxmZ3OHSN1v778P7Yn/dv7v55/fL93/fvGBj+QpfNjs5ojoJRAAEMDAwAAAAA//8a7WyOglGAA4CPJ////z+LhNR7RimZ9/++ft3Kcv0KM4eBqQaHmpbgr/u3tX8/eaT87/NXBgYW6CXOzCyjs5yjYBSMglEwCkbBkAbQvZk//0Lu3ObkYGAVl/7PKqd4jVVF4yq7hvYJFgHhPb/u3LjM8O41pL3w7y9Kp3QUjIJRwMDAwMDAAAAAAP//Gu1sjoJRgAuARib//2cAnUbL+P8/w5+Xzx78+/Z1MaeOAQeboqrwt9NH0z5vWqX89+NX8PUooMqJkWn0xNpRMApGwSgYBaNgSAPQ0lnwQUCgjiYDAzOfAAO7pt4nbiePrRw6hvP+//r56efdW5/+fnjHyPCf4f/oTOYoGAU4AAMDAwAAAP//Gu1sjoJRQAiA79D6y/D/549vDP/+fWMWBB0IoHeXiYtHlOH3b54f1y5q/HnzSvHPy2d8/799A49wMrKM3ss5CkbBKBgFo2AUDB3wH3Koz3/I3kwmLi4GJnGRt6wSEg8Z2TneswiJ3GBTUt3IrmNw88+Thww/b1+HzGiOglEwCnADBgYGAAAAAP//Gu1sjoJRQCyAjlz+/fCe4e/7twys8kon+IKiH7Bp6Xt/P3s86vuZY/q/H99n+P/tNwMD8z8GRobRg4NGwSgYBaNgFIyCQQ9AdTX4VPp/kDs0/0H3ZlpYX2NX01r3+9GDy/9+fHv89+3rl/8+fmD49+MHxEejM5qjYBTgBwwMDAAAAAD//xrtbI6CUUAi+P/zJ8P/Xz8ZWETE3rLKKrz9z8j058/zx8z/NHTvssor8f9+cFfpz9NHiv8+fAUfjQ6qjMAn1o5WSqNgFIyCUTAKRsHgAeBZzL8M/37/Y2BiYWRg5uVhYBGX+soiLn2fTVXjFruu4X5mPoFt/z68v/f35RdI/f/nN2R/5igYBaOAMGBgYAAAAAD//xrtbI6CUUAqgF518u/nTwZG0N2c714/+ff500o2eaXtbCoa/D8unYv6vHlV2p+nX8F7PRhZ/jH8Z2WAdDhHwSgYBaNgFIyCUTCwADqTCeps/v/9j+HfZwYGRr7/DCwi4gycptaPuSztl7Ipqu749+vnu98Pbr/+9+Uj5B6U0dVKo2AUkAYYGBgAAAAA//8a7WyOglFALgDt4wThH9+//v/18x6LqDgDu4YuA7OgMAfDr5+CPyTPqf39+kns79vXov++fmEBjYgyMDMzMML2co5WWqNgFIyCUTAKRgF9wX/oclkGyCAwswA/A4u0wDNWcbFnTIJCn1ml5Y5x6pusZ1VWv/nz7k2GXzevgFczjYJRMArIAAwMDAAAAAD//xrtbI6CUUApgHYc/375DNnLKat4jj8q+S2npb3BjyvnPb6fPOTy6+Y1/j/vfzIwsP9lYGRhBHc6YafdjoJRMApGwSgYBaOADgBUX/8BDRKD7sJkYGBgY2RgkZT9w2Fmc5RNRm7T7ycPnv378unZ3/dvnzB//cLw//ev0cHhUTAKKAEMDAwAAAAA///s3E0KwjAQBeCJTWzApQYstqB7QRde242HceNCcNtKSrS1tjqRVLyA6O59lxjm76HZBPgR3zbk6ytFY5PLiclVtjj4rq3YlU6aZN6djunDnjO2hQ4JdmFSKkLTKRAkBAAA8Bf9UDckzXJ/OiuGiiIzuqskLeR0ZuPleq9Xm+0g1jt2ZcPVhfhWv7eZz89vJmo0wFeI6AUAAP//Gu1sjoJRQDXACMGgwwP+g06tffvl74d3h1klZW5z2zhz/X39wv7r8UPp304flf736gXDv68MDEwcfxkY2Rmh9dhoZTYKRsEoGAWjYBRQFfyHXGkCms38952BgUWShYFdVfMdl43TXnZtg4OsUrJX///+/eT3o/s//33/Dq3KR+vjUTAKqAIYGBgAAAAA//8a7WyOglFALQBdagOu1H7+YPj35fPf/18+P2EWFH7CZWbD8Pfdm5e/Hj+UZL5/256Zh4/z3+ePgv++f+X///MnI8NfyP4R2OFDo2AUjIJRMApGwSigAID2Zv77D96XycjOzsAswP2DiYvrNau88kM2ZdWr7Nr627itHPYwCQp9+3XjKsPPb18hK45YR5vGo2AUUA0wMDAAAAAA//8azVGjYBTQCsBGR0HHqoM6n9++PPn39cs8FgGhI2yKqqr/vn9z/nHxjPWv2zcZ//+GrKZlYPvHwMjKCtE3up9zFIyCUTAKRsEoIB2AT5n9w/D/F6he/cvAxMnJwK6p+4rD0GwNq4T0nj/v37z59/HD039fPn9j5OIevcpkFIwCWgEGBgYAAAAA//8a7WyOglFAM4A00/njO6iz+fXf929nGDm5zrCpqKsy8fB9YuYT+MwsJKzx980rvr/v3vD/+/6dFXyHFyMj5KqU0VnOUTAKRsEoGAWjgDAADdCCOpnQK02YuLj/MEkKvGeVkv3ELCn1l8vEag+nofkKBkam09/PHGMAXWfy78tnBiZ+AXA9PXoQ0CgYBTQADAwMAAAAAP//Gu1sjoJRQDcArcRAd3N+/viURVp+O7er9yUOYzP1X7dv2H07edjl59VLwn9f/2RgYGVgYOL+CzlAiIl5NIpGwSgYBaNgFIwCXADUyfzzh4Hhz3+Gv98YGBh+MzCwaPJ/47Zy2MVpYX+EVUrmA4uY5D0GZubbv58/AZ8yC1paO9q5HAWjgMaAgYEBAAAA//8a7WyOglFATwCa6fzzm+Hf54/fGDk4bnAamd9gYGQ49p1f8NXfD+/+M/xnUGfmuiP59+dPPoa/v7n+//4NXd4zOuI6CkbBKBgFo2AUoADobCaoimRiZ2dg5GX/yyzB/oWJg/szp5HZSU5z2zXcNk7bWeWVf4JO7vt97xbDv08fGUAnwjNycIyG5SgYBbQGDAwMAAAAAP//Gu1sjoJRQHcAPbUWVEeClu78+/f935fPJ5m4+d5w27sJMJjbmP58cNfv541LOr+fPGL4+wl0RQoDAxMn62iHcxSMglEwCkbByAawMw1AW1T+gM5EgNSqLJJ8DGwqGn84DEwPsymp7WIVlbj6/9+/m/8+fvgJupqMkZmF4T/sLITRunQUjAL6AAYGBgAAAAD//xrtbI6CUTAQAHpwEGgvJ+j0u78f3j1mZGN7zGlgysDEzXOd8dQhlr/v3/AyMLGwMQt8YP/3+RPP/58/2MB3foH2cjKMVpajYBSMglEwCkYaAHUyoae3MzMzMHFwMDCLcX1l5hX4wiol+5FFTvE+l4XdOi4bpxWM//59/3b6GMPft68Y/n2WYWDi5Abfszlad46CUUBHwMDAAAAAAP//Gu1sjoJRMIgAaNT1//9/j/5//74WtMyWy9yGk4GZWef7qSPe309fkgOdrAfeywnKuSzMo4cIjYJRMApGwSgY5oAR0sn894/h/98/4DuqGf4xMDALsTGwysgzcBqZX2ZT19nA8Pfvk98vn3789+3rddCKIcgSW4bRe6xHwSgYSMDAwAAAAAD//xrtbI6CUTAYAHim8x/k1Nr//77//fjhFAMzyyl2dW1QZWrJyMLK8f/rF78/79+xMfz/z87w+xfr/3//GCHXo8CuSBmtTEfBKBgFo2AUDDPwH3EPNSMrJwMzO8MvJja2n0xCIr9ZpeQ+cprabOG2d5v5+8nDD392bmD4+/Y1w7+P7xkYWVghZx4wso6miFEwCgYKMDAwAAAAAP//Gu1sjoJRMFjB//8M/75/Ax3ffp3HyWMxu4r6+V8P7xv+vHXV5tft66p/nj1h+Pf1NwMDaHKThYGBkY1t9H7OUTAKRsEoGAXDB/z9y/Dv+1+G/9A+I4uoEAO7hu4jNiXV/f9+/rz5/8un9/9//zrHwMz8gRF0cvtoHTgKRsHgAgwMDAAAAAD//xrtbI6CUTAYAXSm8++7t6Dj3D9wGprv57Z22v/98gUnRk6uH4zsHF+Z+QUV/7x8zvbv6xe2/z9/QO5HGd2PMgpGwSgYBaNgOABQp5GFhYGJh/k3IyfXLxYhkb+sCirfuSzt97Kpai79dfvGiR/njv/++/4tw79PHxj+ff8KqQNh5xqMglEwCgYeMDAwAAAAAP//Gu1sjoJRMJgBdIQWvByIlQ20JOgSIxvbP04TqxNMNk6ivx/eN/959bz9jysXxf48fcvwD7Snkxc0AswE2c85WumOglEwCkbBKBgKAHRmAegQvD//wDOZ/38yMDDxMTKwq2vf5zSy2MumovmQRVzyK4uYxNX/f/9c+f/71+/ReB0Fo2CQAwYGBgAAAAD//xrtbI6CUTCYAaizCFpO++0rA8OfPwx/Xj178//nzwMc+iYMnLqGDL9uXQ9kYGBg/ff5sxnD37+Cfz99ZWXkZGFmgO/nHAWjYBSMglEwCoYAYGRkYGQFrZX9/5+JhRW0UfMvi7TsLy4zm/3cjh5zOAzMLzHz8f/58+4Nw48r5xj+fXwHvWNzdDXPKBgFgxYwMDAAAAAA//8a7WyOglEwlABsppONnYGJi4eBgZHpJCMr6z8OfZN9nCZWIr/fvLb88+S+7a/7tzn+vnoDvn+MiQM008kM6bhCO6+jYBSMglEwCkbBgIN//xj+/frDwPAXctYdEz8XA4uEFAObsvoNNjnFs6wKSldYhMXOMnJxX2dgYvrDyMk5ej7BKBgFQwkwMDAAAAAA//8a7WyOglEwlAAjZFns/+/fGP5+fM/w5/WLZ/++fd3Ipq7NwKFvIvD7yYPn3w7v5f3/65cRIwsr498P75jBx9SCZjpHK+dRMApGwSgYBYMJgE6YZWP+z8jKzsDEyfmfRVr+B6ucwj0OXeN9XNYO69mUVA+ADsP7/eg+w58XT8H3aoJObYfMaI5uExkFo2DQAwYGBgAAAAD//xrtbI6CUTCUAfRIeEZ2DgZmPoEPf1nZDjAwMf/g0NaXY7ZzYfjz8pnlz1vXXH7du83y9/0nyB4YTtDCW9CeTubR5UejYBSMglEwCugDQHsyQQf4/P3L8P8PA8P/H5AzBlhl5P+xa+pdZVNWu8QqIX3j77evbxjZOW4ysrNfYOYXZPj37i3Eef/+jUbUKBgFQw0wMDAAAAAA//8a7WyOglEwlAFspvPHd4a/H94x/Hn14ua/L59ucWjrM3I7ejD8fvwg9v+WNTJ/37/TAR8h//krAyMby+jBQaNgFIyCUTAK6AtAezKZmaF7MxkZ/rP8ZmCVkP7FrqZ9h9vacQ+XleNGFmHRo19PHmb4efv6/z8vnv3/KykDvgIMDEbrrVEwCoYeYGBgAAAAAP//7N0xCgIxEAXQn00CibAiukVYRGHt1cb7Y20h6A1EEVFLtZBkZGPjAWyU/y4xfP4Mw7BJ9E8kCURE+Q70oGoD6BLGeDtuJm626KX7bRrPx/lzv7PxeoE8APV505nDK1dtiYjoC3KL+f6TiQTo0kGHADtqDqYermyoNyj0STm/LcruWver2M6vPIeETSbRzwPwAgAA//8a7WyOglEwnACos8jICJnpfP+O4c/rV4/+ffo4l1VShpfL2knm38/vgT/OHOf+//OnFuiI+X+M7xkYmSF6IEtqRzuao2AUjIJRMAqoBMCzmYwMDGwsDEwsrODDf1hk5L5wGlmc4rR0WMQiIrL9x/kz//++efXvz8tn/5g4OCF7MhkYR/dkjoJRMBwAAwMDAAAA///s3TELwjAQBeBXksaACFpREFGLOOjq4uTfd9dRUKh70VhEJCSRBH+Ac3kf3HjzcRyP47JJ1GbBO4TgMq1rUYzq7NV0IOU9XyxLvd3BN8+1rS57W127zhj4mKFRANTvTyeHPRER/SNlMh3gPIJFKtETkNM51GpzzmflUfQHN2ce70zrc+mPHwAAIABJREFUkyiGBzmefNIlM14xYy8RtQuAr0Y7m6NgFAxnAJ2x/P/rF8O/Tx9Ap9Ne+Pv+3RUWCWlmXnd/hv+/f3p/3rlZ7N+H90b/fv1kYPzzg4EBvKWGCTKyPApGwSgYBaNgFBAJwHUHqPpggSyBZRYWZWBT0XjObe+2n8vCdgUDE/OZr3u3Mvx59/rPn5fPfzOxczD8//kDWleNDm6OglEw7AADAwMAAAD//+zdOwrCQBQF0Ju8GWJhUiQhSsBOBMH9L8BOsbQVm0C6dH4S5yMzFu5B79nFfV+GTaL/4eHcBGun8KssjDP56blPs6yWZnnSm+3Mj+Pa9N3u1XeFv91jZTqGTx1GoRSv1xIR0Zc18MZ91isTQIocUlbQ7eoqVXOWsr4kSg3pPD+qRXuAyCN2MkMXM16X5eoG0U8D8AYAAP//Gu1sjoJRMJIAqLPIxASe6QTd0/nv65fXf9+/XcQsKMTNZesqyMTF6fH9zEk2hjNHTf68fM7w9+NnyGDzaCdzFIyCUTAKRgEOwMjCyMDIwcnAIi7JwCqn+InLzPo4h77pMgZGphPfzxz99+fVi59/Xj3/xcjFzfD/10/4+QKjYBSMgmEOGBgYAAAAAP//7N2xCsIwEAbgMzEVKpRWXCSgVbF7338UXB10KohLoZR0sQ5Brhcl6VvY+x7g1txx5H4eNhmbKh+K7QhhGBDmqpdZ1kT7AkSyQpUfb2TaGdbPNZm2xKbW1BmgN449wgLGnE7BDQNjjP09/174P5nkN5LfkJPpl5IyjUHttI3yUyU3+iGXceesfYkkvajt4QzO9Z/7FZy14TJtqMMYmw4A+AEAAP//Gu1sjoJRMJIBbKbz20+GP69fMrApqd3jMDR9wWVuvebf168MP29c0vlx/lTWt+MHpUF8ho+fwIueRruXo2AUjIJRMILBf8jkJLOIxH92HaMHPPZuW9h19Lf8+/DuwZcDO0Ezmd//vH7xnZGFleH/71+jA5OjYBSMVMDAwAAAAAD//+zdQQrCMBAF0GkmNOJCaRtCXat4BI/v2jMIBUG0IKFVF1YTW0l6C/3vEBNmkvlBswkA4+6Mc5TItJOm7EJoQzC8ntZVB82FaadbnQ7e5/29XXt7XX4aS/3jFifc8aktC0okSgoAwE/oQ6qsj39kxvyeiSTOddjJbKRZVJwVJ870RczmRzblTq02e1+fSShFw9uNN5mMMwHgrxHRFwAA//8aLQVGwSgYBYgZzr9/GP59+wo+DOjfj28Mf9+//fvn9cudTOwcxzjMrBlZpeU1ft29Efbt1FGx33dv8v4GnSL45yf4sm4GRugF3KPXdY6CUTAKRsHQB+Bls6BDgEDXYTEwMPHwMbDKK/5kV9G4xWlmvYlNSX3/vw/vn/64fP7XnxdPvvx584rx7+eP/8FLbUdnMkfBKBgFIMDAwAAAAAD//+zdzQqCQBQF4Ot4hyx0ZakQhssWBb3/pneIFtIuxFyIQiBBOjOGPy16gxbne4mZO8O5B8MmAPwyc9+Z1kM+R/dtWxPLWsYJLfbH3Lwa5iBq2N+EjuqWpiqjrsh23SMPdf0cLybW0NUppgF27OskLBkCAPhL3zzm8JOpzPheaEmbhOcRx37F/ubG0ba010EvXLcQziqVcXJ2DqeLyu70Tq9TfYlW0/nRI2wBADMi+gAAAP//Gu1sjoJRMArwA1Bn8d9fhn9fPkNmOl88P8rIwHCF08yGlU1Vk+fP8yfWX48f8Pl/ZL/V31cfef/9gA5qM4MaHP/gd32OglEwCkbBKBiEANTRBN1dAups/oL0E0EDhkwCQgycBqbXOAzN53PoGp1l4hf4+/vRvW8/r1z48efFs09/375h+Pv5M8P/v/8YGEAHxo12MEfBKBgF6ICBgQEAAAD//xrtbI6CUTAKiAPgUe8///7//PGegYn5PauMHAOnvjHDTy7uD7+ePPzOZfn3LpuSisLfd++F/335KPX3wzuxf18+s///9hWkD2IFbKaTafTy7lEwCkbBKBgQAJ7FhN5zCVoiy8LEwMTNzcDMJ8DAyMcPmrl88u/Lpw+MLCy/mQWFt7OraW3jNDR7ycjBwcDw9zfDz+uXGf7/+AEp10HmjO6bGAWjYBTgAgwMDAAAAAD//xrtbI6CUTAKSAOg5bH//zH8+/6N4e+Hdwy/nz958f/nz21c5raHWWUVuP48e2r87cIpl1/XL9v8fnxP5vfTxwz/f/1lYAAdJMT2D7qnE7LEdvQY/FEwCkbBKKAjAK0yAZW7f/5B9mOCymVWRgZmAUEGNhXNn+y6hmdZBEW3/Lh0+urP65c///34/i2o4wkq60F7NkHlPriTOjpgOApGwSggBjAwMAAAAAD//+zdwQqCQBAG4FnNyigKiehQSUiHDp269O4depQI0kyDMKRFXJtw1+4FHf/vIYadnX930GwCwI+aqFT9prMsiZ+5pBdLxw8u7nZH5ekYqeye2W4v7Kw3KxWHfZVeu1USz6r8sagPLSyl+eGwrkCWTeITtUXcFgDgP/RlHpu9mDoma/ZjmuZyxPZkemt549gaeqkQzGIwOrf94ODMl3uVRJGeYBaFnmDqWq+aH2YBAL5FRG8AAAD//xrtbI6CUTAKKAPge0/+M/z//o3h39cvDH9ePf/w/+uXw2xKapfY1TS5/v36xfr7wR2xH1cvhv68finyx+ULbH8+fmf4942BgYkL1PD5y/AfvMcTtOdn9ATDUTAKRsEooAqA7cWEzmKCOpr/vzAwMAn9Z2CRlPnJZe14gdPYYgczn8DR7+dP/fl56+rPP29ev2MWFHn77+dPiAtGZzBHwSgYBZQABgYGAAAAAP//7N09C8IwEAbgq2mqFqSC0eIifnQWQfzz7v0DLo5OisHFjxrbWhu52h8g6Pg+a/bAe5e7IGwCwG/qcMjfptg848CZ2+KpRT/UzfmyOnN7ikpjRKEPUk6ikTeNnDJJlE1N+LrfujZ9fLqdPAPE1Xj+s5MXTiB4AgB8h+9Onq239UZYfjXiSmp0fHLa/lUEwcnx/LNQ6iIHw703nsWtxWrtqnBX6CNl201VNKw6mCU6mADwB0T0BgAA//8a7WyOglEwCqgLYJ3P378YQIcDgRo8/758Yfj78f3Jf1+/PmFX0eDiNLFk/v/rl93PG5e8ft68avHnxVOGP98eM/z78R+8h4iJ4x/DfzZGxGFCo3s7R8EoGAWjAC8AXV3C8PsvZAYTtE2B4y8DIzsHaBYTdD/mXQ5twz3s6trnGXn5Hv6+fePH388f3/599fIVEwcneKAQDEYH+EbBKBgF1AQMDAwAAAAA///s3UsKwjAQANBJqgaL/YBVqbjuoicQBBce2yMIBU+hpBZBtCTGppHGFj1Ad85bJVlkGWYgM4PJJkKoX+SnplMpu28CGSNKbtSTDxYxuOttc5YbJSUQcmZJGlQX7ukip1XBIyNFXD/uo1pKAPWyTYlINyS8ux+DIoTQP2rnYn6+yX7XhDGgfmhoGF7peFI40fzmTGcwXK5Ojh9kLEn37maXEc/XpRBQHQ92pJWty9Rtx3B8VxFCfQKANwAAAP//Gu1sjoJRMAroBBghZwv9+c3w79tXhn9fPj3++/H9BhYJqSMceiasTOzs7L+fPmH7eeOi26/bNyJ+XDkv9vfjV4Z/nxgYGNn/Q0bpQduHmKHXp4DbRKMNo1EwCkbBCALga0v+QZa5/gYfDM7w/zdkPyarJDMDq7zSXw5D0wtssko72BRVzjGLiIE6kt9/P7j7/t/H9y/+vnv7lwk0APj71+ihbKNgFIwC2gMGBgYAAAAA///s3bEKwjAQBuA7vYa2EQpKS3F2EQQV7Is7+yYdBS0ISos1rS2JXJc+gQ5y3xxuDEn+JCebTSHEbwyLGgTHiWfb8NvOpzN1TnGa+7sMaBFDX1wAFVW2qjTdimw6j3ls6Lp35BoT2bZVw3UvrsGNxIey8pOtEOKPWTummYiAngeoZoBKdUhePQl1iYH/omRZUpIWarU+BdvD0d/sz5x2WmPAPu7QX898yAeo9dj7WOZNIcQ3AcAHAAD//xrtbI6CUTAKBhAwgi8XBy3jAh9s8eM7w7+vX6/9/fxxNouYxHoOYysGZn4Bld+P7tv9vHHF/s+zx8K/nz5i+PftB8O/n9B2EivoBCJGBkYWltGG0ygYBaNgeAFQufjrD3j2ErSfHXRgN7MIJwOLmCQDq6zcVxYB4UusympHWeWVbzIwMLz4dfv6938f3j/79+XTK9BhP6DOJniAbvTAn1EwCkbBQAAGBgYAAAAA///snTsOwjAQRNdWPpZiPiISBVIg4gRUaTg7NQV0SNwBElOQYPNzgtaS4QZAse8QI61mZoeOTYIgfoN3I73TidFanE/RF9U2tQpGqet2Rlmemu36CIw3YTbLQ1WOrargWZWiM3rY6WbQXg3DHTjXW3o7nfCJ2dIRShDEP+OfoPkuJqCWcedi8kRaFoszl/2aJ/LOZe/B4ugWTLJ9PJ1vRLFciUWxsycFtjoAfpbFLibqKUuk01dMlFAChCCIrwMALwAAAP//7N2xCsIwEAbg39ZSFSPoJDgo0sWlg68g+OgdBAcRQUQQKgpSxFRBm7ZJ5YrgK2S4b8kbHHdwuZ+HTcaYXX4NUUUB5EUOk72lTmXkdEXcCufC6Q86RsoqPx2D8npeqv12oQ47lEkGUD/lU2Yn0KDqVkd3uv/jQowxZhWKK6nqDY/6pTxMOgyrAadt4IoempNAeePpyp+FkTccxfp+Sz+btTav58PkKkFRXGigBP3DpJVbrnWMMVsA+AIAAP//7Ny9CsIwEADgi03SVGfr4uKgQxHEJ3DzlQUfQkUpOIjQQcRJ0Ka0xiSS60PY4T4CeYPjkvuhxyYhpHtCshTaa0Nbbfm27vUsmIwLlS1AzjLcclvnh7Q+7bQLSZaUY54+ElfpCL5GefPpg7WJN4bhlkVcqNHOeNLvPiHkr7CK6fGgMIcpFY4CMM4tE1IzwStvXdPjwkfD0TGeLzeD1XobT6bXJt9DfTmDvd/aGBk6QnSJN1UwCSGdAgA/AAAA///s3LEKwjAQBuCzKaViB6laCo4OIri7OvrSbs66OFrIoBSbIoh10OQSubTPIAr3vcBt4X7Ifxw2GWN/oOeXM9cFRgqQzujaPu7bIO7LZL1JxGgywJtKtSwWplYrrMqlLs+A6gq2Mf5qI/Wdgoh6nnTRVvBCxhj7LupgmraD6d7tZPqNIYYxhFkOYT7FaDbfi3S80/JUvI4H455NBYgSLF7820eBsjsWxBhjPw0APgAAAP//Gu1sjoJRMAoGP0De2wmZ7QSN5P/7++7tTQZm5ptcxhYMnKbWDL+fP+H7fuqo6c/b19/85uD4zMTHL/VPRoHl38d3jH8/fWL59/M7F8OfP9ygGU8G8IznX+iVLEiNttEG3CgYBaOAUgDbg8mAxAaVLSwsDEzs7AyMbOw/GZlZvjFycv1gFhT6xyIs9puRl+87s4DQY05T661sSqpbvx0/cPfnzavgWUvI4WlfIPdi/vg+ulx2FIyCUTA0AAMDAwAAAP//7Ns7DwFBFAXgs2PGI6FSsF5ZiR+gUfPfdZQKlUdmbbZfWRsGVwaJWknO10x/q7k593DZJKI/Ihkgq3uRH1FSi9p4UjfRyEhR6IvdhS61s2tsp+fNGrfUn58BQfXV8YR+v0p9Op78zBHRN3xy6ZfLZ/qITwczAJRPMJsN6FYIMxgmph/Ndbu71J1ersoVcfHeucRmcsq3EDlAOHki+nEAHgAAAP//7N2xCsIwEAbgS2KjBXESFwdBKSg4iJMv4OqjOuviLIIg4i44SaFYUi2xITlJC6LgCwj3PUTg8ue/0LBJCPlffihELLtKVqXgMgUuz2On0hit3cloBM35ovz5XJ8OXX3cK81EiObZd60EXHbnCFBDayQ4DMBZge9+J34nEoQQ8stniukvq8oOpqzOJy4ME9wA4wVqbVlQt6LduTbGk204nS1lNFwHvQH4bdqPzQqKyxnsLakSTN9Hp+eyhJB/BgAvAAAA///s3U0KwjAQBeCXDkq3Qd2J4sJtN3p6zyBCV+6lP1qxdNFFTdNEpq3iGcp8kCuECWHek8emEGKCxuGPhz0O3eCFTaLMm/fJO5eF0UHPd3sOGtJtflvbx/3oqjJq85S68omuqodeOz8m2367PEm6PIUQfxUlvH9p0R/lht5fFQagxRKkV7yD+ZptthdAxU18LmyaNDCmRkAJArry/dTju+WXmi1fmkKIiQDwAQAA///s3bEKwjAQBuDLNcEqrYiDRQRnBzcd9ClcfVXBB3DrYHFV6uJSShvbqiUXIS4+g973BoFc4Dj+CzebjLHfI9AdyWU8y8JlM+murcmzxD6apLNYQbjZgkARNPFh9jwdb6/0XAu/N6doLEyeSao0mLr2BBkFhqQlQrdlyPLEk7G/9V37iIBKWRBoQKkWpTQY9gkHQ5CjSGM3qNRkGvvL9Q483FNZXNv04v4U/mQwtXufaFiBfbVfk0zk+8UY+w0A8AYAAP//7N1LCsIwEAbgyat14cq2FFTsQtSteP8jeIAiShelRNQuBBfWxEQm1kNI59vkBiGTyeSnYpMQMiB95IAQwOMRAGcPpuLSO+e9taUqlnm02nCmFH+3V2F0s3btbWd0vcWnbfaiwd27MIMVup2qrzfxbMhZP+tJmZ6E/LVf1xJX971gwtlLzL4Mv8gazMAEEJMxyNmCySRr5LzYyzQ7ynx6lkmKuZmdqU4v9+w0eH9gKqpx3yGEkEEBgA8AAAD//+zczQ7BQBAH8JnSqq8IV0lJJT24unB29LK8hANpIhIHxIU0wQVrNSntruyi7yCd32lPc5+dmT81m4SQ7NATA9QThOR20aEdgjMu2NUXnPlWuwOV4QjMpgPx8QDRdj147TbncDFTXWpLPO5VzFsIKs0WQd17GiBVFYnpxEPSChwhf+0bDoa/T6PPW6BalEUQqvc0bFtiqazCfoKC150We/2J5Xpz03H3uXoDklMALBxDvFrqG0wjqYF8Rmk9QgjJBAB4AwAA///s3b0KwjAQB/C7NmrTVLT2Q3BxExF8/9dwqA4iOAmFQo26pNCkkqZDH0HwfkuyBDIFjss/oWKTEEKGTobNZCIP+8c9PDG38wKDQCPitWuamKVrPtsfp/4i3rZ1tdNVeTBKrbR8gpE19KNyHZC+rp0MmU/mj/JYhJCf0Rn3b2XbueyldhtDNmQvlwn4cQIszSSK6MbyzYVleWk+b6nOJ1tAvgDxjgEvvDB6eCJy6+05YnOY42v3hBDybwDgCwAA///s3c0KgkAQAOBxV8MIJUOKwiI6RBcPdQ+69dZdAw9BFyGL7vbjD9qCpmus9hBB8532BXaZnZ2dwcsmQgh9XzKqdw48iYFrOpRRINYJf6UOZ8wR/6sUawqdzVZtzebL7OyuM/eYFuFzTO63ITd6bRKFrTKOoGKpCDClZuABSBhsIvSjJNIkg2SxYSUASiqQlUokm6iucWqYOdW7TLEmBzoY7VV7tVMXtpdfPb94+JBfTqI6ou4eK6olSBSAbPbrztjiPMERSgihvwYAHwAAAP//7N29CsIwFAXgm6RGrf1LoXRw0tnBwfd/CYfiIlQEaSnaWsGqSZQ21UlwcL3fC2QKJFzOufjZRAihX/rsVvsopbbTMC9Y04lzJZynoKRgIvTHyxVnYTRQl1qr/BDoqpzJIluo03EuixxUkYGuzTmEm5xnN/2k7y+pWZmAE1CE/vSeJna5y3aV0fOz8xI0mJ6vm7l2VBCw4mlb6NOwIEysKE6oL7Ku4Md2QFXlQ+7TO2i9I8PRlrnehonwzFwPSNsk22c6EUIIfQEALwAAAP//Gu1sjoJRMApGASEA7QSCrjkAzWL8/fDu67/Pny7++/r10t/37xhZxKUYOE2tGLnM7Zn//fz+5/eDu9K/Hz+0+HH9ktev2zf+/P/7W43h1w8GRqYvoINDsF+hMtrBHAWjgDoAaTaR8T8TAwP0XB6ICLTjyfEHdBo1AxNoiayoOAObquZVdmX13ewaOrtZpWRusMrKv2Jk42T6fu7Ev89vXzP8efPqP5OwGKjz+f/v29cM4BUMv3+PDg6NglEwCkYBPsDAwAAAAAD//+zcPQvCMBAG4OtFaNNGEykd/EDwTzj5/zfHzorgFyKiqfiZqyRU9+73QOZMBxfel/BjkzHG2vtFGXVINlAAKg3Y058ItK/QrZ21DjNlgWgRxXIgZ3PoDCdJ/XwYdzqO6WanVFUjdzlLX7mj+y3U7uqHC79dhvXVL8mdJgEVovntlhdbxgIiqP38OfqnluE0jQFMY0BtQBgDKDNCme0jpXw6ucK8OIokfb0PG/rstn6Ol6hUKfp5KfLiiv3C3+Cwq8PshTlnjDHWDgB8AQAA///s3T9PwkAYBvDnrpVeSiFVatI0Rr+Agx1cYHX0a7o6uREmFlYGWRwZCCVtaXslDtcXcxhNHA3r+/sAt93w3p/n4WGTMcbOYQdA2+NpO/N0A7JJt2UuqN5vqNVZVxUzIYRUjxMET8+Do25uP9+XD2azHptsm5p8d0f13qeqUJ3WoLoEHQ6AMae1xc8tDf/9YuwvmxLrfIdvCYd+T4CE50EqHzK8hByGcEdR5V5FmXMdr9w4mV8kNwvvPv1whmHbTN+6+vUFXb4jsk/gq5Jkvw8ZDCB66rSnYQOEJHdfMsbYvwH4AgAA///snc8KgkAQh2d3tSQV27Aki269/5N0j+gUVlaU/xKCdtfYUvEBvATzwV72vAszDL/5sNlEEATpn1roCepbqBICTBe94fJVFfmdnaNUPm4nYtsbK5hPjWA+BCkskTyoylOiysJQeear8hmqLF2rZx6Iawwi0cuHfhPPNu9JW6NLfbraBmxSkX+gqn9Mx2+pL+qsJTSxSO25FM2mWPKbWtoOUI9LOnIO1BvvqetemMczxn0BlFYiPkqZ3EtgLGOuFzE+2RrT2c5crF7EHIDWlHwbSfHGl4IgCNI3APABAAD//xrtbI6CUTAKRgEtAagh+/8/w7+vX0CzJwz/QbOfnz49+vvuzdP/374eYtXSZ+Jx8mBk4uVn+vP6FdP/H99As6Qcf14+U/vz7Inhr7u33X4/e2T6/+8/4X+gPaP/vkA6lwyww4UYEZ1MBkZovxKpgznazxwFgx4wQjqXsH2WjBD+f0ZoZ5PpPwMjqLfJDB1oYYEsK2fi5GJgEZNkYFVSe8giIXWCVU5xN4u07FVWMclHLJLSP/9+eM/4Zfemf98O7/v399/f//9Ev/z99/nT378fP/wBHdrFzC8APjUWthR+FIyCUTAKRgGVAQMDAwAAAP//7J3LDgFBEEWrq7UxY4KRiUewk/gJK39vyYathXgshPGIQXdLdRN+gFWdpPddSW1ubtUtFpsMwzD/wjs3Pg9Ta2elYBxDodVxH1BBBDZ3YpPGA3f2ft/iarkVUo6D/qARDUcgJKLODkWT7RNzvab2cuqa/Jba8zE2lzPQoyAjoP3Px8M5QfBeNxP+7qd3REmYIgecML/H9T3tV/pU52+n0olJ8RKRCl3CK42xirAMGJVBKKVFGG2wFK6RnMlqkpljdspnU0vJz4CosVJdyiSdy2Z7ojq9hWp1QdbqQDcvMa748rT+lPmVVsswDMP8EAB4AgAA///s3U1OwzAQBeCJ44b0FwWEukCIRapSddNtz8GW43EXJMQGDhCJUha0KrGThjpKMhNUJ1yBbua7gyWPnt+Yh03GGDuFtgNW57n9n889DwDVDtpk87jxtqR9GqFWa0yU9OcLd3T/APL6RparqF98vE8w/r7Dr89lpdUMd9uQsrRLWnco/2n6o7kBMgbqorQXeztTCuAOKDuBNoEXTWr5F1oeOdIBxztrhsNezz6PFf0RiOAicQdDLa/GbyK4fPVuw+dOOF1Xq2ijHzOqXp5qOmRQG4N0yEpKkwJVLITnk+P7gCq258viziVjjP0/APgFAAD//+ycXWvCMBSG8+Xa2jpFtrkPKl54s///Y3YzBiJubFcbadNU23Mkqa5h816Q85BDQgjkJjeH931DzSZBEMS5CZWWvlpf0NTusyD3YclgsewyZlK6Yx8iilestuu23s7VY/6kZg9XIhnGYAoFP98StjWHolBgSo6FnqA192DKHG01hcpIsJZhZbzFF+1BZVJ9/pPzMAvaW3W7EVp1/8zEhXDsCINMpbO3/ts7qOf4e6RbN91zEZnwmWXXTLqmkg/TL69UptknjxMt0szwKEE5HrciHQGUutm9b3YIbSlG11re3L3J29nrIF+8RMtnzRG8I8CrlRBcfKoYqZcEQRBngzG2BwAA///s3b8PwUAUB/B3dZV2EepnmlgsYrAxGfzNRn8Eib+AEMJRpa2Ea++dnHQwGIwi77Pejbd88967R2GTEEJ+Wd7qquXD/HILVqkE6nwy1dCHiqKViqOdCk+23fS5Oxwxp9e3tAmS8ZVpRIa3pKiSmGdi38GjGKS7zVidj91M7P3XvsBAgDZrV/IQwfR3c55fXiP/4C2vfYxu+sNZnvvM831VLcse8EYLuFcLCk1/wav1Gffbc+7VtgWvemB2Ea1yJTWts/fFTMfTCcr1Ei3HRbwlKXNcqa6hzAIB6hKClpJawAkh5NcBwBMAAP//7J1NS8QwEIZn0ny01i66rHUtooh3L/7//7EePQgW6kdd6bZN0pGkdi2CV1HIAyGQU74OGd7MvCHYDAQCgf8ATflu+2aBBgvWtqC1f9DzdQHRcjUuxhrfOdXSvNXA0uzexskjGfOARBdD0+S2KlMUkqmbWxDnlxEQiOF9m1DfZtT3C+q7Jel+QVqnYG3kvuVS144PfedxaI2fAmjz5XM4wX5QRvEzV3QqbBRC1t9jXu3Vpw5PY99UyWGmbvuiPAjIhT8z5gLHOAZUyej9GkUWuNihlDUKWaNSryiknHYEAAAJtklEQVTVlkm1w8OsQ8YGW5VknivnE9uwo+Mnnq/v+GmxkVfXG54XL3x1Aq4yLB6kfiv4WQlMKXD32tkK7RXL+f0P+ZaBQCDw9wGAD/bOHSdiGAjDM/YmsM5DCRLNFjwkGk5AxQ1oOSUNBRJXQeKlrUG7cZx1XniMbEAbIWqklfzVvsDnf/6ZIJuBQCCwyzhpc8mn+fBi6bB9D6SkTyv9Fty6/kpCVf1AerOkro3tOMxMLRkyBuLiErKr6z1kXPSvj4ckV0emrk5pvTqnRh2bRi2gaxMjq8x1QY1uAIYBqNNgxwFItwA0bmXzR17Yr3FcZicPYNvjC/wD9o9x08lZkYloOg/1nwV+aU8EGEeAc+GFE9MUeJq7+5UW43hAkazZXLzzvHxhWf7Mi/KJFwdLVpRv8cmZRMRR3d+SurtxPWSadQtDWve0UZ2RVY/RPgJn1skmc+OxIvGdZft9ZzYkl4FAILDDAMAnAAAA///snd9KwzAUxnPyp1nXDVFrR6XgI3jj+z+CN+ILTBDUoc6tm0mbHEna1bW98E5Q8oNyDk0hpc3Nx3dyEsRmIBAI/Bdsq/acG3RwhEybOyfU2pKgu1qx4ZwjGROeF2RyfeM7gZIoYmb1lNevq8LE03u7fs8JZRkKEbPFZcLTTBAKwpYls/uSYaWp3e2BaAWoPinWFUWlJmjqGJU6QVPNUWkXY9RauDnRd8o1vjTYNXBB3X5/emR0Do3PYezuwTgnQ8O0L1igl/yGmBnXoeIP4+OHsT821O1H2ys97VLwZ1JK3jiTrIkguGt97P43OhcSBN9CJNfAxA5ktAHGFZFSUy4RvIsZIUwTS5OZRWu0eXk2drtRIGVFT88/2Gz+xs4u3BmWDzzNlixdPLI0U1Fx5d9B3N12peCHzrTfLqVp1ihtY7cPMxAIBAJ/HkLIFwAAAP//7J1NT8JAEIZndre1QJEKQTh6MMS/4c1f7I2zN+8mJhoT9WC0H/QDCjNj2PjRVPAPsM9p2mw2TW9PdnZeJ5sOh8NxqNgJnWLjUrb3QFFr4DQWWqRvnC9SLot7rkqfs9TIslLB+YXqXV4pM54iZ4ni1RKFCGVdayBCe2K6rHzKkhHn+SnH7zMu8zNK4hmXiynF8UTyXFGagJQFbIhs+60dTvQVf9EcTmS9qdmGCy0ZtbU03jVsbJ9sfu/7U0hryV/5/E9H9zdz7rTK/Rccd23YEkppPrfr5hr5Hdhjf4/PANtIkaALqj+w0SJqcAK6F2YqGj2oMHzS0fAOu+GLiYaPqh9+qPA4ReMJeL6g0YxBh3Q0lPXrMxfza6lubxjqlWCnR2wMYVnU6Hk1HQUr8PwNagMyntjMTHvivv0wl2XpcDgchwUAfAIAAP//7F3bTsJAEJ1LWyVgC0EMGl5MNPz/V/jiu28kXqO+gBCF0s6MmQXlEv0C9qTNZLu7H3B65syJZDMiIiLi0OH+S29bdD+fiGeAlqD+6my1V4V9JyrZ1dD9nwAXAz8Lpgro/lA1kLnnfH55hEuqk3G3fn+909lkQI3mpUzHPQA6VaKWlYvjevqBHnNxdD30nFEEM3RCayoEIomJOIFNTSQFlcxUMlDNQDQz8xrWifk3UwZV3vUkrtmX+0pdTRXZm666nbWI6ymr/1BH25cNf4CbLs+/2j0R1+Lp9rRe3PWr+kMcPItOCDf3cBUTgqhAXCNRDURLIKqR2GvlayQugWmBzBVQUofKJD5YB5C0erq36mFkVgpAMwFqNJRa+ZI73c/kpJjx2fkjFcUL9/ojzou3pNd/5nZ7znknqKCWJuEnhHuCIeTC5jC/vQGfkBym/+yolPqrTgY/bziDUamMiIiIOFQAwDcAAAD//+ydO07DQBCGZ+2s15sEOVRB3IcGiYIb0tLQcgYOQRsJgSAP2/vyzqBZO5GIEFxgP8uF15XLT57/nyybmUwmk/mbqdiHpY0zmyyb1LWAzo0FQSwViCnDybKJ+23Edv9F3cFg372iMS/orKTgJYVQ8qgtHraiXF/B8uYOLm7v+Q9pEd82FVonyZo5OjNHY5bkTEPOrcjbhrxvxtKioSFnLyn4BXnHBUYaBq8pYgnDIAmjYPnlC6yB2PdphFOcZBQnIeKA4rTsnxAIzxb9i8lL4zHI+JtsilNu9vwdy6JIucPi5zPL5fGczzivqBcAuk5nXKqTbikDlKWDSnWFlH0adZUVj7xuhZStqOqdqKp3oeoPofWuULor6roTSpnZ+tpBORsOz09x9/hAcfMJ5Yq/ORINgSj4iN5FYYyFSvqiaw2KIqCqfXJionH0lsduWTZVnfZfYrsfC6LyntZMJpPJ/AcAfAMAAP//7J3PaoQwEIczoxITddtCS6GnQumhPfT9n6SXvkL34q7GP3GmzCi7dGFhHyDfRaMgYk4fv5kxyWYikUgkboO3BFRONe2cz7K50JogrikocYwjS0J67hk9TxEV4RsGlSz7/mnsx9f6zNc3FUMpu6S+y6k71tQfGg79HYVux8O44xAeaBrl2j2Pg+fQNzxPjsbB8rLkZprWVFR6SWPMsucXKB+fEF0N27siSxIq5b+LSOlJNuVXMddkEw0RXJVNBDaIdHnPIPIqlyqbJEddZxkBAJu8IJTS5RA4/kofZBtNUciwnAh5xlDYyRT5rBJpbQDnW7DlEaxr0dpO1li6PXi/x6o+oG86rKoZndc+XGH8+dbvzNPyP8296JnUJHJLI3UPpZ/3VKpLOnlW900T8JRUJhKJROIGjDF/AAAA///snT0KwkAQhXfWEIOCeAFBsPAYdp7ZyptYCIKlCMn+ZHdnZHb8KcTWar4q2S3SpHnMe/NUbCqKoij/h0UXcV60f3+63G91sy1nSNEPBd3QoxsCBXej4BqKsSEfGmJBGXyDY5zQGPnd0hhtFY8pSY7Ue+BJa7taw3y3h3azFaHEOVMRW7WH9GOlpZ91GoRo2eb7ff+yxAKBhW8FVu/eHTDEolTssVaO2mndwprOJ9MfD5ivFzJdZ+yMg7QTGc0iIoKtI1gLkGXRE2VCVoiUsZQEiImfTeEqnCybghdLscG64Vl4qf+4oiiK8meMMQ8AAAD//+ydwQrDMAxDbTLW/sYO+/8PrFMXOfFqtvXakx4ECu0h9CZkyRSbhBBC7icagLxkRS3GM6OpNg5GPTdzw0nHzU4Hrtf20v69g3R8g/2jS+wf1efrPZxX7AoVT5e1iE25FpseolT/tgGl2FT9fatac5r+yXDOkVvcDVlI7C7VZfW4L3KbuFtmHfdecpD5jH/RhqPcTGQ6kf6YTb+tjebXksWl2CSEEHI7InIAAAD//wMAmntDviHYe2QAAAAASUVORK5CYII=]]
local wyy_icon_tex
local wyy1_tex
local function b64_decode(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local map = {}
    for i = 1, 64 do map[b:sub(i, i)] = i - 1 end
    data = data:gsub("%s+", "")
    local out = {}
    for i = 1, #data, 4 do
        local a = map[data:sub(i, i)] or 0
        local b2 = map[data:sub(i + 1, i + 1)] or 0
        local c3 = data:sub(i + 2, i + 2)
        local c = map[c3] or 0
        local c4 = data:sub(i + 3, i + 3)
        local d = map[c4] or 0
        out[#out + 1] = string.char(a * 4 + math.floor(b2 / 16))
        if c3 ~= "=" then out[#out + 1] = string.char((b2 % 16) * 16 + math.floor(c / 4)) end
        if c4 ~= "=" then out[#out + 1] = string.char((c % 4) * 64 + d) end
    end
    return table.concat(out)
end
local function get_wyy_icon()
    if wyy_icon_tex then return wyy_icon_tex end
    if type(render.load_image) ~= "function" and type(render.load_image_from_file) ~= "function" then
        return nil
    end

    -- render.load_image 的基准目录是 scripts/images/
    -- wyy2.png 已放到 scripts/images/wyy2.png
    local cands = {
        "wyy2.png",
        "C:/neverwin/scripts/images/wyy2.png",
        "C:\\neverwin\\scripts\\images\\wyy2.png",
        "./wyy2.png",
    }

    local function try_path(p)
        if type(render.load_image_from_file) == "function" then
            local ok, t = pcall(render.load_image_from_file, p)
            if ok and t then return t end
        end
        if type(render.load_image) == "function" then
            local ok2, t2 = pcall(render.load_image, p, 192, 192)
            if ok2 and t2 then return t2 end
            local ok3, t3 = pcall(render.load_image, p)
            if ok3 and t3 then return t3 end
        end
        return nil
    end

    for _, p in ipairs(cands) do
        local t = try_path(p)
        if t then wyy_icon_tex = t; return t end
    end

    -- 兜底：把内嵌 base64 写到 images 目录再按路径加载
    if HAS_FILE then
        local bytes = b64_decode(wyy_icon_b64)
        if #bytes > 0 then
            local tmp = "images/wyy_icon_tmp.png"
            pcall(file.write, tmp, bytes)
            local t = try_path("wyy_icon_tmp.png")
            if t then wyy_icon_tex = t; return t end
            local t2 = try_path("C:/neverwin/scripts/images/wyy_icon_tmp.png")
            if t2 then wyy_icon_tex = t2; return t2 end
        end
    end

    return nil
end
local wyy1_b64 = "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"

local function get_wyy1_icon()
    if wyy1_tex then return wyy1_tex end
    if type(render.load_image) ~= "function" and type(render.load_image_from_file) ~= "function" then
        return nil
    end

    -- render.load_image 的基准目录是 scripts/images/
    -- wyy1.png 已放到 scripts/images/wyy1.png
    local cands = {
        "wyy1.png",
        "C:/neverwin/scripts/images/wyy1.png",
        "C:\\neverwin\\scripts\\images\\wyy1.png",
        "./wyy1.png",
    }

    local function try_path(p)
        if type(render.load_image_from_file) == "function" then
            local ok, t = pcall(render.load_image_from_file, p)
            if ok and t then return t end
        end
        if type(render.load_image) == "function" then
            local ok2, t2 = pcall(render.load_image, p, 192, 192)
            if ok2 and t2 then return t2 end
            local ok3, t3 = pcall(render.load_image, p)
            if ok3 and t3 then return t3 end
        end
        return nil
    end

    for _, p in ipairs(cands) do
        local t = try_path(p)
        if t then wyy1_tex = t; return t end
    end

    -- 兜底：内嵌 base64 解码后写入 images 目录再按路径加载，不依赖外部文件
    if HAS_FILE then
        local bytes = b64_decode(wyy1_b64)
        if #bytes > 0 then
            pcall(file.write, "images/wyy1_icon_tmp.png", bytes)
            for _, p in ipairs({ "wyy1_icon_tmp.png", "images/wyy1_icon_tmp.png" }) do
                local t = try_path(p)
                if t then wyy1_tex = t; return t end
            end
        end
    end

    return nil
end
local function draw_header(x, y, w)
    local lx, ly, ls = x + 16, y + 11, 34
    render.rect_filled(lx, ly, ls, ls, color(22, 23, 34, 255), 9)
    render.rect(lx, ly, ls, ls, C_BORDER, 9, 1)
    local icon = get_wyy_icon()
    if icon then
        render.image(icon, lx + 2, ly + 2, ls - 4, ls - 4, color(255, 255, 255, 255), 7)
    else
        draw_spotify_icon(lx + 4, ly + 4, ls - 8)
    end
    text(lx + ls + 12, y + 12, KNOB, "Netease", 15)
    text(lx + ls + 12, y + 31, SECTION, "cloud village-lky0112", 11)
    render.rect_filled(x + 16, y, w - 32, 1, C_SEP)
end

-- ============================================================
--  КОНТЕНТ ВКЛАДОК
-- ============================================================
local wx, wy = 70, 160
local okpos, saved = pcall(db.load, "media_widget_position", {})
if okpos and type(saved) == "table" then
    wx, wy = tonumber(saved.x) or wx, tonumber(saved.y) or wy
end
local function save_position() pcall(db.save, "media_widget_position", {x=wx, y=wy}) end

local function tab_spotify(ui, gx, cy, gw)
    local ry

    ry, cy = group(gx, cy, gw, "常规", 3)
    widget_toggle(ui, "sp_enabled", gx, ry, gw, "显示媒体窗口",
        function() return spotify.enabled end, function(v) spotify.enabled = v end)
    widget_slider(ui, "sp_scale", gx, ry + RH, gw, "窗口缩放",
        function() return spotify.scale end, function(v) spotify.scale = v end, 70, 150, 1,
        function(v) return string.format("%d%%", math.floor(v + 0.5)) end)
    widget_toggle(ui, "sp_anim_fallback", gx, ry + 2 * RH, gw, "无峰值时模拟发光",
        function() return spotify.animated_fallback end, function(v) spotify.animated_fallback = v end)

    ry, cy = group(gx, cy, gw, "波形", 3)
    widget_toggle(ui, "sp_wave", gx, ry, gw, "启用轮廓波形",
        function() return spotify.perimeter_wave_enabled end, function(v) spotify.perimeter_wave_enabled = v end)
    widget_toggle(ui, "sp_wave_playing", gx, ry + RH, gw, "播放时禁用轮廓波形",
        function() return spotify.perimeter_wave_disable_playing end, function(v) spotify.perimeter_wave_disable_playing = v end)
    widget_toggle(ui, "sp_dark_wave", gx, ry + 2 * RH, gw, "深色波形背景",
        function() return spotify.dark_wave end, function(v) spotify.dark_wave = v end)

    ry, cy = group(gx, cy, gw, "发光", 3)
    widget_toggle(ui, "sp_glow", gx, ry, gw, "启用发光",
        function() return spotify.edge_glow end, function(v) spotify.edge_glow = v end)
    widget_slider(ui, "sp_glow_strength", gx, ry + RH, gw, "发光强度",
        function() return spotify.glow_strength end, function(v) spotify.glow_strength = v end, 0, 100, 1,
        function(v) return string.format("%d%%", math.floor(v + 0.5)) end)
    widget_slider(ui, "sp_glow_resp", gx, ry + 2 * RH, gw, "音频响应",
        function() return spotify.glow_response end, function(v) spotify.glow_response = v end, 50, 350, 1,
        function(v) return string.format("%d%%", math.floor(v + 0.5)) end)

    ry, cy = group(gx, cy, gw, "外观", 1)
    widget_slider(ui, "sp_wave_opacity", gx, ry, gw, "波形不透明度",
        function() return spotify.wave_opacity end, function(v) spotify.wave_opacity = v end, 0, 100, 1,
        function(v) return string.format("%d%%", math.floor(v + 0.5)) end)

    ry, cy = group(gx, cy, gw, "歌词", 4)
    widget_slider(ui, "sp_lyric_size", gx, ry, gw, "歌词字号",
        function() return spotify.lyric_size end, function(v) spotify.lyric_size = v end, 6, 24, 1,
        function(v) return string.format("%d", math.floor(v + 0.5)) end)
    widget_slider(ui, "sp_lyric_oy", gx, ry + RH, gw, "垂直偏移",
        function() return spotify.lyric_offset_y end, function(v) spotify.lyric_offset_y = v end, -40, 80, 1,
        function(v) return string.format("%d", math.floor(v + 0.5)) end)
    widget_slider(ui, "sp_lyric_ox", gx, ry + 2 * RH, gw, "水平偏移",
        function() return spotify.lyric_offset_x end, function(v) spotify.lyric_offset_x = v end, -60, 60, 1,
        function(v) return string.format("%d", math.floor(v + 0.5)) end)
    widget_slider(ui, "sp_lyric_alpha", gx, ry + 3 * RH, gw, "不透明度",
        function() return spotify.lyric_alpha end, function(v) spotify.lyric_alpha = v end, 0, 255, 1,
        function(v) return string.format("%d", math.floor(v + 0.5)) end)

    return cy
end

local function tab_settings(ui, gx, cy, gw)
    local ry
    
    ry, cy = group(gx, cy, gw, "布局与样式", 2)
    widget_toggle(ui, "sp_vertical", gx, ry, gw, "垂直布局",
        function() return spotify.vertical end, function(v) spotify.vertical = v end)
    widget_selector(ui, "sp_style", gx, ry + RH, gw, "播放器样式",
        function() return spotify.style end, function(v) spotify.style = v end, STYLE_NAMES)

    ry, cy = group(gx, cy, gw, "操作", 1)
    widget_button(ui, "sp_reset_pos", gx, ry, gw, "重置窗口位置", function()
        wx = 70
        wy = 160
        save_position()
    end)

    return cy
end

function NLC_UI._button(label, click, action)
    return { label = label, fn = function()
        if click then NLC_UI.click(click)
        elseif type(action) == "string" and NLC.act and type(NLC.act[action]) == "function" then safe(NLC.act[action])
        elseif type(action) == "function" then safe(action) end
    end }
end

NLC_UI.pages = {
    { name = "播放", groups = {
        { title = "搜索与结果", rows = {
            { kind = "text", c = NLC.kw },
            { kind = "buttons", buttons = { NLC_UI._button("搜索", "搜索") } },
            { kind = "list", c = NLC.res_box },
            { kind = "status", c = NLC.sel_lbl },
        } },
        { title = "用户歌单", rows = {
            { kind = "text", c = NLC.uid_input },
            { kind = "buttons", buttons = { NLC_UI._button("拉取歌单", "拉取歌单") } },
            { kind = "list", c = NLC.pl_box },
            { kind = "buttons", buttons = { NLC_UI._button("载入曲目", "载入曲目") } },
            { kind = "list", c = NLC.track_box },
            { kind = "buttons", buttons = {
                NLC_UI._button("整单播放", "整单播放"), NLC_UI._button("收藏当前", "收藏当前"),
            } },
        } },
        { title = "播放控制", rows = {
            { kind = "buttons", buttons = {
                NLC_UI._button("播放选中", "播放选中"), NLC_UI._button("上一首", nil, "prev_track"),
            } },
            { kind = "buttons", buttons = {
                NLC_UI._button("播放 / 暂停", nil, "toggle"), NLC_UI._button("下一首", nil, "next_track"),
                NLC_UI._button("停止", nil, "stop"),
            } },
            { kind = "slider", c = NLC.vol_sl, step = 1 },
            { kind = "toggle", c = NLC.auto_next },
            { kind = "toggle", c = NLC.shuffle_on },
            { kind = "toggle", c = NLC.repeat_one },
            { kind = "keybind", c = NLC.hk_toggle },
            { kind = "keybind", c = NLC.hk_prev },
            { kind = "keybind", c = NLC.hk_next },
        } },
        { title = "当前播放", rows = {
            { kind = "status", label = "歌名", fn = function() return NLC.cur and NLC.cur.name or "未播放" end },
            { kind = "status", label = "歌手", fn = function() return NLC.cur and NLC.cur.artist or "" end },
            { kind = "status", c = NLC.time_lbl },
            { kind = "status", label = "引擎 / 状态", fn = function()
                local state = NLC.playing and (NLC.paused and "已暂停" or "播放中") or "已停止"
                return tostring(NLC.backend or "none") .. " · " .. state
            end },
        } },
        { title = "Cookie 与设置", rows = {
            { kind = "toggle", c = NLC.insecure_chk },
            { kind = "buttons", buttons = { NLC_UI._button("应用并立即重载脚本", "应用并立即重载脚本") } },
            { kind = "status", c = NLC.cookie_lbl },
            { kind = "buttons", buttons = {
                NLC_UI._button("重载 Cookie", "重新读取 cookie.txt"), NLC_UI._button("导入 Cookie", "从剪贴板导入 Cookie"),
            } },
            { kind = "buttons", buttons = {
                NLC_UI._button("字体检测", "韩文字体自检（日志）"), NLC_UI._button("自检测", "自检（网络 / 解码）"),
            } },
            { kind = "status", c = NLC.info_lbl },
        } },
    } },
    { name = "歌词", groups = {
        { title = "桌面歌词", rows = {
            { kind = "toggle", c = NLC.lyr_on }, { kind = "combo", c = NLC.size_box },
            { kind = "slider", c = NLC.px_sl, step = 1 }, { kind = "slider", c = NLC.py_sl, step = 1 },
            { kind = "color", c = NLC.col_base }, { kind = "color", c = NLC.col_hi },
            { kind = "toggle", c = NLC.lyr_glow_on },
            { kind = "slider", c = NLC.lyr_glow_al, step = 1 },
            { kind = "slider", c = NLC.lyr_glow_sp, step = 0.1 },
            { kind = "toggle", c = NLC.lyr_glow_fol }, { kind = "color", c = NLC.lyr_glow_col },
        } },
        { title = "世界歌词", rows = {
            { kind = "toggle", c = NLC.wl_on }, { kind = "toggle", c = NLC.wl_screen },
            { kind = "toggle", c = NLC.wl_follow }, { kind = "toggle", c = NLC.wl_bounce },
            { kind = "label", label = "节拍" },
            { kind = "toggle", c = NLC.wl_beat_on }, { kind = "slider", c = NLC.wl_bpm, step = 1 },
            { kind = "toggle", c = NLC.wl_bpm_auto }, { kind = "status", c = NLC.bpm_lbl },
            { kind = "slider", c = NLC.wl_beat_amp, step = 1 },
            { kind = "slider", c = NLC.wl_beat_scale, step = 1, suffix = "%" },
            { kind = "slider", c = NLC.wl_beat_dur, step = 1, suffix = "ms" },
            { kind = "label", label = "位置与尺寸" },
            { kind = "slider", c = NLC.wl_dist, step = 1 }, { kind = "slider", c = NLC.wl_side, step = 1 },
            { kind = "slider", c = NLC.wl_height, step = 1 }, { kind = "slider", c = NLC.wl_size, step = 1 },
            { kind = "buttons", buttons = {
                NLC_UI._button("钉在面前", "钉在面前（立即重算锚点）"), NLC_UI._button("清除锚点", "清除锚点"),
            } },
            { kind = "label", label = "颜色与淡入淡出" },
            { kind = "color", c = NLC.wl_col_text }, { kind = "toggle", c = NLC.wl_glow_on },
            { kind = "slider", c = NLC.wl_glow_al, step = 1 },
            { kind = "slider", c = NLC.wl_glow_sp, step = 0.1 }, { kind = "color", c = NLC.wl_col_glow },
            { kind = "slider", c = NLC.wl_fade_in, step = 1, suffix = "ms" },
            { kind = "slider", c = NLC.wl_fade_out, step = 1, suffix = "ms" },
        } },
        { title = "歌词设置", rows = {
            { kind = "slider", c = NLC.lyr_off, step = 1 },
            { kind = "toggle", c = NLC.kara_on }, { kind = "toggle", c = NLC.kr_fallback_cb },
        } },
    } },
    { name = "浮窗", media = true, groups = {} },
}

-- ============================================================
--  DRAW CONTROLS
-- ============================================================
local ds_drag, ds_y0, ds_s0 = false, 0, 0

function NLC_UI._row_height(row, id)
    if row.kind == "text" then return 54 end
    if row.kind == "label" then return 32 end
    if row.kind == "list" then
        local rows = row.c and math.max(1, math.floor(tonumber(row.c.height) or 6)) or 6
        return 28 + rows * 24
    end
    if row.kind == "color" then return RH + (NLC_UI.color_open == id and 4 * RH or 0) end
    return RH
end

function NLC_UI._render_row(ui, row, id, x, ry, w)
    local control, kind = row.c, row.kind
    if kind ~= "status" and kind ~= "buttons" and kind ~= "label" and not control then
        NLC_UI._status(ui, x, ry, w, row.label or kind, function() return "控件不可用" end)
        return
    end
    if kind == "label" then
        text(x + 14, ry + (32 - text_h()) / 2, SECTION, tostring(row.label or ""))
    elseif kind == "toggle" then
        widget_toggle(ui, id, x, ry, w, row.label or control.label, control)
    elseif kind == "slider" then
        local step = row.step or (control.kind == "slider_float" and 0.1 or 1)
        local formatter
        if row.suffix then
            formatter = function(value)
                local base = step < 1 and string.format("%.1f", value)
                    or string.format("%d", math.floor(value + (value >= 0 and 0.5 or -0.5)))
                return base .. row.suffix
            end
        end
        widget_slider(ui, id, x, ry, w, row.label or control.label, control, nil,
            control.min, control.max, step, formatter)
    elseif kind == "combo" then
        widget_selector(ui, id, x, ry, w, row.label or control.label, control, nil, nil, true)
    elseif kind == "text" then
        NLC_UI._text_input(ui, id, x, ry, w, control)
    elseif kind == "list" then
        NLC_UI._list(ui, id, x, ry, w, control)
    elseif kind == "color" then
        NLC_UI._color(ui, id, x, ry, w, control)
    elseif kind == "keybind" then
        NLC_UI._keybind(ui, id, x, ry, w, control)
    elseif kind == "buttons" then
        NLC_UI._button_row(ui, id, x, ry, w, row.buttons)
    elseif kind == "status" then
        NLC_UI._status(ui, x, ry, w, row.label, row.fn or control)
    end
end

function NLC_UI._render_page(ui, page_index, gx, cy, gw)
    local page = NLC_UI.pages[page_index]
    if not page then return cy end
    if page.media then
        cy = tab_spotify(ui, gx, cy, gw)
        return tab_settings(ui, gx, cy, gw)
    end
    for group_index, descriptor in ipairs(page.groups) do
        local height = 0
        for row_index, row in ipairs(descriptor.rows) do
            local id = "nlc:" .. page_index .. ":" .. group_index .. ":" .. row_index .. ":" .. row.kind
            height = height + NLC_UI._row_height(row, id)
        end
        local body_y, next_y = NLC_UI._group(gx, cy, gw, descriptor.title, height, true)
        local row_y = body_y
        for row_index, row in ipairs(descriptor.rows) do
            local id = "nlc:" .. page_index .. ":" .. group_index .. ":" .. row_index .. ":" .. row.kind
            local row_height = NLC_UI._row_height(row, id)
            NLC_UI._render_row(ui, row, id, gx, row_y, gw)
            row_y = row_y + row_height
            if row_index < #descriptor.rows then
                render.rect_filled(gx + 12, row_y, gw - 24, 1, C_SEP)
            end
        end
        cy = next_y
    end
    return cy
end

local function draw_controls(ui, x, y, w, vp_h)
    local gx, gw = x + 14, w - 28
    local vp_y = y
    local max_scroll = math.max(0, content_h - vp_h)
    click_used = false
    NLC_UI.wheel_consumed = false

    if ds_drag then
        if ui.down and ui.menu then scroll_y = ds_s0 - (ui.my - ds_y0)
        else ds_drag = false end
    end

    local thumb_h = max_scroll > 0 and math.max(28, vp_h * vp_h / math.max(1, content_h)) or 0
    if max_scroll > 0 and ui.menu then
        if ui.clicked and in_rect(ui.mx, ui.my, x + w - 20, vp_y, 20, vp_h) then sb_drag = true end
        if sb_drag then
            if ui.down then
                local fraction = (ui.my - vp_y - thumb_h / 2) / math.max(1, vp_h - thumb_h)
                scroll_y = math.max(0, math.min(1, fraction)) * max_scroll
            else sb_drag = false end
        end
    else sb_drag = false end
    scroll_y = math.max(0, math.min(scroll_y, max_scroll))

    if tab_transition < 1 then tab_transition = math.min(1, tab_transition + globals.frametime() * 10) end
    local cui = {
        mx = ui.mx, my = ui.my, down = ui.down, released = ui.released, menu = ui.menu,
        clicked = tab_transition >= 1 and ui.clicked and not sb_drag
            and in_rect(ui.mx, ui.my, x, vp_y, w - 20, vp_h),
        vp_y = vp_y, vp_bottom = vp_y + vp_h,
    }

    render.clip_push(x + 1, vp_y, w - 2, vp_h, true)
    local start, fin = vp_y - scroll_y, nil
    if tab_transition < 1 then
        local ease = 1 - (1 - tab_transition) ^ 3
        local shift_old, shift_new = -anim_dir * ease * gw, anim_dir * (1 - ease) * gw
        local old_cui = { mx = -1, my = -1, down = false, released = false, menu = false, clicked = false,
            vp_y = vp_y, vp_bottom = vp_y + vp_h }
        NLC_UI._render_page(old_cui, prev_tab, gx + shift_old, start, gw)
        fin = NLC_UI._render_page(cui, cur_tab, gx + shift_new, start, gw)
    else
        fin = NLC_UI._render_page(cui, cur_tab, gx, start, gw)
    end
    render.clip_pop()
    content_h = fin - start + 4

    if NLC_UI.wheel ~= 0 and not NLC_UI.wheel_consumed
        and in_rect(ui.mx, ui.my, x, vp_y, w - 20, vp_h) then
        scroll_y = scroll_y - NLC_UI.wheel * 42
    end
    NLC_UI.wheel = 0
    max_scroll = math.max(0, content_h - vp_h)
    scroll_y = math.max(0, math.min(scroll_y, max_scroll))

    if cui.clicked and not click_used then
        NLC_UI._before_action()
        NLC_UI.color_open = nil
        if max_scroll > 0 then ds_drag, ds_y0, ds_s0 = true, ui.my, scroll_y end
    end

    if max_scroll > 0 then
        thumb_h = math.max(28, vp_h * vp_h / math.max(1, content_h))
        local track_x = x + w - 10
        render.rect_filled(track_x, vp_y, 3, vp_h, color(255, 255, 255, 10), 2)
        local thumb_y = vp_y + (vp_h - thumb_h) * (scroll_y / max_scroll)
        render.rect_filled(track_x, thumb_y, 3, thumb_h, ACCENT:alpha(sb_drag and 200 or 120), 2)
    end
end

local function draw_panel(ui)
    if not ui.menu then return end
    local x, y, w, h = panel_win.x, panel_win.y, PW, PH
    refresh_accent()
    render.shadow(x, y, w, h, black(120), 22, 12)
    render.rect_filled(x, y, w, h, C_BG, 12)
    render.rect(x, y, w, h, C_BORDER, 12, 1)

    local tabs_y = y + 16
    local tabs_bottom = draw_tabs(ui, x, tabs_y, w)
    local content_y = tabs_bottom + 12
    local content_bottom = y + h - HEADER_H - 8
    draw_controls(ui, x, content_y, w, math.max(40, content_bottom - content_y))
    draw_header(x, y + h - HEADER_H, w)
end

-- ============================================================
--  МЕДИАПЛЕЕР: состояние
-- ============================================================
local layout_anim = 0

local dragging, was_down, dx, dy = false, false, 0, 0
local command = nil
local seek_target = nil
local seek_dragging = false
local seek_preview = nil
local CMD_SLOT = {prev=17, toggle=20, next=16}
local data = {
    title = "等待 Windows 媒体",
    artist = "",
    source = "",
    position = 0,
    duration = 0,
    playing = false,
    valid = false,
    texture = nil,
    tw = 0,
    th = 0
}
local status = "Starting..."
NLC_UI.media_status = function() return status end
local ffi, combase, kernel, shcore, gdip, user32
local manager, pending, thread, ro_owned, gdip_token
local fatal, loaded, stopped = false, false, false
local next_init = 0
local next_poll, next_meta = 0, 0
local textures, texture_count, cover_key = {}, 0, ""
local scope = {}
local ffi_ready = false
local GUIDS = {}
local last_gc = 0 

local function clear_media()
    data.valid = false
    data.title = "未找到匹配的媒体会话"
    data.artist = ""
    data.source = ""
    data.position = 0
    data.duration = 0
    data.playing = false
    data.texture = nil
    cover_key = ""
    seek_target = nil
    seek_dragging = false
    seek_preview = nil
end

-- ============================================================
--  COM-ПОМОЩНИКИ
-- ============================================================
local function check(hr, where)
    if tonumber(hr) < 0 then
        error(where .. ": HRESULT " .. tostring(tonumber(hr)), 0)
    end
end

local function method(p, slot, signature)
    assert(p ~= nil, "NULL COM interface")
    if type(p) == "cdata" and p == ffi.NULL then
        error("NULL COM interface", 0)
    end
    return ffi.cast(signature, ffi.cast("void***", p)[0][slot])
end

local function release(p)
    if p == nil then return end
    if type(p) == "cdata" and p == ffi.NULL then return end
    pcall(function()
        method(p, 2, "uint32_t (__stdcall *)(void*)")(p)
    end)
end

local function own(p)
    if p ~= nil and not (type(p) == "cdata" and p == ffi.NULL) then
        scope[#scope+1] = p
    end
    return p
end

local function keep(p)
    for i = #scope, 1, -1 do
        if scope[i] == p then table.remove(scope, i); return p end
    end
    return p
end

local function clear_scope()
    local old_scope = scope
    scope = {} 
    for i = #old_scope, 1, -1 do
        pcall(release, old_scope[i])
    end
end

local function guid(text)
    if GUIDS[text] then return GUIDS[text] end
    local s = text:gsub("-", "")
    local g = ffi.new("MW_GUID[1]")
    g[0].a = tonumber(s:sub(1, 8), 16)
    g[0].b = tonumber(s:sub(9, 12), 16)
    g[0].c = tonumber(s:sub(13, 16), 16)
    for i = 0, 7 do g[0].d[i] = tonumber(s:sub(17 + i * 2, 18 + i * 2), 16) end
    GUIDS[text] = g
    return g
end

local function object(p, slot)
    local out = ffi.new("void*[1]")
    check(method(p, slot, "int32_t (__stdcall *)(void*, void**)")(p, out), "COM slot " .. slot)
    return own(out[0])
end

local function query(p, iid)
    local out = ffi.new("void*[1]")
    check(method(p, 0, "int32_t (__stdcall *)(void*, const MW_GUID*, void**)")(p, guid(iid), out), "QueryInterface")
    return own(out[0])
end

local function integer(p, slot, ctype)
    local out = ffi.new(ctype .. "[1]")
    check(method(p, slot, "int32_t (__stdcall *)(void*, " .. ctype .. "*)")(p, out), "Property " .. slot)
    return tonumber(out[0])
end

local function hstring(p, slot)
    local out = ffi.new("void*[1]")
    check(method(p, slot, "int32_t (__stdcall *)(void*, void**)")(p, out), "HSTRING")
    if out[0] == nil then return "" end
    local size = ffi.new("uint32_t[1]")
    local raw = combase.WindowsGetStringRawBuffer(out[0], size)
    local result = ""
    if size[0] > 0 and raw ~= nil then
        local n = kernel.WideCharToMultiByte(65001, 0, raw, size[0], nil, 0, nil, nil)
        if n > 0 then
            local buf = ffi.new("char[?]", n)
            kernel.WideCharToMultiByte(65001, 0, raw, size[0], buf, n, nil, nil)
            result = ffi.string(buf, n)
        end
    end
    combase.WindowsDeleteString(out[0])
    return result
end

local function start_op(p, kind, key)
    assert(p ~= nil, "Empty asynchronous operation")
    pending = {p=keep(p), kind=kind, key=key, born=globals.realtime()}
end

local function cancel_pending()
    if not pending then return end
    local p = pending.p
    pending = nil
    local success, info = pcall(query, p, "00000036-0000-0000-c000-000000000046")
    if success and info then method(info, 9, "int32_t (__stdcall *)(void*)")(info) end
    release(p)
end

local function poll_op()
    local op = pending
    local info = query(op.p, "00000036-0000-0000-c000-000000000046")
    local state = integer(info, 7, "int32_t")
    if state == 0 then
        if globals.realtime() - op.born > 8 then
            cancel_pending()
            error("Windows media request timed out", 0)
        end
        return nil
    end
    local out = ffi.new("void*[1]")
    local hr = 0
    if state == 1 then
        hr = method(op.p, 8, "int32_t (__stdcall *)(void*, void**)")(op.p, out)
    else
        hr = integer(info, 8, "int32_t")
    end
    method(info, 10, "int32_t (__stdcall *)(void*)")(info)
    release(op.p)
    pending = nil
    own(out[0])
    check(hr, "Async result")
    if state ~= 1 then error("Windows media request canceled", 0) end
    return out[0], op.kind, op.key
end

-- ============================================================
--  FFI INIT
-- ============================================================
local function init_native()
    if not client.insecure() then
        status = "请先开启 Allow Insecure，然后点“重新连接”"
        return false
    end
    if not ffi_ready then
        ffi = _G.ffi or require("ffi")
        assert(ffi.abi("64bit") and ffi.os == "Windows", "Windows x64 is required")
        if not pcall(ffi.typeof, "MW_GUID") then
            ffi.cdef[[
                typedef struct { uint32_t a; uint16_t b,c; uint8_t d[8]; } MW_GUID;
                typedef struct { uint32_t version; void* callback; int32_t no_thread; int32_t no_codecs; } MW_GdiStartup;
                typedef struct { int32_t x,y,w,h; } MW_Rect;
                typedef struct { uint32_t w,h; int32_t stride,format; void* scan; uintptr_t reserved; } MW_BitmapData;
                void __stdcall keybd_event(uint8_t, uint8_t, uint32_t, uintptr_t);
                int32_t __stdcall RoInitialize(uint32_t);
                void __stdcall RoUninitialize(void);
                int32_t __stdcall RoGetActivationFactory(void*, const MW_GUID*, void**);
                int32_t __stdcall WindowsCreateString(const uint16_t*, uint32_t, void**);
                int32_t __stdcall WindowsDeleteString(void*);
                const uint16_t* __stdcall WindowsGetStringRawBuffer(void*, uint32_t*);
                int32_t __stdcall WideCharToMultiByte(uint32_t,uint32_t,const uint16_t*,int32_t,char*,int32_t,const char*,int32_t*);
                uint32_t __stdcall GetCurrentThreadId(void);
                void __stdcall GetSystemTimeAsFileTime(void*);
                int32_t __stdcall CreateStreamOverRandomAccessStream(void*,const MW_GUID*,void**);
                int32_t __stdcall GdiplusStartup(uintptr_t*,const MW_GdiStartup*,void*);
                void __stdcall GdiplusShutdown(uintptr_t);
                int32_t __stdcall GdipCreateBitmapFromStream(void*,void**);
                int32_t __stdcall GdipDisposeImage(void*);
                int32_t __stdcall GdipGetImageWidth(void*,uint32_t*);
                int32_t __stdcall GdipGetImageHeight(void*,uint32_t*);
                int32_t __stdcall GdipBitmapLockBits(void*,const MW_Rect*,uint32_t,int32_t,MW_BitmapData*);
                int32_t __stdcall GdipBitmapUnlockBits(void*,MW_BitmapData*);
            ]]
        end
        combase = ffi.load("combase")
        kernel = ffi.load("kernel32")
        shcore = ffi.load("shcore")
        gdip = ffi.load("gdiplus")
        user32 = ffi.load("user32")
        ffi_ready = true
    end
    thread = tonumber(kernel.GetCurrentThreadId())
    local hr = tonumber(combase.RoInitialize(1))
    if hr < 0 and hr ~= -2147417850 then check(hr, "RoInitialize") end
    ro_owned = hr >= 0
    loaded = true
    local token = ffi.new("uintptr_t[1]")
    local startup = ffi.new("MW_GdiStartup[1]")
    startup[0].version = 1
    if gdip.GdiplusStartup(token, startup, nil) == 0 then gdip_token = token[0] end
    local name = "Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager"
    local wide = ffi.new("uint16_t[?]", #name + 1)
    for i = 1, #name do wide[i - 1] = name:byte(i) end
    local hs = ffi.new("void*[1]")
    check(combase.WindowsCreateString(wide, #name, hs), "WindowsCreateString")
    local out = ffi.new("void*[1]")
    hr = combase.RoGetActivationFactory(hs[0], guid("2050c4ee-11a0-57de-aed7-c97c70338245"), out)
    combase.WindowsDeleteString(hs[0])
    check(hr, "Windows media activation")
    own(out[0])
    start_op(object(out[0], 6), "manager")
    status = "正在连接 Windows 媒体..."
    return true
end

local function decode_cover(stream)
    if not gdip_token then return nil, "GDI+ 不可用" end
    if texture_count >= 60 then
        textures = {}
        texture_count = 0
        collectgarbage("collect")
    end
    local native = ffi.new("void*[1]")
    check(shcore.CreateStreamOverRandomAccessStream(stream, guid("0000000c-0000-0000-c000-000000000046"), native), "Cover stream")
    own(native[0])
    local bitmap = ffi.new("void*[1]")
    if gdip.GdipCreateBitmapFromStream(native[0], bitmap) ~= 0 then return nil, "封面格式不受支持" end
    local locked = false
    local bits = ffi.new("MW_BitmapData[1]")
    local success, rgba, ow, oh = pcall(function()
        local w, h = ffi.new("uint32_t[1]"), ffi.new("uint32_t[1]")
        assert(gdip.GdipGetImageWidth(bitmap[0], w) == 0, "Cover width")
        assert(gdip.GdipGetImageHeight(bitmap[0], h) == 0, "Cover height")
        w, h = tonumber(w[0]), tonumber(h[0])
        assert(w > 0 and h > 0 and w <= 4096 and h <= 4096, "Cover dimensions exceed limit")
        local rect = ffi.new("MW_Rect[1]")
        rect[0].w = w
        rect[0].h = h
        assert(gdip.GdipBitmapLockBits(bitmap[0], rect, 1, 2498570, bits) == 0, "Cover lock")
        locked = true
        assert(bits[0].scan ~= nil and math.abs(tonumber(bits[0].stride)) >= w * 4, "Invalid cover buffer")
        local dw, dh = 160, 160
        local buf = ffi.new("uint8_t[?]", dw * dh * 4)
        local base = ffi.cast("uint8_t*", bits[0].scan)
        local side = math.min(w, h)
        local sx0 = math.floor((w - side) / 2)
        local sy0 = math.floor((h - side) / 2)
        local radius = 15
        for yy = 0, dh - 1 do
            local sy = sy0 + math.min(side - 1, math.floor(yy * side / dh))
            local row = base + sy * tonumber(bits[0].stride)
            for xx = 0, dw - 1 do
                local sx = sx0 + math.min(side - 1, math.floor(xx * side / dw))
                local src = sx * 4
                local dst = (yy * dw + xx) * 4
                buf[dst] = row[src + 2]
                buf[dst + 1] = row[src + 1]
                buf[dst + 2] = row[src]
                local dx = math.max(0, radius - xx, xx - (dw - 1 - radius))
                local dy = math.max(0, radius - yy, yy - (dh - 1 - radius))
                local d = math.sqrt(dx * dx + dy * dy)
                local alpha = math.max(0, math.min(1, radius + 0.5 - d))
                buf[dst + 3] = math.floor(row[src + 3] * alpha)
            end
        end
        return ffi.string(buf, dw * dh * 4), dw, dh
    end)
    if locked then gdip.GdipBitmapUnlockBits(bitmap[0], bits) end
    gdip.GdipDisposeImage(bitmap[0])
    if not success then return nil, tostring(rgba) end
    local success2, tex = pcall(render.texture, rgba, ow, oh)
    if not success2 or not tex then return nil, "纹理创建失败" end
    texture_count = texture_count + 1
    return {tex = tex, w = ow, h = oh}
end

local function session()
    local needle = tostring(spotify.filter or ""):lower()
    if needle == "" then return object(manager, 6) end
    local list = object(manager, 7)
    if list == nil then return nil end
    local count = integer(list, 7, "uint32_t")
    local first = nil
    for i = 0, math.min(count, 64) - 1 do
        local out = ffi.new("void*[1]")
        check(method(list, 6, "int32_t (__stdcall *)(void*, uint32_t, void**)")(list, i, out), "Session list")
        local s = own(out[0])
        if s ~= nil and hstring(s, 6):lower():find(needle, 1, true) then
            first = first or s
            local info = object(s, 9)
            if info ~= nil and integer(info, 7, "int32_t") == 4 then return s end
        end
    end
    return first
end

local function update_timeline(s)
    data.position = 0
    data.duration = 0
    data.playing = false
    local playback = object(s, 9)
    local rate = 1
    if playback ~= nil then
        data.playing = integer(playback, 7, "int32_t") == 4
        local ref = object(playback, 10)
        if ref ~= nil then rate = integer(ref, 6, "double") end
    end
    local timeline = object(s, 8)
    if timeline ~= nil then
        local first = integer(timeline, 6, "int64_t") / 10000000
        local last = integer(timeline, 7, "int64_t") / 10000000
        local pos = integer(timeline, 10, "int64_t") / 10000000
        local updated = integer(timeline, 11, "int64_t") / 10000000
        if data.playing and updated > 0 then
            local ft = ffi.new("uint64_t[1]")
            kernel.GetSystemTimeAsFileTime(ft)
            local dt = tonumber(ft[0]) / 10000000 - updated
            if dt >= 0 and dt < 86400 then pos = pos + dt * rate end
        end
        data.duration = math.max(0, last - first)
        data.position = math.max(0, pos - first)
        if data.duration > 0 then data.position = math.min(data.position, data.duration) end
    end
end

local last_dbg = ""
local function dbg()
    if status ~= last_dbg then
        last_dbg = status
        if status:find('错误', 1, true) or status:find('失败', 1, true)
            or status:find('Allow Insecure', 1, true) then
            print('[Media widget] ' .. status)
        end
    end
end

local function send_media_key(id)
    if not user32 then return false end
    local vk = (id == 'prev') and 0xB1 or 0xB0
    local ok = pcall(function()
        user32.keybd_event(vk, 0, 0, 0)
        user32.keybd_event(vk, 0, 2, 0)
    end)
    return ok
end

local function step()
    dbg()
    if not loaded then
        local t = globals.realtime()
        if t < next_init then return end
        next_init = t + 1.0
        init_native()
        dbg()
        return
    end
    assert(tonumber(kernel.GetCurrentThreadId()) == thread, "COM thread changed; reload script")
    if pending then
        local result, kind, key = poll_op()
        if kind == nil then return end
        if kind == "manager" then
            assert(result ~= nil, "Windows returned no manager")
            manager = keep(result)
            status = "正在等待匹配的媒体..."
        elseif kind == "properties" then
            assert(result ~= nil, "No media properties")
            data.title = hstring(result, 6)
            data.artist = hstring(result, 9)
            local newkey = data.source .. "\n" .. data.title .. "\n" .. data.artist
            if newkey ~= cover_key then
                cover_key = newkey
                data.texture = nil
            end
            local cached = textures[newkey]
            if cached then
                data.texture = cached.tex
                data.tw = cached.w
                data.th = cached.h
            end
            status = data.playing and "播放中" or "已暂停 / 已停止"
            if not data.texture and data.title ~= "" then
                local thumb = object(result, 15)
                if thumb ~= nil then
                    start_op(object(thumb, 6), "cover", newkey)
                else
                    status = status .. " - 浏览器未提供封面"
                end
            end
        elseif kind == "cover" and key == cover_key and result ~= nil then
            local cover, err = decode_cover(result)
            if cover then
                textures[key] = cover
                data.texture = cover.tex
                data.tw = cover.w
                data.th = cover.h
            else
                status = err or "无封面"
            end
        end
        return
    end
    local now = globals.realtime()
    if not manager or now < next_poll then return end
    next_poll = now + 0.5
    local s = session()
    if s ~= nil and command then
        local action = command
        command = nil
        local chrome = (data.source or ''):lower():find('chrome', 1, true) ~= nil
        if chrome and (action == 'prev' or action == 'next') then
            if not send_media_key(action) then
                status = 'Windows 媒体键发送失败'
            end
        else
            local slot = CMD_SLOT[action]
            local out = ffi.new('void*[1]')
            local hr = method(s, slot, 'int32_t (__stdcall *)(void*, void**)')(s, out)
            if out[0] ~= nil then release(out[0]) end
            if tonumber(hr) < 0 then status = '控制失败：HRESULT ' .. tostring(tonumber(hr)) end
        end
        next_poll = 0
        next_meta = 0
    end
    if s ~= nil and seek_target ~= nil and data.duration > 0 then
        local out = ffi.new('void*[1]')
        local target_100ns = math.floor(math.max(0, math.min(data.duration, seek_target)) * 10000000)
        local hr = method(s, 24, 'int32_t (__stdcall *)(void*, int64_t, void**)')(s, target_100ns, out)
        if out[0] ~= nil then release(out[0]) end
        next_poll = 0
        next_meta = 0
        if tonumber(hr) < 0 then
            status = '跳转失败：HRESULT ' .. tostring(tonumber(hr))
        else
            data.position = math.max(0, math.min(data.duration, seek_target))
        end
        seek_target = nil
    end
    if s == nil then
        clear_media()
        status = "无媒体会话：可尝试清空来源过滤"
        return
    end
    local source = hstring(s, 6)
    if source ~= data.source then
        clear_media()
        next_meta = 0
    end
    data.source = source
    data.valid = true
    update_timeline(s)
    if now >= next_meta then
        next_meta = now + 2
        start_op(object(s, 7), "properties")
    end
end

-- ============================================================
--  AUDIO
-- ============================================================
local audio = {
    meter = nil,
    ole = nil,
    level = 0,
    peak = 0,
    next = 0,
    failed = false,
    last_attempt = -10,
    dynamic_peak = 0,
    last_sound = 0,
    baseline = 0,
    smoothed_peak = 0,
    mode = "无音频设备",
    cdef_done = false
}

local function audio_release()
    if audio.meter then
        pcall(release, audio.meter)
        audio.meter = nil
    end
end

local function audio_init()
    if not ffi_ready or not loaded or not client.insecure() or not ffi then return false end
    if audio.meter then return true end
    if not audio.ole then
        if not audio.cdef_done then
            pcall(ffi.cdef, [[int32_t __stdcall CoCreateInstance(const MW_GUID*, void*, uint32_t, const MW_GUID*, void**);]])
            audio.cdef_done = true
        end
        audio.ole = ffi.load('ole32')
    end
    local enumerator = ffi.new('void*[1]')
    local hr = tonumber(audio.ole.CoCreateInstance(
        guid('BCDE0395-E52F-467C-8E3D-C4579291692E'), nil, 1,
        guid('A95664D2-9614-4F35-A746-DE8DB63617E6'), enumerator))
    if not hr or hr < 0 or enumerator[0] == nil then return false end
    local device = ffi.new('void*[1]')
    hr = tonumber(method(enumerator[0], 4, 'int32_t (__stdcall *)(void*, int32_t, int32_t, void**)')(enumerator[0], 0, 1, device))
    release(enumerator[0])
    if not hr or hr < 0 or device[0] == nil then return false end
    local met = ffi.new('void*[1]')
    hr = tonumber(method(device[0], 3, 'int32_t (__stdcall *)(void*, const MW_GUID*, uint32_t, void*, void**)')(
        device[0], guid('C02216F6-8C67-4B5B-9D00-D008E73E0064'), 1, nil, met))
    release(device[0])
    if not hr or hr < 0 or met[0] == nil then return false end
    audio.meter = met[0]
    return true
end

local audio_release_for_shutdown = audio_release

local function audio_tick(now, dt)
    local target = 0
    if (spotify.edge_glow or (spotify.perimeter_wave_enabled and not spotify.perimeter_wave_disable_playing)) and data.valid and data.playing and ffi_ready then
        if not audio.meter and now - audio.last_attempt >= 3 then
            audio.last_attempt = now
            local ok, result = pcall(audio_init)
            if not ok or not result then
                audio.failed = true
                audio.mode = "无音频设备"
            else
                audio.failed = false
                audio.mode = "音量计就绪"
            end
        end
        if audio.meter and now >= audio.next then
            audio.next = now + 0.035
            local ok, value = pcall(function()
                local v = ffi.new('float[1]')
                local hr = tonumber(method(audio.meter, 3, 'int32_t (__stdcall *)(void*, float*)')(audio.meter, v))
                if not hr or hr < 0 then error('Core Audio peak read failed') end
                return tonumber(v[0])
            end)
            if ok then
                audio.peak = math.max(0, math.min(1, value or 0))
                if audio.peak > 0.002 then audio.last_sound = now end
                local sample_dt = 0.035
                audio.dynamic_peak = math.max(audio.peak, audio.dynamic_peak * math.exp(-sample_dt / 2.4))
                audio.baseline = audio.baseline + (audio.peak - audio.baseline) * math.min(1, sample_dt * 5)
                audio.mode = audio.peak > 0.002 and "实时峰值" or "静音峰值"
            else
                audio_release()
                audio.peak = 0
                audio.mode = "音量计错误"
            end
        end
        if audio.peak > 0.002 then
            local ceiling = math.max(0.025, audio.dynamic_peak)
            local level = math.min(1, audio.peak / ceiling)
            local movement = math.max(0, audio.peak - audio.baseline) / ceiling
            local response = spotify.glow_response / 100
            local contrast = math.max(0, level - 0.25)
            target = math.min(1, (contrast * contrast * 1.25 + movement * 1.8) * response)
        elseif spotify.animated_fallback then
            target = 0.17 + 0.08 * math.sin(now * 3.2) ^ 2
            audio.mode = audio.meter and "模拟 / 静音" or "模拟 / 无设备"
        end
    else
        audio.mode = data.playing and "未就绪" or "已暂停"
    end
    local smoothing = 1 - math.exp(-dt * (target > audio.level and 85 or 12))
    audio.level = audio.level + (target - audio.level) * smoothing
end

-- ============================================================
--  ОТРИСОВКА ВОЛНЫ ПО ПЕРИМЕТРУ
-- ============================================================
local function draw_perimeter_wave(x, y, w, h, s, now, a, strength, active, power)
    local r = 13 * s
    local straight_w = w - 2 * r
    local straight_h = h - 2 * r
    local arc = math.pi * r / 2
    local perimeter = 2 * (straight_w + straight_h) + 4 * arc
    local phases = {
        0, straight_w, straight_w + arc,
        straight_w + arc + straight_h, straight_w + 2 * arc + straight_h,
        2 * straight_w + 2 * arc + straight_h,
        2 * straight_w + 3 * arc + straight_h,
        2 * straight_w + 3 * arc + 2 * straight_h
    }

    local function point(d)
        local xx, yy, nx, ny
        if d < phases[2] then
            xx = r + d; yy = 0; nx = 0; ny = -1
        elseif d < phases[3] then
            local ang = -math.pi / 2 + (d - phases[2]) / r
            nx = math.cos(ang); ny = math.sin(ang)
            xx = w - r + r * nx; yy = r + r * ny
        elseif d < phases[4] then
            xx = w; yy = r + d - phases[3]; nx = 1; ny = 0
        elseif d < phases[5] then
            local ang = (d - phases[4]) / r
            nx = math.cos(ang); ny = math.sin(ang)
            xx = w - r + r * nx; yy = h - r + r * ny
        elseif d < phases[6] then
            xx = w - r - (d - phases[5]); yy = h; nx = 0; ny = 1
        elseif d < phases[7] then
            local ang = math.pi / 2 + (d - phases[6]) / r
            nx = math.cos(ang); ny = math.sin(ang)
            xx = r + r * nx; yy = h - r + r * ny
        elseif d < phases[8] then
            xx = 0; yy = h - r - (d - phases[7]); nx = -1; ny = 0
        else
            local ang = math.pi + (d - phases[8]) / r
            nx = math.cos(ang); ny = math.sin(ang)
            xx = r + r * nx; yy = r + r * ny
        end
        return xx, yy, nx, ny
    end

    local t = now * 1.20
    local audio_power = active and math.max(0, math.min(1, power)) or 0
    local amp = (7.4 + 5.8 * audio_power) * strength ^ 0.35 * s
    local intensity = (0.78 + 0.22 * audio_power) * strength
    local last_x, last_y
    local samples = 96
    for i = 0, samples do
        local u = i / samples
        local px, py, nx, ny = point(u * perimeter)
        local wave = 0.58 * math.sin(2 * math.pi * 6 * u - t)
            + 0.27 * math.sin(2 * math.pi * 11 * u + t * 0.83 + 0.45)
            + 0.15 * math.sin(2 * math.pi * 17 * u - t * 1.17 + 0.7)
        local displacement = 2.2 * s + amp * (0.72 + wave * 0.72)
        local xx = x + px + nx * displacement
        local yy = y + py + ny * displacement
        if last_x then
            for layer = 1, 3 do
                local width = ({9, 3.8, 1.5})[layer] * s
                local alpha = math.floor(({18, 75, 205})[layer] * intensity)
                if alpha > 0 then
                    render.line(
                        last_x, last_y, xx, yy,
                        color(a.r, a.g, a.b, math.min(255, alpha)),
                        math.max(1, width)
                    )
                end
            end
        end
        last_x, last_y = xx, yy
    end
end

-- ============================================================
--  ГЛАВНАЯ ОТРИСОВКА МЕДИАПЛЕЕРА
-- ============================================================
local visual = { progress = 0, glow = 0, last = 0, hover = 0 }

local function safe_width(value, sz, ft)
    local ok, w = pcall(render.text_size, value, "", sz, ft)
    return (ok and tonumber(w)) or #value * sz * 0.56
end

local function crop(value, maxw, sz, ft)
    value = tostring(value or "")
    if safe_width(value, sz, ft) <= maxw then return value end
    local tail = "..."
    while #value > 0 and safe_width(value .. tail, sz, ft) > maxw do
        local previous = NLC_UI._utf8_prev(value, #value + 1)
        value = value:sub(1, previous - 1)
    end
    return value .. tail
end

local function draw_media_widget()
    if not spotify.enabled then return end

    -- 网易云数据覆盖：网易云代码运行在 nlc_env（即 NLC）里，cur/playing/lyrics 等
    -- 都存在 NLC 表中，不是全局 _G。这里从 NLC 读取并覆盖浮窗的 data。
    local widget_lyric = ""
    local nc = NLC.cur
    if nc then
        local has_tex = (NLC.hud and NLC.hud.tex) ~= nil
        if cover_dbg_id ~= nc.id or cover_dbg_has ~= has_tex then
            cover_dbg_id = nc.id
            cover_dbg_has = has_tex
            local szs = "nil"
            if has_tex then
                pcall(function()
                    local s2 = NLC.hud.tex.size
                    szs = tostring(s2.x) .. "x" .. tostring(s2.y)
                end)
            end
            print("[cover] 浮窗检查 id=" .. tostring(nc.id) .. " hud.tex=" .. szs
                .. " pic=" .. tostring(nc.pic_url))
        end
        data.valid = true
        data.title = tostring(nc.name or "")
        data.artist = tostring(nc.artist or "")
        data.duration = (NLC.len_ms or 0) / 1000
        -- 还原 timeline_ms()：暂停用 pos_ms，否则用 (now - start_t)*1000
        local rt = globals.realtime()
        local t_ms = NLC.paused and (NLC.pos_ms or 0)
                or ((rt - (NLC.start_t or rt)) * 1000)
        data.position = t_ms / 1000
        data.playing = NLC.playing and not NLC.paused
        if NLC.hud and NLC.hud.tex then
            data.texture = NLC.hud.tex
            data.tw, data.th = 192, 192
        else
            data.texture = nil
        end
        -- 取当前歌词行（复刻 cur_line_index 逻辑）
        widget_lyric = ""
        if NLC.playing and NLC.lyrics and #NLC.lyrics > 0 then
            local off = 0
            pcall(function() off = NLC.lyr_off and NLC.lyr_off:get() or 0 end)
            local t = (t_ms + off) / 1000
            local idx = 0
            for i = 1, #NLC.lyrics do
                if NLC.lyrics[i].t <= t then idx = i else break end
            end
            if idx > 0 and NLC.lyrics[idx] then
                widget_lyric = tostring(NLC.lyrics[idx].text or "")
            end
        end
    else
        data.valid = false
        data.title = ""
        data.artist = ""
        data.duration = 0
        data.position = 0
        data.playing = false
        data.texture = nil
        widget_lyric = ""
    end

    local target_layout = spotify.vertical and 1 or 0
    layout_anim = layout_anim + (target_layout - layout_anim) * math.min(1, globals.frametime() * 10)
    if math.abs(target_layout - layout_anim) < 0.001 then layout_anim = target_layout end

    local W = lerp(344, 240, layout_anim)
    local H = lerp(110, 270, layout_anim)
    
    local s = spotify.scale / 100
    local w, h = W * s, H * s
    local sw, sh = render.screen_size()
    local exterior = 22 * s
    wx = math.max(exterior, math.min(wx, math.max(exterior, sw - w - exterior)))
    wy = math.max(exterior, math.min(wy, math.max(exterior, sh - h - exterior)))

    local mx, my = input.cursor()
    local down = input.key_down(1)
    local menu = input.menu_open()
    local panel_blocked = menu and NLC_UI.panel.inside
    local pressed = down and not was_down and not panel_blocked
    local released = (not down) and was_down and not panel_blocked
    if panel_blocked and (dragging or seek_dragging) then
        dragging = false
        seek_dragging = false
        seek_preview = nil
        save_position()
    end

    local now = globals.realtime()
    local delta = math.max(0, math.min(0.08, now - (visual.last > 0 and visual.last or now)))
    visual.last = now
    local fade = math.min(1, delta * 12)
    local ratio = (data.duration > 0 and data.position / data.duration) or 0
    ratio = clamp01(ratio)
    if math.abs(visual.progress - ratio) > 0.25 or not data.valid then
        visual.progress = ratio
    else
        visual.progress = lerp(visual.progress, ratio, fade)
    end
    visual.glow = lerp(visual.glow, data.playing and 1 or 0, fade)
    audio_tick(now, delta)

    local a = ACCENT
    local white_c = color(244, 244, 248)
    local muted = color(152, 155, 172)
    local subtle = color(106, 109, 126)
    local panel = color(24, 25, 34, 235)
    local panel2 = color(30, 31, 42, 240)

    local function R(xx, yy, ww, hh, c, r)
        render.rect_filled(wx + xx * s, wy + yy * s, ww * s, hh * s, c, (r or 0) * s)
    end
    local function T(xx, yy, str, c, sz, ft)
        render.text(wx + xx * s, wy + yy * s, c, str or '', '', (sz or 12) * s, ft or FONT)
    end
    local function C(cx, cy, rad, c)
        render.circle_filled(wx + cx * s, wy + cy * s, rad * s, c, 32)
    end

    -- Хелпер для бегущей строки
    local function draw_text_marquee(x_start, y, str, col, sz, ft, max_w, align_center)
        local tw = safe_width(str, sz * s, ft) / s
        if tw <= max_w then
            local dx = align_center and (x_start + (max_w - tw) / 2) or x_start
            T(dx, y, str, col, sz, ft)
        else
            local gap = 40
            local total_w = tw + gap
            local offset = (now * 30) % total_w
            
            render.clip_push(wx + x_start * s, wy + (y - 2) * s, max_w * s, (sz + 4) * s, true)
            
            local dx1 = x_start - offset
            T(dx1, y, str, col, sz, ft)
            
            local dx2 = dx1 + total_w
            if dx2 < x_start + max_w then
                T(dx2, y, str, col, sz, ft)
            end
            
            render.clip_pop()
        end
    end

    -- Интерполяция позиций элементов
    local cover_x = lerp(12, 60, layout_anim)
    local cover_y = lerp(23, 20, layout_anim)
    local cover_s = lerp(64, 120, layout_anim)
    
    local text_x = lerp(88, 20, layout_anim)
    local text_y = lerp(28, 150, layout_anim)
    local text_w = lerp(158, 200, layout_anim)
    
    local px = lerp(88, 20, layout_anim)
    local py = lerp(87, 245, layout_anim)
    local pw = lerp(160, 200, layout_anim)

    local b_prev_cx = lerp(264, 84, layout_anim)
    local b_toggle_cx = lerp(292, 120, layout_anim)
    local b_next_cx = lerp(320, 156, layout_anim)
    local b_cy = lerp(53, 212, layout_anim)
    
    local b_prev_r = lerp(12, 14, layout_anim)
    local b_toggle_r = lerp(14, 18, layout_anim)
    local b_next_r = lerp(12, 14, layout_anim)

    local buttons = {
        {id = 'prev', cx = b_prev_cx, cy = b_cy, r = b_prev_r},
        {id = 'toggle', cx = b_toggle_cx, cy = b_cy, r = b_toggle_r},
        {id = 'next', cx = b_next_cx, cy = b_cy, r = b_next_r},
    }

    local progress_hovered = menu and not panel_blocked and mx >= wx + px * s and mx <= wx + (px + pw) * s and my >= wy + (py - 5) * s and my <= wy + (py + 8) * s
    local buttons_hovered = false
    for _, b in ipairs(buttons) do
        local bx1, by1 = wx + (b.cx - b.r) * s, wy + (b.cy - b.r) * s
        local bx2, by2 = wx + (b.cx + b.r) * s, wy + (b.cy + b.r) * s
        b.hovered = menu and not panel_blocked and not dragging and mx >= bx1 and mx <= bx2 and my >= by1 and my <= by2
        if b.hovered then buttons_hovered = true end
    end

    if menu and pressed and progress_hovered and data.valid and data.duration > 0 then
        seek_dragging = true
    end
    if seek_dragging then
        local ratio_drag = clamp01((mx - (wx + px * s)) / (pw * s))
        seek_preview = ratio_drag
        visual.progress = ratio_drag
        if released then
            local target = ratio_drag * data.duration
            if NLC.cur then
                local target_ms = target * 1000
                -- 真正驱动音频跳转；ds_seek_ms 成功时会同步 start_t / pos_ms / last_poll
                local ok = false
                pcall(function() ok = NLC.ds_seek_ms(target_ms) end)
                if ok then
                    data.position = target
                end
            end
            seek_dragging = false
        end
    elseif released then
        seek_preview = nil
        seek_dragging = false
    end

    local drag_area = menu and not panel_blocked and not buttons_hovered and not progress_hovered and mx >= wx and mx <= wx + w and my >= wy and my <= wy + h
    if drag_area and pressed then
        dragging = true
        dx = mx - wx
        dy = my - wy
    end
    if dragging then
        if menu and down then
            wx = math.max(exterior, math.min(mx - dx, math.max(exterior, sw - w - exterior)))
            wy = math.max(exterior, math.min(my - dy, math.max(exterior, sh - h - exterior)))
        else
            dragging = false
            save_position()
        end
    end
    was_down = down

    -- Отрисовка фона в зависимости от стиля
    if spotify.style == 1 then
        -- Default Style
        if spotify.edge_glow then
            local strength = spotify.glow_strength / 100
            local active = data.valid and data.playing
            local peak = active and math.max(0, math.min(1, audio.level)) or 0
            local alpha = active and math.floor((0.22 + 0.78 * peak) * strength * 235)
                or math.floor(48 * strength)
            if alpha > 0 then
                render.shadow(wx, wy, w, h, color(a.r, a.g, a.b, alpha), 13 * s, 22 * s)
            end
        end
        
        if spotify.perimeter_wave_enabled and not (data.valid and data.playing and spotify.perimeter_wave_disable_playing) then
            draw_perimeter_wave(wx, wy, w, h, s, now, a, 0.83, data.valid and data.playing, audio.level)
        end

        render.rect_filled(wx, wy, w, h, color(13, 14, 22, 210), 13 * s)

        if spotify.dark_wave and spotify.wave_opacity > 0 then
            local wave_a = spotify.wave_opacity / 100
            local pad = 13 * s
            local clipped = pcall(render.clip_push, wx + pad, wy + pad, w - 2 * pad, h - 2 * pad, true)
            local t = now * 0.5
            local amp = 12.5 * s
            local step_y = 12 * s
            local step_x = 8 * s
            local y0 = wy + pad
            local y1 = wy + h - pad
            local x0 = wx + pad
            local x1 = wx + w - pad
            for yy = y0, y1, step_y do
                local yn = (yy - wy) / h
                local envelope = math.max(0, math.sin(yn * math.pi))
                local brush = 0.55 + 0.45 * math.sin(yy * 0.045 + t * 0.35)
                local prevx, prevy = nil, nil
                for xx = x0, x1, step_x do
                    local shape = math.sin(xx * 0.008 + yy * 0.015 + t * 0.9) * amp
                        + math.sin(xx * 0.017 - yy * 0.020 + t * 0.7) * amp * 0.4
                        + math.cos(xx * 0.004 + t * 0.5) * amp * 0.6
                    local pyy = yy + shape * envelope
                    local xn = math.abs((xx - wx) / w - 0.5) * 2
                    local intensity = math.max(0, 1 - xn * xn) * (0.3 + envelope * 0.7) * brush
                    if prevx then
                        local alpha = math.floor(90 * wave_a * intensity)
                        if alpha > 3 then
                            render.line(prevx, prevy, xx, pyy, color(190, 199, 224, alpha), 1 * s)
                        end
                    end
                    prevx, prevy = xx, pyy
                end
            end
            if clipped then pcall(render.clip_pop) end
        end

        render.rect(wx, wy, w, h, color(65, 67, 84, 92), 13 * s, 1 * s)

    elseif spotify.style == 2 then
        -- Minimalist Style
        render.rect_filled(wx, wy, w, h, color(18, 18, 24, 240), 12 * s)
        render.rect(wx, wy, w, h, color(255, 255, 255, 30), 12 * s, 1 * s)
        
        if spotify.edge_glow then
            local strength = spotify.glow_strength / 100
            local active = data.valid and data.playing
            local peak = active and math.max(0, math.min(1, audio.level)) or 0
            if active and peak > 0.01 then
                render.shadow(wx, wy, w, h, color(a.r, a.g, a.b, math.floor(peak * 50 * strength)), 12 * s, 15 * s)
            end
        end

    elseif spotify.style == 3 then
        -- Glass Style
        render.rect_filled(wx, wy, w, h, color(255, 255, 255, 12), 14 * s)
        render.rect(wx, wy, w, h, color(255, 255, 255, 40), 14 * s, 1 * s)
        
        -- Внутреннее свечение
        render.rect_filled(wx + 1, wy + 1, w - 2, h - 2, color(255, 255, 255, 5), 13 * s)
        
        if spotify.edge_glow then
            local strength = spotify.glow_strength / 100
            local active = data.valid and data.playing
            local peak = active and math.max(0, math.min(1, audio.level)) or 0
            local alpha = active and math.floor((0.15 + 0.85 * peak) * strength * 200) or math.floor(60 * strength)
            if alpha > 0 then
                render.shadow(wx, wy, w, h, color(a.r, a.g, a.b, alpha), 14 * s, 18 * s)
            end
        end
    end

    -- Отрисовка контента
    R(cover_x, cover_y, cover_s, cover_s, color(24, 25, 34, 200), 12 * lerp(10/12, 1, layout_anim))
    if data.texture and data.tw > 0 and data.th > 0 then
        render.image(data.texture, wx + cover_x * s, wy + cover_y * s, cover_s * s, cover_s * s, white_c, 12 * lerp(10/12, 1, layout_anim) * s)
    else
        local wyy1_icon = get_wyy1_icon()
        if wyy1_icon then
            render.image(wyy1_icon, wx + cover_x * s, wy + cover_y * s, cover_s * s, cover_s * s, white_c, 12 * s)
        else
            local cx = cover_x + cover_s / 2
            local cy = cover_y + cover_s / 2
            C(cx, cy, cover_s / 2, SPOTIFY_GREEN)
            for deg = -60, 60, 3 do
                local rad = math.rad(deg)
                local px2 = cx + math.sin(rad) * (cover_s / 4)
                local py2 = cy + (1 - math.cos(rad)) * (cover_s / 4) - 4
                C(px2, py2, cover_s / 20, white_c)
            end
        end
    end

    local displaytitle = data.valid and (data.title ~= '' and data.title or '未知歌曲') or '当前没有播放'
    local displayartist = data.valid and (data.artist ~= '' and data.artist or '网易云音乐') or '请开始播放'
    
    if layout_anim > 0.5 then
        -- 竖排：居中滚动
        draw_text_marquee(15, text_y, displaytitle, white_c, 14, FONT, W - 30, true)
        draw_text_marquee(15, text_y + 18, displayartist, muted, 11, FONT, W - 30, true)
        if widget_lyric ~= "" then
            local lsz = spotify.lyric_size
            draw_text_marquee(15 + spotify.lyric_offset_x, text_y + 36 + spotify.lyric_offset_y,
                widget_lyric, color(200, 210, 230, spotify.lyric_alpha), lsz, FONT, W - 30, true)
        end
    else
        -- 横排：滚动
        draw_text_marquee(text_x, text_y, displaytitle, white_c, 14, FONT, text_w, false)
        draw_text_marquee(text_x, text_y + 18, displayartist, muted, 11, FONT, text_w, false)
        
        local status_text = data.valid and (data.playing and '播放中' or '已暂停') or '离线'
        local pill_w = safe_width(status_text, 9 * s, FONT) / s + 16
        R(text_x, text_y + 33, pill_w, 15, color(33, 35, 47, 210), 8)
        C(text_x + 8, text_y + 40.5, 2.3, data.playing and color(a.r, a.g, a.b, 235) or subtle)
        T(text_x + 14, text_y + 35.5, status_text, muted, 9, FONT)

        if widget_lyric ~= "" then
            local lsz = spotify.lyric_size
            draw_text_marquee(text_x + spotify.lyric_offset_x, text_y + 52 + spotify.lyric_offset_y,
                widget_lyric, color(200, 210, 230, spotify.lyric_alpha), lsz, FONT, text_w, false)
        end
    end

    local shown_progress = seek_dragging and seek_preview or visual.progress
    R(px, py, pw, 3, color(50, 52, 67, 255), 2)
    if shown_progress and shown_progress > 0 then
        R(px, py, pw * shown_progress, 3, color(a.r, a.g, a.b, 235), 2)
        C(px + pw * shown_progress, py + 1.5, 3.4, color(a.r, a.g, a.b, 245))
    end
    T(px, py + 8, (data.valid and timestamp(seek_dragging and (seek_preview * data.duration) or data.position)) or '--:--', subtle, 9, FONT)
    local endtext = data.duration > 0 and timestamp(data.duration) or '--:--'
    T(px + pw - safe_width(endtext, 9 * s, FONT) / s, py + 8, endtext, subtle, 9, FONT)

    for _, b in ipairs(buttons) do
        if b.hovered and pressed and NLC.cur then
            local na = NLC.act
            if b.id == 'toggle' and na and na.toggle then na.toggle()
            elseif b.id == 'next' and na and na.next_track then na.next_track()
            elseif b.id == 'prev' and na and na.prev_track then na.prev_track() end
        end
        local bg = (b.id == 'toggle') and color(a.r, a.g, a.b, 220) or (b.hovered and color(48, 50, 66, 255) or panel2)
        C(b.cx, b.cy, b.r, bg)
        local cc = (b.id == 'toggle') and color(20, 20, 28) or (data.valid and white_c or subtle)
        
        local base_r = (b.id == 'toggle') and 5 or 4
        local base_w = (b.id == 'toggle') and 2.6 or 1.8
        local base_h = (b.id == 'toggle') and 10 or 10
        local scale_r = b.r / 14

        if b.id == 'prev' then
            R(b.cx - 6 * scale_r, b.cy - 5 * scale_r, 1.8 * scale_r, 10 * scale_r, cc, 0)
            render.triangle_filled(
                wx + (b.cx + 4 * scale_r) * s, wy + (b.cy - 5 * scale_r) * s,
                wx + (b.cx + 4 * scale_r) * s, wy + (b.cy + 5 * scale_r) * s,
                wx + (b.cx - 4 * scale_r) * s, wy + b.cy * s, cc
            )
        elseif b.id == 'next' then
            R(b.cx + 4.2 * scale_r, b.cy - 5 * scale_r, 1.8 * scale_r, 10 * scale_r, cc, 0)
            render.triangle_filled(
                wx + (b.cx - 4 * scale_r) * s, wy + (b.cy - 5 * scale_r) * s,
                wx + (b.cx - 4 * scale_r) * s, wy + (b.cy + 5 * scale_r) * s,
                wx + (b.cx + 4 * scale_r) * s, wy + b.cy * s, cc
            )
        elseif data.playing then
            R(b.cx - 4.5 * scale_r, b.cy - 5 * scale_r, 2.6 * scale_r, 10 * scale_r, cc, 1)
            R(b.cx + 1.9 * scale_r, b.cy - 5 * scale_r, 2.6 * scale_r, 10 * scale_r, cc, 1)
        else
            render.triangle_filled(
                wx + (b.cx - 3 * scale_r) * s, wy + (b.cy - 6 * scale_r) * s,
                wx + (b.cx - 3 * scale_r) * s, wy + (b.cy + 6 * scale_r) * s,
                wx + (b.cx + 6 * scale_r) * s, wy + b.cy * s, cc
            )
        end
    end

    if not data.valid then
        local msg = '在播放页搜索并播放歌曲'
        local mw = safe_width(msg, 9 * s, FONT) / s
        local msg_x = layout_anim > 0.5 and (W - mw) / 2 or 246
        T(msg_x, py - 12, msg, subtle, 9, FONT)
    end
end

-- ============================================================
--  SHUTDOWN
-- ============================================================
local function shutdown_native()
    if loaded and tonumber(kernel.GetCurrentThreadId()) ~= thread then
        print("[Media widget] Cleanup skipped on different COM thread")
        return false
    end
    if audio_release_for_shutdown then audio_release_for_shutdown() end
    if ffi_ready then
        cancel_pending()
        clear_scope()
    end
    if manager then
        release(manager)
        manager = nil
    end
    if gdip_token then
        gdip.GdiplusShutdown(gdip_token)
        gdip_token = nil
    end
    if ro_owned then
        combase.RoUninitialize()
        ro_owned = false
    end
    loaded = false
    return true
end

-- ============================================================
--  ПЛАВАЮЩАЯ ПАНЕЛЬ: клавиатура / текст / колесо
-- ============================================================
events.on("input", function(msg, wparam)
    if not input.menu_open() then
        if NLC_UI.text_focus or NLC_UI.key_capture then NLC_UI._reset_transient(true) end
        return nil
    end

    if msg == 0x020A then
        if not NLC_UI.panel.inside then return nil end
        wparam = tonumber(wparam) or 0
        local delta
        if math.abs(wparam) <= 2048 then delta = wparam
        else delta = math.floor(wparam / 65536) end
        if delta >= 32768 then delta = delta - 65536 end
        NLC_UI.wheel = NLC_UI.wheel + delta / 120
        return true
    end

    local captured = NLC_UI.key_capture
    if captured then
        if msg ~= 0x0100 and msg ~= 0x0104 then return true end
        if wparam == 0x1B then
            NLC_UI.key_capture = nil
            NLC_UI.key_capture_original = nil
        elseif wparam == 0x2E or wparam == 0x08 then
            captured:change(0)
            NLC_UI.key_capture = nil
            NLC_UI.key_capture_original = nil
        elseif wparam and wparam > 0 then
            captured:change(wparam)
            NLC_UI.key_capture = nil
            NLC_UI.key_capture_original = nil
        end
        return true
    end

    local control = NLC_UI.text_focus
    if not control then return nil end
    if msg == 0x0100 or msg == 0x0104 then
        local draft = NLC_UI.text_draft or ""
        local caret = NLC_UI.text_caret or (#draft + 1)
        if wparam == 0x0D then
            NLC_UI._commit_text()
        elseif wparam == 0x1B then
            NLC_UI._reset_transient(false)
        elseif wparam == 0x25 then
            NLC_UI.text_caret = NLC_UI._utf8_prev(draft, caret)
        elseif wparam == 0x27 then
            NLC_UI.text_caret = NLC_UI._utf8_next(draft, caret)
        elseif wparam == 0x24 then
            NLC_UI.text_caret = 1
        elseif wparam == 0x23 then
            NLC_UI.text_caret = #draft + 1
        elseif wparam == 0x08 and caret > 1 then
            local previous = NLC_UI._utf8_prev(draft, caret)
            NLC_UI.text_draft = draft:sub(1, previous - 1) .. draft:sub(caret)
            NLC_UI.text_caret = previous
        elseif wparam == 0x2E and caret <= #draft then
            local next_index = NLC_UI._utf8_next(draft, caret)
            NLC_UI.text_draft = draft:sub(1, caret - 1) .. draft:sub(next_index)
            NLC_UI.text_caret = caret
        elseif wparam == 0x56 and input.key_down(0x11) then
            local clipboard = safe(function() return utils.clipboard_get() end)
            if type(clipboard) == "string" then NLC_UI._insert_text(clipboard) end
        end
        return true
    elseif msg == 0x0102 then
        local codepoint = tonumber(wparam) or 0
        if codepoint >= 0xD800 and codepoint <= 0xDBFF then
            NLC_UI.pending_high_surrogate = codepoint
            return true
        elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
            local high = NLC_UI.pending_high_surrogate
            NLC_UI.pending_high_surrogate = nil
            if high then
                codepoint = 0x10000 + (high - 0xD800) * 0x400 + codepoint - 0xDC00
                NLC_UI._insert_text(NLC_UI._utf8_encode(codepoint))
            end
            return true
        end
        NLC_UI.pending_high_surrogate = nil
        if codepoint >= 32 and codepoint ~= 127 and codepoint <= 0x10FFFF then
            NLC_UI._insert_text(NLC_UI._utf8_encode(codepoint))
        end
        return true
    end
    return true
end)

-- ============================================================
--  ГЛАВНЫЙ ЦИКЛ
-- ============================================================
events.on("paint", function()
    if stopped then return end

    -- Windows 媒体功能已停用：浮窗改为显示网易云内容
    if ffi_ready and spotify.enabled then
        clear_scope()
        local now = globals.realtime()
        if now - last_gc > 2.0 then
            collectgarbage("collect")
            last_gc = now
        end
    end

    local mx, my = input.cursor()
    local down = input.key_down(0x01)
    local clicked = down and not mouse_prev
    local released = mouse_prev and not down
    local menu_open = input.menu_open()

    if not menu_open then
        NLC_UI._reset_transient(true)
        slider_active = nil
        sb_drag = false
        ds_drag = false
    end

    local ui = { mx = mx, my = my, down = down, clicked = clicked, released = released, menu = menu_open }

    if menu_open then
        dock_anim = dock_anim + (1 - dock_anim) * math.min(1, globals.frametime() * 14)
        if dock_anim > 0.995 then dock_anim = 1 end
    else
        dock_anim = 0
    end

    local docked = update_dock()
    if not docked then
        local sw, sh = render.screen_size()
        panel_win.x, panel_win.y = sw - PW - 40, (sh - PH) / 2
    end
    NLC_UI.panel.x, NLC_UI.panel.y = panel_win.x, panel_win.y
    NLC_UI.panel.w, NLC_UI.panel.h = panel_win.w, panel_win.h
    NLC_UI.panel.inside = menu_open and in_rect(mx, my, panel_win.x, panel_win.y, panel_win.w, panel_win.h)

    draw_media_widget()

    if docked and dock_anim < 1 then
        local sw, sh = render.screen_size()
        render.clip_push(dock_edge, 0, sw - dock_edge, sh)
        draw_panel(ui)
        render.clip_pop()
    else
        draw_panel(ui)
    end

    mouse_prev = down
end)

events.on("unload", function()
    stopped = true
    save_position()
    NLC_UI.save()
    local success, err = pcall(shutdown_native)
    if not success then
        print("[Media widget] Cleanup error: " .. tostring(err))
    end
end)

client.notify("Netease 媒体播放器 " .. VERSION .. " 已加载", "Ciallo～(∠・ω< )⌒★")