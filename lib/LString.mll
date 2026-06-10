-- MLL bindings for Lua 5.4 string primitives

strByte :: String -> Integer -> LuaPure "string.byte" Integer
strLen :: String -> LuaPure "string.len" Integer
strSub :: String -> Integer -> Integer -> LuaPure "string.sub" String
strChar :: Integer -> LuaPure "string.char" String
