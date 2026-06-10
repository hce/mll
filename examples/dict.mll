-- A pure binary search tree dictionary, using Ord for keys.

data Dict k v = Empty | Node k v (Dict k v) (Dict k v)

empty :: Dict k v
empty = Empty

insert :: k -> v -> Dict k v -> Dict k v
insert k v Empty = Node k v Empty Empty
insert k v (Node nk nv left right)
    | k < nk    = Node nk nv (insert k v left) right
    | k > nk    = Node nk nv left (insert k v right)
    | otherwise = Node k v left right

lookup' :: k -> Dict k v -> Maybe v
lookup' _ Empty = Nothing
lookup' k (Node nk nv left right)
    | k < nk    = lookup' k left
    | k > nk    = lookup' k right
    | otherwise = Just nv

fromMaybe :: a -> Maybe a -> a
fromMaybe def Nothing = def
fromMaybe _ (Just x) = x

size :: Dict k v -> Integer
size Empty = 0
size (Node _ _ left right) = 1 + size left + size right

append :: [a] -> [a] -> [a]
append [] ys = ys
append (x:xs) ys = x : append xs ys

keys :: Dict k v -> [k]
keys Empty = []
keys (Node k _ left right) = append (keys left) (k : keys right)

values :: Dict k v -> [v]
values Empty = []
values (Node _ v left right) = append (values left) (v : values right)

main :: IO ()
main = do
    let d = insert "cherry" 3
          $ insert "banana" 2
          $ insert "apple" 1
          $ empty
    putStrLn (show (lookup' "banana" d))
    putStrLn (show (lookup' "date" d))
    putStrLn (show (size d))
    putStrLn (show (fromMaybe 0 (lookup' "apple" d)))
    putStrLn (show (fromMaybe 0 (lookup' "missing" d)))
    putStrLn (show (keys d))
