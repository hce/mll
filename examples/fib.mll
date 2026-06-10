fib :: [Integer]
fib = 1:1:zipWith (+) fib (tail fib)

main :: IO ()
main = putStrLn $ "First 12 fibonacci numbers: " ++ show (take 12 fib)
