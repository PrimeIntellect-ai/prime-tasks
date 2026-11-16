Add VEHICLE_FINDER service
Hi:
Many thanks for your project!

I have missed in your project the VEHICLE_FINDER service, that forces the vehicle to update its gps position on the BMW servers. At least in my vehicle (2015 F31), if you don't force the vehicle finder in the BMW app, this data is not updated automatically and the last location you requested remains.

The ideal would be to create a service that from time to time (could be 1, 2, 3 ... hours) runs the VEHICLE_FINDER service so that the location of the vehicle is always updated.

I have tried to make a simple modification in your code to test by CLI if it works, and yes, it works.

Thank you!

### Additional contract requirements

- Expose `RemoteServices.trigger_remote_vehicle_finder()` as a callable operation. Calling it must invoke the VEHICLE_FINDER service to request a fresh vehicle GPS position from BMW.
