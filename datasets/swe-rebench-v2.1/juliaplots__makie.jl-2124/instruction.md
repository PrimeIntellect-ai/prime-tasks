broken edge case: plotting an empty list of polygons
When trying to develop a  Makie plot recipe I found that currently (Makie v0.15.3) `poly!(ax, Vector{Point2f}[])` throws `ERROR: MethodError: no method matching to_vertices(::Vector{Any})`.
