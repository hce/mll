-- A pure hash map in MATA-LL.
--
-- Uses an AVL tree indexed by hash values, with association list
-- buckets for collision handling. Requires a hash function per key type.
--
-- Performance: O(log n) per operation (assuming few collisions).

-- Reuse AVL tree as the bucket index
data Tree v = TEmpty | TNode Integer Integer v (Tree v) (Tree v)
    deriving Show

theight :: Tree v -> Integer
theight TEmpty = 0
theight (TNode h _ _ _ _) = h

tnode :: Integer -> v -> Tree v -> Tree v -> Tree v
tnode k v l r = TNode (1 + max (theight l) (theight r)) k v l r

tbalance :: Tree v -> Integer
tbalance TEmpty = 0
tbalance (TNode _ _ _ l r) = theight l - theight r

trotateRight :: Tree v -> Tree v
trotateRight (TNode _ k v (TNode _ lk lv ll lr) r) = tnode lk lv ll (tnode k v lr r)
trotateRight t = t

trotateLeft :: Tree v -> Tree v
trotateLeft (TNode _ k v l (TNode _ rk rv rl rr)) = tnode rk rv (tnode k v l rl) rr
trotateLeft t = t

trebalance :: Tree v -> Tree v
trebalance TEmpty = TEmpty
trebalance (TNode h k v l r)
    | tbalance (TNode h k v l r) > 1 && tbalance l < 0  = trotateRight (tnode k v (trotateLeft l) r)
    | tbalance (TNode h k v l r) > 1                    = trotateRight (tnode k v l r)
    | tbalance (TNode h k v l r) < -1 && tbalance r > 0 = trotateLeft (tnode k v l (trotateRight r))
    | tbalance (TNode h k v l r) < -1                   = trotateLeft (tnode k v l r)
    | otherwise                                          = TNode h k v l r

tinsert :: Integer -> v -> Tree v -> Tree v
tinsert k v TEmpty = tnode k v TEmpty TEmpty
tinsert k v (TNode h nk nv left right)
    | k < nk    = trebalance (tnode nk nv (tinsert k v left) right)
    | k > nk    = trebalance (tnode nk nv left (tinsert k v right))
    | otherwise = TNode h k v left right

tlookup :: Integer -> Tree v -> Maybe v
tlookup _ TEmpty = Nothing
tlookup k (TNode _ nk nv left right)
    | k < nk    = tlookup k left
    | k > nk    = tlookup k right
    | otherwise = Just nv

-- Association list for collision buckets
data Bucket k v = BEmpty | BCons k v (Bucket k v)
    deriving Show

blookup :: k -> Bucket k v -> Maybe v
blookup _ BEmpty = Nothing
blookup k (BCons bk bv rest)
    | k == bk   = Just bv
    | otherwise = blookup k rest

binsert :: k -> v -> Bucket k v -> Bucket k v
binsert k v BEmpty = BCons k v BEmpty
binsert k v (BCons bk bv rest)
    | k == bk   = BCons k v rest
    | otherwise = BCons bk bv (binsert k v rest)

bdelete :: k -> Bucket k v -> Bucket k v
bdelete _ BEmpty = BEmpty
bdelete k (BCons bk bv rest)
    | k == bk   = rest
    | otherwise = BCons bk bv (bdelete k rest)

bsize :: Bucket k v -> Integer
bsize BEmpty = 0
bsize (BCons _ _ rest) = 1 + bsize rest

-- Hash map: Tree of buckets
data PureMap k v = PureMap (Tree (Bucket k v))
    deriving Show

-- String hash via Lua (MLL strings aren't char lists)
hashStr :: String -> LuaPure "__mll_hashstr" Integer

pmEmpty :: PureMap k v
pmEmpty = PureMap TEmpty

bucketFor :: Integer -> Tree (Bucket k v) -> Bucket k v
bucketFor h tree = case tlookup h tree of
    Just b  -> b
    Nothing -> BEmpty

pmInsert :: k -> v -> PureMap k v -> PureMap k v
pmInsert k v (PureMap tree) = PureMap (tinsert h (binsert k v (bucketFor h tree)) tree)
    where h = hashStr (show k)

pmLookup :: k -> PureMap k v -> Maybe v
pmLookup k (PureMap tree) = blookup k (bucketFor h tree)
    where h = hashStr (show k)

pmMember :: k -> PureMap k v -> Bool
pmMember k m = case pmLookup k m of
    Just _  -> True
    Nothing -> False

treeSize :: Tree (Bucket k v) -> Integer
treeSize TEmpty = 0
treeSize (TNode _ _ bucket left right) = bsize bucket + treeSize left + treeSize right

pmSize :: PureMap k v -> Integer
pmSize (PureMap tree) = treeSize tree

fromMaybe :: a -> Maybe a -> a
fromMaybe def Nothing = def
fromMaybe _ (Just x) = x

main :: IO ()
main = do
    let m = pmInsert "alice" 30
          $ pmInsert "bob" 25
          $ pmInsert "charlie" 35
          $ pmInsert "dave" 40
          $ pmInsert "eve" 28
          $ pmEmpty
    putStrLn (show (fromMaybe 0 (pmLookup "bob" m)))
    putStrLn (show (fromMaybe 0 (pmLookup "eve" m)))
    putStrLn (show (fromMaybe 0 (pmLookup "nobody" m)))
    putStrLn (show (pmSize m))
    putStrLn (show (pmMember "alice" m))
    putStrLn (show (pmMember "nobody" m))
    -- Update
    let m2 = pmInsert "alice" 31 m
    putStrLn (show (fromMaybe 0 (pmLookup "alice" m2)))
    putStrLn (show (pmSize m2))
    -- Show the tree structure
    putStrLn (show m)
