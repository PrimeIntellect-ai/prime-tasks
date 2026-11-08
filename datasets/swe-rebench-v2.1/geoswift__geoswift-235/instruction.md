Support for subtracting geometries from others?
There are usually 4 ways of combining different polygons, which have different names depending on who you ask. Here are some examples:

![image](https://user-images.githubusercontent.com/1865635/145707654-4c1f9b40-4f65-4574-8f04-2cc2e26b6f34.png)

![image](https://user-images.githubusercontent.com/1865635/145707660-c13cdb24-9c3c-4741-a41f-242ef58c772c.png)

![image](https://user-images.githubusercontent.com/1865635/145707673-82348ab0-70f5-4306-a2f4-f3cfb3b71eb1.png)

In GEOSwift, we have **Union**, **Intersection** and **Difference**. But as far as I know, we don't have **Subtract**.

Is there a particular reason that Subtract is missing, or if not, can it be added?

### Additional contract requirements

- Provide symmetric difference for `GeometryConvertible` operands through `GeometryConvertible.symmetricDifference(with:)`, with the signature `symmetricDifference(with: GeometryConvertible) throws -> Geometry?`.
- The result must retain portions belonging to exactly one input and exclude portions shared by both.
