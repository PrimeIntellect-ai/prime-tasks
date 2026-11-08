find_packages() include does not allow inclusion of subpackages without super packages
Hello! I'm trying to solve [an issue](https://github.com/fedora-infra/bodhi/issues/994) I've got in my project with [the change in setuptools 28.0 that made exclude also exclude all subpackages](https://github.com/pypa/setuptools/pull/733). I had been relying on that behavior to exclude my package's top level package so that I could distribute one of the subpackages as its own add-on package.

I decided to try to include just the subpackage and its subpackages instead, but this also does not seem to work on 28.0 unless I include the top level package (which I am trying to avoid).

To be a little more concrete, here are examples of different behavior. With setuptools-18.0.1, I get this with my project:

```
$ python -c "from setuptools import find_packages; print find_packages(include=['bodhi.server', 'bodhi.server.*'])"
['bodhi.server', 'bodhi.server.static', 'bodhi.server.services', 'bodhi.server.models', 'bodhi.server.views', 'bodhi.server.consumers', 'bodhi.server.scripts']
```

That's the results I want (note that 'bodhi' is not included). With setuptools-28.2.0, I get this with my project:

```
$ python -c "from setuptools import find_packages; print find_packages(include=['bodhi.server', 'bodhi.server.*'])"
[]
```

If I add ```'bodhi'``` (which I do not want), the ```bodhi.server``` packages get included.
