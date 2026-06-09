data Handler = Handler { run :: Integer -> IO Lua () }

main :: IO ()
main = putStrLn "hello"
