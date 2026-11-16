Add more Algorithms (min/max/mean/median.....)
ref https://github.com/sentinel-hub/titiler-openeo/blob/5452bd2d5026c761526d0ad0a715af28dbef352a/titiler/openeo/processes/implementations/math.py#L175-L202

### Additional contract requirements

Add `std` (standard deviation) and `var` (variance) algorithms that reduce input bands to a single per-pixel result and respect masked pixels.
