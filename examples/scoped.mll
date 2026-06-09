export processEvent :: forall s. Integer -> LuaIO s ()
processEvent n = do
    liftIO $ putStrLn ("Processing event: " ++ show n)

main :: IO ()
main = putStrLn "scoped test"
