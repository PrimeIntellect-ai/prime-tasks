change default for geom_col argument in read_*_gpd to geometry.name
When we use a `read_*_gpd` (e.g., `read_staypoints_gpd`) with a valid geodataframe it throws an error if the geometry column is not named 'geom'. I think if the geometry dataframe is already valid it should default to the geometry.name argument.
