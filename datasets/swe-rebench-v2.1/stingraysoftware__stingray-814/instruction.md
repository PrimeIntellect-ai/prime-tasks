Error reading the event file
Hi Stingray Development Team,

When analyzing a NICER X-ray data, I got an error when reading the event file:

File /data/software/anaconda/envs/tugbabztp/lib/python3.12/site-packages/stingray/events.py:625, in EventList.read(cls, filename, fmt, **kwargs)
    622                 setattr(evt, key.lower(), evtdata.additional_data[key])
    623     return evt
--> 625 return super().read(filename=filename, fmt=fmt)

File /data/software/anaconda/envs/tugbabztp/lib/python3.12/site-packages/stingray/base.py:647, in StingrayObject.read(cls, filename, fmt)
    643             ts[col_strip] += new_value
    645         ts.remove_column(col)
--> 647 return cls.from_astropy_table(ts)

File /data/software/anaconda/envs/tugbabztp/lib/python3.12/site-packages/stingray/base.py:425, in StingrayObject.from_astropy_table(cls, ts)
    422     setattr(cls, attr.lower(), np.array(ts[attr]))
    424 for key, val in ts.meta.items():
--> 425     setattr(cls, key.lower(), val)
    427 return cls

AttributeError: property 'exposure' of 'EventList' object has no setter

but I realized that I only get this error when we use the most recent version distributed by conda which I installed just a few days ago (stingray version: 2.0.0). The same code works just fine with the previous version (stingray version: 1.1.1) again installed earlier from conda.

Thanks !

### Additional contract requirements

- When converting an Astropy table to a `StingrayTimeseries` whose metadata includes the read-only `exposure` property, emit a `UserWarning` containing `protected attribute(s) of StingrayTimeseries: exposure`.
