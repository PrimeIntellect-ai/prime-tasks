#or and #ref tags don't combine as expected in "large" maps
On aero 1.1.4 the #or and #ref tags do not combined as expected when the maps contain enough data.

The following config map
```clojure
 {:x "foo"
  :y #or [#ref [:x] "bar"]}
```
will properly evaluate to
```clojure
 {:x "foo"
  :y "foo"}
```

However the config map
```clojure
 {:x "foo"
  :y #or [#ref [:x] "bar"]
  :junk0 "0"
  :junk1 "1"
  :junk2 "2"
  :junk3 "3"
  :junk4 "4"
  :junk5 "5"
  :junk6 "6"
  :junk7 "7"
  :junk8 "8"}
```
improperly evaluates to
```clojure
 {:x "foo"
  :y nil
  :junk0 "0"
  :junk1 "1"
  :junk2 "2"
  :junk3 "3"
  :junk4 "4"
  :junk5 "5"
  :junk6 "6"
  :junk7 "7"
  :junk8 "8"}
```

### Additional contract requirements

- When the config is `{:y #or [#ref [:x] "bar"]}` and `:x` is absent, it must resolve to `{:y "bar"}`.
