Newlines not treated as whitespace in emphasis pattern
The following input is correctly not a list as there is no blank line between the first and second lines:

```plaintext
not a list
* list item 1
* list item 2
* list item 3
```

However, now that we have list-like syntax, the inline patterns make a mess of it and we get this output:

```html
<p>not a list
<em> list item 1
</em> list item 2
* list item 3</p>
```

It seems that `* list item 1\n*` is incorrectly being identified as `em`. However, the reference implementation renders that as:

```html
<p>not a list
* list item 1
* list item 2
* list item 3</p>
````

See [Babelmark](http://johnmacfarlane.net/babelmark2/?text=not+a+list%0A*+list+item+1%0A*+list+item+2%0A*+list+item+3) for comparison.

If we remove the newlines:

```plaintext
not a list * list item 1 * list item 2 * list item 3
```

Then things work as they should (see [Babelmark](http://johnmacfarlane.net/babelmark2/?normalize=1&text=not+a+list+*+list+item+1+*+list+item+2+*+list+item+3)):

```html
<p>not a list * list item 1 * list item 2 * list item 3</p>
```

Which suggests that the problem is that we are not properly accounting for newlines as being whitespace somewhere in an inline pattern.

Note that Commonmark differs from Markdown here in that it recognizes the list without the blank line. In fact, the Commonmark spec [acknowledges that this behavior is different][1] from Markdown. This issue is not about that. See #338 for that discussion. Please keep this discussion on point.

Finally, this issue was first reported on [StackOverflow](https://stackoverflow.com/q/54529652/866026) by user [Minato](https://stackoverflow.com/users/3960567/minato).

[1]: https://spec.commonmark.org/0.28/#example-266
