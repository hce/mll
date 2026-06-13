#!/usr/bin/env lua
-- Generate a synthetic Impulse Tracker (.it) file for benchmarking.
-- 4-channel module with synthetic square wave samples.
-- The note data is entirely original (an LLM's failed attempt at
-- transcribing Mozart from memory). No copyrighted material.

local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function le32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256) end

-- Generate a square wave sample at a given length
local function make_square_sample(length)
    local data = {}
    local half = math.floor(length / 8)
    for i = 1, length do
        local phase = (i % (half * 2)) < half
        data[i] = string.char(phase and 40 or 216)  -- +40 / -40 as unsigned
    end
    return table.concat(data)
end

-- Note name to IT note number (C-5 = 60)
local notes = {
    ["C"]  = 0, ["C#"] = 1, ["Db"] = 1, ["D"]  = 2, ["D#"] = 3, ["Eb"] = 3,
    ["E"]  = 4, ["F"]  = 5, ["F#"] = 6, ["Gb"] = 6, ["G"]  = 7, ["G#"] = 8,
    ["Ab"] = 8, ["A"]  = 9, ["A#"] = 10, ["Bb"] = 10, ["B"]  = 11,
}
local function note(name, octave) return octave * 12 + notes[name] end
local REST = 255
local NOTECUT = 254

-- Mozart Symphony No. 40, K.550, opening theme
-- Encoded as {note, instrument, volume} per row per channel
-- 4 channels: Violin I (melody), Violin II (accompaniment), Viola, Cello/Bass
-- Speed 6, Tempo 132 (allegro molto)

local tempo = 132
local speed = 3  -- ticks per row (faster rows for sixteenth note resolution)

-- Each row = one sixteenth note at this speed
-- Quarter note = 4 rows, eighth = 2 rows, half = 8 rows

local function n(name, oct) return {note(name, oct), 1, 48} end
local function n2(name, oct) return {note(name, oct), 2, 40} end  -- accompaniment
local function n3(name, oct) return {note(name, oct), 3, 36} end  -- viola
local function n4(name, oct) return {note(name, oct), 4, 44} end  -- cello
local r = {REST, 0, 255}    -- rest (no new note)
local cut = {NOTECUT, 0, 255}  -- note off

-- Violin I: opening melody (bars 1-8 approx)
-- The famous Eb-D-D, Eb-D-D, Eb-D-Eb-F#-G pattern
local melody = {
    -- Bar 1: rest (accompaniment starts alone)
    r, r, r, r,  r, r, r, r,
    -- Bar 2: Eb5-D5-D5 (eighth-eighth-quarter)
    n("Eb",5), r, n("D",5), r,  n("D",5), r, r, r,
    -- Bar 3: Eb5-D5-D5
    n("Eb",5), r, n("D",5), r,  n("D",5), r, r, r,
    -- Bar 4: Eb5-D5-Eb5-F#5-G5
    n("Eb",5), r, n("D",5), r,  n("Eb",5), r, n("F#",5), r,
    -- Bar 5: G5 (half), rest
    n("G",5), r, r, r,  r, r, r, r,
    -- Bar 6: Bb5-A5-A5
    n("Bb",5), r, n("A",5), r,  n("A",5), r, r, r,
    -- Bar 7: Bb5-A5-A5
    n("Bb",5), r, n("A",5), r,  n("A",5), r, r, r,
    -- Bar 8: Bb5-A5-Bb5-C#6-D6
    n("Bb",5), r, n("A",5), r,  n("Bb",5), r, n("C#",6), r,
    -- Bar 9: D6 (half), rest
    n("D",6), r, r, r,  r, r, r, r,
    -- Bar 10-11: D6-C6-Bb5-A5-Bb5-A5-G5-F#5
    n("D",6), r, r, r,  n("C",6), r, r, r,
    n("Bb",5), r, r, r,  n("A",5), r, r, r,
    -- Bar 12: G5-F#5-G5-A5
    n("Bb",5), r, n("A",5), r,  n("G",5), r, n("F#",5), r,
    -- Bar 13: G5 (whole)
    n("G",5), r, r, r,  r, r, r, r,
}

-- Violin II: repeated eighth-note accompaniment figure (Bb4-Bb4-Bb4...)
local accomp = {}
for i = 1, #melody do
    if i <= 8 then
        -- First bar: start the rhythm
        if (i % 2) == 1 then
            accomp[i] = n2("Bb",3)
        else
            accomp[i] = n2("D",4)
        end
    else
        if (i % 2) == 1 then
            accomp[i] = n2("Bb",3)
        else
            accomp[i] = n2("D",4)
        end
    end
end

-- Viola: sustained notes (simplified)
local viola = {}
for i = 1, #melody do
    if (i - 1) % 8 == 0 then
        viola[i] = n3("D",4)
    else
        viola[i] = r
    end
end

-- Cello: bass notes
local cello = {}
for i = 1, #melody do
    if (i - 1) % 8 == 0 then
        cello[i] = n4("G",3)
    else
        cello[i] = r
    end
end

local num_rows = #melody
local num_channels = 4
local num_samples = 4
local num_patterns = 1
local num_orders = 8  -- repeat the pattern to make it longer for benchmarking

-- Build sample data
local sample_len = 256
local sample_data = make_square_sample(sample_len)

