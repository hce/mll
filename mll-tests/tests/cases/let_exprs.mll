main :: IO ()
main = do
    assert (let x = 5 in x + x == 10) "let in expr"
    assert (let a = 3 in let b = 4 in a + b == 7) "nested let"
