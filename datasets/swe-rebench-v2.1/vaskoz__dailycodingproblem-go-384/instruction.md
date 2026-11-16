Day 185
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Given two rectangles on a 2D graph, return the area of their intersection. If the rectangles don't intersect, return 0.

For example, given the following rectangles:
```
{
    "top_left": (1, 4),
    "dimensions": (3, 3) # width, height
}
```
and
```
{
    "top_left": (0, 5),
    "dimensions" (4, 3) # width, height
}
```
return 6.

### Additional contract requirements

- The solution is provided in the Go package `day185` as a type `Rectangle` and a function `AreaOfIntersection(r1, r2 Rectangle) int` that returns the area of the intersection of the two rectangles, or 0 when they do not intersect.
- `Rectangle` is a struct whose fields, in order, are the top-left x coordinate, the top-left y coordinate, the width and the height, all of type `int`. This matches the order used in the example above, so `Rectangle{1, 4, 3, 3}` denotes the first rectangle of the example.
- For the example above, `AreaOfIntersection` returns 6.
