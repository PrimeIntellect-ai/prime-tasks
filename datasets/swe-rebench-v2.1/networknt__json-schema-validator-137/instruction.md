Maps of URLs can have performance impacts
While incorporating the feature of URL mappings into an app, [Spotbugs](https://spotbugs.readthedocs.io/en/stable/) flagged the [inefficient use of URL in maps](https://spotbugs.readthedocs.io/en/stable/bugDescriptions.html#dm-maps-and-sets-of-urls-can-be-performance-hogs-dmi-collection-of-urls).

While this is an easy fix, it does make a breaking change in the API since 1.0.5.

### Additional contract requirements

- URL mappings use URL strings for both map keys and values (`Map<String, String>`), rather than `URL` objects (`Map<URL, URL>`). Keys identify public URLs and values identify local URLs; this is the intended breaking change to the URL-mapping API.
