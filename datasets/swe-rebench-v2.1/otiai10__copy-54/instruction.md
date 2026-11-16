opt.Untouchable + opt.PreserveTimes error copying subdirectory
This is very minor issue. But interesting.

Here is error log from my code, which I provide for clarity:

`Final: main.go#DoitRunApps(): error App.RunApp(), error =
 AppLogicCustomStartAsOfDt.RunApp(): (15) Normal Daily Run utility.go#Otiai10CopyMerge() error, in=data, out=bkp/d20210305, error =
 chtimes bkp/d20210305/downloads: no such file or directory
`

I decided to use OnDirExists.Untouchable for first test of certain logic in my code, as opposed to
Merge. Also using opt.PreserveTimes = true. Copying directory data=/ which contains data/downloads, data/in and data/out. Destination is bkp/d20210305 where subdirectory
d20210305 must be created as part of the copy -- which it was. The error occurred in
subdirectory downloads/ which was not created.

[HIDDEN]

Thus, the apparent logical difficulty: if directory does not exist then why preserve times?

I will workaround by simply not using PreserveTimes=true in this instance. I suppose
just adding a documentation note about the incompatiblity of these options would
suffice. Or, perhaps, add a line of code or two.

### Additional contract requirements

The incompatibility between `OnDirExists` returning `Untouchable` and
`PreserveTimes` being `true` must be resolved behaviorally, not merely
documented. When copying a source directory into a destination where
`OnDirExists` returns `Untouchable` and `PreserveTimes` is `true`:

- A destination subdirectory that does not exist yet must still be created and
  its contents copied (it was never touched, so it is not "untouchable").
- A destination subdirectory that already exists must be left untouched.
- `Copy` must not return an error in this situation.
