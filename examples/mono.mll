twice :: (a -> a) -> a -> a
twice f x = f (f x)

main :: IO ()
main = do
    putStrLn (show (twice (\x -> x + 1) 5))
    putStrLn (twice (\s -> s ++ "!") "hello")
