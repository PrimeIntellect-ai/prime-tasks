Allow array as key, multiple arguments to fetcher
In the [parameter documentation](https://github.com/Kong/swrv#parameters), the readme mentions that it is possible to pass an array as a cache key to useSWRV, presumably to allow passing multiple arguments to the fetch function as SWR does.

Currently, this does not work and it brakes the caching completely.

Is there a plan to support this feature, or is there another way to pass multiple arguments to the fetcher function?
