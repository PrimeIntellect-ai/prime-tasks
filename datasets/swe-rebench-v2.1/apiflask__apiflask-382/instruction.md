KeyError when using add_url_for with flask View
## context

[flask-graphql](https://github.com/graphql-python/flask-graphql) is a project that adds graphql support to flask applications.

apiflask produces an error when using `add_url_for` with view_func=`GraphQLView.as_view(...)`.

## steps to reproduce

1. setup a minimal apiflask application that uses flask-graphql
```
#requirements.txt
apiflask
flask-graphql
```
```python
# app.py
from apiflask import APIFlask
from flask_graphql import GraphQLView
from graphql.type.schema import GraphQLSchema
from graphql.type.scalars import GraphQLString
from graphql.type.definition import (GraphQLField, GraphQLObjectType)

app = APIFlask(__name__)

# setup basic graphql schema
query = PersonType = GraphQLObjectType('Person', {
        'name': GraphQLField(GraphQLString),
    })

schema = GraphQLSchema(query=query)

app.add_url_rule('/graphql', view_func=GraphQLView.as_view(
    'graphql',
    schema=schema,
    graphiql=True,
))
```

2. Run the flask app
```python -m flask run```

3. Visit the AP documentation at `http://localhost:5000/docs:`


## Expected Result:
Either the '/graphql' endpoint is ignored, or docs are generated for the endpoint.

## Actual Results:
`KeyError: 'get'`

Truncated Stacktrace:
```bash
  File "...\venv\lib\site-packages\apiflask\route.py", line 39, in record_spec_for_view_class
    method = view_class.__dict__[method_name.lower()]
KeyError: 'get'
```

Environment:

- Python version: 3.9.13
- Flask version: 2.1.3
- APIFlask version: 1.1.3

## proposed solution
From my understanding, apiflask has support for flask `MethodView`. This seems to be implemented in `route.py`.

`GraphQLView` is a `View` not a `MethodView`.

This error seems to be caused by apiflask treating the `GraphQLView` like it is a `MethodView`.

[HIDDEN]
