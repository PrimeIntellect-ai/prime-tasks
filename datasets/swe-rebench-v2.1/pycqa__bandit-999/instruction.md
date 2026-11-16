urllib.urlopen does not exist in Python 3
### Describe the bug

The blacklist calls plugin checks for urllib usage. Specifically it checks for functions that don't exist in Python 3. Namely these:
- urllib.urlopen
- urllib.urlretrieve
- urllib.URLopener
- urllib.FancyURLopener

These also don't exist in Python 3:
- urllib2.urlopen
- urllib2.Request


### Reproduction steps

```bash
1. Read through https://docs.python.org/3/library/urllib.html
2. Compare with what was available in Python 2.7 https://docs.python.org/2.7/library/urllib.html
```


### Expected behavior

I expect that we shouldn't have to test for old Python 2 modules when Bandit no longer supports Python2.

### Bandit version

1.7.5 (Default)

### Python version

3.7

### Additional context

_No response_
