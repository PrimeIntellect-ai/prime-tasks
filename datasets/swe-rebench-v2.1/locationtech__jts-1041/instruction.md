VariableBuffer result polygon has incorrect hole
### Description

I am encountering an issue with the Variable Buffer class. Specifically, I am working with an open LineString. Given that the LineString is open and does not intersect itself, the buffer operation should yield a simple polygon without any interior rings (holes). However, in the current implementation, the resulting polygon contains an unnecessary interior ring. This is causing a disruption in the order of the resulting polygon coordinates.

### Steps to Reproduce
Here's the .Net code to reproduce the issue:
```
public void Test()
        {
            var coordinates = new Coordinate[]
            {
                new Coordinate(200         ,   91.37371939),
                new Coordinate(199.9906516 ,   71.396149),
                new Coordinate(199.925198  ,   66.39682954),
                new Coordinate(135.4977781 ,   0.125906357),
                new Coordinate(56.41194182 ,   0.598175835),
                new Coordinate(0.024520295 ,   69.50077743),
                new Coordinate(0.000508719 ,   74.50086084),
                new Coordinate(6.22E-22    ,   76.39546845),
            };
            double[] widths = new double[]
            {
                5.4573551091373282,
                5.5548897583660466,
                5.5793006151088935,
                6.0919286067086738,
                6.4781230068945561,
                6.96634014175149,
                6.9907509984943372,
                7,
            };

            var innerLine = new LineString(coordinates);

            var variableBuffer = new VariableBuffer(innerLine, widths);
            var completeBuffer = variableBuffer.GetResult();

        }
```

This is a plot of the inner line coordinates.
![image](https://github.com/locationtech/jts/assets/97237245/8e03f5d1-3052-48f2-91ea-9ec544f951db)
