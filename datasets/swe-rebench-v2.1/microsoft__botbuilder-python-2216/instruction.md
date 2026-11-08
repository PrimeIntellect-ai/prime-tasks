[Bug] on_turn_error: unhandled error: 'text'
### [Github issues](https://github.com/Microsoft/botbuilder-python) should be used for bugs and feature requests. Use [Stack Overflow](https://stackoverflow.com/questions/tagged/botframework) for general "how-to" questions.

## Version
latest

## Describe the bug
Using botbuilder-python and teams-ai SDK to build a Teams bot with AI response. When sideloading the bot in the M365 Copilot, on_turn_error will occur if trying to conversation with the bot.
Linked issue: https://github.com/microsoft/teams-ai/issues/2326

## To Reproduce
https://github.com/user-attachments/assets/f4192af5-4fc0-4c03-a8e7-ba79c19c14ff

```bash
[on_turn_error] unhandled error: 'text'
Traceback (most recent call last):
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\botbuilder\core\bot_adapter.py", line 174, in run_pipeline
    return await self._middleware.receive_activity_with_status(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\botbuilder\core\middleware_set.py", line 69, in receive_activity_with_status
    return await self.receive_activity_internal(context, callback)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\botbuilder\core\middleware_set.py", line 79, in receive_activity_internal
    return await callback(context)
           ^^^^^^^^^^^^^^^^^^^^^^^
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\teams\app.py", line 745, in on_turn
    await self._start_long_running_call(context, self._on_turn)
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\teams\app.py", line 903, in _start_long_running_call
    return await func(context)
           ^^^^^^^^^^^^^^^^^^^
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\teams\app.py", line 751, in _on_turn
    self._remove_mentions(context)
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\teams\app.py", line 786, in _remove_mentions
    context.activity.text = context.remove_recipient_mention(context.activity)
                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\botbuilder\core\turn_context.py", line 392, in remove_recipient_mention
    return TurnContext.remove_mention_text(activity, activity.recipient.id)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "c:\Users\frankqian\TeamsApps\test11\.venv\Lib\site-packages\botbuilder\core\turn_context.py", line 401, in remove_mention_text
    [HIDDEN]
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^
KeyError: 'text'
```
## Expected behavior
Give a clear and concise description of what you expected to happen.

## Screenshots
If applicable, add screenshots to help explain your problem.

## Additional context
Add any other context about the problem here.

### Additional contract requirements

- Processing a recipient-matching mention entity without a `text` property must not raise a `KeyError`.
- If there is no mention to remove, preserve the message text.
