Nullable enum warning for null value in example section
I receive warning when trying to use null value in example section for property with enum.

**To Reproduce**

1. Given this OpenAPI/AsyncAPI document:
[nullable_enum.yaml](https://github.com/stoplightio/spectral/files/5274847/nullable_enum.txt)

2. Run this CLI command:
> spectral lint -v nullable_enum.yaml

3. See error
> Found 82 rules (66 enabled)
> Linting nullable_enum.yaml
> OpenAPI 3.x detected
>
> nullable_enum.yaml
>  39:23  warning  typed-enum  Enum value `null` does not respect the specified type `string`.
> ✖ 1 problem (0 errors, 1 warning, 0 infos, 0 hints)
>

**Expected behavior**
No warnings produced

**Environment:**
 - Library version: 5.5.0
 - OS: Debian 9 (image node:14.11-slim from Docker Hub)

**Additional context**
FROM node:14.11-slim
RUN yarn global add @stoplight/spectral
ADD nullable_enum.yaml nullable_enum.yaml
RUN spectral lint -v nullable_enum.yaml
