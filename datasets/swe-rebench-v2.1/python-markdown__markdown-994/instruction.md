image short-reference links not supported
Hi,

I've encountered an unexpected behavior:

Markdown:
```
[![Build Status]](https://travis-ci.org/commonmark/cmark)


[Build Status]: https://img.shields.io/travis/commonmark/cmark/master.svg?style=flat
```

Produces
```
<p>
  <a href="https://travis-ci.org/commonmark/cmark">![Build Status]</a>
</p>
```

Expected behavior: (inserted the above markdown snippet as is into this issue)

[![Build Status]](https://travis-ci.org/commonmark/cmark)

[Build Status]: https://img.shields.io/travis/commonmark/cmark/master.svg?style=flat

or in html:
```
<p>
  <a href="https://travis-ci.org/commonmark/cmark"><img src="https://img.shields.io/travis/commonmark/cmark/master.svg?style=flat" alt="Build Status"></a>
</p>
```
In babel:

https://babelmark.github.io/?text=%5B!%5BBuild+Status%5D%5D(https%3A%2F%2Ftravis-ci.org%2Fcommonmark%2Fcmark)%0A%0A%0A%5BBuild+Status%5D%3A+https%3A%2F%2Fimg.shields.io%2Ftravis%2Fcommonmark%2Fcmark%2Fmaster.svg%3Fstyle%3Dflat
