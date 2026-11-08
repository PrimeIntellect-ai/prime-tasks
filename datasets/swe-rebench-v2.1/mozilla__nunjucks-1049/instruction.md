env.render() invokes the callback twice
Node: 6, 7
Nunjucks: 3.0.1
OS: Win 10x64

Under [specific circumstances](/Spown/nunj_double_rainder), when a templating error occurs the callback of the ``.render()`` method runs twice: one for the error and one more time returning an incomplete output. In the test case provided I took my project and reduced it to a minimum condition for this to happen.  Just run it and the output should show something like this
```
sending for webpage content
render #1
 error is:
 Template render error: (d:\Projects\nunj_double_rainder\tmpl\views\page_view.html)
  Template render error: (d:\Projects\nunj_double_rainder\tmpl\mixins\_header.html)
  Template render error: (d:\Projects\nunj_double_rainder\tmpl\mixins\_register_auth.html)
  Error: Unable to call `map_elements["nonExistantMacro"]`, which is undefined or falsey
 rendered content is:
 undefined
render #2
 error is:
 null
 rendered content is:
 Layout
 |- [<- extends] Serial Layout:
    |- [<- includes] _Header:
      |- [<- includes] _register_auth:
    |- [<- extends] page_view
    |/_Header
 |/Serial Layout
/Layout
express app.send(): Error: Can't set headers after they are sent.
got webpage content length: <h1>U FAIL!</h1><div>Reason: Template render error: (d:\Projects\nunj_double_rainder\tmpl\views\page_view.html)
  Template render error: (d:\Projects\nunj_double_rainder\tmpl\mixins\_header.html)
  Template render error: (d:\Projects\nunj_double_rainder\tmpl\mixins\_register_auth.html)
  Error: Unable to call `map_elements["nonExistantMacro"]`, which is undefined or falsey</div>
```

Here the second callback run yelds a text, where it lacks `` |- [<- import] map_elements:`` after ``|- [<- includes] _register_auth:`` from
[here](/Spown/nunj_double_rainder/blob/65748ded18d563dd8846fbfb8feb13d5b1c5540f/tmpl/mixins/_register_auth.html#L2)

Further investigation has shown that if I unwrap [this](/Spown/nunj_double_rainder/blob/65748ded18d563dd8846fbfb8feb13d5b1c5540f/tmpl/mixins/_header.html#L1) (if I remove the ``if`` check) - the whole construction starts to work as it should.

This error may be a very circumstantial, but it is also very serious, since render callback often contains the ``express``'s ``.send()`` method and it throws exception if you try to send the second time, potentially crashing the whole app, not just failing to render one page. If not caught that is...

I tried to traceback it but some parts seem to be async and there is just too much VM noise so I loose the track of the callback after going like 20 steps deep into ``.render()``
