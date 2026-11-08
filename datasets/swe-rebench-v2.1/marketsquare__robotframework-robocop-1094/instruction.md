Option to disable empty-variable rule for VAR and leave it for *** Variables *** section
Since new `VAR` syntax has by default the same settings as creating empty variables in `*** Variables ***` section, it is inconsistent with old `Create Dictionary` / `Create List` / `Set Variable` keywords that allowed creating empty variables with no need to use placeholders.

For example, this:
```robotframework
&{some_dict}    Create Dictionary  # no issues
```
with VAR and default for `empty-variable` rule is suggested to be refactored into this:
```robotframework
VAR    &{some_dict}    # now Robocop will complain
```

It seems inconsistent with previous way of creating empty variables inside of keywords. Maybe that suggestion is not necessarily bad but it would be nice-to-have feature to separate the setting for Variables section and for inline-created VARs.
