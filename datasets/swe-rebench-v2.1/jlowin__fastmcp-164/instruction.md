Allow optional types for resource template params
It would be nice if I could register a function as a resource_template where the function takes optional parameters and the resource_template only be required to fulfill the mandatory parameters.

`ValueError: Mismatch between URI parameters {'name'} and function parameters {'name', 'id', 'new_name'}`

e.x

```
def do_cool_thing(new_name: str, name: Optional[str], id: Optional[str] ):
   ...

 mcp.add_resource_fn(uri="scheme://{name}/{new_name}", do_cool_thing)
 mcp.add_resource_fn(uri="scheme://{id}/{new_name}", do_cool_thing)
```

### Additional contract requirements

- A function parameter is optional when it declares a default value; parameters without a default are mandatory.
- An `Optional[...]` type annotation alone does not make a parameter omittable. In the illustrated registrations, `name` and `id` need defaults (for example, `= None`) to be omitted from the URI template.
- Registering a function with a URI template that contains no parameters must raise `ValueError` with a message matching `URI template must contain at least one parameter`.
- When required function arguments are missing from the URI template, raise `ValueError` with a message matching `URI parameters .* must be a subset of the required function arguments`.
- Otherwise, if the URI template contains a parameter that is not a function argument, raise `ValueError` with a message matching `URI parameters .* must be a subset of the function arguments`.
