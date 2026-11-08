`cssSelector` behavior changed since v1.16.2
Before v1.16.2, calling `cssSelector()` on the "A" paragraph in
```
<div>
  <div id="id1">
    <p>A</p>
  </div>
</div>
```
produced the result `#id1 > p`.

From v1.16.2, the result becomes `html > body > div > div > p` which is bound more to the structure of the HTML, and doesn't utilize the supposedly unique id anymore.

The [cssSelector doc](https://jsoup.org/apidocs/org/jsoup/nodes/Element.html#cssSelector()) also says
> If the element has an ID, returns #id; otherwise returns the parent (if any) CSS selector, followed by '>', followed by a unique selector for the element (tag.class.class:nth-child(n)).

which very likely leads to the understanding that the higher precedence of ID also applies to the parent CSS selector.
