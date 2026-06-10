-- HashMap example: O(1) dictionary backed by Lua tables.

fromMaybe :: a -> Maybe a -> a
fromMaybe def Nothing = def
fromMaybe _ (Just x) = x

main :: IO ()
main = do
    let m = hmInsert "alice" 30
          $ hmInsert "bob" 25
          $ hmInsert "charlie" 35
          $ hmEmpty

    putStrLn (show m)
    putStrLn (show (hmLookup "bob" m))
    putStrLn (show (hmLookup "dave" m))
    putStrLn (show (hmSize m))
    putStrLn (show (hmMember "alice" m))
    putStrLn (show (hmMember "dave" m))
    putStrLn (show (hmKeys m))
    putStrLn (show (hmValues m))

    -- Delete and check
    let m2 = hmDelete "bob" m
    putStrLn (show (hmSize m2))
    putStrLn (show (hmLookup "bob" m2))

    -- Update existing key
    let m3 = hmInsert "alice" 31 m
    putStrLn (show (fromMaybe 0 (hmLookup "alice" m3)))
