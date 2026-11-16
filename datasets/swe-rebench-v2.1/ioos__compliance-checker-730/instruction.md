CF Grid Mapping Required Attributes
The CF-1.7 checker incorrectly requires all attributes listed when only some are applicable.

[Appendix F](http://cfconventions.org/Data/cf-conventions/cf-conventions-1.7/cf-conventions.html#appendix-grid-mappings) describes the grid mapping specifications:

> Each recognized grid mapping is described in one of the sections below. Each section contains: the valid name that is used with the grid_mapping_name attribute; a list of the specific attributes that may be used to assign values to the mapping’s parameters; the standard names used to identify the coordinate variables that contain the mapping’s independent variables; and references to the mapping’s definition or other information that may help in using the mapping. Since the attributes used to set a mapping’s parameters may be shared among several mappings, their definitions are contained in a table in the final section. The attributes which describe the ellipsoid and prime meridian may be included, when applicable, with any grid mapping.

The operative phrase is
> a list of the specific attributes that __may__ be used to assign values to the mapping’s parameters

The checker's incorrect behavior is illustrated in the following example, testing the `lambert_conformal_conic` grid mapping (output shown):

```
§5.6 Horizontal Coorindate Reference Systems, Grid Mappings, Projections
* false_easting is a required attribute for grid mapping lambert_conformal_conic
* false_northing is a required attribute for grid mapping lambert_conformal_conic
```
The spec indicates that the attributes `false_easting` and `false_northing` are valid attributes but not *required* attributes (hence the "...__may__ be used to assign values to the mapping's parameters...").

The correct behavior should only test the conditions for the attributes (found in Table F.1) if the attributes exist.
