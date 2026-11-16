Broken available_namespaces method
## 1) Bug

[This function](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/src/pynwb/__init__.py#L104-L106) is broken. There are 2 problems. [HIDDEN]

### Steps to Reproduce
```python
from pynwb import available_namespaces
namespaces = available_namespaces()
```
### Environment
Please describe your environment according to the following bullet points.
- **Python Executable:** Python
- **Python Version:** All
- **Operating System:** All
- **Pynwb Version:** dev

### Additional contract requirements

- Calling `available_namespaces()` with no arguments must complete successfully and return a tuple containing the names of all namespaces currently available to the library.
