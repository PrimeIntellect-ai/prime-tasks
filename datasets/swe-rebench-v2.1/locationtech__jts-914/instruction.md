Incorrect orientation index
[HIDDEN] to ensure consistent behaviour with the description and left case i.e. an orientation index of -1 (right) when one point lies to the right of the line and the other lies on the line.

https://github.com/locationtech/jts/blob/25510f7efc78648c7c8962b47b942f3ee3804f8c/modules/core/src/main/java/org/locationtech/jts/geom/LineSegment.java#L162

A suggested fix has been submitted on the NTS repo:
https://github.com/NetTopologySuite/NetTopologySuite/pull/618
