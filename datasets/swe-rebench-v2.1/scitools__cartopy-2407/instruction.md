Projection._project_multiline() returns empty list rather than empty sgeom.MultiLineString
### Description

When providing a MultiLineString to the [crs.Projection.project_geometry()](https://scitools.org.uk/cartopy/docs/latest/_modules/cartopy/crs.html#Projection) function, if an empty MultiLineString is provided or if the projection returns no geometries, an empty list is returned, rather than an empty MultiLineString. In all other _project_* functions, an empty geometry is returned if the geoms list is empty.

This is a problem for me as I am projecting global LineStrings/MultiLineStrings from Plate Carree to Mercator, and some of these objects may be north/south of the limits of the Mercator projection, and so return nothing when projected. This leads to crs.Projection.project_geometry() returning an empty list rather than an empty MultiLineString, which caused my downstream code to fail as it expected the returned object to have  a `geoms` attribute. I can bypass this issue with an `isinstance(geom, list)` condition, but the underlying issue should probably be fixed.

#### Code to reproduce

```
>>> import cartopy.crs as ccrs
>>> import shapely.geometry as sgeom
>>> ccrs.Mercator().project_geometry(sgeom.MultiLineString([sgeom.LineString([[0, 0], [1, 1]])]), ccrs.PlateCarree())
<MULTILINESTRING ((0 0, 111319.491 110579.965))>
>>> type(ccrs.Mercator().project_geometry(sgeom.MultiLineString([sgeom.LineString([[0, 0], [1, 1]])]), ccrs.PlateCarree()))
<class 'shapely.geometry.multilinestring.MultiLineString'>
>>> ccrs.Mercator().project_geometry(sgeom.MultiLineString(), ccrs.PlateCarree())
[]
>>> type(ccrs.Mercator().project_geometry(sgeom.MultiLineString(), ccrs.PlateCarree()))
<class 'list'>
>>> ccrs.Mercator().project_geometry(sgeom.MultiLineString([sgeom.LineString([[0, 88], [1, 88]])]), ccrs.PlateCarree())
[]
>>> type(ccrs.Mercator().project_geometry(sgeom.MultiLineString([sgeom.LineString([[0, 88], [1, 88]])]), ccrs.PlateCarree()))
<class 'list'>
```
