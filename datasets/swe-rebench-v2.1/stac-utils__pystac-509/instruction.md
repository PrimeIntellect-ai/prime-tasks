sat extension update
A colleague of mine discovered that the sat extension within pystac is not up-to-date with the current sat extension as specified here:
https://github.com/stac-extensions/sat#item-properties

The following items could be added:

Field Name | Type | Description
-- | -- | --
sat:platform_international_designator | string | The International Designator, also known as COSPAR ID, and NSSDCA ID
sat:absolute_orbit | integer | The obsolute orbit number at the time of acquisition.
sat:anx_datetime | string | The Ascending Node Crossing (ANX) time, in UTC. It is formatted according to RFC 3339, section 5.6.

So far we fill in the properties dictionary directly. Eventually we can contribute here in the next weeks.

### Additional contract requirements

- `pystac.extensions.sat.SatExtension.apply` accepts, in addition to the existing
  `orbit_state` and `relative_orbit` arguments, the optional keyword arguments
  `absolute_orbit: Optional[int]`, `platform_international_designator: Optional[str]`
  and `anx_datetime: Optional[datetime.datetime]`, and stores each supplied value on
  the extended object.
- `pystac.extensions.sat.SatExtension` exposes read/write properties
  `absolute_orbit: Optional[int]`, `platform_international_designator: Optional[str]`
  and `anx_datetime: Optional[datetime.datetime]`.
- `pystac.extensions.sat.SatExtension.summaries(obj: pystac.Collection)` returns a
  `pystac.extensions.sat.SummariesSatExtension` bound to the collection's summaries,
  exposing read/write properties:
  - `platform_international_designator: Optional[List[str]]`
  - `orbit_state: Optional[List[OrbitState]]`
  - `absolute_orbit: Optional[RangeSummary[int]]`
  - `relative_orbit: Optional[RangeSummary[int]]`
  - `anx_datetime: Optional[RangeSummary[datetime.datetime]]`
- `pystac.extensions.sat.ItemSatExtension.__repr__` returns the string
  `"<ItemSatExtension Item id={item.id}>"` for the wrapped item.
- `pystac.extensions.sat.AssetSatExtension.__repr__` returns the string
  `"<AssetSatExtension Asset href={asset.href}>"` for the wrapped asset.
