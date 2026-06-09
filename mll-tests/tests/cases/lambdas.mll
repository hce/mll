main :: IO ()
main = do
    let f = \x -> x + 1
    assert (f 5 == 6) "lambda single param"

    let add = \x y -> x + y
    assert (add 3 4 == 7) "lambda multi param"

    let apply = \g x -> g x
    assert (apply (+1) 10 == 11) "lambda higher order"
