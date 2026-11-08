Unable to convert Parquet files with WKT geometry
As reported in https://github.com/planetlabs/gpq/issues/33#issuecomment-1600016255, converting Parquet files with a geometry column containing WKT values does not work (when there is more than one row).
