Weird behaviour of indices() function
### What happened?

When I create a first FieldList object and call the fl.indices() function, I get a nice dictionary of metadata like this one:
```
{'class': ['od'], 'stream': ['enfo'], 'levtype': ['sfc'], 'type': ['pf'], 'expver': ['0001'], 'date': [20231128], 'time': [1200], 'domain': ['g'], 'number': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 'param': ['2t']}
```
but when I operate on the object, by doing `fl_new = fl.sel(param='2t')` or `fl_new = ekds.order_by("number", "stepRange")`, then I get the following error when calling fl_new.indices():
```
TypeError: 'list' object is not callable
```
Do you know what is the issue?

### What are the steps to reproduce the bug?

See above.

### Version

feature/tensor

### Platform (OS and architecture)

macOS

### Relevant log output

_No response_

### Accompanying data

_No response_

### Organisation

_No response_
