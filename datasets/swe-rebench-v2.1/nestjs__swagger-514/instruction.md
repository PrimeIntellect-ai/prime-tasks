Error on build using plugin
## I'm submitting a...
<pre><code>[ ] Regression
[X] Bug report
[ ] Feature request
[ ] Documentation issue or request
[ ] Support request
</code></pre>

## Current behavior

When use the plugin with nest (nest-cli.json):
```
{
  "sourceRoot": "src",
  "compilerOptions": {
    "plugins": ["@nestjs/swagger/plugin"]
  }
}
```
And try to run the build on project with command:
`nest build`

The following error happens:
"Error  Cannot read property 'kind' of undefined"

## Expected behavior

Build without the error of 'cannot read property kind of undefined'.

## Minimal reproduction of the problem with instructions

It happens on project NewSchool Backend: https://github.com/NewSchoolBR/newschool-backend

Please uses the branch 'develop' to reproduction.

Change the file nest-cli.json adding the plugin from:
```
{
  "collection": "@nestjs/schematics",
  "sourceRoot": "src",
  "compilerOptions": {
    "plugins": ["@nestjs/swagger/plugin"]
  }
}
```
To:
```
{
  "collection": "@nestjs/schematics",
  "sourceRoot": "src"
}
```

Install the npm packages of project running:
`npm i`

And then run:
`npm run build`

After it the error happens.

## What is the motivation / use case for changing the behavior?

The project cannot use the plugin.

## Environment
<pre><code>Nest version: 6.14.1

For Tooling issues:
- Node version: 12.13.0
- Platform: Linux

Others:
- Operating system version: Ubuntu 18.4
- IDE: VS Code
- Package Manager: NPM
</code></pre>
