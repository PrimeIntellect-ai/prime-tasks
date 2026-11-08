Problem with APIFlask generating docs with flask-apscheduler extension: KeyError: 'scheduler'
### Discussed in https://github.com/greyli/apiflask/discussions/206

<div type='discussions-op-text'>

<sup>Originally posted by **diten** February 13, 2022</sup>
Hi,
I'm pretty new to APIFlask, but I'm starting to like it, a lot. So really great work you guys/girls.
I think there must be a better way to fix this, I just tell what I have done meanwhile.

I'm facing a small problem, which I sort of fix it, but I just comment it here so if is not anywhere (I can't find anything about it), it's helpful to others.

I had a small app, I converted it to APIFlask, but it uses APScheduler, and it keep crashing.
If I remove APScheduler, everything worked right.
So with a little debugging I got to the culprit.

In `app.py._generate_spec` :
when it iterates over the rules, the scheduler rules aren't  well managed and crash the spec generation.
(I don't quite get if APScheduler definitions are right o wrong).

So my fix was really fast and ugly, but again, it could help somebody else:

Just before `for rule in rules:` I filtered all the /scheduler rules
```
        # extract scheduler rules as  a temp fix.
        rules: t.List[t.Any] = list(filter(lambda x: not str(x).startswith('/scheduler'), rules))
```

This let me keep using APIFlask and APscheduler altogether.
Scheduler functionality is obviously not in OAS Specs, but I have tried using `@doc(hide=True)` over the Scheduler definition to try to hide it, first, cause I don't want to show it, and then to see if that help solve the problem, but it didn't worked out.
Nonetheless, Scheduler functionality is there and working perfectly now.

Bye, cheers, Diten.
</div>

The error traceback:

```pytb
Traceback (most recent call last):
  File "/Users/greyli/projects/apiflask/venv/lib/python3.8/site-packages/flask/app.py", line 2073, in wsgi_app
    response = self.full_dispatch_request()
  File "/Users/greyli/projects/apiflask/venv/lib/python3.8/site-packages/flask/app.py", line 1518, in full_dispatch_request
    rv = self.handle_user_exception(e)
  File "/Users/greyli/projects/apiflask/venv/lib/python3.8/site-packages/flask/app.py", line 1516, in full_dispatch_request
    rv = self.dispatch_request()
  File "/Users/greyli/projects/apiflask/src/apiflask/app.py", line 415, in dispatch_request
    return view_function(*req.view_args.values())  # type: ignore
  File "/Users/greyli/projects/apiflask/src/apiflask/app.py", line 550, in spec
    response = jsonify(self._get_spec('json'))
  File "/Users/greyli/projects/apiflask/src/apiflask/app.py", line 621, in _get_spec
    self._spec = self._generate_spec().to_dict()
  File "/Users/greyli/projects/apiflask/src/apiflask/app.py", line 884, in _generate_spec
    blueprint = self.blueprints[blueprint_name]
KeyError: 'scheduler'
```

### Additional contract requirements

- Generating the OpenAPI document must not raise `KeyError` when a registered view's
  endpoint contains a dot but the part before the last dot is not the name of a
  registered blueprint. This is the case for routes registered by extensions such as
  Flask-APScheduler, whose endpoints look like `scheduler.get_jobs`.
- Such a view is treated as an ordinary view: it is included in the generated OpenAPI
  document (its path and operation appear in the spec), exactly like a view whose
  endpoint contains no dot.
