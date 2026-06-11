-- MLL Runtime

-- Thunk infrastructure (non-strict evaluation)
local __thunk_mt = {}
local function __thunk(f) return setmetatable({f, false}, __thunk_mt) end
local function __force(x)
    if getmetatable(x) == __thunk_mt then
        if x[2] then return x[1] end
        local val = x[1]()
        x[1] = val
        x[2] = true
        return val
    end
    return x
end

-- List primitives (internal)
local function __mll_cons(h, t) return {h, t} end
local function __mll_lazy_cons(h, thunk) return {h, thunk, __lazy = true} end
local function __mll_head(l) l = __force(l); return l[1] end
local function __mll_tail(l)
    l = __force(l)
    if l.__lazy then
        l[2] = l[2]()
        l.__lazy = nil
    end
    return l[2]
end

-- Deep-force an MLL value for export to Lua.
-- Converts lazy cons lists to plain Lua arrays, forces thunks, recurses into tuples.
local function __mll_to_lua(x)
    x = __force(x)
    if type(x) ~= "table" then return x end
    -- Check if it's a cons list (2-element table, not tagged)
    if x[2] ~= nil and type(x[1]) ~= "string" then
        -- Could be a cons cell or a tuple; try to walk as a list
        local result = {}
        local cur = x
        local is_list = true
        while cur ~= nil do
            if type(cur) ~= "table" then is_list = false; break end
            result[#result + 1] = __mll_to_lua(__force(cur[1]))
            cur = __mll_tail(cur)
        end
        if is_list then return result end
    end
    -- Tuple or ADT: force each element
    local result = {}
    for i, v in ipairs(x) do result[i] = __mll_to_lua(v) end
    return result
end

-- Wrap a Lua callback so it deep-forces all arguments before forwarding.
-- Used at the FFI boundary: Lua functions don't understand MLL thunks.
local function __mll_wrap_callback(f)
    return function(...)
        local args = table.pack(...)
        for i = 1, args.n do args[i] = __mll_to_lua(args[i]) end
        return f(table.unpack(args, 1, args.n))
    end
end

-- Run an IO action: if it's a thunk (function), force it; otherwise return as-is
local function __mll_run(action)
    action = __force(action)
    if type(action) == "function" then return action() else return action end
end

-- Primitives that require Lua runtime dispatch
local function not_(x) return not __force(x) end
local function engage(f, ...)
    if select('#', ...) > 0 then return __force(f)(...) else return __force(f) end
end
local function liftIO(action) return action end
local function show(x)
    x = __force(x)
    if type(x) == "number" then return tostring(x)
    elseif type(x) == "string" then return x
    elseif type(x) == "boolean" then
        if x then return "True" else return "False" end
    elseif type(x) == "nil" then return "Nothing"
    elseif type(x) == "table" then
        if x[2] ~= nil or (x[1] ~= nil and type(x[2]) == "nil") then
            local parts = {}
            local cur = x
            local is_list = true
            while cur ~= nil do
                if type(cur) ~= "table" then is_list = false; break end
                parts[#parts + 1] = show(__force(cur[1]))
                cur = __mll_tail(cur)
            end
            if is_list then return "[" .. table.concat(parts, ", ") .. "]" end
        end
        local parts = {}
        for i, v in ipairs(x) do parts[i] = show(v) end
        if type(x[1]) == "string" then return x[1] .. "(" .. table.concat(parts, ", ", 2) .. ")"
        else return "(" .. table.concat(parts, ", ") .. ")" end
    else return tostring(x) end
end
local function error_(msg) error(__force(msg)) end
local function max(a, b) return math.max(__force(a), __force(b)) end
local function min(a, b) return math.min(__force(a), __force(b)) end
local function pure(x) return x end
local function return_(x) return x end
local function Just(x) return x end
local Nothing = nil
local function show_Integer(x) return show(x) end
local function show_Number(x) return show(x) end
local function show_String(x) return show(x) end
local function show_Bool(x) return show(x) end
local function show_List_(x) return show(x) end
local function show_Maybe(x) return show(x) end
local function eq_Integer(a, b) a = __force(a); b = __force(b); return a == b end
local function eq_Number(a, b) a = __force(a); b = __force(b); return a == b end
local function eq_String(a, b) a = __force(a); b = __force(b); return a == b end
local function eq_Bool(a, b) a = __force(a); b = __force(b); return a == b end
local function ord_lt__Integer(a, b) a = __force(a); b = __force(b); return a < b end
local function ord_lt__Number(a, b) a = __force(a); b = __force(b); return a < b end
local function ord_lt__String(a, b) a = __force(a); b = __force(b); return a < b end
local function ord_gt__Integer(a, b) a = __force(a); b = __force(b); return a > b end
local function ord_gt__Number(a, b) a = __force(a); b = __force(b); return a > b end
local function ord_gt__String(a, b) a = __force(a); b = __force(b); return a > b end
local function ord_le__Integer(a, b) a = __force(a); b = __force(b); return a <= b end
local function ord_le__Number(a, b) a = __force(a); b = __force(b); return a <= b end
local function ord_le__String(a, b) a = __force(a); b = __force(b); return a <= b end
local function ord_ge__Integer(a, b) a = __force(a); b = __force(b); return a >= b end
local function ord_ge__Number(a, b) a = __force(a); b = __force(b); return a >= b end
local function ord_ge__String(a, b) a = __force(a); b = __force(b); return a >= b end
local function head(xs) return __mll_head(xs) end
local function tail(xs) return __mll_tail(xs) end
local function map(f, xs)
    f = __force(f); xs = __force(xs)
    if xs == nil then return nil end
    return __mll_lazy_cons(f(__mll_head(xs)), function()
        return map(f, __mll_tail(xs))
    end)
end
local function filter(pred, xs)
    pred = __force(pred); xs = __force(xs)
    if xs == nil then return nil end
    local h = __mll_head(xs)
    if pred(h) then
        return __mll_lazy_cons(h, function() return filter(pred, __mll_tail(xs)) end)
    else
        return filter(pred, __mll_tail(xs))
    end
end
local function take(n, xs)
    n = __force(n); xs = __force(xs)
    if n <= 0 or xs == nil then return nil end
    return __mll_cons(__mll_head(xs), take(n - 1, __mll_tail(xs)))
end
local function zipWith(f, xs, ys)
    f = __force(f); xs = __force(xs); ys = __force(ys)
    if xs == nil or ys == nil then return nil end
    return __mll_lazy_cons(f(__mll_head(xs), __mll_head(ys)), function()
        return zipWith(f, __mll_tail(xs), __mll_tail(ys))
    end)
end
-- Hash helper
local function __mll_hashstr(s) s = __force(s); local h = 5381 for i = 1, #s do h = ((h * 33) + string.byte(s, i)) % 2147483647 end return h end

-- HashMap runtime (backed by Lua tables)
local hashmap_empty = {}
local function hashmap_insert(k, v, m) k = __force(k); v = __force(v); m = __force(m); local t = {} for a,b in pairs(m) do t[a] = b end t[k] = v return t end
local function hashmap_lookup(k, m) k = __force(k); m = __force(m); local v = m[k] if v == nil then return nil else return v end end
local function hashmap_delete(k, m) k = __force(k); m = __force(m); local t = {} for a,b in pairs(m) do t[a] = b end t[k] = nil return t end
local function hashmap_size(m) m = __force(m); local n = 0 for _ in pairs(m) do n = n + 1 end return n end
local function hashmap_keys(m) m = __force(m); local r = nil local ks = {} for k in pairs(m) do ks[#ks+1] = k end table.sort(ks) for i = #ks, 1, -1 do r = __mll_cons(ks[i], r) end return r end
local function hashmap_values(m) m = __force(m); local r = nil local ks = {} for k in pairs(m) do ks[#ks+1] = k end table.sort(ks) for i = #ks, 1, -1 do r = __mll_cons(m[ks[i]], r) end return r end
local function hashmap_member(k, m) k = __force(k); m = __force(m); return m[k] ~= nil end
local function show_HashMap(m) m = __force(m); local parts = {} for k, v in pairs(m) do parts[#parts+1] = show(k) .. " -> " .. show(v) end table.sort(parts) return "{" .. table.concat(parts, ", ") .. "}" end
local function hashmap_fromList(xs) xs = __force(xs); local t = {} local cur = xs while cur ~= nil do local pair = __mll_head(cur) t[__force(pair[1])] = __force(pair[2]) cur = __mll_tail(cur) end return t end

-- Specialized list show: uses a typed element show function
local function __mll_show_list(elem_show, xs)
    xs = __force(xs)
    if xs == nil then return "[]" end
    local parts = {}
    local cur = xs
    while cur ~= nil do
        parts[#parts + 1] = elem_show(__force(__mll_head(cur)))
        cur = __mll_tail(cur)
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

-- Lua error convention wrapper: converts (val, err) to Either String a
-- Success: Right val, Failure: Left errmsg
local function __mll_try(val, err)
    if val == nil then return {1, err or "unknown error"} else return {2, val} end
end

-- Iterator-to-lazy-list: calls a Lua iterator factory and builds a lazy MLL list.
-- Single-value iterators produce a flat list; multi-value iterators pack into tuples.
local function __mll_iter(factory, ...)
    local iter = factory(...)
    local function go()
        local vals = {iter()}
        if vals[1] == nil then return nil end
        local val = #vals == 1 and vals[1] or vals
        return __mll_lazy_cons(val, go)
    end
    return go()
end

local function getArgs()
    local result = nil
    if arg then
        for i = #arg, 1, -1 do result = __mll_cons(arg[i], result) end
    end
    return result
end
local function exit_(code)
    if code == 1 then os.exit(0) else os.exit(code[2]) end
end

-- Bitwise operations (Lua 5.4 native operators wrapped as functions)
local function __mll_bxor(a, b) return __force(a) ~ __force(b) end
local function __mll_band(a, b) return __force(a) & __force(b) end
local function __mll_bor(a, b) return __force(a) | __force(b) end
local function __mll_bnot(a) return ~__force(a) end
local function __mll_shl(a, b) return __force(a) << __force(b) end
local function __mll_shr(a, b) return __force(a) >> __force(b) end

-- Array primitives (O(1) indexed access, built from MLL lists)
local function __mll_array_from_list(xs)
    xs = __force(xs)
    local arr = {}
    local cur = xs
    while cur ~= nil do
        arr[#arr + 1] = __force(__mll_head(cur))
        cur = __mll_tail(cur)
    end
    return arr
end
local function __mll_array_index(arr, i) return __force(arr)[__force(i) + 1] end
local function __mll_array_length(arr) return #__force(arr) end

-- ByteString runtime (backed by Lua strings)
-- All indices are 0-based in MLL, converted to 1-based for Lua internally.
local __mll_bs_empty = ""
local __mll_bs; do
    local F = __force
    local sb, sc, sr, ss = string.byte, string.char, string.rep, string.sub
    __mll_bs = {
        function(s) return #F(s) end,                                           -- [1] length
        function(s, i) return sb(F(s), F(i) + 1) end,                          -- [2] index
        function(s, i, len) s=F(s); i=F(i); len=F(len); return ss(s, i+1, i+len) end, -- [3] sub
        function(b) return sc(F(b)) end,                                        -- [4] singleton
        function(a, b) return F(a) .. F(b) end,                                -- [5] concat
        function(s) return #F(s) == 0 end,                                      -- [6] null
        function(s) return sb(F(s), 1) end,                                     -- [7] head
        function(s) return ss(F(s), 2) end,                                     -- [8] tail
        function(b, s) return sc(F(b)) .. F(s) end,                             -- [9] cons
        function(s, b) return F(s) .. sc(F(b)) end,                             -- [10] snoc
        function(n, b) return sr(sc(F(b)), F(n)) end,                           -- [11] replicate
        function(xs)                                                             -- [12] pack
            xs = F(xs); local t = {}; local cur = xs
            while cur ~= nil do t[#t+1] = sc(F(__mll_head(cur))); cur = __mll_tail(cur) end
            return table.concat(t)
        end,
        function(s)                                                              -- [13] unpack
            s = F(s); local r = nil
            for i = #s, 1, -1 do r = __mll_cons(sb(s, i), r) end
            return r
        end,
        function(f, s)                                                           -- [14] map
            f=F(f); s=F(s); local t = {}
            for i = 1, #s do t[i] = sc(F(f)(sb(s, i))) end
            return table.concat(t)
        end,
        function(f, acc, s)                                                      -- [15] foldl
            f=F(f); acc=F(acc); s=F(s)
            for i = 1, #s do local b=sb(s,i); local r=F(f)(acc,b); if r==nil then r=F(F(f)(acc))(b) end; acc=F(r) end
            return acc
        end,
        function(a, b)                                                           -- [16] xor
            a=F(a); b=F(b); local t = {}
            for i = 1, #a do t[i] = sc(sb(a, i) ~ sb(b, i)) end
            return table.concat(t)
        end,
        function(f, a, b)                                                        -- [17] zipwith
            f=F(f); a=F(a); b=F(b); local len=math.min(#a, #b); local t = {}
            for i = 1, len do local ba,bb=sb(a,i),sb(b,i); local r=F(f)(ba,bb); if r==nil then r=F(F(f)(ba))(bb) end; t[i]=sc(F(r)) end
            return table.concat(t)
        end,
        function(s) return F(s) end,                                             -- [18] tostring
        function(s) return F(s) end,                                             -- [19] fromstring
        function(s, i)                                                           -- [20] getU16LE
            s=F(s); i=F(i)+1; local lo,hi=sb(s,i),sb(s,i+1); return lo+hi*256
        end,
        function(s, i)                                                           -- [21] getU32LE
            s=F(s); i=F(i)+1; local a,b,c,d=sb(s,i),sb(s,i+1),sb(s,i+2),sb(s,i+3); return a+b*256+c*65536+d*16777216
        end,
        function(s, i)                                                           -- [22] getI8 (signed)
            s=F(s); local v=sb(s,F(i)+1); if v>=128 then return v-256 else return v end
        end,
        function(s, i)                                                           -- [23] getI16LE (signed)
            s=F(s); i=F(i)+1; local v=sb(s,i)+sb(s,i+1)*256; if v>=32768 then return v-65536 else return v end
        end,
        function(v)                                                              -- [24] putI16LE (signed int to 2-byte BS)
            v=F(v); if v<0 then v=v+65536 end; return sc(v%256, v//256%256)
        end,
        function(xs)                                                             -- [25] concatList
            xs = F(xs); local t = {}; local cur = xs
            while cur ~= nil do t[#t+1] = F(__mll_head(cur)); cur = __mll_tail(cur) end
            return table.concat(t)
        end,
    }
end
local function show_ByteString(s) s = __force(s); local t = {} for i = 1, #s do t[i] = string.format("%02x", string.byte(s, i)) end return "ByteString " .. table.concat(t) end
local function eq_ByteString(a, b) return __force(a) == __force(b) end

-- MutArray runtime (mutable integer arrays, backed by Lua tables)
-- Operations are effectful and run inside LuaIO s.
-- 0-based indexing externally, 1-based internally.
local function __mll_ma_new(size, init)
    size = __force(size); init = __force(init)
    local t = {}; for i = 1, size do t[i] = init end; return t
end
local function __mll_ma_read(arr, idx) return __force(arr)[__force(idx) + 1] end
local function __mll_ma_write(arr, idx, val) __force(arr)[__force(idx) + 1] = __force(val) end
local function __mll_ma_modify(arr, idx, f)
    arr = __force(arr); idx = __force(idx) + 1; f = __force(f)
    arr[idx] = __force(f)(arr[idx])
end
local function __mll_ma_length(arr) return #__force(arr) end
local function __mll_ma_from_list(xs)
    xs = __force(xs); local t = {}; local cur = xs
    while cur ~= nil do t[#t+1] = __force(__mll_head(cur)); cur = __mll_tail(cur) end
    return t
end
local function __mll_ma_to_list(arr)
    arr = __force(arr); local r = nil
    for i = #arr, 1, -1 do r = __mll_cons(arr[i], r) end
    return r
end

-- Generated by MATA-LL compiler (https://github.com/hce/mata-ll)

local Normal = {1}
local Err = function(_p0) return {2, _p0} end

local AnyString = function(_p0) return {1, _p0} end
local AnyInteger = function(_p0) return {2, _p0} end
local AnyNumber = function(_p0) return {3, _p0} end
local AnyBool = function(_p0) return {4, _p0} end
local AnyNull = {5}

local Left = function(_p0) return {1, _p0} end
local Right = function(_p0) return {2, _p0} end

local LT = 1
local EQ = 2
local GT = 3

-- Typeclass instances
local function eq_Ordering(_arg0, _arg1)
    _arg0 = __force(_arg0)
    _arg1 = __force(_arg1)
    if _arg0 == 1 and _arg1 == 1 then
        return true
    elseif _arg0 == 2 and _arg1 == 2 then
        return true
    elseif _arg0 == 3 and _arg1 == 3 then
        return true
    else
        return false
    end
end

local sqrt, putStrLn, assert, id, const, flip, foldl, foldr, length, reverse, mapM_, when, print_, fst, snd, bsSetByte, outRate, clamp, appI, hdrOrdNum, hdrSmpNum, hdrPatNum, hdrSpeed, hdrTempo, getOrder, getChanPan, smpOffset, smpLen, smpLoopBegin, smpLoopEnd, smpC5Freq, smpDataPtr, smpGlobalVol, smpDefaultVol, smpFlags, smpIs16Bit, smpHasLoop, readSmp, patOffset, patRows, semiRatio, pow2, noteInc, nf, fi, fiSmp, fiPos, fi16, fiInc, fiGVl, fiVol, fiPan, fiAct, fiLen, fiLpS, fiLpE, fiLp, fiDPtr, fiC5, mkChan, initChans, decodeRow, decRowLoop, trigNote, applyVol, applyEffect, setNoteFreq, loadSmp, mixTick, mixFrames, mixFrame, advPos, doTicks, doTickLoop, doRows, processPattern, emitChunks, doOrders, play, fst_TupInteger_IntegerTInteger, snd_TupInteger_IntegerTInteger, fst_TupByteString_TupByteString_IntegerTByteString, fst_TupByteString_IntegerTByteString, snd_TupByteString_TupByteString_IntegerTTupByteString_Integer, snd_TupByteString_IntegerTInteger, fst_TupLByteString_LIntegerTLByteString, snd_TupLByteString_LIntegerTLInteger
sqrt = function(_arg0)
    local _ffi0 = __force(_arg0)
    return math.sqrt(__force(_ffi0))
end

putStrLn = function(_arg0)
    local _ffi0 = __force(_arg0)
    return print(__force(_ffi0))
end

assert = function(_arg0, _arg1)
    _arg0 = __force(_arg0)
    _arg1 = __force(_arg1)
    if _arg0 == true then
        return putStrLn(".")
    elseif _arg0 == false then
        local msg = _arg1
        return __force(error)(__force(msg))
    end
    error("Non-exhaustive patterns")
end

id = function(_arg0)
    local x = __force(_arg0)
    return x
end

const = function(_arg0, _arg1)
    local x = __force(_arg0)
    return x
end

flip = function(_arg0, _arg1, _arg2)
    local f = __force(_arg0)
    local b = __force(_arg1)
    local a = __force(_arg2)
    return f(a, b)
end

foldl = function(_arg0, _arg1, _arg2)
    _arg0 = __force(_arg0)
    _arg1 = __force(_arg1)
    _arg2 = __force(_arg2)
    if _arg2 == nil then
        local acc = _arg1
        return __force(acc)
    elseif _arg2 ~= nil then
        local f = _arg0
        local acc = _arg1
        local x = __mll_head(_arg2)
        local xs = __mll_tail(_arg2)
        return foldl(__force(f), (__force(f)(__force(acc), __force(x))), __force(xs))
    end
    error("Non-exhaustive patterns")
end

foldr = function(_arg0, _arg1, _arg2)
    _arg0 = __force(_arg0)
    _arg1 = __force(_arg1)
    _arg2 = __force(_arg2)
    if _arg2 == nil then
        local acc = _arg1
        return __force(acc)
    elseif _arg2 ~= nil then
        local f = _arg0
        local acc = _arg1
        local x = __mll_head(_arg2)
        local xs = __mll_tail(_arg2)
        return __force(f)(__force(x), (foldr(__force(f), __force(acc), __force(xs))))
    end
    error("Non-exhaustive patterns")
end

length = function(_arg0)
    _arg0 = __force(_arg0)
    if _arg0 == nil then
        return 0
    elseif _arg0 ~= nil then
        local xs = __mll_tail(_arg0)
        return (1 + length(__force(xs)))
    end
    error("Non-exhaustive patterns")
end

reverse = function(_arg0)
    local xs = __force(_arg0)
    local function go(_warg0, _warg1)
        _warg1 = __force(_warg1)
        if _warg1 == nil then
            local acc = _warg0
            return __force(acc)
        elseif _warg1 ~= nil then
            local acc = _warg0
            local x = __mll_head(_warg1)
            local rest = __mll_tail(_warg1)
            return __force(go)(__thunk(function() return (__mll_cons(__force(x), __force(acc))) end), __force(rest))
        end
        error("Non-exhaustive patterns")
    end
    return __force(go)(nil, xs)
end

mapM_ = function(_arg0, _arg1)
    _arg0 = __force(_arg0)
    _arg1 = __force(_arg1)
    if _arg1 == nil then
        return __force(pure)(nil)
    elseif _arg1 ~= nil then
        local f = _arg0
        local x = __mll_head(_arg1)
        local xs = __mll_tail(_arg1)
        return (function()
            __force(f)(__force(x))
            return mapM_(__force(f), __force(xs))
        end)()
    end
    error("Non-exhaustive patterns")
end

when = function(_arg0, _arg1)
    local cond = __force(_arg0)
    local action = __force(_arg1)
    return (function()
        if cond then
            return action
        else
            return __force(pure)(nil)
        end
    end)()
end

print_ = function(_arg0)
    local x = __force(_arg0)
    return putStrLn((__force(show)(x)))
end

fst = function(_arg0)
    _arg0 = __force(_arg0)
    local x = _arg0[1]
    return __force(x)
end

snd = function(_arg0)
    _arg0 = __force(_arg0)
    local y = _arg0[2]
    return __force(y)
end

bsSetByte = function(_arg0, _arg1, _arg2)
    local bs = __force(_arg0)
    local idx = __force(_arg1)
    local val = __force(_arg2)
    return __force(__mll_bs[5])((__force(__mll_bs[3])(bs, 0, idx)), (__force(__mll_bs[5])((__force(__mll_bs[4])(val)), (__force(__mll_bs[3])(bs, ((idx + 1)), (((__force(__mll_bs[1])(bs) - idx) - 1)))))))
end

outRate = 44100

clamp = function(_arg0, _arg1, _arg2)
    local lo = __force(_arg0)
    local hi = __force(_arg1)
    local x = __force(_arg2)
    return (function()
        if __force(ord_lt__Integer)(x, lo) then
            return lo
        else
            return (function()
                if __force(ord_gt__Integer)(x, hi) then
                    return hi
                else
                    return x
                end
            end)()
        end
    end)()
end

appI = function(_arg0, _arg1)
    _arg0 = __force(_arg0)
    _arg1 = __force(_arg1)
    if _arg0 == nil then
        local ys = _arg1
        return __force(ys)
    elseif _arg0 ~= nil then
        local x = __mll_head(_arg0)
        local xs = __mll_tail(_arg0)
        local ys = _arg1
        return __mll_cons(__force(x), appI(__force(xs), __force(ys)))
    end
    error("Non-exhaustive patterns")
end

hdrOrdNum = function(_arg0)
    local bs = __force(_arg0)
    return __force(__mll_bs[20])(bs, 32)
end

hdrSmpNum = function(_arg0)
    local bs = __force(_arg0)
    return __force(__mll_bs[20])(bs, 36)
end

hdrPatNum = function(_arg0)
    local bs = __force(_arg0)
    return __force(__mll_bs[20])(bs, 38)
end

hdrSpeed = function(_arg0)
    local bs = __force(_arg0)
    return __force(__mll_bs[2])(bs, 50)
end

hdrTempo = function(_arg0)
    local bs = __force(_arg0)
    return __force(__mll_bs[2])(bs, 51)
end

getOrder = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local i = __force(_arg1)
    return __force(__mll_bs[2])(bs, ((192 + i)))
end

getChanPan = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local ch = __force(_arg1)
    return __force(__mll_bs[2])(bs, ((64 + ch)))
end

smpOffset = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local i = __force(_arg1)
    return __force(__mll_bs[21])(bs, (((192 + hdrOrdNum(bs)) + (i * 4))))
end

smpLen = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[21])(bs, ((off + 48)))
end

smpLoopBegin = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[21])(bs, ((off + 52)))
end

smpLoopEnd = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[21])(bs, ((off + 56)))
end

smpC5Freq = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[21])(bs, ((off + 60)))
end

smpDataPtr = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[21])(bs, ((off + 72)))
end

smpGlobalVol = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[2])(bs, ((off + 17)))
end

smpDefaultVol = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[2])(bs, ((off + 19)))
end

smpFlags = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[2])(bs, ((off + 18)))
end

smpIs16Bit = function(_arg0)
    local flags = __force(_arg0)
    return __force(eq_Integer)((((flags // 2)) % 2), 1)
end

smpHasLoop = function(_arg0)
    local flags = __force(_arg0)
    return __force(eq_Integer)((((flags // 16)) % 2), 1)
end

readSmp = function(_arg0, _arg1, _arg2, _arg3)
    local bs = __force(_arg0)
    local dPtr = __force(_arg1)
    local pos = __force(_arg2)
    local is16 = __force(_arg3)
    return (function()
        if is16 then
            return __force(__mll_bs[23])(bs, ((dPtr + (pos * 2))))
        else
            return (function()
                local v = __force(__mll_bs[2])(bs, ((dPtr + pos)))
                return (function()
                    if __force(ord_ge__Integer)(v, 128) then
                        return (v - 256)
                    else
                        return v
                    end
                end)()
            end)()
        end
    end)()
end

patOffset = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local i = __force(_arg1)
    return __force(__mll_bs[21])(bs, ((((192 + hdrOrdNum(bs)) + (hdrSmpNum(bs) * 4)) + (i * 4))))
end

patRows = function(_arg0, _arg1)
    local bs = __force(_arg0)
    local off = __force(_arg1)
    return __force(__mll_bs[20])(bs, ((off + 2)))
end

semiRatio = function(_arg0)
    _arg0 = __force(_arg0)
    if _arg0 == 0 then
        return 65536
    elseif _arg0 == 1 then
        return 69433
    elseif _arg0 == 2 then
        return 73562
    elseif _arg0 == 3 then
        return 77936
    elseif _arg0 == 4 then
        return 82570
    elseif _arg0 == 5 then
        return 87480
    elseif _arg0 == 6 then
        return 92682
    elseif _arg0 == 7 then
        return 98193
    elseif _arg0 == 8 then
        return 104032
    elseif _arg0 == 9 then
        return 110218
    elseif _arg0 == 10 then
        return 116772
    elseif _arg0 == 11 then
        return 123715
    else
        return 65536
    end
end

pow2 = function(_arg0)
    _arg0 = __force(_arg0)
    if _arg0 == 0 then
        return 1
    else
        local n = _arg0
        return (2 * pow2(((__force(n) - 1))))
    end
end

noteInc = function(_arg0, _arg1)
    local note = __force(_arg0)
    local c5 = __force(_arg1)
    return (function()
        local oct = (((note // 12)) - 5)
        local semi = (note % 12)
        local base = ((((c5 * semiRatio(semi)) * 256)) // ((outRate * 65536)))
        return (function()
            if __force(ord_ge__Integer)(oct, 0) then
                return (base * pow2(oct))
            else
                return (base // pow2(((0 - oct))))
            end
        end)()
    end)()
end

nf = 14

fi = function(_arg0, _arg1)
    local ch = __force(_arg0)
    local f = __force(_arg1)
    return ((ch * nf) + f)
end

fiSmp = 0

fiPos = 1

fi16 = 2

fiInc = 3

fiGVl = 4

fiVol = 5

fiPan = 6

fiAct = 7

fiLen = 8

fiLpS = 9

fiLpE = 10

fiLp = 11

fiDPtr = 12

fiC5 = 13

mkChan = function(_arg0)
    local pan = __force(_arg0)
    return (function() local _l = nil; _l = __mll_cons(8363, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(pan, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); _l = __mll_cons(0, _l); return _l end)()
end

initChans = function(_arg0, _arg1, _arg2)
    local fd = __force(_arg0)
    local n = __force(_arg1)
    local i = __force(_arg2)
    return (function()
        if __force(ord_ge__Integer)(i, n) then
            return nil
        else
            return (function()
                local p = getChanPan(fd, i)
                local pv = (function()
                    if __force(ord_ge__Integer)(p, 128) then
                        return 32
                    else
                        return p
                    end
                end)()
                return appI((mkChan(pv)), (initChans(fd, n, ((i + 1)))))
            end)()
        end
    end)()
end

decodeRow = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5, _arg6)
    local fd = __force(_arg0)
    local off = __force(_arg1)
    local arr = __force(_arg2)
    local masks = __force(_arg3)
    local lv = __force(_arg4)
    local numCh = __force(_arg5)
    local numSmp = __force(_arg6)
    return __force(decRowLoop)(fd, off, arr, masks, lv, numCh, numSmp)
end

decRowLoop = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5, _arg6)
    local fd = __force(_arg0)
    local off = __force(_arg1)
    local arr = __force(_arg2)
    local masks = __force(_arg3)
    local lv = __force(_arg4)
    local numCh = __force(_arg5)
    local numSmp = __force(_arg6)
    return (function()
        local marker = __force(__mll_bs[2])(fd, off)
        return (function()
            if __force(eq_Integer)(marker, 0) then
                return __force(return_)({masks, {lv, (off + 1)}})
            else
                return (function()
                    local ch = (((marker - 1)) % 64)
                    local hmb = (marker // 128)
                    local off2 = (off + 1)
                    local mask = (function()
                        if __force(eq_Integer)(hmb, 1) then
                            return __force(__mll_bs[2])(fd, off2)
                        else
                            return __force(__mll_bs[2])(masks, ch)
                        end
                    end)()
                    local msk2 = (function()
                        if __force(eq_Integer)(hmb, 1) then
                            return bsSetByte(masks, ch, mask)
                        else
                            return masks
                        end
                    end)()
                    local off3 = (function()
                        if __force(eq_Integer)(hmb, 1) then
                            return (off2 + 1)
                        else
                            return off2
                        end
                    end)()
                    local b0 = (mask % 2)
                    local b1 = (((mask // 2)) % 2)
                    local b2 = (((mask // 4)) % 2)
                    local b3 = (((mask // 8)) % 2)
                    local b4 = (((mask // 16)) % 2)
                    local b5 = (((mask // 32)) % 2)
                    local b6 = (((mask // 64)) % 2)
                    local note = (function()
                        if __force(eq_Integer)(b0, 1) then
                            return __force(__mll_bs[2])(fd, off3)
                        else
                            return (function()
                                if __force(eq_Integer)(b4, 1) then
                                    return __force(__mll_bs[2])(lv, ((ch * 4)))
                                else
                                    return 255
                                end
                            end)()
                        end
                    end)()
                    local off4 = (off3 + b0)
                    local ins = (function()
                        if __force(eq_Integer)(b1, 1) then
                            return __force(__mll_bs[2])(fd, off4)
                        else
                            return (function()
                                if __force(eq_Integer)(b5, 1) then
                                    return __force(__mll_bs[2])(lv, (((ch * 4) + 1)))
                                else
                                    return 0
                                end
                            end)()
                        end
                    end)()
                    local off5 = (off4 + b1)
                    local vol = (function()
                        if __force(eq_Integer)(b2, 1) then
                            return __force(__mll_bs[2])(fd, off5)
                        else
                            return (function()
                                if __force(eq_Integer)(b6, 1) then
                                    return __force(__mll_bs[2])(lv, (((ch * 4) + 2)))
                                else
                                    return 255
                                end
                            end)()
                        end
                    end)()
                    local off6 = (off5 + b2)
                    local cmd = (function()
                        if __force(eq_Integer)(b3, 1) then
                            return __force(__mll_bs[2])(fd, off6)
                        else
                            return 0
                        end
                    end)()
                    local cmdVal = (function()
                        if __force(eq_Integer)(b3, 1) then
                            return __force(__mll_bs[2])(fd, ((off6 + 1)))
                        else
                            return 0
                        end
                    end)()
                    local off7 = (off6 + ((function()
                        if __force(eq_Integer)(b3, 1) then
                            return 2
                        else
                            return 0
                        end
                    end)()))
                    local lv2 = (function()
                        if __force(eq_Integer)(b0, 1) then
                            return bsSetByte(lv, ((ch * 4)), note)
                        else
                            return lv
                        end
                    end)()
                    local lv3 = (function()
                        if __force(eq_Integer)(b1, 1) then
                            return bsSetByte(lv2, (((ch * 4) + 1)), ins)
                        else
                            return lv2
                        end
                    end)()
                    local lv4 = (function()
                        if __force(eq_Integer)(b2, 1) then
                            return bsSetByte(lv3, (((ch * 4) + 2)), vol)
                        else
                            return lv3
                        end
                    end)()
                    return (function()
                        __force(trigNote)(fd, arr, ch, note, ins, vol, cmd, cmdVal, numSmp)
                        return decRowLoop(fd, off7, arr, msk2, lv4, numCh, numSmp)
                    end)()
                end)()
            end
        end)()
    end)()
end

trigNote = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5, _arg6, _arg7, _arg8)
    local fd = __force(_arg0)
    local arr = __force(_arg1)
    local ch = __force(_arg2)
    local note = __force(_arg3)
    local ins = __force(_arg4)
    local vol = __force(_arg5)
    local cmd = __force(_arg6)
    local cmdVal = __force(_arg7)
    local numSmp = __force(_arg8)
    return (function()
        if __force(eq_Integer)(note, 254) then
            return __force(__mll_ma_write)(arr, (fi(ch, fiAct)), 0)
        else
            return (function()
                local _ = (function()
                    if (__force(ord_gt__Integer)(ins, 0) and __force(ord_le__Integer)(ins, numSmp)) then
                        return __force(loadSmp)(fd, arr, ch, ins)
                    else
                        return __force(return_)(nil)
                    end
                end)()
                local _ = (function()
                    if __force(ord_lt__Integer)(note, 120) then
                        return __force(setNoteFreq)(arr, ch, note)
                    else
                        return __force(return_)(nil)
                    end
                end)()
                local _ = __force(applyVol)(arr, ch, vol)
                return __force(applyEffect)(arr, ch, cmd, cmdVal)
            end)()
        end
    end)()
end

applyVol = function(_arg0, _arg1, _arg2)
    local arr = __force(_arg0)
    local ch = __force(_arg1)
    local vol = __force(_arg2)
    return (function()
        if __force(ord_le__Integer)(vol, 64) then
            return __force(__mll_ma_write)(arr, (fi(ch, fiVol)), vol)
        else
            return (function()
                if (__force(ord_ge__Integer)(vol, 128) and __force(ord_le__Integer)(vol, 192)) then
                    return __force(__mll_ma_write)(arr, (fi(ch, fiPan)), ((vol - 128)))
                else
                    return __force(return_)(nil)
                end
            end)()
        end
    end)()
end

applyEffect = function(_arg0, _arg1, _arg2, _arg3)
    local arr = __force(_arg0)
    local ch = __force(_arg1)
    local cmd = __force(_arg2)
    local val = __force(_arg3)
    return (function()
        if __force(eq_Integer)(cmd, 8) then
            return __force(__mll_ma_write)(arr, (fi(ch, fiPan)), ((val // 4)))
        else
            return (function()
                if (__force(eq_Integer)(cmd, 19) and __force(eq_Integer)(((val // 16)), 8)) then
                    return __force(__mll_ma_write)(arr, (fi(ch, fiPan)), ((((((val % 16)) * 17)) // 4)))
                else
                    return __force(return_)(nil)
                end
            end)()
        end
    end)()
end

setNoteFreq = function(_arg0, _arg1, _arg2)
    local arr = __force(_arg0)
    local ch = __force(_arg1)
    local note = __force(_arg2)
    return (function()
        local c5 = __force(__mll_ma_read)(arr, (fi(ch, fiC5)))
        local inc = noteInc(note, c5)
        local _ = __force(__mll_ma_write)(arr, (fi(ch, fiPos)), 0)
        local _ = __force(__mll_ma_write)(arr, (fi(ch, fiInc)), inc)
        return __force(__mll_ma_write)(arr, (fi(ch, fiAct)), 1)
    end)()
end

loadSmp = function(_arg0, _arg1, _arg2, _arg3)
    local fd = __force(_arg0)
    local arr = __force(_arg1)
    local ch = __force(_arg2)
    local sn = __force(_arg3)
    return (function()
        local off = smpOffset(fd, ((sn - 1)))
        local sl = smpLen(fd, off)
        local lb = smpLoopBegin(fd, off)
        local le = smpLoopEnd(fd, off)
        local c5 = smpC5Freq(fd, off)
        local dp = smpDataPtr(fd, off)
        local dv = smpDefaultVol(fd, off)
        local gv = smpGlobalVol(fd, off)
        local fl = smpFlags(fd, off)
        local hl = (function()
            if smpHasLoop(fl) then
                return 1
            else
                return 0
            end
        end)()
        local b16 = (function()
            if smpIs16Bit(fl) then
                return 1
            else
                return 0
            end
        end)()
        return (function()
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fiSmp)), sn)
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fiLen)), sl)
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fiLpS)), lb)
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fiLpE)), le)
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fiLp)), hl)
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fiDPtr)), dp)
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fiC5)), c5)
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fiVol)), dv)
            local _ = __force(__mll_ma_write)(arr, (fi(ch, fi16)), b16)
            return __force(__mll_ma_write)(arr, (fi(ch, fiGVl)), gv)
        end)()
    end)()
end

mixTick = function(_arg0, _arg1, _arg2, _arg3, _arg4)
    local fd = __force(_arg0)
    local arr = __force(_arg1)
    local spt = __force(_arg2)
    local numCh = __force(_arg3)
    local chunks = __force(_arg4)
    return (function()
        local pcm = __force(mixFrames)(fd, arr, spt, numCh, nil)
        return __force(return_)(__thunk(function() return (__mll_cons(pcm, chunks)) end))
    end)()
end

mixFrames = function(_arg0, _arg1, _arg2, _arg3, _arg4)
    _arg0 = __force(_arg0)
    _arg1 = __force(_arg1)
    _arg2 = __force(_arg2)
    _arg3 = __force(_arg3)
    _arg4 = __force(_arg4)
    if _arg2 == 0 then
        local fd = _arg0
        local arr = _arg1
        local acc = _arg4
        return __force(return_)((__force(__mll_bs[25])((reverse(__force(acc))))))
    else
        local fd = _arg0
        local arr = _arg1
        local n = _arg2
        local numCh = _arg3
        local acc = _arg4
        return (function()
            local frame = __force(mixFrame)(__force(fd), __force(arr), __force(numCh), 0, 0, 0)
            local l = __force(fst_TupInteger_IntegerTInteger)(frame)
            local r = __force(snd_TupInteger_IntegerTInteger)(frame)
            local ml = (((l * 48)) // ((128 * 3)))
            local mr = (((r * 48)) // ((128 * 3)))
            local pcm = __force(__mll_bs[5])((__force(__mll_bs[24])((clamp(((0 - 32768)), 32767, ml)))), (__force(__mll_bs[24])((clamp(((0 - 32768)), 32767, mr)))))
            return mixFrames(__force(fd), __force(arr), ((__force(n) - 1)), __force(numCh), __thunk(function() return (__mll_cons(pcm, __force(acc))) end))
        end)()
    end
end

mixFrame = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5)
    local fd = __force(_arg0)
    local arr = __force(_arg1)
    local numCh = __force(_arg2)
    local ch = __force(_arg3)
    local la = __force(_arg4)
    local ra = __force(_arg5)
    return (function()
        if __force(ord_ge__Integer)(ch, numCh) then
            return __force(return_)({la, ra})
        else
            return (function()
                local act = __force(__mll_ma_read)(arr, (fi(ch, fiAct)))
                return (function()
                    if __force(eq_Integer)(act, 0) then
                        return mixFrame(fd, arr, numCh, ((ch + 1)), la, ra)
                    else
                        return (function()
                            local pos = __force(__mll_ma_read)(arr, (fi(ch, fiPos)))
                            local sl = __force(__mll_ma_read)(arr, (fi(ch, fiLen)))
                            local dp = __force(__mll_ma_read)(arr, (fi(ch, fiDPtr)))
                            local vol = __force(__mll_ma_read)(arr, (fi(ch, fiVol)))
                            local pan = __force(__mll_ma_read)(arr, (fi(ch, fiPan)))
                            local is16 = __force(__mll_ma_read)(arr, (fi(ch, fi16)))
                            local gvl = __force(__mll_ma_read)(arr, (fi(ch, fiGVl)))
                            local smpPos = (pos // 256)
                            local smp = (function()
                                if __force(ord_lt__Integer)(smpPos, sl) then
                                    return readSmp(fd, dp, smpPos, (__force(eq_Integer)(is16, 1)))
                                else
                                    return 0
                                end
                            end)()
                            local sv = (function()
                                if __force(eq_Integer)(is16, 1) then
                                    return (((((smp * vol) * gvl) * 128)) // (((64 * 64) * 128)))
                                else
                                    return ((((((smp * vol) * gvl) * 128) * 256)) // (((64 * 64) * 128)))
                                end
                            end)()
                            local nl = (la + (((sv * ((64 - pan)))) // 64))
                            local nr = (ra + (((sv * pan)) // 64))
                            local _ = __force(advPos)(arr, ch)
                            return mixFrame(fd, arr, numCh, ((ch + 1)), nl, nr)
                        end)()
                    end
                end)()
            end)()
        end
    end)()
end

advPos = function(_arg0, _arg1)
    local arr = __force(_arg0)
    local ch = __force(_arg1)
    return (function()
        local pos = __force(__mll_ma_read)(arr, (fi(ch, fiPos)))
        local inc = __force(__mll_ma_read)(arr, (fi(ch, fiInc)))
        local sl = __force(__mll_ma_read)(arr, (fi(ch, fiLen)))
        local hl = __force(__mll_ma_read)(arr, (fi(ch, fiLp)))
        local ls = __force(__mll_ma_read)(arr, (fi(ch, fiLpS)))
        local le = __force(__mll_ma_read)(arr, (fi(ch, fiLpE)))
        local nPos = (pos + inc)
        local slFP = (sl * 256)
        local lsFP = (ls * 256)
        local leFP = (le * 256)
        local fPos = (function()
            if (__force(eq_Integer)(hl, 1) and (__force(ord_ge__Integer)(nPos, leFP) and __force(ord_gt__Integer)(leFP, lsFP))) then
                return (lsFP + ((((nPos - lsFP)) % ((leFP - lsFP)))))
            else
                return nPos
            end
        end)()
        local _ = __force(__mll_ma_write)(arr, (fi(ch, fiPos)), fPos)
        return (function()
            if (__force(eq_Integer)(hl, 0) and __force(ord_ge__Integer)(nPos, slFP)) then
                return __force(__mll_ma_write)(arr, (fi(ch, fiAct)), 0)
            else
                return __force(return_)(nil)
            end
        end)()
    end)()
end

doTicks = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5)
    local fd = __force(_arg0)
    local arr = __force(_arg1)
    local speed = __force(_arg2)
    local spt = __force(_arg3)
    local numCh = __force(_arg4)
    local chunks = __force(_arg5)
    return __force(doTickLoop)(fd, arr, speed, spt, numCh, 0, chunks)
end

doTickLoop = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5, _arg6)
    local fd = __force(_arg0)
    local arr = __force(_arg1)
    local speed = __force(_arg2)
    local spt = __force(_arg3)
    local numCh = __force(_arg4)
    local tick = __force(_arg5)
    local chunks = __force(_arg6)
    return (function()
        if __force(ord_ge__Integer)(tick, speed) then
            return __force(return_)(chunks)
        else
            return (function()
                local chunks2 = mixTick(fd, arr, spt, numCh, chunks)
                return doTickLoop(fd, arr, speed, spt, numCh, ((tick + 1)), chunks2)
            end)()
        end
    end)()
end

doRows = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5, _arg6, _arg7, _arg8, _arg9, _arg10, _arg11)
    local fd = __force(_arg0)
    local arr = __force(_arg1)
    local masks = __force(_arg2)
    local lv = __force(_arg3)
    local dataOff = __force(_arg4)
    local row = __force(_arg5)
    local numRows = __force(_arg6)
    local speed = __force(_arg7)
    local tempo = __force(_arg8)
    local numCh = __force(_arg9)
    local numSmp = __force(_arg10)
    local chunks = __force(_arg11)
    return (function()
        if __force(ord_ge__Integer)(row, numRows) then
            return (function()
                local st2 = __force(__mll_ma_to_list)(arr)
                return __force(return_)({chunks, st2})
            end)()
        else
            return (function()
                local rr = decodeRow(fd, dataOff, arr, masks, lv, numCh, numSmp)
                local masks2 = __force(fst_TupByteString_TupByteString_IntegerTByteString)(rr)
                local lv2 = __force(fst_TupByteString_IntegerTByteString)((__force(snd_TupByteString_TupByteString_IntegerTTupByteString_Integer)(rr)))
                local nextOff = __force(snd_TupByteString_IntegerTInteger)((__force(snd_TupByteString_TupByteString_IntegerTTupByteString_Integer)(rr)))
                local spt = (((outRate * 60)) // ((tempo * 24)))
                local chunks2 = doTicks(fd, arr, speed, spt, numCh, chunks)
                return doRows(fd, arr, masks2, lv2, nextOff, ((row + 1)), numRows, speed, tempo, numCh, numSmp, chunks2)
            end)()
        end
    end)()
end

processPattern = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5, _arg6, _arg7)
    local fd = __force(_arg0)
    local st = __force(_arg1)
    local pOff = __force(_arg2)
    local nRows = __force(_arg3)
    local speed = __force(_arg4)
    local tempo = __force(_arg5)
    local numCh = __force(_arg6)
    local numSmp = __force(_arg7)
    return (function()
        local masks = __force(__mll_bs[11])(64, 0)
        local lv = __force(__mll_bs[11])(256, 0)
        return __force(__mll_run)(__thunk(function() return ((function()
            local arr = __force(__mll_ma_from_list)(st)
            return doRows(fd, arr, masks, lv, ((pOff + 8)), 0, nRows, speed, tempo, numCh, numSmp, nil)
        end)()) end))
    end)()
end

emitChunks = function(_arg0, _arg1)
    _arg0 = __force(_arg0)
    _arg1 = __force(_arg1)
    if _arg1 == nil then
        local sw = _arg0
        return __force(return_)(nil)
    elseif _arg1 ~= nil then
        local sw = _arg0
        local c = __mll_head(_arg1)
        local cs = __mll_tail(_arg1)
        return (function()
            __force(sw)(__force(c))
            return emitChunks(__force(sw), __force(cs))
        end)()
    end
    error("Non-exhaustive patterns")
end

doOrders = function(_arg0, _arg1, _arg2, _arg3, _arg4, _arg5, _arg6, _arg7, _arg8, _arg9)
    local fd = __force(_arg0)
    local sw = __force(_arg1)
    local st = __force(_arg2)
    local idx = __force(_arg3)
    local ordNum = __force(_arg4)
    local speed = __force(_arg5)
    local tempo = __force(_arg6)
    local numCh = __force(_arg7)
    local numSmp = __force(_arg8)
    local noLoop = __force(_arg9)
    return (function()
        if __force(ord_ge__Integer)(idx, ordNum) then
            return __force(return_)(nil)
        else
            return (function()
                local pat = getOrder(fd, idx)
                return (function()
                    if __force(eq_Integer)(pat, 254) then
                        return doOrders(fd, sw, st, ((idx + 1)), ordNum, speed, tempo, numCh, numSmp, noLoop)
                    else
                        return (function()
                            if __force(eq_Integer)(pat, 255) then
                                return (function()
                                    if noLoop then
                                        return __force(return_)(nil)
                                    else
                                        return __force(return_)(nil)
                                    end
                                end)()
                            else
                                return (function()
                                    local pOff = patOffset(fd, pat)
                                    local nRows = patRows(fd, pOff)
                                    local result = processPattern(fd, st, pOff, nRows, speed, tempo, numCh, numSmp)
                                    local chunks = __force(fst_TupLByteString_LIntegerTLByteString)(result)
                                    local st2 = __force(snd_TupLByteString_LIntegerTLInteger)(result)
                                    return (function()
                                        emitChunks(sw, (reverse(chunks)))
                                        return doOrders(fd, sw, st2, ((idx + 1)), ordNum, speed, tempo, numCh, numSmp, noLoop)
                                    end)()
                                end)()
                            end
                        end)()
                    end
                end)()
            end)()
        end
    end)()
end

play = function(_arg0, _arg1, _arg2)
    local swallower = __force(_arg0)
    local fd = __force(_arg1)
    local noLoop = __force(_arg2)
    return (function()
        local numCh = 22
        local st = initChans(fd, numCh, 0)
        return doOrders(fd, swallower, st, 0, (hdrOrdNum(fd)), (hdrSpeed(fd)), (hdrTempo(fd)), numCh, (hdrSmpNum(fd)), noLoop)
    end)()
end

fst_TupInteger_IntegerTInteger = function(_arg0)
    _arg0 = __force(_arg0)
    local x = _arg0[1]
    return __force(x)
end

snd_TupInteger_IntegerTInteger = function(_arg0)
    _arg0 = __force(_arg0)
    local y = _arg0[2]
    return __force(y)
end

fst_TupByteString_TupByteString_IntegerTByteString = function(_arg0)
    _arg0 = __force(_arg0)
    local x = _arg0[1]
    return __force(x)
end

fst_TupByteString_IntegerTByteString = function(_arg0)
    _arg0 = __force(_arg0)
    local x = _arg0[1]
    return __force(x)
end

snd_TupByteString_TupByteString_IntegerTTupByteString_Integer = function(_arg0)
    _arg0 = __force(_arg0)
    local y = _arg0[2]
    return __force(y)
end

snd_TupByteString_IntegerTInteger = function(_arg0)
    _arg0 = __force(_arg0)
    local y = _arg0[2]
    return __force(y)
end

fst_TupLByteString_LIntegerTLByteString = function(_arg0)
    _arg0 = __force(_arg0)
    local x = _arg0[1]
    return __force(x)
end

snd_TupLByteString_LIntegerTLInteger = function(_arg0)
    _arg0 = __force(_arg0)
    local y = _arg0[2]
    return __force(y)
end


-- Exports
return {
    play = function(...)
        local args = table.pack(...)
        for i = 1, args.n do if type(args[i]) == "function" then args[i] = __mll_wrap_callback(args[i]) end end
        return __mll_to_lua(play(table.unpack(args, 1, args.n)))
    end,
}
