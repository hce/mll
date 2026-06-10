-- MLL Prelude
-- This module is auto-imported into every MLL program.

-- FFI primitives
putStrLn :: String -> LuaIO "print" ()
sqrt :: Number -> LuaPure "math.sqrt" Number

-- Process control
data ExitValue = Normal | Err Integer

-- Testing
assert :: Bool -> String -> IO ()
assert True _ = putStrLn "."
assert False msg = error msg

-- Common data types
data Any = AnyString String | AnyInteger Integer | AnyNumber Number | AnyBool Bool | AnyNull

data Either a b = Left a | Right b

data Ordering = LT | EQ | GT
    deriving Eq

-- Identity and combinators
id :: a -> a
id x = x

const :: a -> b -> a
const x _ = x

flip :: (a -> b -> c) -> b -> a -> c
flip f b a = f a b

-- Strict list operations (no lazy evaluation needed)
foldl :: (b -> a -> b) -> b -> [a] -> b
foldl _ acc [] = acc
foldl f acc (x:xs) = foldl f (f acc x) xs

foldr :: (a -> b -> b) -> b -> [a] -> b
foldr _ acc [] = acc
foldr f acc (x:xs) = f x (foldr f acc xs)

length :: [a] -> Integer
length [] = 0
length (_:xs) = 1 + length xs

reverse :: [a] -> [a]
reverse xs = go [] xs
    where
        go acc [] = acc
        go acc (x:rest) = go (x:acc) rest

-- Conditional execution (non-strict evaluation makes this safe:
-- the action is thunked and only forced when the condition is true)
when :: Bool -> IO () -> IO ()
when cond action = if cond then action else putStrLn ""

-- Tuple accessors
fst :: (a, b) -> a
fst (x, _) = x

snd :: (a, b) -> b
snd (_, y) = y

-- head, tail, map, filter, take, zipWith are implemented in the
-- Lua runtime to support lazy cons cells (infinite lists).
