Non-syntactic sugar version of {"var": [""]} not working?
On the playground, running something like:

data:

```
{"integers": [1,2,3,4,5,6,7,8]}
```

```
{"map":[
	{"var":"integers"},
	{"*":[{"var":[""]},2]}
]}
```

should be equivalent to:

```
{"map":[
	{"var":"integers"},
	{"*":[{"var":""},2]}
]}
```

But it looks like `{"var": [""]}` actually returns nil?