-- Build pattern data
local function encode_pattern(rows)
    local data = {}
    for row = 1, rows do
        local channels = {melody[row], accomp[row], viola[row], cello[row]}
        for ch = 1, num_channels do
            local cell = channels[ch]
            if cell and cell[1] ~= REST then
                -- channel marker: (ch) + 128 (has mask byte)
                data[#data+1] = string.char(ch + 128)
                -- mask: note + instrument + volume = 0x07
                data[#data+1] = string.char(0x07)
                -- note
                data[#data+1] = string.char(cell[1])
                -- instrument
                data[#data+1] = string.char(cell[2])
                -- volume
                data[#data+1] = string.char(cell[3])
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
-- No instruments in this file
local pattern_ptr_offset = sample_ptr_offset + num_samples * 4
local sample_headers_start = pattern_ptr_offset + num_patterns * 4
local sample_header_size = 80
local pattern_start = sample_headers_start + num_samples * sample_header_size
local pattern_header_size = 8
local sample_data_start = pattern_start + pattern_header_size + #pat_data

-- Build file
local out = {}

-- IT Header (192 bytes)
out[#out+1] = "IMPM"                        -- magic
local song_name = "MLL Benchmark"
out[#out+1] = song_name .. string.rep("\0", 26 - #song_name) -- song name (26 bytes)
out[#out+1] = le16(0x1004)                  -- pattern row highlight
out[#out+1] = le16(num_orders)   -- OrdNum
out[#out+1] = le16(0)            -- InsNum (no instruments)
out[#out+1] = le16(num_samples)  -- SmpNum
out[#out+1] = le16(num_patterns) -- PatNum
out[#out+1] = le16(0x0214)       -- Cwt (compatible with 2.14)
out[#out+1] = le16(0x0214)       -- Cmwt
out[#out+1] = le16(0x0009)       -- Flags (stereo + linear slides)
out[#out+1] = le16(0x0001)       -- Special
out[#out+1] = string.char(128)   -- GV (global volume)
out[#out+1] = string.char(48)    -- MV (mix volume)
out[#out+1] = string.char(speed) -- IS (initial speed)
out[#out+1] = string.char(tempo) -- IT (initial tempo)
out[#out+1] = string.char(128)   -- Sep (panning separation)
out[#out+1] = string.char(0)     -- PWD
out[#out+1] = le16(0)            -- MsgLength
out[#out+1] = le32(0)            -- MsgOffset
out[#out+1] = le32(0)            -- Reserved

-- Channel pan (64 bytes) - 4 active channels
local chanpan = {}
for i = 1, 4 do chanpan[i] = string.char(32) end  -- center pan
for i = 5, 64 do chanpan[i] = string.char(128 + 32) end  -- disabled
out[#out+1] = table.concat(chanpan)

-- Channel volume (64 bytes)
local chanvol = {}
for i = 1, 64 do chanvol[i] = string.char(64) end
out[#out+1] = table.concat(chanvol)

-- Orders
for i = 1, num_orders do
    out[#out+1] = string.char(0)  -- all play pattern 0
end

-- Sample pointers (no instrument pointers since InsNum=0)
for i = 1, num_samples do
    out[#out+1] = le32(sample_headers_start + (i-1) * sample_header_size)
end

-- Pattern pointers
out[#out+1] = le32(pattern_start)

-- Sample headers (80 bytes each)
local c5_freqs = {8363, 8363, 8363, 8363}  -- base frequencies
for i = 1, num_samples do
    local sh = {}
    sh[#sh+1] = "IMPS"                      -- magic
    sh[#sh+1] = string.rep("\0", 12)         -- DOS filename
    sh[#sh+1] = string.char(0)               -- zero
    sh[#sh+1] = string.char(64)              -- GvL (global volume)
    sh[#sh+1] = string.char(0x11)            -- Flg (sample present + loop)
    sh[#sh+1] = string.char(64)              -- Vol (default volume)
    local sname = "SynthSample"
    sh[#sh+1] = sname .. string.rep("\0", 26 - #sname)  -- name (26 bytes)
    sh[#sh+1] = string.char(0)               -- Cvt (unsigned samples)
    sh[#sh+1] = string.char(0)               -- DfP
    sh[#sh+1] = le32(sample_len)             -- Length
    sh[#sh+1] = le32(0)                      -- LoopBegin
    sh[#sh+1] = le32(sample_len)             -- LoopEnd
    sh[#sh+1] = le32(c5_freqs[i])            -- C5Speed
    sh[#sh+1] = le32(0)                      -- SusLoopBegin
    sh[#sh+1] = le32(0)                      -- SusLoopEnd
    sh[#sh+1] = le32(sample_data_start + (i-1) * sample_len)  -- SamplePointer
    sh[#sh+1] = string.char(0)               -- ViS
    sh[#sh+1] = string.char(0)               -- ViD
    sh[#sh+1] = string.char(0)               -- ViR
    sh[#sh+1] = string.char(0)               -- ViT
    local header = table.concat(sh)
    -- Pad to 80 bytes
    out[#out+1] = header .. string.rep("\0", 80 - #header)
end

-- Pattern
out[#out+1] = le16(#pat_data)    -- packed size
out[#out+1] = le16(num_rows)     -- rows
out[#out+1] = le32(0)            -- reserved
out[#out+1] = pat_data

-- Sample data (4 copies of the same square wave)
for i = 1, num_samples do
    out[#out+1] = sample_data
end

-- Write file
local filename = arg[1] or "benchmark.it"
local f = io.open(filename, "wb")
f:write(table.concat(out))
f:close()
print("Generated " .. filename .. " (" .. #table.concat(out) .. " bytes)")
