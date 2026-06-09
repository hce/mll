data Tree = Branch Tree Tree | Leaf Integer

depth :: Tree -> Integer
depth (Leaf _) = 0
depth (Branch a b) = 1 + max (depth a) (depth b)

main :: IO ()
main = do
    let t = Branch (Branch (Leaf 1) (Leaf 2)) (Leaf 3)
    putStrLn ("Depth: " ++ show (depth t))
