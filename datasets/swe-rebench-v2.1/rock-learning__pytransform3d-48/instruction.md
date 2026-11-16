Angle between similar Quaternions sometimes nan

Ran into a weird issue of dot product of checked/normalized quaternions becoming >1. Didn't have time to look deeper into it, maybe after the weekend.
```python
import pytransform3d.rotations as pr

a = ((0.9689124217106448 , 0.24740395925452294 , 0.0 , 0.0))
b = ((0.9689124217106448 , 0.247403959254523 , 0.0 , 0.0))
a = pr.check_quaternion(a)
b = pr.check_quaternion(b)

print("dot:" , np.dot(a,b))
print("divisor:", np.linalg.norm(a)*np.linalg.norm(a))
print("angle between quaternions:", pr.angle_between_vectors(a,b))
```

>dot: 1.0000000000000002
>divisor: 1.0
>angle between quaternions: nan
