Can no longer just run `sushi`
We used to be able to do `sushi` to run SUSHI on the current working directory, but now we have to do `sushi .`. I don't think there is a good reason why we can't just assume `.` when there is no input directory, so we should bring back `sushi` with no dot as an allowed command.
