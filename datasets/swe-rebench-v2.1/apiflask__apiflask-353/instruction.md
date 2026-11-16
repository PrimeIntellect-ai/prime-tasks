Allow path parameters overriding
APIFlask currently doesn't allow overriding path parameters specification. The proposal is to add such feature.

Consider following example:
I'm writing an endpoint which takes (among other things) one or several path parameters, and let's say, that one of them is of enum type which I want to validate using `@input` decorator and providing a schema with `location="path"`, and moreover, I would like to generate a proper OpenAPI spec based on this schema.
But when it comes to actually implementing this snippet, I run into an exception from APISpec which states that I'm trying to insert a duplicated path parameter; this is because APIFlask generates path parameter spec on its own under the hood, so I'm proposing to add a boolean flag argument which can be passed to an individual view's `@input` decorator and which will allow to skip default path parameter spec generation or overriding the default spec with the one generated from a schema.

A sample usage of such feature would look like this:
```py
@blueprint.input(SampleSchema(), location="path", drop_path_parameters=True)
```
Or, alternatively, this could be a default behaviour for schemas with `location="path"`.
