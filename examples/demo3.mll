data Color = Red | Green | Blue

colorName :: Color -> String
colorName c = case c of
    Red   -> "red"
    Green -> "green"
    Blue  -> "blue"

main :: IO ()
main = putStrLn (colorName Red)
