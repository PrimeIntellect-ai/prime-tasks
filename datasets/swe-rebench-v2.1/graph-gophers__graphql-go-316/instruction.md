Descriptions not parsed properly
**What version of the lib are you using?**
3e8838

**What did you do?**
Switched from comments (using `#`) to descriptions (using `"`, `"""`). Described some types but did not some others.

**What did you expect to see?**
When types are introspected, descriptions are properly assigned.

**What did you see instead?**
Non-described types have assigned description of the latest described types.

**To reproduce**
Run [this](https://gist.github.com/michaljemala/c6d2d38652d70b4ed563313f74092876) GraphQL server and introspect the types using
```
curl -XPOST -d '{"query":"{described: __type(name: \"Query\") {description} non-described: __type(name: \"NonDescribed\"){description}}"}' localhost:8080/query

{
  "data": {
    "described": {
      "description":" This is a described type. "
    },
    "nondescribed":{
        "description":" This is a described type. "
    }
  }
}
```
But you should see:
```
{
  "data": {
    "described": {
      "description":" This is a described type. "
    },
    "nondescribed":{
        "description":""
    }
  }
}
```
