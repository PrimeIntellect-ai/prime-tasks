getDirections' config parameter is wrongly typed
Hi, I am trying version 0.1.0 installed via yarn and realized that `config.steps` option of `getDirections` is not working as it is expected. The code I tried is as follows:

    client.getDirections({
      waypoints: [
        {
          coordinates: start
        },
        {
          coordinates: goal
        }
      ],
      geometries: 'geojson',
      profile: 'walking',
      steps:true,
      overview:"full"
    })

and I got a response whose `steps` property is an empty Array. I checked the request parameter on the Firefox DevTools and found that parameter `steps` was there but the value was empty.
![screenshot](https://user-images.githubusercontent.com/3016888/41428940-84236cd2-7046-11e8-8f83-b7d2ce046dba.png)

I have tried to change `true` to `"true"` in above code, but type checking complained. [HIDDEN]

### Additional contract requirements

When a caller supplies the native boolean `steps: true` to Directions, the resulting request must carry the `steps` query parameter as the string `true`, not as an empty value.
