[Proposal] Improve toString() of InterceptorState
### Request Statement

When Firebase Crashlytics gets an error report from code within a request interceptor,
the information from the log is very limited.

For example:

```
// Crashlytics report header
DioMixin.request
io.flutter.plugins.firebase.crashlytics.FlutterError - Instance of 'InterceptorState<DioException>'

// Raw stacktrace
      Fatal Exception: io.flutter.plugins.firebase.crashlytics.FlutterError: Instance of 'InterceptorState<DioException>'
       at DioMixin.request(dio_mixin.dart:350)
       at DioMixin.get(dio_mixin.dart:64)
       at HttpChatRepository.getChatMessages(http_chat_repository.dart:12)
       at ChatNotifier.fetchMessages(chat_notifier.dart:38)
       at PollingManager._queue(polling_manager.dart:19)
       at PollingManager.startPolling.<fn>(polling_manager.dart:32)
```

### Solution Brainstorm

Instead of having `InterceptorState<T>` use the default toString() implementation,
which is `Instance of 'InterceptorState<DioException>'`,
provide the error details of the underlying DioException in the toString() implementation,
[HIDDEN]
and providing the details of the DioException in the toString() implementation.

### Additional contract requirements

When an `InterceptorState` contains a `DioException`, its string representation must include useful details of that exception, so that the error information is visible instead of only the default instance description. The representation need not use a particular wrapper or formatting.
