v0.9.4 breaks the returns.json decorator with type=int
Before `v0.9.4` this code worked and converted the JSON field to an `int`:

```py
    @uplink.returns.json(key=('metadata', 'length'), type=int)
    @uplink.get('records/{id}')
    def get_record_length(self, record_id: uplink.Path(name='id')):
        pass
```

With `v0.9.4` the endpoint returns a `<Response [200]>` object instead of the expected `int`.

Am I not using the `type` argument of `returns.json` as intended? It would be very useful to be able to do simple type conversions such as this without having to write a model.
