Climatology cell_methods check bug
**Version of compliance checker running:** latest develop code, commit bfdcf8bbe87cfe22de929b00511d18dac94001ba

**Describe the checker this affects:** CF

**Attach a minimal CDL or NetCDF file which is able to reproduce the issue**
```
netcdf bug {
dimensions:
	time = 1 ;
        nv = 2 ;
variables:
	float time(time) ;
		time:climatology = "climatology_bounds" ;
		time:units = "days since 1900-01-01" ;
                time:long_name = "time" ;
	float climatology_bounds(time, nv) ;
	float v(time) ;
                v:cell_methods = "time: mean within years time: mean over years" ;
                v:long_name = "v" ;

:Conventions = "CF-1.8" ;
:title = "bug" ;
:history = "none" ;

data:

 time = 35795 ;
 climatology_bounds = 35795, 43100 ;
}
```

**To Reproduce:**
`compliance-checker -t cf:1.8 bug.nc`

**Describe the issue below:**
This regexp in your code seems not handle well the CF spec: https://github.com/ioos/compliance-checker/blob/develop/compliance_checker/cf/cf_1_6.py#L3266
