data Person = Person { personName :: String
                      , personAge :: Integer }

greet :: Person -> String
greet p = "Hello, " ++ personName p ++ "! You are " ++ show (personAge p) ++ " years old."

main :: IO ()
main = do
    let p = Person "Alice" 30
    putStrLn (greet p)
    putStrLn (personName p)
    putStrLn (show (personAge p))
