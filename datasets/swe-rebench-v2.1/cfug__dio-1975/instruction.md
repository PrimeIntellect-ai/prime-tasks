Dio 5 interceptors.clear() break the app
### Package

dio

### Version

5.3.2

### Operating-System

Android

### Output of `flutter doctor -v`

```shell
flutter doctor --verbose
[!] Flutter (Channel stable, 3.13.2, on macOS 13.0.1 22A400 darwin-x64, locale en-VN)
    • Flutter version 3.13.2 on channel stable at /Users/xuantung/Desktop/Develop/flutter/3.13.2/flutter
    ! Warning: `flutter` on your path resolves to /Users/xuantung/Desktop/Develop/flutter/3.3.10/flutter/bin/flutter, which is not inside your current Flutter SDK checkout at /Users/xuantung/Desktop/Develop/flutter/3.13.2/flutter. Consider adding /Users/xuantung/Desktop/Develop/flutter/3.13.2/flutter/bin to the front of your path.
    ! Warning: `dart` on your path resolves to /Users/xuantung/Desktop/Develop/flutter/3.3.10/flutter/bin/dart, which is not inside your current Flutter SDK checkout at /Users/xuantung/Desktop/Develop/flutter/3.13.2/flutter. Consider adding /Users/xuantung/Desktop/Develop/flutter/3.13.2/flutter/bin to the front of your path.
    • Upstream repository https://github.com/flutter/flutter.git
    • Framework revision ff5b5b5fa6 (4 weeks ago), 2023-08-24 08:12:28 -0500
    • Engine revision b20183e040
    • Dart version 3.1.0
    • DevTools version 2.25.0
    • If those were intentional, you can disregard the above warnings; however it is recommended to use "git" directly to perform update checks and upgrades.

[!] Android toolchain - develop for Android devices (Android SDK version 33.0.2)
    • Android SDK at /Users/xuantung/Library/Android/sdk
    ✗ cmdline-tools component is missing
      Run `path/to/sdkmanager --install "cmdline-tools;latest"`
      See https://developer.android.com/studio/command-line for more details.
    ✗ Android license status unknown.
      Run `flutter doctor --android-licenses` to accept the SDK licenses.
      See https://flutter.dev/docs/get-started/install/macos#android-setup for more details.

[✓] Xcode - develop for iOS and macOS (Xcode 14.3.1)
    • Xcode at /Applications/Xcode.app/Contents/Developer
    • Build 14E300c
    • CocoaPods version 1.12.1

[✓] Chrome - develop for the web
    • Chrome at /Applications/Google Chrome.app/Contents/MacOS/Google Chrome

[✓] Android Studio (version 2022.3)
    • Android Studio at /Applications/Android Studio.app/Contents
    • Flutter plugin can be installed from:
      🔨 https://plugins.jetbrains.com/plugin/9212-flutter
    • Dart plugin can be installed from:
      🔨 https://plugins.jetbrains.com/plugin/6351-dart
    • Java version OpenJDK Runtime Environment (build 17.0.6+0-17.0.6b829.9-10027231)

[✓] VS Code (version 1.82.2)
    • VS Code at /Applications/Visual Studio Code.app/Contents
    • Flutter extension can be installed from:
      🔨 https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter

[✓] Connected device (3 available)
    • SM A235F (mobile) • R58W2095NQK • android-arm64  • Android 13 (API 33)
    • macOS (desktop)   • macos       • darwin-x64     • macOS 13.0.1 22A400 darwin-x64
    • Chrome (web)      • chrome      • web-javascript • Google Chrome 116.0.5845.187

[✓] Network resources
    • All expected network resources are available.

! Doctor found issues in 2 categories.
```


### Dart Version

_No response_

### Steps to Reproduce

My app stopped working after updating Dio from version 4 to 5.
After debugging, I found that `_dio.interceptors.clear();` make post request send empty data to the server.
The error occurs without any warning, It can break many apps, and the developer might not know where it went wrong until they send a post request.

```
  Dio _dio = Dio(
    BaseOptions(
      connectTimeout:  const Duration(seconds: AppConfigure.connectionTimeout),
      receiveTimeout:  const Duration(seconds: AppConfigure.receiveTimeout),
    ),
  );
  _dio.interceptors.clear();
  _dio.interceptors.addAll([
    LogInterceptor(requestBody: true, responseHeader: false, requestHeader: false, request: false, responseBody: true),
  ]);
  const _extra = <String, dynamic>{};
  final queryParameters = <String, dynamic>{};
  final _headers = <String, dynamic>{};
  final _data = <String, dynamic>{
  };
  _data.addAll({
    "test": "1"
  });
  final _result = await _dio
      .fetch<Map<String, dynamic>>(Options(
    method: 'POST',
    headers: _headers,
    extra: _extra,
  )
      .compose(
    _dio.options,
    '/data',
    queryParameters: queryParameters,
    data: _data,
  )
      .copyWith(
      baseUrl: "http://192.168.6.102:3000"));
```

### Expected Result

Working normally as version 4

### Actual Result

On server:
With `_dio.interceptors.clear();`: receive {}
No `_dio.interceptors.clear();`: receive {"test": "1"}
