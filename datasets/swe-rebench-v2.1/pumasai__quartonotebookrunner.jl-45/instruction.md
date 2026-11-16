Copying and overriding ENV variables
Currently, the server process copies ENV variables from quarto, but the worker processes from Malt do not copy ENV variables from the server. So one currently has no option to set them, global env variables will not have an effect on the workers. So one cannot influence JULIA_LOAD_PATH, JULIA_DEPOT_PATH, etc. for the workers.

### Additional contract requirements

- Environment variables that are present in the server process must be visible to the Malt worker processes that execute notebook code.
- A notebook can set environment variables for its worker through the `julia` frontmatter key, using an `env` entry that is a list of `"KEY=VALUE"` strings, for example:

  ```
  ---
  julia:
      env: ["FOO=BAR"]
  ---
  ```

  Each listed variable must be present in the worker's environment when the notebook code runs.
- If a variable set in a notebook's `julia.env` is also present in the server environment, the notebook's value must be visible to notebook code.
