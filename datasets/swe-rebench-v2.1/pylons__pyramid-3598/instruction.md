Add `authenticated` view predicate
`authenticated=bool` view predicate could be nice - essentially the same in function as

```
effective_principals=pyramid.security.Authenticated
effective_principals=not_(pyramid.security.Authenticated)
```

except not that much PITA to remember how to write correctly or what to import from where.

---

It would also make [this @mmerickel's pattern](https://github.com/Pylons/pyramid/issues/436#issuecomment-3965530) slightly more readable:

```
@view_config(context=HTTPForbidden, authenticated=False)
def unauthenticated_forbidden_view(request):
    location = request.route_url('login', _query={'came_from': request.path})
    return HTTPSeeOther(location)

@view_config(context=HTTPForbidden, authenticated=True, renderer='forbidden.mako')
def forbidden_view(request):
    request.response.status = 403
    return {
        # params required for rendering mytemplate.mako
    }
```

### Additional contract requirements

The public name of the predicate is ``is_authenticated``; it replaces the
``authenticated`` spelling shown in the examples above. It is accepted by
both ``Configurator.add_view`` and ``Configurator.add_route`` as
``is_authenticated=True`` or ``is_authenticated=False``. When the keyword is
omitted, no authentication predicate is added.

``Request.is_authenticated`` is a read-only property. It returns ``True`` when
the request has an authenticated identity and ``False`` otherwise, and
attempting to assign to it raises ``AttributeError``.
