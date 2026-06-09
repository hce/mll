fromMaybe :: a -> Maybe a -> a
fromMaybe def Nothing = def
fromMaybe _ (Just x) = x

nothingInt :: Maybe Integer
nothingInt = Nothing

main :: IO ()
main = do
    assert (fromMaybe 0 (Just 42) == 42) "fromMaybe Just"
    assert (fromMaybe 0 nothingInt == 0) "fromMaybe Nothing"
