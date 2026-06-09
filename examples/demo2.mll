applyTwice :: (Integer -> Integer) -> Integer -> Integer
applyTwice f x = f (f x)

main :: IO ()
main = do
    let inc = \x -> x + 1
    putStrLn (show (applyTwice inc 5))
