main :: IO ()
main = putStrLn (show ("Hello", 17, 23, 42, "World")) >>
    putStrLn (show [(1, 2, "3"), (4, 5, "6"), (7, 8, "9")] )
