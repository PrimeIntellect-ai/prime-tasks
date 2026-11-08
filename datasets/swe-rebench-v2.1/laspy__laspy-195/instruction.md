Update header working right?
Greetings,

python: 3.9.9
laspy: 2.1.1

I am editing some las files, filtering by classification and sampling. When I store/assign the PackedPointRecord filtered in a new lasdata and perform the header_update the method does not calculate the bounding box correctly I think:

```python
def filter_las(las_f: LasData, sampling: int, las_classes: Iterable) -> PackedPointRecord:
    filter_classes = np.isin(las_f.classification, las_classes)
    pts_f = las_f.points[filter_classes]
    return pts_f[::sampling]

las_f = laspy.read(Path(las_file_path))
new_las = laspy.create(point_format=las_f.header.point_format, file_version=las_f.header.version)
new_las.points = filter_las(las_f, 5, [1,2,3])
new_las.update_header() # the max values are updated but the min values remains 0 after this.

# original bounding box
print(f'X[{las.header.x_min}, {las.header.x_max}]')
print(f'Y[{las.header.y_min}, {las.header.y_max}]')
print(f'Z[{las.header.z_min}, {las.header.z_max}]')

# results:
X[635551.39, 635642.52]
Y[4295586.09, 4295727.16]
Z[392.45, 422.03]

# new bounding box
print(f'X[{new_las.header.x_min}, {new_las.header.x_max}]')
print(f'Y[{new_las.header.y_min}, {new_las.header.y_max}]')
print(f'Z[{new_las.header.z_min}, {new_las.header.z_max}]')

# results:
X[0.0, 635642.29]
Y[0.0, 4295719.87]
Z[0.0, 421.91]
```

I checked the code inside header.py and when it updates it keeps the self.min value if the self.min is lower then the new value, I don't understand.

```python
self.z_min = min(
            self.z_min,
            (points["Z"].min() * self.z_scale) + self.z_offset,
        )

```
Because is a new lasdata object, the bounding box is 0, so the min (X,Y,Z) values never get updated if the new values from the new pointrecord are higher then 0.

thank you.
