data Color = Red | Green | Blue

name :: Color -> String
name Red = "red"
name Green = "green"
name Blue = "blue"

data Shape = Circle Number | Rect Number Number

area :: Shape -> Number
area (Circle r) = 3.14 * r * r
area (Rect w h) = w * h

colorName :: Color -> String
colorName c = case c of
    Red -> "red"
    Green -> "green"
    Blue -> "blue"

main :: IO ()
main = do
    assert (name Red == "red") "name Red"
    assert (name Green == "green") "name Green"
    assert (name Blue == "blue") "name Blue"
    assert (area (Rect 3.0 4.0) == 12.0) "area Rect 3 4"
    assert (colorName Green == "green") "case Green"
