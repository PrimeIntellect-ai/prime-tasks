queryString.exclude an hash url is not expected
```
queryString.exclude('https://xxx.com?a=b#/home', ['a'])
```

expect:

```
https://xxx.com#/home
```

result
```
https://xxx.com?a=b#%2Fhome
```
