data Color = Red | Green | Blue
    deriving Show

data Secret = Secret Integer

main :: IO ()
main = do
    -- This should work: Color has Show
    assert (show Red == "Red") "show with deriving"
    -- This should work: Integer has Show
    assert (show 42 == "42") "show Integer"
    assert (show True == "True") "show Bool"
