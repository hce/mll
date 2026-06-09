longExpr :: Integer -> Integer -> Integer -> Integer
longExpr a b c =
    a + b
      + c

main :: IO ()
main = do
    let x = longExpr 1 2 3
    putStrLn (show x)
