:pass rendered before indentation
Hello fippsters!  Thanks for your cool tool and all the hard work you've put into it!

I am new to fipp so I could very well be misunderstanding how to express myself in fipp and/or desired vs actual behavior, but here I go anyway:

Given the following code:
```Clojure
(require '[fipp.engine :as fe])

(fe/pprint-document
   [:group
    [:span [:pass "<"] "AA" [:pass ">"]]
    [:align
     :line
     [:span [:pass "<"] "BB" [:pass ">"]]
     :line
     [:span [:pass "<"] "CC" [:pass ">"]]
     [:align
      :line
      [:span [:pass "<"] "DD" [:pass ">"]]]]]
   {:width 6})
```
I get the following output:
```
<AA>
<  BB>
<  CC>
<    DD>
```
When I was more expecting something like:
```
<AA>
  <BB>
  <CC>
    <DD>
```

I noticed this while exploring using background colors in puget: https://github.com/greglook/puget/issues/44.
