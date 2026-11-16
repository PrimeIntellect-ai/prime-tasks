add static version of PromiseState#_mapFlatMapValue ?
That method is useful when building components that receive a prop that may or may not be a PromiseState.

eg.
```js
const Comp = ({table}) => {
  table = table instanceof PromiseState ? table : PromiseState.resolve(table)
  return (
    <div>
      {table.fulfilled && <span>{table.value.length}</span>}
    <div>
  )
}
```

(It should probably get a name like `PromiseState.ensure()`, mapFlatMapValue is kind of cryptic)

Sounds like a useful addition?

### Additional contract requirements

Provide a static operation that wraps a raw value as a fulfilled PromiseState. When given an existing PromiseState, the operation must preserve its fulfillment or rejection state and payload rather than treating it as a raw fulfilled value.
