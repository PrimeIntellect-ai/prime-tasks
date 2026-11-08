Bug: File Menu Lint Updates Date Modified in All Cases
Linting a file updates the yaml modification date even though the file hasn't been modified.

**For example:**

File x has modified date in yaml: 2023-04-07T13:56:26+02:00, and on file system: 2023-04-27 17:44.

After linting, the yaml modified date is set to the current date time, rather than the actual last modified date, which was recorded by the file system as 2023-04-27 17:44.

So in this case I expected the yaml to be updated to the last modification date from the file system rather than the current time.

**Example 2:**

The yaml modified date and file system are the same — a date in the past. In this case the file shouldn't be touched.


---

This issue occured to me as I was just modifying a few files in a folder of many files and I linted the whole folder, expecting that only the files I had modified would be linted, but every single file got their yaml modification dates updated. So this means that all mod dates for these files are now incorrect.
