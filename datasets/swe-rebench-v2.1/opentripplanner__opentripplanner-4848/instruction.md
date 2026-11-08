Scooter rental leg is errouneously returned as bike rental
#4809 has surfaced a problem in the rental code.

The visible sympton is that scooter legs, which are internally treated the same as bicycle legs, are not correctly returned with the mode SCOOTER.

This is because all the scooter modes have the traverse mode BICYCLE as the SCOOTER traverse mode cannot traverse a regular `StreetEdge`

### References

https://github.com/opentripplanner/OpenTripPlanner/pull/4809/files#diff-6dfc9e97787bac2c99bfa7377e0265cc640a59df6066cea35599be4500d1ed9fL260-R261

https://github.com/opentripplanner/OpenTripPlanner/blob/f830edbeb602d0085a9bd7eb97d9e75cd1d0cdc5/src/main/java/org/opentripplanner/routing/vehicle_rental/RentalVehicleType.java#L81
