push function break loop
This code shows [0] instead of [0,1,2,3,4,5,6,7,8,9]
```
names = []
for x = 0; x < 10; x = x + 1 {
    names.push(x)
}
echo(names)
```
