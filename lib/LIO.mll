-- LIO: Lua io library bindings
--
-- Default stream operations (stdin/stdout) work directly.
-- File handle operations require LuaUserData support (not yet available).

-- Read a line from stdin
readLine :: LuaIO "io.read" String

-- Read from stdin with mode: "l" (line), "n" (number), "a" (all)
readStdin :: String -> LuaIO "io.read" String

-- Write to stdout (no trailing newline, unlike putStrLn)
writeStdout :: String -> LuaIO "io.write" ()

-- Flush stdout
flushStdout :: LuaIO "io.flush" ()

-- Iterate lines from a file as a lazy list
fileLines :: String -> LuaIterator "io.lines" String
