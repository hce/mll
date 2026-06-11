local tracker = require "tracker"

local function mk_process_chunk(handle)
	return function(chunk)
		-- We could be writing to a sound card here,
		-- to stdio, piped to sox, or to a file
		handle:write(chunk)
	end
end

local input = io.open("HongKong_Music.it", "rb")
local output = io.open("HongKong_Music.wav", "wb")

local chunk_swallower = mk_process_chunk(output)

local tracker_data = input:read("a")
tracker.play(chunk_swallower, tracker_data)
