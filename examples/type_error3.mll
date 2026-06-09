double :: Integer -> Integer
double x = x + x

main :: IO ()
main = putStrLn (show (double "hello"))
