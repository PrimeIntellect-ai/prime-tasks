Undetectable Delimiter error for local files ending with a empty line, even if skipEmptyLines is true
By default excel adds a empty line at the end of exported csv files. If you try to parse these with the local file function and auto detect delimiter you'll end up with an "Undetectable Delimiter" error. Even if you enable skipEmptyLines you'll get the error.

It can be reproduced with the demo on your website and the attached file.
[Mappe1.zip](https://github.com/mholt/PapaParse/files/236626/Mappe1.zip)
