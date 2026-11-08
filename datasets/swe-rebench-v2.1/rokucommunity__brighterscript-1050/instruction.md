Support multi-dimensional array comma access syntax
Apparently multi-dimensional arrays support using a comma to access sub levels, rather than `[idx][idx]`.
The parser currently fails with this syntax.
![image](https://github.com/rokucommunity/brighterscript/assets/2544493/cb1e2cf3-e027-4fa2-9bab-6266d7e654ba)


Here's some examples:

```brighterscript
myMultiArray = [["hello"]]

'currently supported syntax
print myMultiArray[0][0]
'currently broken syntax
print myMultiArray[0, 0]
```

This seems to work for however many levels of nesting you have.
```brighterscript
myMultiArray = [[[[[[[[["hello"]]]]]]]]]
print myMultiArray[0][0][0][0][0][0][0][0][0]
print myMultiArray[0, 0, 0, 0, 0, 0, 0, 0, 0]
```

### Additional contract requirements

Comma-separated indexing must also be accepted in indexed assignments, preserving each index expression in the parsed access.
