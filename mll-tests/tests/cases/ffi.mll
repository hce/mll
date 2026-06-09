floor' :: Number -> LuaPure "math.floor" Number
ceil :: Number -> LuaPure "math.ceil" Number

main :: IO ()
main = do
    assert (floor' 3.7 == 3.0) "floor 3.7"
    assert (ceil 3.2 == 4.0) "ceil 3.2"
    assert (sqrt 4.0 == 2.0) "sqrt 4"
