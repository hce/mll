fib :: [Integer]
fib = 1:1:zipWith (+) fib (tail fib)

flip :: (a -> b -> c) -> b -> a -> c
flip f a b = f b a

export fibonacci :: Integer -> [Integer]
fibonacci = flip take fib
