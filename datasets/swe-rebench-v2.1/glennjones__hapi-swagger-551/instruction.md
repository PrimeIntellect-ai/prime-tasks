Allow vendor extension at the route level (x-*)
#### Context

* *hapi-swagger version*: 9.2.0

#### What are you trying to achieve or the steps to reproduce?

It is now possible to provide arbitrary vendor extensions with `x-*` outside of the info property but it still does not work on a route level. It seems like this could be easily fixed and that would allow to generate code samples with swagger.

```js
                // at the route level
                plugins: {
                    'hapi-swagger': {
                      'x-code-samples':
                        {
                            lang: 'JavaScript',
                            source: 'console.log(\'Hello World\');'
                      },
                    },
                }
```

#### What result did you get?

nothing is displayed in the swagger.json

#### What did you expect?

to have a 'x-code-samples' property for the corresponding operation in the swagger output

#### Proposal

It seems that there is some old code which allowed 'x-meta' at the route level option, why not make it accept anything instead of just 'x-meta'?
