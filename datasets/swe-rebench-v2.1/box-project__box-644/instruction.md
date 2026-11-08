Docker support with PHP 8
As latest version 3.16.0, Box is supposed to support both PHP 7.x and 8.x

But when you look inside [DockerFileGenerator](https://github.com/box-project/box/blob/3.16.0/src/DockerFileGenerator.php#L43-L49) no images are defined for PHP 8.0 and 8.1

Is it just forgotten ? `8.0-cli-alpine` and `8.1-cli-alpine` images are available on DockerHub

### Additional contract requirements

- A PHP 8.0 requirement must select the `8.0-cli-alpine` Docker base image.
- A PHP 8.1 requirement must select the `8.1-cli-alpine` Docker base image.


- - When the PHP constraint is `^5.3` and no Docker base image is suitable, the exception message must be exactly: `Could not find a suitable Docker base image for the PHP constraint(s) "^5.3". Images available: "8.1-cli-alpine", "8.0-cli-alpine", "7.4-cli-alpine", "7.3-cli-alpine", "7.2-cli-alpine", "7.1-cli-alpine", "7-cli-alpine"`.
