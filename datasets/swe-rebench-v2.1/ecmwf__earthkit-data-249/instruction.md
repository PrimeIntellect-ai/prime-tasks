normalize to date-list does not accept requests which are already lists of dates
### Is your feature request related to a problem? Please describe.

(I'm not sure if this qualifies as a bug or an enhancement, but to be positive I'll put it in the enhancement bucket!)

The normalize decorator for date-list successfully turns a MARS format list-string (i.e. a string with `/` used as a separator to make a list). However, if I provide a list of dates the decorator returns the following error:
```
AttributeError: 'StrWrapper' object has no attribute 'to_datetime'
```

I experienced this primarily with cds requests, where valid cdsapi requests now fail, for example:
```
s = from_source(
    "cds",
    "reanalysis-era5-single-levels",
    variable=["2t"],  #, "msl"],
    product_type="reanalysis",
    area=[50, -50, 20, 50],
    date=["2007-01-01","2008-02-04"],
    time="12:00",
)
```

And for completeness if I pass the date in the MARS format it works fine:
```
s = from_source(
    "cds",
    "reanalysis-era5-single-levels",
    variable=["2t"],  #, "msl"],
    product_type="reanalysis",
    area=[50, -50, 20, 50],
    date="2007-01-01/2008-02-04",
    time="12:00",
)
```


### Describe the solution you'd like

- I would like the decorators not to fail if the argument is already in the expected format
- I would not like to lose functionality we have implemented in the cdsapi

### Describe alternatives you've considered

_No response_

### Additional context

For a super simple minimal reproducible example, this code might be useful:
```
from earthkit.data.decorators import normalize

@normalize("date", "date-list(%Y-%m-%d)")
def f_norm(*args, **kwargs):
    return args, kwargs

# understands:
f_norm(date="2002-01-01/2003-03-01/2003-02-01")
# does not understand:
f_norm(date=["2002-01-01","2003-03-01","2003-02-01"])
```

### Organisation

ECMWF
