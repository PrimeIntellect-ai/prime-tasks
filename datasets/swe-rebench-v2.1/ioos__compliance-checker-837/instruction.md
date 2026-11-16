CF Checker Plugin: extend notification if check for order of dimension fails
# Current situation

Dimensions of data variables are recommended to be ordered as follows:

* spatio-temporal dimensions (e.g. X, Y, Z and T) should be in the **order**: **TZYX**
* **additional dimensions** should be located to the **left** of the spatio-temporal dimensions

This is recommended in [section 2.4](http://cfconventions.org/Data/cf-conventions/cf-conventions-1.8/cf-conventions.html#dimensions) of the CF Conventions:

> If any or all of the dimensions of a variable have the interpretations of "date or time" (T), "height or depth" (Z), "latitude" (Y), or "longitude" (X) then we recommend, but do not require (see Section 1.4, "Relationship to the COARDS Conventions" ), those dimensions to appear in the relative order T, then Z, then Y, then X in the CDL definition corresponding to the file. All other dimensions should, whenever possible, be placed to the left of the spatiotemporal dimensions.

The check for this is done in `cf.CFBaseCheck._dims_in_order` and looks as follows:

```python
    def _dims_in_order(self, dimension_order):
        """
        :param list dimension_order: A list of axes
        :rtype: bool
        :return: Returns True if the dimensions are in order U*, T, Z, Y, X,
                 False otherwise
        """

        regx = regex.compile(r"^[^TZYX]*T?Z?Y?X?$")
        dimension_string = "".join(dimension_order)
        return regx.match(dimension_string) is not None
```

# Issue

If the user gets

```
VARIBALE's dimensions are not in the recommended order T, Z, Y, X. They are DIMENSIONs
```

it it not obvious whether

1. one or more of the dimensions T, Z, Y and/or X were not properly recognized,
2. an additional dimension is _wrongly_ located, or
3. the dimensions T, Z, Y and/or X are actually wrongly ordered.


# Solution

Extend the user output. Although quite long, I would suggest the following text:

```
VARIBALE's spatio-temporal dimensions are not in the recommended order T, Z, Y, X and/or further dimensions are not located left of T, Z, Y, X.  The dims are DIMENSIONs. Their guessed types are DIMENSION_TYPES (U: other/unknown; L: unlimited).
```

When there is agreement reached, I will be happy to create a PR.


# Outlook / Addtional Question

Considering unlimited dimensions as L-type and not as T-, Z-, Y- or X-type (if they were of such a type) might cause issues. E.g. if the Y dimension was unlimited, we would get a warning in the current situation.

[A reply](https://github.com/cf-convention/discuss/issues/60#issuecomment-661827686) to my [issue on order of dimensions in timeSeries datasets in the CF Discussion Repo](https://github.com/cf-convention/discuss/issues/60) suggest that the requirement for unlimited dimensions to be located on the left ([CF Section 9.3](http://cfconventions.org/Data/cf-conventions/cf-conventions-1.8/cf-conventions.html#representations-features)), might be related to the technical limitation of netCDF3 (one unlimited dim; unlimited dim most left):

> If there is a need for either the instance or an element dimension to be the netCDF unlimited dimension (so that more features or more elements can be appended), then that dimension must be the outer dimension of the data variable i.e. the leading dimension in CDL.

This means that the identification of unlimited dimensions in the IOOS CC CF Plugin could drop. Similarly the dimension type `L` could be dropped, which would simplify checking the order of dimensions.

### Additional contract requirements

- For a dimension-order failure, use this message format: `{variable}'s spatio-temporal dimensions are not in the recommended order T, Z, Y, X and/or further dimensions are not located left of T, Z, Y, X. The dimensions (and their guessed types) are {dimensions} (with U: other/unknown; L: unlimited).` List dimensions as comma-separated `name (type)` entries; for example, `latitude (Y), power (U)`.
