Time picker on Android shows outdated native dialog
When you use the [Time Picker](https://flatpickr.js.org/examples/#time-picker) example on docs with a Android device a dialog shows up which looks nothing like the date picker dialog. It even lets you select milliseconds and microseconds even though the `dateFormat` is `H:i`.

![image](https://user-images.githubusercontent.com/2737132/67004020-9fbf5300-f0df-11e9-9a97-ec94d01b14a5.png)

Looking a bit further into it I noticed that this behavior is caused by the `step="any"` attribute which gets automatically applied to the mobile input when the original input has not `step` attribute set.
Removing the attribute completely or setting ist to `0` shows the "regular" Android time picker.

![image](https://user-images.githubusercontent.com/2737132/67004168-f6c52800-f0df-11e9-8e24-98f0bb390719.png)

## Your Environment
* flatpickr version used: 4.6.3
* Browser name and version: Google Chrome 77.0
* OS and version: Android 7.1.1

### Additional contract requirements

When the original input has a `step` attribute, the generated mobile input must
preserve that same `step` value. When the original input has no `step` attribute,
the generated mobile input must not receive an automatically applied `step` value
(removing the attribute or setting it to `0` is acceptable).
