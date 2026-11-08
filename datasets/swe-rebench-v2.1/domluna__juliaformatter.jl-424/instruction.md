Error formatting nested for...in
I am running into a bug that causes the formatter to error on nested `for..in` calls. Here is a minimal example that causes an error:

```
x = [[1,2,3], [4,5,6]]
print([z for y in x for z in y])
```

Let me know if there is a way to fix this, I'm not sure what the best approach would be. The following code works with the formatter, but doesn't produce the appropriate list and instead produces generators:

```
x = [[1,2,3], [4,5,6]]

print([(z for z in y) for y in x])
```
