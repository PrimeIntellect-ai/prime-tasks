Having only one submission type shows all submission types
## Current Behavior
If an event only uses one submission type, the submission form shows submission types for ALL events


## Expected Behavior
Only submission types for the current conference should populate the dropdown.
Added bonus: if only one, the field should be read-only/text.

## Steps to Reproduce

1. https://pretalx.com/orga/event/[YOUREVENT]/cfp/types/
2. Enter only one type
3. Navigate to https://pretalx.com/[YOUREVENT]/submit/
4. Click the dropdown for "Submission type"

<img width="801" alt="Screen Shot 2019-03-30 at 5 35 39 pm" src="https://user-images.githubusercontent.com/813732/55272568-53aeeb80-5312-11e9-8de9-e101aa53034f.png">


### Work around

Enter more than one submission type.

## Your Environment

Pretalx hosted environment

### Additional contract requirements

- The submission form is provided by a public class `InfoForm` in the module `pretalx.submission.forms`. It is constructed as `InfoForm(event, **kwargs)`, where `event` is an Event instance and `kwargs` are standard Django form keyword arguments such as `data`, `files`, and `initial`. The form honours these arguments as a standard Django form does.
- `InfoForm` exposes a field named `submission_type`. Its queryset contains only the submission types that belong to the given event.
- When the event has exactly one submission type, the `submission_type` field's `initial` value is that submission type and its widget is a `django.forms.HiddenInput`.
- When the event has more than one submission type, the `submission_type` field keeps a normal select widget and its queryset contains all of the event's submission types.
