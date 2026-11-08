Should we add `order` property to `encDef.sort`?
Currently Vega-lite’s `encDef.sort` looks exactly like vega Scale's `DataRef.sort`, which only contains `aggr` and `op` properties while the `order` field is deprecated as same mechanism can be achieved by using `reverse` property of the scale.

However, in vega-lite’s encoding definition, `sort` is another top-level object, not a part of `scale`.  If we do not have `order` property.  Specifying descending sort would require specifying both `sort` and `scale` like the following Barley example, which is kind of miss the point for extracting `sort` from `scale`.

```js
{
      data: {url: 'data/barley.json'},
      marktype: 'point',
      encoding: {
        x: {type: 'Q',name: 'yield'},
        y: {
          name: 'variety',
          type: 'O',
          sort: {field: 'yield', op: 'median'},
          __scale: {reverse: true}__
        },
        row: {
          type: 'O',
          name: 'site',
          sort: {field: 'yield', op: 'median'},
          __scale: {reverse: true}__
        },
        color: {type: 'N',name: 'year'}
      }
    }
```

By having `order` property, the spec can be a bit nicer:

```
{
  data: {url: 'data/barley.json'},
  marktype: 'point',
  encoding: {
    x: {type: 'Q',name: 'yield'},
    y: {
      name: 'variety',
      type: 'O',
      sort: {field: 'yield', op: ‘median’, __order:’desc'__}
    },
    row: {
      type: 'O',
      name: 'site',
      sort: {field: 'yield', op: 'median', __order:’desc’__},
    },
    color: {type: 'N',name: 'year'}
  }
}
```

### Additional contract requirements

- The `order` property of a sort definition accepts the string values `'ascending'` and `'descending'`. A sort definition with `order: 'descending'` expresses descending sorting: the scale is reversed, without the user having to specify `scale.reverse`.
- The default value of `sort` is `'ascending'`. Consequently, an ordinal field whose encoding does not specify a sort produces a scale domain that includes `sort: true`.
