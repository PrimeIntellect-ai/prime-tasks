EnumDiscriminants should inherit the repr of the enum they are derived from
The below example code will generate `VehicleDiscriminants` enum with `Car` and `Truck` variants but it will be `repr(usize)` instead of inheriting the `u8` repr of `Vehicle` additionally they will have the default enum representations (`Car = 0` and `Vehicle = 1` in this case)

```
// Custom discriminant tests
#[derive(EnumDiscriminants, Debug, PartialEq)]
#[strum_discriminants(derive(FromRepr))]
#[repr(u8)]
enum Vehicle {
    Car(CarModel) = 1,
    Truck(TruckModel) = 3,
}
```

I would have expected the above code to produce the following:
```
#[repr(u8)]
#[derive(FromRepr)]
enum VehicleDiscriminants {
    Car = 1,
    Truck = 3,
}
```
