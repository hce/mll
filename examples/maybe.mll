main :: IO ()
main = do
    let a = Nothing :: Maybe Integer
    let b = Nothing :: Maybe String
    putStrLn $ show (a, b)
