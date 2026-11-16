timeout for specific request
Hi it will be better to provide an option for request to set timeout for waiting requests (i'm not talking about connection timeout). Manually, i can do that, but when I'm running Build Runner, I need to make this "modification" again.

for example, my `user_network_service.chopper.dart`
```
  @override
  Future<Response<UserModel>> profile() {
    final Uri $url = Uri.parse('/user/profile');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client
        .send<UserModel, UserModel>($request)
        .timeout(Duration(seconds: 5));
  }
  ```

### Additional contract requirements

- Expose a named `timeout` option on HTTP method annotations, accepting a `Duration` to set the waiting timeout for that request.
