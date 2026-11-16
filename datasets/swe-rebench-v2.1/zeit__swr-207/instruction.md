Dynamic polling interval
When changing `refreshInterval` dynamically:

```js
const [int, setInt] = useState(0)
const { data } = useSWR('/api', { refreshInterval: int })

return <>
  {data}
  <button onClick={() => setInt(int + 1000)}>update</button>
</>
```

Sometimes the received `data` will not be updated from the data source upon interval changes. Need to refine the interval change logic and [HIDDEN]

Also we need a test to make sure it'll be stable in the future.

### Additional contract requirements

A runtime change to `refreshInterval` must be reflected by polling so that data can be refreshed from the source, including when polling is enabled from zero.
