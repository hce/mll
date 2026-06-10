gmatch :: String -> String -> LuaIterator "string.gmatch" String

main :: IO ()
main = do
        let myString = "Mata lai le kiao"
        let stringParts = gmatch myString "[^ ]+"
        putStrLn (show stringParts)
