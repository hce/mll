class Describe a where
    describe :: a -> String

data Color = Red | Green | Blue

instance Describe Color where
    describe Red = "the color red"
    describe Green = "the color green"
    describe Blue = "the color blue"

data Shape = Circle Number | Square Number

instance Describe Shape where
    describe (Circle r) = "a circle with radius " ++ show r
    describe (Square s) = "a square with side " ++ show s

main :: IO ()
main = do
    putStrLn (describe Red)
    putStrLn (describe Blue)
    putStrLn (describe (Circle 3.14))
    putStrLn (describe (Square 5.0))
