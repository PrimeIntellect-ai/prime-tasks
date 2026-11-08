Make `WebService` and standalone class
Context: https://github.com/skiptests/astraea/pull/1197#discussion_r1037338472

* 讓 `WebService` 變成一個真正的 Class Object，以 object instance 的方式使用他，而非呼叫 static method
* 讓 `WebService` object 釋出自己 binding 的 port 編號
* 讓 `WebService` 可以透過指定 port = 0 來自己挑選 port

### Additional contract requirements

A `WebService` instance exposes the TCP port it bound through its public `int port()` method. When configured with port `0`, the selected bound port is available through this method.

A `WebService` is created with `new WebService(admin, port, brokerIdToJmxPort)`, where `admin` is an `Admin`, `port` is an `int`, and `brokerIdToJmxPort` is a `Function<Integer, Optional<Integer>>` that maps a broker id to that broker's optional JMX port. It implements `AutoCloseable`.

A `RecordHandler` can be created from an `Admin` alone with `new RecordHandler(admin)`; its default producer connects to the bootstrap servers reported by that admin.
