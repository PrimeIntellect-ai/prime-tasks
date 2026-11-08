Editing the icon of a server fails
### Steps to reproduce

```py
await bot.rest.edit_guild(ctx.guild_id, icon="path on disk or url")
```


### Expected result

Server icon should have changed

### Actual result

```
Traceback (most recent call last):
  File "D:\Documents\Git Stuff\hikari-test-bot\.venv\Lib\site-packages\lightbulb\app.py", line 1162, in invoke_application_command
    await context.invoke()
  File "D:\Documents\Git Stuff\hikari-test-bot\.venv\Lib\site-packages\lightbulb\context\base.py", line 334, in invoke
    await self.command.invoke(self)
  File "D:\Documents\Git Stuff\hikari-test-bot\.venv\Lib\site-packages\lightbulb\commands\base.py", line 798, in invoke
    await self(context, **kwargs)
  File "D:\Documents\Git Stuff\hikari-test-bot\.venv\Lib\site-packages\lightbulb\commands\base.py", line 712, in __call__
    return await self.callback(context, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "D:\Documents\Git Stuff\hikari-test-bot\main.py", line 107, in show_level
    return await show_help(ctx)
           ^^^^^^^^^^^^^^^^^^^^
  File "D:\Documents\Git Stuff\hikari-test-bot\.venv\Lib\site-packages\lightbulb\commands\base.py", line 385, in __call__
    await self.callback(context)
  File "D:\Documents\Git Stuff\hikari-test-bot\main.py", line 88, in show_help
    await bot.rest.edit_guild(ctx.guild_id, icon="server_icon.png")
  File "D:\Documents\Git Stuff\hikari\hikari\impl\rest.py", line 2570, in edit_guild
    await asyncio.gather(*tasks)
  File "D:\Python\3.11.2\Lib\asyncio\events.py", line 80, in _run
    self._context.run(self._callback, *self._args)
  File "D:\Documents\Git Stuff\hikari\hikari\impl\rest.py", line 2549, in <lambda>
    task.add_done_callback(lambda future: body.put("icon", future.result()))
                                                           ^^^^^^^^^^^^^^^
  File "D:\Documents\Git Stuff\hikari\hikari\files.py", line 355, in data_uri
    return to_data_uri(await self.read(), self.mimetype)
                       ^^^^^^^^^^^^^^^^^
  File "D:\Documents\Git Stuff\hikari\hikari\files.py", line 360, in read
    async for chunk in self:
  File "D:\Documents\Git Stuff\hikari\hikari\files.py", line 818, in __aiter__
    chunk = await loop.run_in_executor(self._executor, self._pointer.read, _MAGIC)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "D:\Python\3.11.2\Lib\concurrent\futures\thread.py", line 58, in run
    result = self.fn(*self.args, **self.kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ValueError: read of closed file
```

### System info

```shell
hikari (2.0.0.dev119) [2d5d5fcf]
located at D:\Documents\Git Stuff\hikari\hikari
CPython 3.11.2 MSC v.1934 64 bit (AMD64)
Windows nullstation 10 10.0.19044 AMD64 AMD64 Family 23 Model 8 Stepping 2, AuthenticAMD
```


### Further info

_No response_

### Checklist

- [X] I have made sure to remove ANY sensitive information (bot token, passwords, credentials, personal details, etc.).
- [X] I have searched the issue tracker and have made sure it's not a duplicate. If it is a follow up of another issue, I have specified it.
