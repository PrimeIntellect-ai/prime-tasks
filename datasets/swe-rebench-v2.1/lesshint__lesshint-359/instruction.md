Operators shouldnt be preceded and  followed by one space if this operator is not an operator but just a char.
**Which version of `lesshint` are you using?**

last one

**How are you running `lesshint`? CLI, Node.js API, Grunt/Gulp plugin?**

gulp-lesslint

**What's your `.lesshintrc` configuration?**

vanilla

**If you're reporting a bug, please show us some code that's failing.**

```less
        margin-right: -(@grid-gutter-width / 4);
```

**What did you expect to happen?**

    {nothing}

**What's the actual result?**

    Warning: tables.less: line 13, col 25, spaceAroundOperator: Operators should be preceded and followed by one space.

**Would you be interested in submitting a PR for this issue?**

Why not


----

alternativ:

`@grid-whatever-width` shouldn't be allowed as name at all...
