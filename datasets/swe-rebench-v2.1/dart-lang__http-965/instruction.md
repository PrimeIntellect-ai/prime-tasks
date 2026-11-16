StreamedRequest.sink should be a StreamSink
Right now `StreamedRequest.sink` is declared as an `EventSink<List<int>>`:

```dart
  /// The sink to which to write data that will be sent as the request body.
  ///
  /// This may be safely written to before the request is sent; the data will be
  /// buffered.
  ///
  /// Closing this signals the end of the request.
  EventSink<List<int>> get sink => _controller.sink;
```

However, the sink of a `StreamController` is a child class `StreamSink`, which has useful methods like `addStream`: https://api.dart.dev/stable/2.17.5/dart-async/StreamConsumer/addStream.html

Being able to add a stream using this method is essential if you need the stream to be paused when the send buffer is full, e.g. if you are reading from disk faster than you can send it over the network.

Here's a simple example showing how a StreamController is notified when the send buffer is full:

```dart
void main() async {
  final server = await HttpServer.bind('127.0.0.1', 8456);
  server.listen((event) {
    print('server got client');
    final sub = event.listen((event) {});
    // Pause it on the server end, Dart will no longer read from the socket
    // causing new data to be buffered by the OS
    sub.pause();
  });

  final request = StreamedRequest('post', Uri.parse('http://127.0.0.1:8456'));

  final controller = StreamController<List<int>>(
    onPause: () {
      print('paused');
    },
    onResume: () {
      print('resumed');
    },
  );

  Timer.periodic(
    const Duration(seconds: 1),
    (timer) {
      if (controller.isPaused) {
        print('not sending (paused)');
        return;
      }
      print('sending 512K');
      controller.add(Uint8List(512 * 1024));
    },
  );

  // Cast request.sink to a StreamSink so we can call addStream
  (request.sink as StreamSink<List<int>>).addStream(controller.stream);

  await request.send();
}
```

Outputs:

```dart
paused
resumed
sending 512K
paused
server got client
resumed
sending 512K
paused
resumed
sending 512K
paused
resumed
sending 512K
paused
resumed
sending 512K
paused
resumed
sending 512K
paused
not sending - paused
not sending - paused
not sending - paused
not sending - paused
not sending - paused
```

[HIDDEN]
[HIDDEN]
```

This would also allow us to get upload progress events without adding any callbacks to post / send:

```dart
final progress = ValueNotifier<int>(0);
request.sink.addStream(
  file.openRead().map((e) {
    progress.value += e.length;
    return e;
  }),
);
```

### Additional contract requirements

- `StreamedRequest.sink` must expose the `StreamSink<List<int>>` API so callers can use `addStream` directly, without a cast.
