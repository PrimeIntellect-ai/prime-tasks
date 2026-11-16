feat: Allow routing parameters in `middleware`
**Description**
Currently is not possible to access routing parameters on middlewares. Would be nice in cases where we have nested routing parameters and have different logic dependent on that parameter (e.g. `/[userId]/tasks/[taskId]`, middleware on `/[userId]/_middleware.dart` that checks if we have permissions for that `[userId`) .

My current workaround relies on private implementations 😕:

**Middleware `/[test]/_middleware.dart`:**
```dart
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog/src/_internal.dart' show toShelfHandler;

Handler middleware(Handler handler /* String test */) { // `String test` does not work
  return fromShelfHandler((request) async {
    print((request.context['shelf_router/params'] as Map<String, String>?)?['test']);
    return toShelfHandler(handler)(request);
  });
}
```

**Index `/[test]/index.dart`:**
```dart
Future<Response> onRequest(RequestContext context, String test) async {
  return Response(body: '$test');
}
```

### Additional contract requirements

- Add a public getter `Request.params` on the `Request` class exported by `package:dart_frog/dart_frog.dart`. It returns a `Map<String, String>` containing the URL parameters captured by the router for the current request, and an empty map when no parameters are captured.
- Middleware can read the routing parameters for the current request through `RequestContext.request.params`.
