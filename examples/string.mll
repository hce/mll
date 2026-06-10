gmatch :: String -> String -> LuaIterator "string.gmatch" String
gmatchTriplets :: String -> String -> LuaIterator "string.gmatch" (String, String, Maybe String)

main :: IO ()
main = do
    -- Simple word splitting
    let words = gmatchTriplets "Mata lai le; kiao!" "(%w+)([,%.;!%?]?)"
    putStrLn (show words)
