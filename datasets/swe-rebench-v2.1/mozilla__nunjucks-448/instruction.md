Raw is broken, gets confused with "fake" variable declarations
Raw blocks break when there's something that looks like a variable declaration but isn't, for example `{{ x }` (it opens like a variable but doesn't end like one).

### Sample

```html
{% raw %}
<code>
{{ i_am_a_dumb_variable }}

{{ i_am_an_imposter_i_kill_nunjucks }
</code>
{% endraw %}
```

### Stacktrace

```
/Users/aaron/git/nunjucks/src/environment.js:425
            else throw err;
                       ^
Template render error: (/Users/aaron/git/nunjucks/tests/raw.html)
  expected endraw, got end of file
    at Object.exports.prettifyError (/Users/aaron/git/nunjucks/src/lib.js:34:15)
    at Obj.extend.render (/Users/aaron/git/nunjucks/src/environment.js:423:27)
    at /Users/aaron/git/nunjucks/src/environment.js:270:35
    at createTemplate (/Users/aaron/git/nunjucks/src/environment.js:194:25)
    at handle (/Users/aaron/git/nunjucks/src/environment.js:206:25)
    at /Users/aaron/git/nunjucks/src/environment.js:223:21
    at next (/Users/aaron/git/nunjucks/src/lib.js:198:13)
    at Object.exports.asyncIter (/Users/aaron/git/nunjucks/src/lib.js:205:5)
    at Obj.extend.getTemplate (/Users/aaron/git/nunjucks/src/environment.js:202:17)
    at Obj.extend.render (/Users/aaron/git/nunjucks/src/environment.js:262:14)
```

This obviously isn't the expected behavior. I'm looking into the parser's raw parsing, but maybe someone more familiar with the codebase knows precisely where it messes up.
