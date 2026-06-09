data Tree = Branch Tree Tree | Leaf Integer

depth :: Tree -> Integer
depth (Leaf _) = 0
depth (Branch a b) = 1 + max (depth a) (depth b)

main :: IO ()
main = putStrLn (depth (Leaf 5))
