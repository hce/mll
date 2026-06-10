-- LIO: Lua io library bindings

-- Opaque file handle (Lua userdata with metatable methods)
newtype FileHandle = FileHandle LuaUserData

-- Error convention: Lua functions return nil on failure
data IOResult a = IOSuccess a | IOFailure String

-- Default stream operations (stdin/stdout)
readLine :: LuaIO "io.read" String
readStdin :: String -> LuaIO "io.read" String
writeStdout :: String -> LuaIO "io.write" ()
flushStdout :: LuaIO "io.flush" ()

-- File open/close
fOpen :: String -> String -> LuaIO "io.open" FileHandle
fClose :: FileHandle -> LuaIO ":close" ()

-- File methods (handle as first arg, colon-call in Lua)
fRead :: FileHandle -> String -> LuaIO ":read" String
fReadLine :: FileHandle -> LuaIO ":read" String
fWrite :: FileHandle -> String -> LuaIO ":write" ()
fFlush :: FileHandle -> LuaIO ":flush" ()
fSeek :: FileHandle -> String -> Integer -> LuaIO ":seek" Integer

-- Iterate lines from a file path as a lazy list
fileLines :: String -> LuaIterator "io.lines" String
