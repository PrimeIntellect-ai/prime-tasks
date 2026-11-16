Panic
In commit 5b9d69f a regression was introduced, since then this fragment panics
```
<html>
    <body>
        <ul>
            <table><tr></tr></table>
        </ul>
    </body>
</html>
```

### Additional contract requirements

- Rendering this fragment at width 80 must produce the empty string (`""`).
