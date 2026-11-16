Topology broken for wedges
Forgot to update topology. We also do not have test coverage on this. Problem is that `face_npoints` is not dispatched (and will require adaption to the new interface. Maybe something like [HIDDEN] is sufficient for all cells.

### Additional contract requirements

- Topology must correctly recognize neighboring wedge cells that share a local face, including triangular and quadrilateral faces.
