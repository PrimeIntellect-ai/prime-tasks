Scaling issue when moving from pylas to laspy2
Using the same example as my previous issue when we were porting from pylas to laspy2, I am seeing a change in behavior in how scaling is happening.

Our min and max values are usually on the order of +/- 2 meters and our resolutions is usually around 1mm (though sometimes a bit better than that). So, when using pylas, we had set the scale in the header to 0.0001, so that we had one order of magnitude more resolution in the LAS file than our best possible accuracy.

This worked great in pylas, but with laspy2, it seems to be scaling the points when they are assigned in the wrong direction.

On pylas, if I executed the following code on a typical dataframe:
```
 las.header.x_scale = 0.0001
    las.header.y_scale = 0.0001
    las.header.z_scale = 0.0001

    las.x = colorizedPCL[:,0]
    las.y = colorizedPCL[:,1]
    las.z = colorizedPCL[:,2]
```

then lasinfo would give

```
scale factor x y z:         0.0001 0.0001 0.0001
  offset x y z:               0 0 0
  min x y z:                  -0.0412 -0.4811 0.0818
  max x y z:                  2.9329 1.2274 1.7042
```

With laspy2, the lasinfo output of the generated file is

```
scale factor x y z:         0.0001 0.0001 0.0001
  offset x y z:               0 0 0
  min x y z:                  -0.0051 -0.0050 -0.0005
  max x y z:                  0.0209 0.0144 0.0212
```

It seems like there is a spurious scaling of the data by laspy with a scale factor of 100. Just to check my sanity and make sure I wasn't feeding it bad data, I did add some debug code just assigning to las.x, las.y, las.z to see the actual min/max of my data and it was
```
xmin:-0.5099982241278208 xmax:2.0899958628936233 ymin:-0.499999825182655 ymax:1.4399942241674726 zmin:-0.05 zmax:255.0
```

It altogether may be the case, like in the last issue,  that  I am incorrectly using pylas and am not thinking about scaling correctly. My understanding was that the min/max of the actual data should always be whatever you set the data to be and that the scaling simply indicates how much the data is scaled by before writing to file because the LAS format uses integers to store the data.
