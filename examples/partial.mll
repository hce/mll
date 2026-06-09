add :: Integer -> Integer -> Integer
add a b = a + b

apply :: (Integer -> Integer) -> Integer -> Integer
apply f x = f x

main :: IO ()
main = do
    let inc = add 1
    putStrLn (show (inc 5))
    putStrLn (show (apply (add 10) 7))
    let double = add 0
    putStrLn (show (apply inc (inc 3)))
