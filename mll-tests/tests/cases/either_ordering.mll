fromRight :: b -> Either a b -> b
fromRight def (Left _) = def
fromRight _ (Right x) = x

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

compareInt :: Integer -> Integer -> Ordering
compareInt a b
    | a < b     = LT
    | a == b    = EQ
    | otherwise = GT

main :: IO ()
main = do
    assert (fromRight 0 (Right 42) == 42) "fromRight Right"
    assert (fromRight 0 (Left "err") == 0) "fromRight Left"
    assert (isLeft (Left "x")) "isLeft Left"
    assert (not (isLeft (Right 1))) "isLeft Right"
    let c = compareInt 1 2
    assert (not (c == EQ)) "compareInt 1 2 is not EQ"
