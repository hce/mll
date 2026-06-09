data Color = Red | Green | Blue

colorName :: Color -> String
colorName c = case c of
    Red   -> "red"
    Green -> "green"
    Blue  -> "blue"

applyTwice :: (Integer -> Integer) -> Integer -> Integer
applyTwice f x = f (f x)

main :: IO ()
main = do
    putStrLn (colorName Red)
    putStrLn (colorName Blue)
    let inc = \x -> x + 1
    putStrLn (show (applyTwice inc 5))
    let result = let a = 10
                     b = 20
                 in a + b
    putStrLn ("Result: " ++ show result)
