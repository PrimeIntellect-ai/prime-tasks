CF: incorrect errors on units attribute for status_flag variables
**Version of compliance checker running:** 5.0.2 (doesn't occur in 5.0.0)

**Describe the checker this affects:**  CF (all versions)

**Attach a minimal CDL or NetCDF file which is able to reproduce the issue**
```
netcdf sample {
dimensions:
	TIME = 11 ;
variables:
	double TIME(TIME) ;
		TIME:standard_name = "time" ;
		TIME:units = "days since 1950-01-01 00:00:00 UTC" ;
	byte TIME_quality_control(TIME) ;
		TIME_quality_control:standard_name = "time status_flag" ;
		TIME_quality_control:flag_values = 0b, 1b, 2b, 3b, 4b, 5b, 6b, 7b, 8b, 9b ;
		TIME_quality_control:flag_meanings = "no_qc_performed good_data probably_good_data bad_data_that_are_potentially_correctable bad_data value_changed not_used not_used interpolated_values missing_values" ;
	double LATITUDE(TIME) ;
		LATITUDE:standard_name = "latitude" ;
		LATITUDE:units = "degrees_north" ;
	byte LATITUDE_quality_control(TIME) ;
		LATITUDE_quality_control:standard_name = "latitude status_flag" ;
		LATITUDE_quality_control:flag_values = 0b, 1b, 2b, 3b, 4b, 5b, 6b, 7b, 8b, 9b ;
		LATITUDE_quality_control:flag_meanings = "no_qc_performed good_data probably_good_data bad_data_that_are_potentially_correctable bad_data value_changed not_used not_used interpolated_values missing_values" ;
	double LONGITUDE(TIME) ;
		LONGITUDE:standard_name = "longitude" ;
		LONGITUDE:units = "degrees_east" ;
	byte LONGITUDE_quality_control(TIME) ;
		LONGITUDE_quality_control:standard_name = "longitude status_flag" ;
		LONGITUDE_quality_control:flag_values = 0b, 1b, 2b, 3b, 4b, 5b, 6b, 7b, 8b, 9b ;
		LONGITUDE_quality_control:flag_meanings = "no_qc_performed good_data probably_good_data bad_data_that_are_potentially_correctable bad_data value_changed not_used not_used interpolated_values missing_values" ;
}
```


**To Reproduce:**
Run the CF-1.6 checker as `compliance-checker -t cf:1.6 sample.cdl`

**Describe the issue below:**
The output includes
```
                                     Errors
--------------------------------------------------------------------------------
§3.1 Units
* time must be in a valid units format <unit> since <epoch> not None
* variables defining latitude ("LATITUDE_quality_control") must use degrees_north or degrees if defining a transformed grid. Currently None
* variables defining longitude ("LONGITUDE_quality_control") must use degrees_east or degrees if defining a transformed grid. Currently None
```
The first error message doesn't report the variable name, but I've confirmed it's referring to the `TIME_quality_control` variable. So all three errors are looking at flag variables (with a [standard_name_modifier](http://cfconventions.org/cf-conventions/v1.6.0/cf-conventions.html#standard-name-modifiers) "status_flag"). Obviously these should not have units.

### Additional contract requirements

- When reporting that `temp_flag` has units despite its `status_flag` standard name modifier, emit exactly: `units attribute for variable temp_flag must be unset when status_flag standard name modifier is set`.
