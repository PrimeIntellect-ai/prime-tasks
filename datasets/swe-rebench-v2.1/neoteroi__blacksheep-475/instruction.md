Application starts fail due OpenAPIHandler can't handle list[UUID4] type in a model
**Describe the bug**
In case a Pydantic model has a field like `list[UUID4]` OpenAPIHandler can't build proper schema for a response with a such model.


```python
app = Application()

docs = OpenAPIHandler(info=Info(title="Example API", version="0.0.1"))
docs.bind_app(app)


class Group(BaseModel):
    users: list[UUID4] = Field(..., title="List of user IDs")


@app.router.post("/")
def get_group() -> Group:
    ...

```

```bash
Traceback (most recent call last):
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/application.py", line 726, in _handle_lifespan
    await self.start()
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/application.py", line 715, in start
    await self.after_start.fire()
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/application.py", line 126, in fire
    await handler(self.context, *args, **kwargs)
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/common.py", line 403, in build_docs
    docs = self.generate_documentation(app)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 435, in generate_documentation
    paths = self.get_paths(app)
            ^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 444, in get_paths
    own_paths = self.get_routes_docs(app.router, path_prefix)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 1131, in get_routes_docs
    responses=self.get_responses(handler) or {},
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 1029, in get_responses
    {
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 1033, in <dictcomp>
    content=self._get_content_from_response_info(value.content),
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 970, in _get_content_from_response_info
    ] = self._get_media_type_from_content_doc(content)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 928, in _get_media_type_from_content_doc
    media_type.schema = self.get_schema_by_type(content_doc.type)
                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 637, in get_schema_by_type
    schema = self._get_schema_by_type(child_type, type_args)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 653, in _get_schema_by_type
    return self._get_schema_for_class(object_type)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 574, in _get_schema_for_class
    properties[field.name] = self.get_schema_by_type(
                             ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 637, in get_schema_by_type
    schema = self._get_schema_by_type(child_type, type_args)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 660, in _get_schema_by_type
    schema = self._try_get_schema_for_iterable(object_type, type_args)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 723, in _try_get_schema_for_iterable
    items=self.get_schema_by_type(item_type, context_type_args),
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 637, in get_schema_by_type
    schema = self._get_schema_by_type(child_type, type_args)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 665, in _get_schema_by_type
    schema = self._try_get_schema_for_generic(object_type, type_args)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/DEV/neoteroi/BlackSheep/blacksheep/server/openapi/v3.py", line 756, in _try_get_schema_for_generic
    parameters = origin.__parameters__
```
