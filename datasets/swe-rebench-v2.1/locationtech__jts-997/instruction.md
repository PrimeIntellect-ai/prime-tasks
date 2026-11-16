VariableBuffer fails when vertex distance = 0
Does VariableBuffer support 0 buffer distance at one of the vertex? Here's what I found from NetTopologySuite  library, and I suspect that the same issue is presented on the JTS library also.

The code is in NTS, but it's trivial to convert it to Java.

The code below is working fine, even though it has a 0  buffer distance

```
using NetTopologySuite.Geometries;
using NetTopologySuite.Operation.Buffer;

namespace tryNetTopo
{
    internal class Program
    {
        static void Main(string[] args)
        {
            var polylineCoordinates = new Coordinate[]
              {
                    new Coordinate(2216883.9690149571, 5312555.8022460323),
                    new Coordinate(2216880.7776965303, 5312561.9943400519),
                    new Coordinate(2216874.5057125678, 5312574.1638290221),
                    new Coordinate(2216873.0320880935, 5312576.8179701111),
                    new Coordinate(2216872.0585015123, 5312578.3818236338),
                    new Coordinate(2216871.4142499096, 5312579.3486044565)
              };

            double[] arr = new double[polylineCoordinates.Length];
            for (int i = 0; i < arr.Length; i++)
            {
                arr[i] = 1;
            }

            arr[3] = 0;

            var line = new LineString(polylineCoordinates);

            var result = VariableBuffer.Buffer(line, arr);
        }
    }
}
```


BUT, the following code doesn't work, even though it just contains an extra coordinate, which shouldn't matter?

```
using NetTopologySuite.Geometries;
using NetTopologySuite.Operation.Buffer;

namespace tryNetTopo
{
    internal class Program
    {
        static void Main(string[] args)
        {
            var polylineCoordinates = new Coordinate[]
              {
                    new Coordinate(2216883.9690149571, 5312555.8022460323),
                    new Coordinate(2216880.7776965303, 5312561.9943400519),
                    new Coordinate(2216874.5057125678, 5312574.1638290221),
                    new Coordinate(2216873.0320880935, 5312576.8179701111),
                    new Coordinate(2216872.0585015123, 5312578.3818236338),
                    new Coordinate(2216871.4142499096, 5312579.3486044565),
                    new Coordinate(2216863.677298767 , 5312590.6634067535),         // adding this coordinate will cause the error
              };

            double[] arr = new double[polylineCoordinates.Length];
            for (int i = 0; i < arr.Length; i++)
            {
                arr[i] = 1;
            }

            arr[3] = 0;

            var line = new LineString(polylineCoordinates);

            var result = VariableBuffer.Buffer(line, arr);
        }
    }
}
```

### Additional contract requirements

- Provide a public static method `buffer(Geometry geom, double[] distances)` in the class `org.locationtech.jts.operation.buffer.VariableBuffer`. It computes the variable-width buffer of a single `LineString`, where `distances` contains one entry per vertex of the line.
- Zero distances are allowed. A cap at a vertex whose distance is zero collapses to that vertex, and a segment whose two endpoint distances are both zero contributes no polygon.
- If every distance is zero, the result is an empty `Polygon`.
- The method never returns `null`; an empty geometry represents a void buffer.
