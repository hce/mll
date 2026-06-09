data Forest = Empty | Cons Tree Forest

data Tree   = Node Integer Forest

countNodes :: Tree -> Integer
countNodes (Node val forest) = 1 + countForest forest

countForest :: Forest -> Integer
countForest Empty = 0
countForest (Cons t f) = countNodes t + countForest f

main :: IO ()
main = (putStrLn . show) $ countForest forest
  where
    forest = Cons (Node 42 (Cons (Node 23 Empty) Empty)) (Cons (Node 5 Empty) Empty)
