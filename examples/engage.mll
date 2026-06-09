export processEvent :: forall s. LuaFunction s -> Integer -> LuaIO s Integer
processEvent luafn n = do
    let f = engage luafn :: Integer -> Integer -> LuaIO s Integer
    f n (n + 1)

main :: IO ()
main = putStrLn "engage test ok"
