`buffer::Service` should probably erase the inner service type
Currently, `tower::buffer::Service` is parameterized over the type of the inner `Service` inside the buffer worker. However, the `Service` struct does not actually need to know the type of the inner service, only the types of the inner service's `Future` and `Error` associated types.

In many cases, the `Service` type will likely be a significantly longer type than the `Future` and `Error` types --- when the service is composed of a number of chained middleware services, its type may be quite complex. Although futures will also often be composed of many nested future types, these will generally not be quite as large as `Service` types, for a few reasons:
-  Some middleware `Service`s may not wrap the inner service's future, and simply perform logic in `call` and/or `poll_ready`. These `Service`s will be generic over the inner `Service` type, but will not wrap the `Future` type
- Some middleware may return boxed futures, erasing the inner `Future` type while still being generic over the inner `Service` type

Therefore, we may wish to consider changing the definition of the `buffer::Service` type to be generic over only the `Future` and `Error` types of the inner service. This could reduce type complexity that may impact compilation time (as well as binary size, if type names are ever displayed in the program). Of course, because this changes the type signature of `buffer::Worker`, this will have to wait until the next breaking change.

cc @olix0r, who initially suggested this.
