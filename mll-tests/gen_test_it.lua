#!/usr/bin/env lua
-- Generate an Impulse Tracker (.it) file for benchmarking.
-- Mozart's Symphony No. 40 in G minor (K.550), first movement opening.
-- Composition is public domain; samples are synthetic waveforms.

local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function le32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256) end

-- Generate waveform samples (signed 8-bit stored as unsigned)
local function make_sample(length, wavefn)
    local data = {}
    for i = 1, length do
        local t = (i - 1) / length
        local v = math.floor(wavefn(t) * 50 + 128)  -- center at 128, amplitude 50
        if v < 0 then v = 0 elseif v > 255 then v = 255 end
        data[i] = string.char(v)
    end
    return table.concat(data)
end

-- Different waveforms for different timbres
local function square(t) return (t % 1) < 0.5 and 1 or -1 end
local function triangle(t)
    local p = (t * 2) % 2
    return p < 1 and (p * 2 - 1) or (3 - p * 2)
end
local function saw(t) return (t % 1) * 2 - 1 end

-- Note name to IT note number
local N = {
    C=0, ["C#"]=1, Db=1, D=2, ["D#"]=3, Eb=3, E=4, F=5,
    ["F#"]=6, Gb=6, G=7, ["G#"]=8, Ab=8, A=9, ["A#"]=10, Bb=10, B=11,
}
local function note(name, octave) return octave * 12 + N[name] end

-- Helpers for pattern encoding
local REST = 255
local CUT = 254
local function m(name, oct, vol) return {note(name, oct), 1, vol or 56} end  -- melody (instrument 1)
local function a(name, oct, vol) return {note(name, oct), 2, vol or 24} end  -- accomp (instrument 2)
local function v(name, oct, vol) return {note(name, oct), 3, vol or 20} end  -- viola (instrument 3)
local function b(name, oct, vol) return {note(name, oct), 4, vol or 28} end  -- bass (instrument 4)
local r = {REST, 0, 255}   -- rest (continue previous)
local cut = {CUT, 0, 255}  -- note off

-- Each row = one eighth note
-- Quarter = 2 rows, Half = 4 rows, Whole = 8 rows
-- Speed 4, Tempo 160 gives ~5 rows/second → good pacing

