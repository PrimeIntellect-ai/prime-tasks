Introduce includePathRegex
The opposite to `excludePathRegex` but a combination should be possible (exclude winning over include).

Usecase: Only build certain modules that contain OpenAPI files in case they changed, to deploy those changes as artifacts for the frontend team to integrate.
