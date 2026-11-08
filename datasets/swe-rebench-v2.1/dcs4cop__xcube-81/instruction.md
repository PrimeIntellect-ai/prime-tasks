Case insensitive WMTS KVP parameters

In the dcs4cop viewer, by default the WMTS getTile request is launched using the TIME dimension parameter. For Landsat, Sentinel and CMEMS layers it isn't a problem.
Only for the OLCI layers, the response is not wat we expected. A getTile request with the uppercase TIME parameter will result in the default image(I guess the latest available date), regardless of the time value.
It looks like the uppercase TIME parameter is skipped by the WMTS service. However, the OLCI WMTS service is working correctly when the time parameter is written in lowercase.

To fulfill the WMTS OGC standards, can you adapt the service so that the WMTS parameters are case insensitive?

![image](https://user-images.githubusercontent.com/206773/59012644-51986a00-8838-11e9-952b-5c38de58f0de.png)

### Additional contract requirements

- Add a public function `caseless_dict(*args, **kwargs) -> Dict` in module `xcube.util.caseless`. It returns a dictionary-like object that treats string keys case-insensitively for containment checks, item access, assignment, deletion, `get` and `pop`. Optional positional arguments (for example a mapping) initialise the underlying dictionary.


- For WMTS KVP GetTile requests, an invalid TIME dimension value must result in HTTP 400, regardless of the parameter name's casing.
