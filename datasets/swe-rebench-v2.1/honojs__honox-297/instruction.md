Middleware not running
### What version of HonoX are you using?

0.1.40

### What steps can reproduce the bug?

Create a directory called `admin`. In that directory create a file called `_middleware.ts`, create a new directory in the admin directory called `dashboard`, place an `index.tsx` file in that directory.

if you now go to the `/admin/dashboard` route the middleware will not be ran. If you place a file in the `admin` directory the middleware will run.

will NOT RUN the middleware
```
admin/
├── _middleware.ts
├── dashboard/
│   └── index.tsx
```

will RUN the middleware
```
admin/
├── _middleware.ts
├── anotherFile.tsx
├── dashboard/
│   └── index.tsx
```

the other file can be any .tsx/.ts file

### What is the expected behavior?

that the middleware should run, not depending if there are other files in the directory or not.

### What do you see instead?

the middleware is not being run on that route/child-routes when empty in an folder

### Additional information

_No response_
