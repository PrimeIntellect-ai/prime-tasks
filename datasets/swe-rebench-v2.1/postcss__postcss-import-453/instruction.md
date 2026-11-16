Module build failure after upgrade from 12.0.1 to 14.0.0
Hello,

After updating my Angular app from 10 to 11 recently, I am encountering build errors from postcss-import after the package is upgraded to `14.0.0`.

Downgrading the package manually to `12.0.1`, which was the previously installed version by Angular, fixes the problem.
Not sure if this is a screw up on my behalf from the Angular migration or not, if so, apologies for spamming your issue tracker.

```
Error: ./src/styles.css
Module build failed (from ./node_modules/mini-css-extract-plugin/dist/loader.js):
ModuleBuildError: Module build failed (from ./node_modules/postcss-loader/dist/cjs.js):
TypeError: Cannot read property '0' of undefined
    at /home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/@angular-devkit/build-angular/node_modules/postcss-import/index.js:78:37
    at Array.forEach (<anonymous>)
    at applyMedia (/home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/@angular-devkit/build-angular/node_modules/postcss-import/index.js:70:16)
    at /home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/@angular-devkit/build-angular/node_modules/postcss-import/index.js:51:9
    at async LazyResult.runAsync (/home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/@angular-devkit/build-angular/node_modules/postcss/lib/lazy-result.js:358:11)
    at async Object.loader (/home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/postcss-loader/dist/index.js:95:14)
    at /home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/webpack/lib/NormalModule.js:316:20
    at /home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/loader-runner/lib/LoaderRunner.js:367:11
    at /home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/loader-runner/lib/LoaderRunner.js:233:18
    at context.callback (/home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/loader-runner/lib/LoaderRunner.js:111:13)
    at Object.loader (/home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/postcss-loader/dist/index.js:104:7)
 @ multi ./node_modules/@clr/icons/clr-icons.min.css ./node_modules/@clr/ui/clr-ui.min.css ./src/styles.css styles[2]

Error: ./src/styles.css (./node_modules/css-loader/dist/cjs.js??ref--13-1!./node_modules/postcss-loader/dist/cjs.js??ref--13-2!./src/styles.css)
Module build failed (from ./node_modules/postcss-loader/dist/cjs.js):
TypeError: Cannot read property '0' of undefined
    at /home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/@angular-devkit/build-angular/node_modules/postcss-import/index.js:78:37
    at Array.forEach (<anonymous>)
    at applyMedia (/home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/@angular-devkit/build-angular/node_modules/postcss-import/index.js:70:16)
    at /home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/@angular-devkit/build-angular/node_modules/postcss-import/index.js:51:9
    at async LazyResult.runAsync (/home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/@angular-devkit/build-angular/node_modules/postcss/lib/lazy-result.js:358:11)
    at async Object.loader (/home/runner/work/ProvisionThat/ProvisionThat/ProvisionThat-Web/ProvisionThat.Web.Frontend/ClientApp/node_modules/postcss-loader/dist/index.js:95:14)
```

