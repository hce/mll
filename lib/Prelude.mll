-- MLL Prelude
-- This module is auto-imported into every MLL program.

-- FFI primitives
putStrLn :: String -> LuaIO "print" ()
sqrt :: Number -> LuaPure "math.sqrt" Number

-- Testing
assert :: Bool -> String -> IO ()
assert True _ = putStrLn "."
assert False msg = error msg

-- Identity and combinators
id :: a -> a
id x = x

const :: a -> b -> a
const x _ = x

flip :: (a -> b -> c) -> b -> a -> c
flip f b a = f a b

-- List operations
head :: [a] -> a
head (x:_) = x
head [] = error "head: empty list"

tail :: [a] -> [a]
tail (_:xs) = xs
tail [] = error "tail: empty list"

map :: (a -> b) -> [a] -> [b]
map _ [] = []
map f (x:xs) = f x : map f xs

filter :: (a -> Bool) -> [a] -> [a]
filter _ [] = []
filter p (x:xs)
    | p x       = x : filter p xs
    | otherwise  = filter p xs

foldl :: (b -> a -> b) -> b -> [a] -> b
foldl _ acc [] = acc
foldl f acc (x:xs) = foldl f (f acc x) xs

foldr :: (a -> b -> b) -> b -> [a] -> b
foldr _ acc [] = acc
foldr f acc (x:xs) = f x (foldr f acc xs)

take :: Integer -> [a] -> [a]
take _ [] = []
take n (x:xs)
    | n <= 0    = []
    | otherwise = x : take (n - 1) xs

zipWith :: (a -> b -> c) -> [a] -> [b] -> [c]
zipWith _ [] _ = []
zipWith _ _ [] = []
zipWith f (x:xs) (y:ys) = f x y : zipWith f xs ys

length :: [a] -> Integer
length [] = 0
length (_:xs) = 1 + length xs

reverse :: [a] -> [a]
reverse xs = go [] xs
    where
        go acc [] = acc
        go acc (x:rest) = go (x:acc) rest
