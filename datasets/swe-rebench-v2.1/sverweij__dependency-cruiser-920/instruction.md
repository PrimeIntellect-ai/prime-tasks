Issue: using `workspace:` to implement nohoist in a package.json while using pnpm throws an error
<!--- Provide a general summary of the issue in the Title above -->
If you are using pnpm to do workspace manage, you don't define your workspaces in package.json - `workspaces` property, instead, separately in a pnpm-workspaces.yaml file.

One of our packages had a leftover workspaces nohoist property from when we used to use yarn, like this:

```
 "workspaces": {
    "nohoist": [
      "vite",
      "rollup"
    ]
  },
 ```

 but doesn't specify any workspaces.

 When analyzed with `pnpm depcruise packages/package-name -T json -c > results.json

 it throws an error:

 ```
   ERROR: Extracting dependencies ran afoul of...

  pWorkspace.endsWith is not a function
... in packages/...
```

Removing the nohoist makes it work as expected.

### Expected Behavior

If the workspaces property of the package.json is an object with only a nohoist property, ignore it.

<!--- Tell us what you expect should happen -->

### Current Behavior
 ```
   ERROR: Extracting dependencies ran afoul of...

  pWorkspace.endsWith is not a function
... in packages/...
```

<!--- Tell what happens instead -->

### Possible Solution

If the workspaces property of the package.json is an object with only a nohoist property, ignore it in

<!--- Not obligatory, but suggestions how to fix the bug, or ideas what the reason for the bug is are welcome. -->

### Steps to Reproduce (for bugs)

<!--- Provide a link to a live example, or an unambiguous set of steps to -->
<!--- reproduce this bug. Include code to reproduce, if relevant -->

1.
2.
3.
4.

### Context

<!--- How has this issue affected you? What are you trying to accomplish? -->
<!--- Providing context helps us understand better, which will likely result in better, faster, stronger fixes -->

### Your Environment

<!--- Include as many relevant details about the environment you experienced the bug in -->

- Version used:
- Node version:
- Operating System and version:
- Link to your project:
