Assembly top level location ignored

In focusing on the color fix of PR #1157, I may have overlooked the importance of this comment as no tests had failed:

https://github.com/CadQuery/cadquery/issues/1170#issuecomment-1268792075

There is a bug (regression) when a loc is specified at the top level.  The `test_step_export` does not catch the failure because the top level locations are either (0, 0, 0) or applied to a nested assy.

You can see that in the `simple_assy` fixture the top level loc is ignored when visualizing the assembly in cq-editor (because it calls `toCAF`).

Another way to reproduce the issue is to compare the origin of an assembly as exported to STL (`toCompound`) vs STEP (`toCAF`) when a top level loc is specified.  This points to an issue with `toCAF`.

The following example has no issue.  The compound and assembly visualized in cq-editor show the same origin.

```py
import cadquery as cq
from cadquery.occ_impl.shapes import *

# a table;  origin is bottom corner of table leg
w = 1200
l = 700
h = 800
t = 25

leg_w = 40
leg_l = 60

leg = box(leg_w, leg_l, h)
top = box(w, l, t)

assy = (
    cq.Assembly()
    .add(leg, name="leg0", loc=cq.Location((leg_w / 2, leg_l / 2, 0)))
    .add(leg, name="leg1", loc=cq.Location((w - leg_w / 2, leg_l / 2, 0)))
    .add(leg, name="leg2", loc=cq.Location((leg_w / 2, l - leg_l / 2, 0)))
    .add(leg, name="leg3", loc=cq.Location((w - leg_w / 2, l - leg_l / 2, 0)))
    .add(top, name="top", loc=cq.Location((w / 2, l / 2, h)))
)

comp = assy.toCompound()

show_object(comp, name="comp")
show_object(assy, name="assy")
```


Say I'd like to change the origin.  Here a location is applied at the top level.
The compound and assembly results are now different.  The result is not expected.

```py
import cadquery as cq
from cadquery.occ_impl.shapes import *

# a table;  origin is centered under table
w = 1200
l = 700
h = 800
t = 25

leg_w = 40
leg_l = 60

leg = box(leg_w, leg_l, h)
top = box(w, l, t)

assy = (
    cq.Assembly(
        loc=cq.Location((-w / 2, -l / 2, 0))
    )  # origin is centered under table top
    .add(leg, name="leg0", loc=cq.Location((leg_w / 2, leg_l / 2, 0)))
    .add(leg, name="leg1", loc=cq.Location((w - leg_w / 2, leg_l / 2, 0)))
    .add(leg, name="leg2", loc=cq.Location((leg_w / 2, l - leg_l / 2, 0)))
    .add(leg, name="leg3", loc=cq.Location((w - leg_w / 2, l - leg_l / 2, 0)))
    .add(top, name="top", loc=cq.Location((w / 2, l / 2, h)))
)

comp = assy.toCompound()

show_object(comp, name="comp")
show_object(assy, name="assy")
```
![image](https://github.com/CadQuery/cadquery/assets/16394272/00c01749-30aa-44d8-a7cc-7964a9385777)
