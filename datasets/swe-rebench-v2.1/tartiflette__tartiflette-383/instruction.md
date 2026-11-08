OBJECT supporting directive does not run if object is a part of union
* [ ] **Explain with a simple sentence the expected behavior**
I think the title covers the problem pretty much. The problem is easily reproducible.
I'm sorry, I can't provide the `Dockerfile` example. The image we're using is `python:3.8-alpine`, if that carries any weight.

Interestingly, placing the directive on the union definition will run the directive, despite the directive not supporting type UNION.

* [ ] **Tartiflette version:** _1.1.3_
* [ ] **Python version:** _3.8_
* [ ] **Executed in docker:** Yes
* [ ] **GraphQL Schema & Query:**
```
schema {
  query: Query
}

directive @run_me_this on OBJECT

type Query {
  rootQueryField: CoupleOfResponses
}

union CoupleOfResponses = ResponseOne | ResponseTwo

type ResponseOne @run_me_this {
...
}


type ResponseTwo {
...
}
```

```
# code
class RunMeThis("run_me_this"):
  async def on_pre_output_coercion(self, directive_args, next_directive, value, ctx, info):
    # never runs
    return await next_directive(value, ctx, info)
```

```
# the request
query {
  rootQueryField {
    ...on ResponseOne {
      ...
    }
  }
}
