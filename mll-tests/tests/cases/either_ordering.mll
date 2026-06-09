fromEither :: Either a a -> a
fromEither (Left x) = x
fromEither (Right x) = x

compareInt :: Integer -> Integer -> Ordering
compareInt a b
    | a < b     = LT
    | a == b    = EQ
    | otherwise = GT

main :: IO ()
main = do
    assert (fromEither (Right 42) == 42) "fromEither Right"
    assert (fromEither (Left 99) == 99) "fromEither Left"
    let c = compareInt 1 2
    assert (not (c == EQ)) "compareInt 1 2 is not EQ"
