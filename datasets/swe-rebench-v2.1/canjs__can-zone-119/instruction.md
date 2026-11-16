The ended hook should only ever be called once
Currently it's possible for it to be called multiple times, such as when an error occurs within the initial "run" task.
