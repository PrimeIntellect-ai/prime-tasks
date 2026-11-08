Multiple version including VERSION_NEUTRAL return 404
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current behavior

when I use version as array with `VERSION_NEUTRAL` the request without version responses 404

### Minimum reproduction code

https://github.com/MarcosRava/nest-js-multiple-version-with-neutral

### Steps to reproduce

1. `yarn install`
2.  `yarn test:e2e`

See the error on the console

### Expected behavior

Expect 200 as response status

### Package

- [ ] I don't know. Or some 3rd-party package
- [ ] <code>@nestjs/common</code>
- [X] <code>@nestjs/core</code>
- [ ] <code>@nestjs/microservices</code>
- [ ] <code>@nestjs/platform-express</code>
- [ ] <code>@nestjs/platform-fastify</code>
- [ ] <code>@nestjs/platform-socket.io</code>
- [ ] <code>@nestjs/platform-ws</code>
- [ ] <code>@nestjs/testing</code>
- [ ] <code>@nestjs/websockets</code>
- [ ] Other (see below)

### Other package

_No response_

### NestJS version

8.4.5

### Packages versions

```json
{
  "name": "nest-js-multiple-version-with-neutral",
  "version": "0.0.1",
  "description": "",
  "author": "",
  "private": true,
  "license": "UNLICENSED",
  "scripts": {
    "prebuild": "rimraf dist",
    "build": "nest build",
    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\"",
    "start": "nest start",
    "start:dev": "nest start --watch",
    "start:debug": "nest start --debug --watch",
    "start:prod": "node dist/main",
    "lint": "eslint \"{src,apps,libs,test}/**/*.ts\" --fix",
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:debug": "node --inspect-brk -r tsconfig-paths/register -r ts-node/register node_modules/.bin/jest --runInBand",
    "test:e2e": "jest --config ./test/jest-e2e.json"
  },
  "dependencies": {
    "@nestjs/common": "^8.0.0",
    "@nestjs/core": "^8.0.0",
    "@nestjs/platform-express": "^8.0.0",
    "reflect-metadata": "^0.1.13",
    "rimraf": "^3.0.2",
    "rxjs": "^7.2.0",
    "semver": "^7.3.7"
  },
  "devDependencies": {
    "@nestjs/cli": "^8.0.0",
    "@nestjs/schematics": "^8.0.0",
    "@nestjs/testing": "^8.0.0",
    "@types/express": "^4.17.13",
    "@types/jest": "27.5.0",
    "@types/node": "^16.0.0",
    "@types/supertest": "^2.0.11",
    "@typescript-eslint/eslint-plugin": "^5.0.0",
    "@typescript-eslint/parser": "^5.0.0",
    "eslint": "^8.0.1",
    "eslint-config-prettier": "^8.3.0",
    "eslint-plugin-prettier": "^4.0.0",
    "jest": "28.0.3",
    "prettier": "^2.3.2",
    "source-map-support": "^0.5.20",
    "supertest": "^6.1.3",
    "ts-jest": "28.0.1",
    "ts-loader": "^9.2.3",
    "ts-node": "^10.0.0",
    "tsconfig-paths": "4.0.0",
    "typescript": "^4.3.5"
  },
  "jest": {
    "moduleFileExtensions": [
      "js",
      "json",
      "ts"
    ],
    "rootDir": "src",
    "testRegex": ".*\\.spec\\.ts$",
    "transform": {
      "^.+\\.(t|j)s$": "ts-jest"
    },
    "collectCoverageFrom": [
      "**/*.(t|j)s"
    ],
    "coverageDirectory": "../coverage",
    "testEnvironment": "node"
  }
}

```


### Node.js version

v16.13.1

### In which operating systems have you tested?

- [X] macOS
- [ ] Windows
- [ ] Linux

### Other

_No response_
