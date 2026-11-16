Singleton operator has no effect on an array of objects
Consider the following input:
```
[
{"type":"command"},
{"type":"commands"}
]
```
and expression `$[type='command']`. It returns the first object properly. However, I want to use the singleton operator to have easier handling: `$[][type='command']` does not return an array of matches and `$[type='command'][]` does neither.
How can I always return an array of results in my case?