[Jump to Line](https://github.com/postcss/postcss-import/blob/8b239c6c5e2f5da1e70eeeb6192513cbeee46a73/index.js#L78)

This appears to be caused by the following line in the styles.css:
`@import "../node_modules/@clr/ui/clr-ui-dark.min.css" screen and (prefers-color-scheme: dark);`

Specifically, around the media query at the end of the import. Removing the media query fixes the error
`@import "../node_modules/@clr/ui/clr-ui-dark.min.css";`

angular.json
```
{
  "$schema": "./node_modules/@angular/cli/lib/config/schema.json",
  "version": 1,
  "newProjectRoot": "projects",
  "projects": {
    "ClientApp": {
      "projectType": "application",
      "schematics": {},
      "root": "",
      "sourceRoot": "src",
      "prefix": "app",
      "architect": {
        "build": {
          "builder": "@angular-devkit/build-angular:browser",
          "options": {
            "progress": true,
            "outputPath": "dist/ClientApp",
            "index": "src/index.html",
            "main": "src/main.ts",
            "polyfills": "src/polyfills.ts",
            "tsConfig": "tsconfig.app.json",
            "aot": true,
            "assets": [
              "src/silent-refresh.html",
              "src/silent-refresh.js",
              "src/CHANGELOG.txt",
              "src/favicon.ico",
              "src/assets",
              "src/docs"
            ],
            "styles": [
              "node_modules/@clr/icons/clr-icons.min.css",
              "node_modules/@clr/ui/clr-ui.min.css",
              "src/styles.css"
            ],
            "scripts": [
              "node_modules/@webcomponents/webcomponentsjs/custom-elements-es5-adapter.js",
              "node_modules/@webcomponents/webcomponentsjs/webcomponents-bundle.js",
              "node_modules/@clr/icons/clr-icons.min.js"
            ],
            "allowedCommonJsDependencies": [
              "qrcode"
            ]
          },
          "configurations": {
            "production": {
              "fileReplacements": [
                {
                  "replace": "src/environments/environment.ts",
                  "with": "src/environments/environment.prod.ts"
                }
              ],
              "optimization": true,
              "outputHashing": "all",
              "sourceMap": false,
              "namedChunks": false,
              "extractLicenses": true,
              "vendorChunk": false,
              "buildOptimizer": true,
              "budgets": [
                {
                  "type": "initial",
                  "maximumWarning": "5mb",
                  "maximumError": "10mb"
                },
                {
                  "type": "anyComponentStyle",
                  "maximumWarning": "6kb",
                  "maximumError": "10kb"
                }
              ]
            }
          }
        },
        "serve": {
          "builder": "@angular-devkit/build-angular:dev-server",
          "options": {
            "browserTarget": "ClientApp:build"
          },
          "configurations": {
            "production": {
              "browserTarget": "ClientApp:build:production"
            }
          }
        },
        "extract-i18n": {
          "builder": "@angular-devkit/build-angular:extract-i18n",
          "options": {
            "browserTarget": "ClientApp:build"
          }
        },
        "test": {
          "builder": "@angular-devkit/build-angular:karma",
          "options": {
            "main": "src/test.ts",
            "polyfills": "src/polyfills.ts",
            "tsConfig": "tsconfig.spec.json",
            "karmaConfig": "karma.conf.js",
            "assets": [
              "src/favicon.ico",
              "src/assets"
            ],
            "styles": [
              "src/styles.css"
            ],
            "scripts": []
          }
        },
        "lint": {
          "builder": "@angular-devkit/build-angular:tslint",
          "options": {
            "tsConfig": [
              "tsconfig.app.json",
              "tsconfig.spec.json",
              "e2e/tsconfig.json"
            ],
            "exclude": [
              "**/node_modules/**"
            ]
          }
        },
        "e2e": {
          "builder": "@angular-devkit/build-angular:protractor",
          "options": {
            "protractorConfig": "e2e/protractor.conf.js",
            "devServerTarget": "ClientApp:serve"
          },
          "configurations": {
            "production": {
              "devServerTarget": "ClientApp:serve:production"
            }
          }
        }
      }
    }
  },
  "defaultProject": "ClientApp"
}
```

package.json
```
{
  "name": "provisionthat.web",
  "version": "1.0.0",
  "scripts": {
    "ng": "ng",
    "update": "ng update",
    "start": "ng serve",
    "build": "ng build --subresource-integrity",
    "test": "ng test",
    "lint": "ng lint",
    "e2e": "ng e2e"
  },
  "private": true,
  "dependencies": {
    "@angular/animations": "^11.1.2",
    "@angular/common": "^11.1.2",
    "@angular/compiler": "^11.1.2",
    "@angular/core": "^11.1.2",
    "@angular/forms": "^11.1.2",
    "@angular/localize": "^11.1.2",
    "@angular/platform-browser": "^11.1.2",
    "@angular/platform-browser-dynamic": "^11.1.2",
    "@angular/router": "^11.1.2",
    "@cds/core": "^5.0.0",
    "@clr/angular": "^5.0.1",
    "@clr/core": "^4.0.11",
    "@clr/icons": "^5.0.1",
    "@clr/ui": "^5.0.1",
    "@webcomponents/custom-elements": "^1.4.3",
    "@webcomponents/webcomponentsjs": "^2.5.0",
    "angular-oauth2-oidc": "^10.0.3",
    "angularx-qrcode": "^11.0.0",
    "dompurify": "^2.2.6",
    "marked": "^2.0.0",
    "nan": "^2.14.2",
    "postcss": "^8.2.5",
    "rxjs": "^6.6.3",
    "tslib": "^2.0.0",
    "zone.js": "^0.11.3"
  },
  "devDependencies": {
    "@angular-devkit/build-angular": "^0.1101.4",
    "@angular/cli": "^11.1.4",
    "@angular/compiler-cli": "^11.1.2",
    "@angular/language-service": "^11.1.2",
    "@fortawesome/angular-fontawesome": "^0.8.2",
    "@fortawesome/fontawesome-svg-core": "^1.2.34",
    "@fortawesome/pro-light-svg-icons": "^5.15.2",
    "@fortawesome/pro-regular-svg-icons": "^5.15.2",
    "@fortawesome/pro-solid-svg-icons": "^5.15.2",
    "@types/jasmine": "~3.6.0",
    "@types/jasminewd2": "^2.0.8",
    "@types/node": "^14.14.25",
    "codelyzer": "^6.0.0",
    "jasmine-core": "~3.6.0",
    "jasmine-spec-reporter": "^6.0.0",
    "karma": "^6.1.0",
    "karma-chrome-launcher": "~3.1.0",
    "karma-coverage-istanbul-reporter": "^3.0.3",
    "karma-jasmine": "~4.0.0",
    "karma-jasmine-html-reporter": "^1.5.0",
    "protractor": "~7.0.0",
    "ts-node": "^9.1.1",
    "tslint": "^6.1.3",
    "typescript": "^4.1.3"
  }
}
```

```
cat package-lock.json | grep postcss-import
 "postcss-import": "14.0.0",
```
