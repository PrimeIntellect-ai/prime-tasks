Add parseBooleans option
Parsing an object like
```javascript
{
    test: true
}
```
results in `test=true`. Using stringify it results in
```javascript
{
    test: "true"
}
```

That's why I think we need an additional option like parseNumbers for booleans.
