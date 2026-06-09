data Person = Person { personName :: String, personAge :: Integer }

main :: IO ()
main = do
    let p = Person "Alice" 30
    assert (personName p == "Alice") "personName accessor"
    assert (personAge p == 30) "personAge accessor"
    assert (p.personName == "Alice") "dot syntax name"
    assert (p.personAge == 30) "dot syntax age"
