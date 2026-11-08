Authenticator corrupts request body
## Steps to Reproduce
When I added an authenticator for `ChopperClient`, my POST request started giving an HTTP code 400.

Just add an authenticator for the client.

```dart
ServerApi.create(
  client: ChopperClient(
    baseUrl: Environment().config.baseUrl,
    authenticator: MyAuthenticator(localDataSource), // here
    errorConverter: const ServerErrorConverter(),
    converter: JsonSerializableConverter(),
    interceptors: [
      ChopperLoggingInterceptor(),
      ChopperCurlInterceptor(),
    ],
  ),
);

class MyAuthenticator extends Authenticator {
  final LocalDataSource localDataSource;

  MyAuthenticator(this.localDataSource);

  @override
  FutureOr<Request?> authenticate(
    Request request,
    Response response, [
    Request? originalRequest,
  ]) async {
    if (response.statusCode == 401) {
      final authModel = await localDataSource.getAuthModelFromCache();
      String newToken = authModel.token;

      final Map<String, String> updatedHeaders =
          Map<String, String>.of(request.headers);

      newToken = 'Bearer $newToken';
      updatedHeaders.update(
        'Authorization',
        (String _) => newToken,
        ifAbsent: () => newToken,
      );
      return request.copyWith(
        headers: updatedHeaders,
      );
    }
    return null;
  }
}
```

I'm debugged `ChopperClient`'s code and here after [HIDDEN] body converts to string.

<img width="745" alt="Screenshot 2022-12-07 at 13 27 59" src="https://user-images.githubusercontent.com/93736963/206167742-46cebf60-81a0-4f21-bbf3-6ce52d9a608c.png">

**Expected results:** <!-- what did you want to see? -->
The request should save the body type after `request.copyWith`.

**Actual results:** <!-- what did you see? -->
The authenticator converts the body to string.

```
[Global Loggy] 👻 13:35:37.198690 INFO - --> POST https://xxx/api/administration/add-admin
[Global Loggy] 👻 13:35:37.198868 INFO - content-type: application/json; charset=utf-8
[Global Loggy] 👻 13:35:37.199273 INFO - {"email":"asdf@asdf.asdf"}
[Global Loggy] 👻 13:35:37.199460 INFO - --> END POST (26-byte body)

[Global Loggy] 👻 13:35:39.315634 INFO - --> POST https://xxx/api/administration/add-admin
[Global Loggy] 👻 13:35:39.316050 INFO - content-type: application/json; charset=utf-8
[Global Loggy] 👻 13:35:39.316252 INFO - Authorization: xxxx
[Global Loggy] 👻 13:35:39.316526 INFO - "{\"email\":\"asdf@asdf.asdf\"}"
[Global Loggy] 👻 13:35:39.316773 INFO - --> END POST (32-byte body)
```

<details>
<summary>Code sample</summary>

<!--
      Please create a minimal reproducible sample that shows the problem
      and attach it below between the lines with the backticks.

      To create it you can use `dart create bug` command and update the `main.dart` file.

      Alternatively, you can use https://dartpad.dev/
      which is capable of creating and running small Dart apps.

      Without this we will unlikely be able to progress on the issue, and because of that
      we regretfully will have to close it.
-->

```dart
ServerApi.create(
  client: ChopperClient(
    baseUrl: Environment().config.baseUrl,
    authenticator: MyAuthenticator(localDataSource), // here
    errorConverter: const ServerErrorConverter(),
    converter: JsonSerializableConverter(),
    interceptors: [
      ChopperLoggingInterceptor(),
      ChopperCurlInterceptor(),
    ],
  ),
);

class MyAuthenticator extends Authenticator {
  final LocalDataSource localDataSource;

  MyAuthenticator(this.localDataSource);

  @override
  FutureOr<Request?> authenticate(
    Request request,
    Response response, [
    Request? originalRequest,
  ]) async {
    if (response.statusCode == 401) {
      final authModel = await localDataSource.getAuthModelFromCache();
      String newToken = authModel.token;

      final Map<String, String> updatedHeaders =
          Map<String, String>.of(request.headers);

      newToken = 'Bearer $newToken';
      updatedHeaders.update(
        'Authorization',
        (String _) => newToken,
        ifAbsent: () => newToken,
      );
      return request.copyWith(
        headers: updatedHeaders,
      );
    }
    return null;
  }
}
```

</details>

<details>
  <summary>Logs</summary>

<!--
      Run your application with `dart run main.dart --verbose` and attach all the
      log output below between the lines with the backticks. If there is an
      exception, please see if the error message includes enough information
      to explain how to solve the issue.
-->

```
[Global Loggy] 👻 13:35:37.198690 INFO - --> POST https://xxx/api/administration/add-admin
[Global Loggy] 👻 13:35:37.198868 INFO - content-type: application/json; charset=utf-8
[Global Loggy] 👻 13:35:37.199273 INFO - {"email":"asdf@asdf.asdf"}
[Global Loggy] 👻 13:35:37.199460 INFO - --> END POST (26-byte body)

[Global Loggy] 👻 13:35:39.315634 INFO - --> POST https://xxx/api/administration/add-admin
[Global Loggy] 👻 13:35:39.316050 INFO - content-type: application/json; charset=utf-8
[Global Loggy] 👻 13:35:39.316252 INFO - Authorization: xxxx
[Global Loggy] 👻 13:35:39.316526 INFO - "{\"email\":\"asdf@asdf.asdf\"}"
[Global Loggy] 👻 13:35:39.316773 INFO - --> END POST (32-byte body)
```

<!--
     Run `dart analyze` and attach any output of that command below.
     If there are any analysis errors, try resolving them before filing this issue.
-->

<!-- Finally, paste the output of running `dart --version` here. -->

```
Dart SDK version: 2.18.2 (stable) (Tue Sep 27 13:24:11 2022 +0200) on "macos_arm64"
```

</details>

### Additional contract requirements

- When an authenticator changes a request and that request is retried, preserve its JSON body. A JSON payload already serialized for the original request must not be serialized again into a JSON string on retry.
