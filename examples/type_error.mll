add :: Integer -> Integer -> Integer
add a b = a ++ b

main :: IO ()
main = putStrLn (show (add 1 2))
