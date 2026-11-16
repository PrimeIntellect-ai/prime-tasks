`find-in-text` selector does not seem to work when it's the last argument of a `child` selector
I don't know if it's a bug or if I missed something, but `find-in-text` selector does not seem to work when it's the last argument of a `child` selector:

```
(let [tree (-> "<div><div><span>a</span></div></div>" h/parse h/as-hickory)]
      (hs/select (hs/child
                  (hs/tag :div)
                  (hs/find-in-text #"a"))
               tree)) ; => []
```

But it works when adding a dummy `and`:

```
(let [tree (-> "<div><div><span class=\"go\">a</span></div></div>" h/parse h/as-hickory)]
      (hs/select (hs/child
                  (hs/tag :div)
                  (hs/and hs/any (hs/find-in-text #"a"))
               tree)) ; => works
```
