RecursionError: maximum recursion depth exceeded
### What happened?

I have some grib2 files for 3 different variables and I am trying to group them into a single file. However when trying to save the results to this new file I am hitting a  `RecursionError`

### What are the steps to reproduce the bug?

See code snippet below:
```
from earthkit.data import from_source
import sys
import datetime
ds = from_source('empty')
for path in sys.argv[1:]:
    print(path)
    new = from_source('file', path)

    # Define start and end dates for the loop
    start_date = datetime.datetime(2021, 1, 1, 0, 5)
    end_date = datetime.datetime(2021, 1, 10, 10, 50)
    delta = datetime.timedelta(minutes=15)

    # Loop from start_date to end_date
    current_date = start_date
    while current_date <= end_date:
        ds += new.sel(valid_datetime=current_date.isoformat())
        current_date += delta

# Save the final dataset
ds.save('combined.grib')
```

Where sys.argv[1:] can be a path pointing to the grib file you want to modify.

error logs below:
![Image](https://github.com/user-attachments/assets/c1dc12e5-2495-40ef-aef3-5e4df49b436f)

### Version

0.12.0

### Platform (OS and architecture)

Linux

### Relevant log output

```shell

```

### Accompanying data

_No response_

### Organisation

ECMWF

### Additional contract requirements

- The combined dataset built by repeated concatenation must be saveable: calling
  `save()` on it must complete without raising `RecursionError`, and the saved file
  must contain all the concatenated fields.
