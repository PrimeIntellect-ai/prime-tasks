[fuzz result] blank line between indented code block and paragraph doesn't loosen list
```markdown
-     test

  test2
```

---

```console
$ cmark
-     test

  test2
<ul>
<li>
<pre><code>test
</code></pre>
<p>test2</p>
</li>
</ul>
$ cargo run
   Compiling pulldown-cmark v0.10.0 (/home/michael/Development/pulldown-cmark/pulldown-cmark)
    Finished dev [unoptimized + debuginfo] target(s) in 0.76s
     Running `target/debug/pulldown-cmark`
-     test

  test2
<ul>
<li>
<pre><code>test
</code></pre>
test2</li>
</ul>
```
