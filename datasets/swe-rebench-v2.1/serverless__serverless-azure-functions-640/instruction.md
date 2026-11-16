Add suport for Node.js 16
On March 30, 2022, Microsoft announced that Node.js 16 was available for Azure Functions [https://azure.microsoft.com/en-us/updates/generally-available-nodejs-16-in-azure-functions-2/](https://azure.microsoft.com/en-us/updates/generally-available-nodejs-16-in-azure-functions-2/), but this plugin does not support this version. I found an open pull request about this issue, but with a small mistake in the code [https://github.com/serverless/serverless-azure-functions/pull/610](https://github.com/serverless/serverless-azure-functions/pull/610). Could you please add support for Node.js 16?

### Additional contract requirements

- The `Runtime` enum exported from `src/config/runtime.ts` includes a member `NODE16` with the value `"nodejs16"`.
- `isNodeRuntime(runtime)` exported from `src/config/runtime.ts` returns `true` for `Runtime.NODE16`.
- `isPythonRuntime(runtime)` exported from `src/config/runtime.ts` returns `false` for `Runtime.NODE16`.
- `getRuntimeVersion(runtime)` exported from `src/config/runtime.ts` returns `"16"` for `Runtime.NODE16`, and throws an `Error` whose message is `Runtime ${runtime} not included in supportedRuntimes` for a runtime that is not supported.
- `getRuntimeLanguage(runtime)` exported from `src/config/runtime.ts` returns `"nodejs"` for `Runtime.NODE16`, and throws an `Error` whose message is `Runtime ${runtime} not included in supportedRuntimes` for a runtime that is not supported.
- `getFunctionWorkerRuntime(runtime)` exported from `src/config/runtime.ts` returns `"node"` for `Runtime.NODE16`.
- `FunctionAppResource.getParameters(config)` in `src/armTemplates/resources/functionApp.ts` returns, for a Linux function app configured with `Runtime.NODE16`, a `linuxFxVersion` parameter whose value is `"NODE|16"` and a `functionAppNodeVersion` parameter whose value is `"~16"`.
- `ConfigService` in `src/services/configService.ts` accepts `nodejs16` as a supported runtime: constructing it with `provider.runtime` set to `nodejs16` does not throw. Its unsupported-runtime error message lists `nodejs16` among the supported runtimes.


- - For unsupported runtimes, the ConfigService error message contains `Runtime ${runtime} is not supported` and later includes `nodejs16`.
