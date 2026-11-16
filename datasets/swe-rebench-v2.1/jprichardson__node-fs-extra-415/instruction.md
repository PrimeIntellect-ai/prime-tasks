fs.move doesn't return error on moving same nonexistent folder/file
#### Issue:
When i `fs.move()` using two paths that are the same and both are invalid(nonexistent) paths, the function does not return an error, which it should since you are trying to move a nonexistent path.

#### Setup:
This is being ran inside of an electron render, which means its being ran inside of a chrome wrapper. This issue persists through fs-extra 3.0

#### Example:
`fs.move("nonexistent/path","nonexistent/path", (err) => { console.log(err)})`
`// err returns null`

#### Usage:
I use this in my personal repo:
https://github.com/zosman1/The_Archiver/blob/c65ed9dfb7ae0855b1fcb8026204c8d6876a96af/app/index.js#L25
