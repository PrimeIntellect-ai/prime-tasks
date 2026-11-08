Pip install missing some files
Looks like the PyPi package is missing some files. This is what I get when i try to run it on my local machine with a direct install.

```
[2020-04-23 15:48:49 -0700] [96733] [ERROR] Exception in ASGI application
Traceback (most recent call last):
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/uvicorn/protocols/http/httptools_impl.py", line 385, in run_asgi
    result = await app(self.scope, self.receive, self.send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/uvicorn/middleware/proxy_headers.py", line 45, in __call__
    return await self.app(scope, receive, send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/fastapi/applications.py", line 149, in __call__
    await super().__call__(scope, receive, send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/applications.py", line 102, in __call__
    await self.middleware_stack(scope, receive, send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/middleware/errors.py", line 181, in __call__
    raise exc from None
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/middleware/errors.py", line 159, in __call__
    await self.app(scope, receive, _send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/middleware/base.py", line 25, in __call__
    response = await self.dispatch_func(request, self.call_next)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/optimade/server/middleware.py", line 30, in dispatch
    response = await call_next(request)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/middleware/base.py", line 45, in call_next
    task.result()
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/middleware/base.py", line 38, in coro
    await self.app(scope, receive, send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/middleware/cors.py", line 76, in __call__
    await self.app(scope, receive, send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/exceptions.py", line 82, in __call__
    raise exc from None
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/exceptions.py", line 71, in __call__
    await self.app(scope, receive, sender)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/routing.py", line 550, in __call__
    await route.handle(scope, receive, send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/routing.py", line 227, in handle
    await self.app(scope, receive, send)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/routing.py", line 41, in app
    response = await func(request)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/optimade/server/routers/landing.py", line 37, in landing
    return TEMPLATES.TemplateResponse("landing_page.html", context)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/templating.py", line 80, in TemplateResponse
    template = self.get_template(name)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/starlette/templating.py", line 67, in get_template
    return self.env.get_template(name)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/jinja2/environment.py", line 883, in get_template
    return self._load_template(name, self.make_globals(globals))
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/jinja2/environment.py", line 857, in _load_template
    template = self.loader.load(self, name, globals)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/jinja2/loaders.py", line 115, in load
    source, filename, uptodate = self.get_source(environment, name)
  File "/usr/local/Caskroom/miniconda/base/envs/dev/lib/python3.7/site-packages/jinja2/loaders.py", line 197, in get_source
    raise TemplateNotFound(template)
jinja2.exceptions.TemplateNotFound: landing_page.html

```
