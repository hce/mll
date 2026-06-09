main :: IO ()
main = do
    -- Right sections
    assert (head (map (+1) [1, 2, 3]) == 2) "right section (+1)"
    assert (head (map (*2) [3, 4, 5]) == 6) "right section (*2)"
    assert (head (filter (>2) [1, 2, 3, 4]) == 3) "right section (>2)"

    -- Left sections
    assert (head (map (10-) [1, 2, 3]) == 9) "left section (10-)"
    assert (head (map (100.0/) [2.0, 4.0, 5.0]) == 50.0) "left section (100.0/)"

    -- Section as value
    let double = (*2)
    assert (double 21 == 42) "section as value"
