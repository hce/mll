fib :: [Integer]
fib = 1:1:zipWith (+) fib (tail fib)

-- fib :: [Integer]
-- fib = [1, 2, 3]

main :: IO ()
main = do
    print $ "Hello " ++ show 23 ++ " world!"
    (print . show) $ take 20 $ take 10 $ take 1000 fib
