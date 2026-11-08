Ugly display of { and } in example code
The generated example code looks like this...

```
curl 'https://api.foo/v2/devices/%7Bid%7D/tags' \
  --header 'Authorization: xxx'
```

However really in the UI it would be nicer to look like

```
curl 'https://api.foo/v2/devices/{id}/tags' \
  --header 'Authorization: xxx'
```
