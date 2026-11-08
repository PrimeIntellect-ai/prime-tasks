Public API for relationship introspection
I think there's a gap in the API today, its reasonable for folks to want to do things like

- have the server default include all direct relationships
- do things like in https://github.com/miragejs/miragejs/issues/298#issuecomment-574766130

We need a public API for folks to be able to introspect all the relationships.

We have these APIs on schema, just need to review them + make them public.

Also for the first bullet point above, we should pass `model` into the `include()` function.
