Add TollCollection.name
The Mapbox Directions API has just introduced a [`toll_collection.name`](https://docs.mapbox.com/api/navigation/directions/#route-step-object) property to the response model, indicating the name of the toll booth or electronic toll collection gantry. We should add an optional `name` property to the `TollCollection` struct.

/ref mapbox/mapbox-java#1432
/cc @jill-cardamon @LukasPaczos
