data Tree = Branch Tree Tree | Leaf Integer

depth :: Tree -> Integer
depth (Leaf _) = 0
depth (Branch a b) = "wrong" ++ show (depth a)

main :: IO ()
main = putStrLn (show (depth (Leaf 1)))
