DHCP regression
[This commit](https://github.com/Azure/WALinuxAgent/commit/9bb5d40ad80177b49e397d871df2faded2d6e48d) added an exception when there is no interface found, resulting in the following logs:

```
'2018/04/23 02:55:05.255749 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 02:57:01.471314 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 02:58:57.619919 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 03:00:53.930831 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 03:02:50.577667 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 03:04:46.782791 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 03:06:42.903693 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 03:08:39.078856 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 03:10:35.215515 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n',
'2018/04/23 03:12:31.405739 ERROR Event: name=WALinuxAgent, op=UnhandledError, message=Traceback (most recent call last):\n'
```

As there is nothing to be done about this we should remove the exception.