-- ============================================================
-- MELODY (Violin I) — the famous theme
-- ============================================================
-- The rhythm: short-short-LONG, short-short-LONG, short-short-short-short-LONG
-- Phrase 1: Eb-D D(half), Eb-D D(half), Eb-D Eb-F# G(half)
-- Phrase 2: Bb-A A(half), Bb-A A(half), Bb-A Bb-C# D(half)
-- Then descending: D-Eb-C-D-Bb-C-A-Bb-G-A-F#-G-Eb-F#-G (simplified)
local melody = {}
local function mel(t) for _, x in ipairs(t) do melody[#melody+1] = x end end

-- Bar 1: accompaniment alone (8 eighth notes of rest)
mel{r, r, r, r,  r, r, r, r}

-- Bars 2-5: First phrase
-- Pickup + bar 2: ____ ____ Eb D | D ___ ___ Eb D
mel{r, r, r, r,  r, r, m("Eb",5), m("D",5)}
mel{m("D",5), r, r, r,  r, r, m("Eb",5), m("D",5)}
-- Bar 4: D ___ ___ Eb D
mel{m("D",5), r, r, r,  r, r, m("Eb",5), m("D",5)}
-- Bar 5: Eb _  D _  Eb F# | G ___ ___ ___
mel{m("Eb",5), r, m("D",5), r,  m("Eb",5), r, m("F#",5), r}
mel{m("G",5), r, r, r,  r, r, r, r}

-- Bars 7-10: Second phrase (transposed up)
mel{r, r, r, r,  r, r, m("Bb",5), m("A",5)}
mel{m("A",5), r, r, r,  r, r, m("Bb",5), m("A",5)}
mel{m("A",5), r, r, r,  r, r, m("Bb",5), m("A",5)}
mel{m("Bb",5), r, m("A",5), r,  m("Bb",5), r, m("C#",6), r}
mel{m("D",6), r, r, r,  r, r, r, r}

-- Bars 12-16: Descending passage
mel{m("D",6), r, r, r,  m("C",6), r, r, r}
mel{m("Bb",5), r, r, r,  m("A",5), r, r, r}
mel{m("G",5), r, m("F#",5), r,  m("G",5), r, m("A",5), r}
mel{m("Bb",5), r, r, r,  m("A",5), r, r, r}
mel{m("G",5), r, r, r,  m("F#",5), r, r, r}
mel{m("G",5), r, r, r,  r, r, r, r}

-- ============================================================
-- ACCOMPANIMENT (Violin II) — the nervous pulsing eighths
-- ============================================================
local accomp = {}
for i = 1, #melody do
    -- Alternating Bb3-D4 eighth notes throughout
    if (i % 2) == 1 then
        accomp[i] = a("Bb",3)
    else
        accomp[i] = a("D",4)
    end
end

-- ============================================================
-- VIOLA — sustained harmonies
-- ============================================================
local viola = {}
for i = 1, #melody do
    -- Change harmony every 8 rows (1 bar)
    local bar = math.floor((i - 1) / 8)
    if (i - 1) % 8 == 0 then
        if bar < 6 then
            viola[i] = v("D",4)       -- G minor: D
        elseif bar < 11 then
            viola[i] = v("D",4)       -- Still D
        else
            viola[i] = v("Eb",4)      -- Passing harmony
        end
    else
        viola[i] = r
    end
end

-- ============================================================
-- BASS (Cello + Double Bass)
-- ============================================================
local bass = {}
for i = 1, #melody do
    local bar = math.floor((i - 1) / 8)
    if (i - 1) % 8 == 0 then
        if bar < 6 then
            bass[i] = b("G",2)
        elseif bar < 11 then
            bass[i] = b("D",3)
        else
            bass[i] = b("G",2)
        end
    else
        bass[i] = r
    end
end

-- ============================================================
-- FILE GENERATION
-- ============================================================
local num_rows = #melody
local num_channels = 4
local num_samples = 4
local num_patterns = 1
local num_orders = 12  -- repeat for longer benchmark

-- Samples: different waveforms and lengths for timbral variety
local samples = {
    {len = 200, wave = triangle, c5 = 8363},   -- 1: Melody (triangle = softer, string-like)
    {len = 128, wave = square,   c5 = 8363},   -- 2: Accompaniment (square = crisp)
    {len = 300, wave = triangle, c5 = 8363},   -- 3: Viola (triangle, longer = warmer)
    {len = 400, wave = saw,      c5 = 8363},   -- 4: Bass (saw = rich harmonics)
}
for i, s in ipairs(samples) do
    s.data = make_sample(s.len, s.wave)
end

-- Build pattern data
local function encode_pattern(rows)
    local data = {}
    for row = 1, rows do
        local channels = {melody[row], accomp[row], viola[row], bass[row]}
        for ch = 1, num_channels do
            local cell = channels[ch]
            if cell and cell[1] ~= REST then
                data[#data+1] = string.char(ch + 128)  -- channel + has-mask flag
                data[#data+1] = string.char(0x07)       -- mask: note + instrument + volume
                data[#data+1] = string.char(cell[1])    -- note
                data[#data+1] = string.char(cell[2])    -- instrument
                data[#data+1] = string.char(cell[3])    -- volume
            end
        end
        data[#data+1] = string.char(0)  -- end of row
    end
    return table.concat(data)
end

local pat_data = encode_pattern(num_rows)

-- Calculate offsets
local header_size = 192
local order_offset = header_size
local sample_ptr_offset = order_offset + num_orders
local pattern_ptr_offset = sample_ptr_offset + num_samples * 4
local sample_headers_start = pattern_ptr_offset + num_patterns * 4
local sample_header_size = 80
local pattern_start = sample_headers_start + num_samples * sample_header_size
local pattern_header_size = 8
local sample_data_start = pattern_start + pattern_header_size + #pat_data

-- Accumulate sample data offsets
local sample_offsets = {}
local offset = sample_data_start
for i, s in ipairs(samples) do
    sample_offsets[i] = offset
    offset = offset + s.len
end

-- Build file
local out = {}

-- IT Header (192 bytes)
out[#out+1] = "IMPM"
local song_name = "Mozart K550 - I"
out[#out+1] = song_name .. string.rep("\0", 26 - #song_name)
out[#out+1] = le16(0x1004)                  -- pattern row highlight
out[#out+1] = le16(num_orders)
out[#out+1] = le16(0)                       -- InsNum
out[#out+1] = le16(num_samples)
out[#out+1] = le16(num_patterns)
out[#out+1] = le16(0x0214)                  -- Cwt
out[#out+1] = le16(0x0214)                  -- Cmwt
out[#out+1] = le16(0x0009)                  -- Flags (stereo + linear slides)
out[#out+1] = le16(0x0001)                  -- Special
out[#out+1] = string.char(128)              -- GV
out[#out+1] = string.char(48)               -- MV
out[#out+1] = string.char(4)                -- Speed (ticks per row)
out[#out+1] = string.char(160)              -- Tempo (BPM)
out[#out+1] = string.char(128)              -- Sep
out[#out+1] = string.char(0)                -- PWD
out[#out+1] = le16(0)                       -- MsgLength
out[#out+1] = le32(0)                       -- MsgOffset
out[#out+1] = le32(0)                       -- Reserved

-- Channel pan: slight stereo spread
local pans = {20, 44, 28, 36}  -- melody left-ish, accomp right-ish
local chanpan = {}
for i = 1, 4 do chanpan[i] = string.char(pans[i]) end
for i = 5, 64 do chanpan[i] = string.char(128 + 32) end  -- disabled
out[#out+1] = table.concat(chanpan)

-- Channel volume
local chanvol = {}
for i = 1, 64 do chanvol[i] = string.char(64) end
out[#out+1] = table.concat(chanvol)

-- Orders
for i = 1, num_orders do
    out[#out+1] = string.char(0)
end

-- Sample pointers
for i = 1, num_samples do
    out[#out+1] = le32(sample_headers_start + (i-1) * sample_header_size)
end

-- Pattern pointer
out[#out+1] = le32(pattern_start)

-- Sample headers
for i, s in ipairs(samples) do
    local sh = {}
    sh[#sh+1] = "IMPS"
    sh[#sh+1] = string.rep("\0", 12)         -- DOS filename
    sh[#sh+1] = string.char(0)               -- zero
    sh[#sh+1] = string.char(64)              -- GvL
    sh[#sh+1] = string.char(0x11)            -- Flg (sample + loop)
    sh[#sh+1] = string.char(64)              -- Vol
    local sname = "Sample " .. i
    sh[#sh+1] = sname .. string.rep("\0", 26 - #sname)
    sh[#sh+1] = string.char(0)               -- Cvt (unsigned)
    sh[#sh+1] = string.char(0)               -- DfP
    sh[#sh+1] = le32(s.len)                  -- Length
    sh[#sh+1] = le32(0)                      -- LoopBegin
    sh[#sh+1] = le32(s.len)                  -- LoopEnd
    sh[#sh+1] = le32(s.c5)                   -- C5Speed
    sh[#sh+1] = le32(0)                      -- SusLoopBegin
    sh[#sh+1] = le32(0)                      -- SusLoopEnd
    sh[#sh+1] = le32(sample_offsets[i])       -- SamplePointer
    sh[#sh+1] = string.char(0)               -- ViS
    sh[#sh+1] = string.char(0)               -- ViD
    sh[#sh+1] = string.char(0)               -- ViR
    sh[#sh+1] = string.char(0)               -- ViT
    local header = table.concat(sh)
    out[#out+1] = header .. string.rep("\0", 80 - #header)
end

-- Pattern
out[#out+1] = le16(#pat_data)
out[#out+1] = le16(num_rows)
out[#out+1] = le32(0)
out[#out+1] = pat_data

-- Sample data
for _, s in ipairs(samples) do
    out[#out+1] = s.data
end

-- Write file
local filename = arg[1] or "mozart_k550.it"
local f = io.open(filename, "wb")
f:write(table.concat(out))
f:close()
local total = #table.concat(out)
print(string.format("Generated %s (%d bytes, %d rows, %d orders)", filename, total, num_rows, num_orders))
