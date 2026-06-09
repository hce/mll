data Action = Action (Integer -> IO ())

main :: IO ()
main = putStrLn "provenance ok"
