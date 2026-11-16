Store clone costs too much CPU
![photo_2020-12-21_16-07-05](https://user-images.githubusercontent.com/12077877/102844121-b7157100-4445-11eb-93d5-01b9c1fbc1bc.jpg)

This is an example that a cluster enables a scatter-range-scheduler. We need to estimate store clone is these cases.

### Additional contract requirements

- `StoreInfo.Clone` must return an independent deep copy of the store's metadata: mutating the clone's metadata, including its label slice, must not change the original `StoreInfo`.
- `StoreInfo.Clone` must be cheap. The previous implementation performed a full reflective deep copy of the metadata and allocated about 39 objects per call; the fixed implementation must allocate fewer than 20 objects per `Clone` call.
