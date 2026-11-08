Parsing >>>>>>… takes quadratic time and eventually crashes with recursion error
```pycon
>>> import markdown, timeit
>>> num, dur = timeit.Timer(lambda: markdown.markdown(">" * 100)).autorange(); dur / num
0.004344235559692607
>>> num, dur = timeit.Timer(lambda: markdown.markdown(">" * 200)).autorange(); dur / num
0.016907797248859425
>>> num, dur = timeit.Timer(lambda: markdown.markdown(">" * 300)).autorange(); dur / num
0.05682634799741208
>>> markdown.markdown(">" * 331)
…
RecursionError: maximum recursion depth exceeded while calling a Python object
```

Same results in 3.0.1 and master.

### Additional contract requirements

- Specifically, `markdown.markdown('>>>>>>>>>>')` must render as:
```html
<blockquote>
<blockquote>
<blockquote>
<blockquote>
<blockquote>
<p>&gt;&gt;&gt;&gt;&gt;</p>
</blockquote>
</blockquote>
</blockquote>
</blockquote>
</blockquote>
```


Parsing long runs of `>` markers must avoid quadratic-time growth.
