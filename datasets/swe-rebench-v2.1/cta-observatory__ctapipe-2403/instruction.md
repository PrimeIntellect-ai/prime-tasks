h_max is inconsistent between HillasIntersection and HillasReconstructor
Both HillasReconstructor and HillasIntersection calculate a quantity h_max and return it in the ReconstructedGeometryContainer, but they are inconistent in the physical meaning of h_max: For HillasIntersection, it is the vertical height of the shower maximum above the array, for HillasReconstructor it is the distance of the shower maximum location from the array center, i.e. kind of a "slant height"

Whatever h_max really should be, it should of course be the same everywhere.

### Additional contract requirements

The `h_max` value stored in the `ReconstructedGeometryContainer` by either reconstruction algorithm is the vertical height of the shower maximum above sea level, including the observatory elevation. The two algorithms may produce different estimates for an event, but their returned heights must refer to this same physical quantity.
