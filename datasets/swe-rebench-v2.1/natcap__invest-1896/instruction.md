SWY monthly QF outputs have 0 values instead of nodata
@newtpatrol was testing 3.14.2 and noticed that `QF.tif` had some 0 values around the watershed, where it looks like `nodata` values should be. I found that the monthly QF is where this is introduced. I'm not yet sure if it's part of the logic of the function `_calculate_monthly_quickflow_flow` or if it's a nodata masking bug.

![image](https://github.com/natcap/invest/assets/2659980/ba7eaadf-b9f6-4a6c-98c5-6b790a40b7de)
