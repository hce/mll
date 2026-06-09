sin :: Number -> LuaPure "math.sin" Number
cos :: Number -> LuaPure "math.cos" Number
floor :: Number -> LuaPure "math.floor" Number
random :: Number -> Number -> LuaIO "math.random" Number

main :: IO ()
main = do
    putStrLn (show (sin 0.5))
    putStrLn (show (cos 0.0))
    putStrLn (show (floor 3.7))
    r <- random 1.0 10.0
    putStrLn (show r)
