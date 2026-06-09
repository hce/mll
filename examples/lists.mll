sum :: [Integer] -> Integer
sum [] = 0
sum (x:xs) = x + sum xs

main :: IO ()
main = do
    let xs = [1, 2, 3, 4, 5]
    putStrLn (show xs)
    putStrLn (show (sum xs))
    putStrLn (show (length xs))
    putStrLn (show (map (\x -> x * x) xs))
    putStrLn (show (take 3 xs))
    putStrLn (show (reverse xs))
    putStrLn (show (filter (\x -> x > 2) xs))
