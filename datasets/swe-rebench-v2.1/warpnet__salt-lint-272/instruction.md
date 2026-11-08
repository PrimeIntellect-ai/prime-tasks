Error 206 triggered with nested literal brace
**Describe the bug**
Error 206 is erroneously reported for the following construction

**To Reproduce**
```
[206] [LOW] Jinja variables should have spaces before and after: '{{ var_name }}'
test.sls:3
    - name: '{${{ key }}}'
```


**Expected behavior**
No issue on this line.


**Desktop (please complete the following information):**

- OS: Windows 10
- Version 0.6.1
