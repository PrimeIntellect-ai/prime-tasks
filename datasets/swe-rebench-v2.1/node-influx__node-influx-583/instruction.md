Incorrect encoding when using placeholders / bind parameters
The `placeholders` is not correctly encoded in the request to the influx instance (see https://docs.influxdata.com/influxdb/v1.8/tools/api/#bind-parameters for expected encoding)

Using the following query:

```
influx.query(
  'select * from response_times where host = $host',
  {
    placeholders: { host: 'example' }
  }
);
```

## Expected Behavior

Query parameter `params` should be `params={ host: 'example' }`

## Actual Behavior

Query parameter `params` is  empty (`params=`)

## Details

[HIDDEN]

In a scenario where `options.query` looks like the following:

```
const options = {
  query: {
    p: 'pwd',
    u: 'user',
    params: { host: 'example' }
  }
};

querystring.stringify(options.query) === 'p=pwd&u=user&params='
```

## Proposed solution

[HIDDEN]

## Specifications

- Version: 5.6.3
- Platform: OS X

### Additional contract requirements

- When placeholders are supplied, the request’s `params` query parameter must carry the placeholders object as JSON text, preserving its bind-parameter keys and values.
