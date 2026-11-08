unclosed tag in code span
Hello,

I'm facing a problem, not sure where the problem really is (I'm not a Python developer), but I managed to create a little use case showing it.

Using fresh install mkdocs (1.1.2) and markdown 3.3.3 (problem is not here with markdown 3.2.2)

This `.md` file works
```md
A text

Another text `<?php`.

<div>
hello
</div>
```

Adding a new line, and it no longer works with error `AttributeError: 'NoneType' object has no attribute 'end'`

```md
A text

New line

Another text `<?php`.

<div>
hello
</div>
```

It also fails with other combinations of `code` tags containing HTML and/or PHP. But this one is the smaller use case I've found.

Thanks!
