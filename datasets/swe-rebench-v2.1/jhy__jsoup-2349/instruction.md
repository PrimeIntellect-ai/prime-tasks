Pretty printing consecutive text nodes should collapse consecutive whitespace
Since Jsoup 1.20.1, pretty-printing documents with consecutive text nodes does not fully collapse their whitespace:

```kotlin
val doc = Jsoup.parseBodyFragment("Before <span>Node</span> After")
doc.select("span").remove()
doc.toString()
```

```html
<html>
 <head></head>
 <body>Before  After</body>
</html>
```

(Note the double whitespace between "Before" and "After".)

Re-parsing the document and pretty-printing the result does then fully collapse the whitespace:

```kotlin
val doc = Jsoup.parseBodyFragment("Before <span>Node</span> After")
doc.select("span").remove()
Jsoup.parse(doc.toString()).toString()
```

```html
<html>
 <head></head>
 <body>Before After</body>
</html>
```

In my opinion, the pretty printer should produce the same result for consecutive or merged text nodes. Otherwise, the printer's output is not stable. (I.e. re-parsing and re-printing should not change the result.)
