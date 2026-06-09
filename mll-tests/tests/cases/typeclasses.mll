class Describe a where
    describe :: a -> String

data Color = Red | Blue
    deriving (Show, Eq)

instance Describe Color where
    describe Red = "the color red"
    describe Blue = "the color blue"

main :: IO ()
main = do
    assert (describe Red == "the color red") "describe Red"
    assert (describe Blue == "the color blue") "describe Blue"
    assert (show Red == "Red") "show Red"
    assert (show Blue == "Blue") "show Blue"
    assert (Red == Red) "Red == Red"
    assert (not (Red == Blue)) "Red /= Blue"
