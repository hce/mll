add :: Integer -> Integer -> Integer
add = (+)

inc :: Integer -> Integer
inc = (+ 1)

inc' :: Integer -> Integer
inc' = (+) 1


main :: IO ()
main = do
    (putStrLn . show) $ (+) 1 2
    print $ inc 2
    print $ inc' 3
