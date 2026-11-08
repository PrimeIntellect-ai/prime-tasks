serialization/deserialization bug
I think I found a serialization/deserialization bug, for which there isn't an open issue. I ran this against the latest version of superjson about a week ago:

```
> x = sj.serialize({q: [9, {henlo: undefined, yee: new Date(), yee2: new Date(), foo1: new Date(), z: Symbol('cool')}]})
{
  json: { q: [ 9, [Object] ] },
  meta: {
    values: { 'q.1.henlo': [Array], 'q.1.yee': [Array], 'q.1.foo1': [Array] }
  }
}
> x.json.q
[
  9,
  {
    henlo: undefined,
    yee: '2020-09-06T22:41:57.555Z',
    yee2: '2020-09-06T22:41:57.555Z',
    foo1: '2020-09-06T22:41:57.555Z',
    z: Symbol(cool)
  }
]
> sj.deserialize(x)
{
  q: [
    9,
    {
      henlo: undefined,
      yee: 2020-09-06T22:41:57.555Z,
      yee2: '2020-09-06T22:41:57.555Z',
      foo1: 2020-09-06T22:41:57.555Z,
      z: Symbol(cool)
    }
  ]
}
```
