Loader reports warning when using importLibrary multiple times
When loading the maps library followed by another library using `loader.importLibrary()` and async/await syntax, a misleading warning-message `"Google Maps already loaded outside @googlemaps/js-api-loader.This may result in undesirable behavior as options and script parameters may not match."` is written to the console.

Here's the code that triggers this behavior:

```typescript
import Loader from '@googlemaps/js-api-loader';

async function main() {
  const loader = new Loader({apiKey: 'MY_API_KEY'});

  const {Map} = await loader.importLibrary('maps');

  // this line will trigger the warning message:
  await loader.importLibrary('marker');
}
```

The reason appears to be that the `done` flag isn't correctly set to `true` after the maps-api has initially been loaded.
