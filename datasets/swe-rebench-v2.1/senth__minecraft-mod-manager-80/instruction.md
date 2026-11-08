JSONDecode error when reading API response
### Describe the bug
Throws an exception when reading invalid JSON from the API response

**From #60**
> I think this is probably a related issue with the same symptom.
>
> `minecraft-mod-manager install shulkerboxtooltip`
>
> throws:
> `simplejson.errors.JSONDecodeError: Expecting value: line 1 column 1 (char 0)`
>
> using version 1.2.1

### Additional contract requirements

- Add a public method `Downloader.get(self, url: str)` in module `minecraft_mod_manager/gateways/downloader.py` that requests `url` and returns the parsed JSON body of the response.
- The method accepts loosely formatted JSON, including leading whitespace or embedded newlines, and returns its parsed value.
- A response body that is not valid JSON still raises the usual JSON parsing error (a `ValueError`).
