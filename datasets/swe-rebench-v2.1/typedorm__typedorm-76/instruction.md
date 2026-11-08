Wrong level nesting with expressions using Logical operators
Generated expression are getting wrong level of nesting where it should be flat

i.e
```Typescript
AND : {
x: '11',
y: '22',
z: '33
}
```

should have been transformed into
(x = 11) AND (y=22) AND (z=33)

instead it is currently being transformed as
((x = 11) AND (y = 22)) AND (z=33)
