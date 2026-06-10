data Expr a where
    LitI  :: Integer -> Expr Integer
    LitB  :: Bool -> Expr Bool
    Add   :: Expr Integer -> Expr Integer -> Expr Integer
    IfE   :: Expr Bool -> Expr a -> Expr a -> Expr a

eval :: Expr Integer -> Integer
eval (LitI n) = n
eval (Add a b) = eval a + eval b
eval (IfE c t f) = if evalBool c then eval t else eval f

evalBool :: Expr Bool -> Bool
evalBool (LitB b) = b
evalBool (IfE c t f) = if evalBool c then evalBool t else evalBool f

main :: IO ()
main = do
    assert (eval (LitI 42) == 42) "LitI 42"
    assert (eval (Add (LitI 1) (LitI 2)) == 3) "Add 1 2"
    assert (eval (Add (Add (LitI 10) (LitI 20)) (LitI 5)) == 35) "nested Add"
    assert (evalBool (LitB True) == True) "LitB True"
    assert (evalBool (LitB False) == False) "LitB False"
    assert (eval (IfE (LitB True) (LitI 1) (LitI 2)) == 1) "IfE true"
    assert (eval (IfE (LitB False) (LitI 1) (LitI 2)) == 2) "IfE false"
