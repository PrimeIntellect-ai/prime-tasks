Tests are broken on Python 3.8
From what I saw, many tests break on Python 3.8 beta (118 as time of writing) because new `DeprecationWarning` are raised. One I spotted is _class 'websockets.protocol.WebSocketCommonProtocol'> should be instaniated by asyncio internals only, please avoid its creation from user code_ which is not reported on Python 3.7. This causes the assertions on how many warnings are logged to fail.

I tested on the current `master` branch.

Since Python 3.8 is still in beta, I don't think this is urgent. I should be able to help on that if you want.

Original report: https://bugzilla.redhat.com/show_bug.cgi?id=1718208
