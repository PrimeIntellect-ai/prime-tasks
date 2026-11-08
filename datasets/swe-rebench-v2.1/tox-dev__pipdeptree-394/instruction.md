erroneous warnings with development versions of packages installed
### What pipdeptree version are you using?

2.23.0 or 2.23.1.dev6+g02f4f26

### Are you running pipdeptree in a virtual environment?

Yes

### Describe the problem

Development versions are not being correctly parsed.  In a (probably ill advised) venv where most things are installed from the development branches I am seeing many warnings like:

```
@ pipdeptree --reverse -p six
Warning!!! Possibly conflicting dependencies found:
* aiohttp==4.0.0a2.dev0
 - frozenlist [required: >=1.1.1, installed: 1.4.2.dev0]
 - multidict [required: >=4.5,<7.0, installed: 6.0.6.dev0]
 - yarl [required: >=1.0,<2.0, installed: 1.9.5.dev0]
* aiohttp-jinja2==1.6
 - aiohttp [required: >=3.9.0, installed: 4.0.0a2.dev0]
* aiosignal==1.3.1
 - frozenlist [required: >=1.1.0, installed: 1.4.2.dev0]
* area-detector-handlers==0.0.10.post2.dev0+gf58ca85
 - pandas [required: Any, installed: 3.0.0.dev0+1025.gb4d40a2bf6]
* argon2-cffi-bindings==21.2.0
 - cffi [required: >=1.0.1, installed: 1.17.0.dev0]
* arrow==1.3.0
 - python-dateutil [required: >=2.7.0, installed: 2.9.0.post1.dev1+g0353b78]
* awkward==2.6.6
 - numpy [required: >=1.18.0, installed: 2.1.0.dev0]
* awkward-cpp==35
 - numpy [required: >=1.18.0, installed: 2.1.0.dev0]
* blosc2==3.0.0b1
 - numpy [required: >=1.23.0, installed: 2.1.0.dev0]
 - msgpack [required: Any, installed: 1.1.0rc1]
 - numexpr [required: Any, installed: 2.10.2.dev0]
[...it goes on for a couple of screens...]
```
