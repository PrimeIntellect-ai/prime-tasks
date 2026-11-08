"Invalid type: Is" when using "is defined"
When using "is defined", I'm getting "Template render error: assertType: invalid type: Is".

``` nunjucks
{% if content is defined %}
    {{ content }}
{% endif %}```

Full error output

```
Template render error: Template render error: assertType: invalid type: Is
    at Object._prettifyError (/Users/jonathan/testApp/node_modules/nunjucks/src/lib.js:35:11)
    at /Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:547:19
    at Template.root [as rootRenderFunc] (eval at _compile (/Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:617:18), <anonymous>:22:3)
    at Template.render (/Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:540:10)
    at /Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:350:27
    at createTemplate (/Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:299:9)
    at handle (/Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:311:11)
    at /Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:323:9
    at next (/Users/jonathan/testApp/node_modules/nunjucks/src/lib.js:281:7)
    at Object.asyncIter (/Users/jonathan/testApp/node_modules/nunjucks/src/lib.js:287:3)
    at Environment.getTemplate (/Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:305:9)
    at Environment.render (/Users/jonathan/testApp/node_modules/nunjucks/src/environment.js:344:10)
    at Object.render (/Users/jonathan/testApp/node_modules/nunjucks/index.js:91:14)
    at Object.processStyles (/Users/jonathan/testApp/utils/css.js:220:27)
    at main (/Users/jonathan/testApp/main.js:16:33)
    at <anonymous>
```

I'm using Nunjucks 3.1.2
