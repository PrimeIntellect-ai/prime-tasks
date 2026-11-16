`uniqueWith` doesn't return items that are not equal to themselves
```ts
const errors = [
  { id: 1, reason: 'No name' },
  { id: 1, reason: 'No name' },
  { reason: 'No name' },
  { reason: 'No name' }
]

R.uniqueWith(errors, (errorA, errorB) => {
  if(errorA.id === undefined || errorB.id === undefined){
    return false
  }
  return errorA.id === errorB.id
})
```

expected
```ts
[
  { id: 1, reason: 'No name' },
  { reason: 'No name' },
  { reason: 'No name' }
]
```

actual
```ts
[
  { id: 1, reason: 'No name' },
]
```

It was unexpected for me that items not equal to themselves were removed from the array
