gmatch :: String -> String -> LuaIterator "string.gmatch" String
gmatchPairs :: String -> String -> LuaIterator "string.gmatch" (String, String)

main :: IO ()
main = do
    -- Simple word splitting
    let words = gmatch "Mata lai le kiao" "%w+"
    putStrLn (show words)

    -- Capture groups return tuples
    let kvs = gmatchPairs "name=Hans lang=MLL" "(%w+)=(%w+)"
    putStrLn (show (fst (head kvs)))
    putStrLn (show (snd (head kvs)))
    putStrLn (show (fst (head (tail kvs))))
    putStrLn (show (snd (head (tail kvs))))
