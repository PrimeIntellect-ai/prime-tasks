Bug: fetch requests don't forward X-Ray trace header
### Expected Behavior

When I make requests using the Fetch API and using Tracer, the `X-Amzn-Trace-Id` header should be constructed and forwarded along with the request so that I can get a full trace for a request.

For example, if I have an API Gateway A -> Lambda A -> API Gateway B -> Lambda B, and the first function in the chain is instrumented with Tracer, we should be able to see a trace like this:

<img width="987" alt="Image" src="https://github.com/user-attachments/assets/ccb95acf-c6c0-4c29-a3ad-23436d2a63b9" />

This is already supported when using the global `http` and `https` modules and their derivatives (i.e. `axios`) but doesn't work in our implementation when using Tracer with `fetch`.

### Current Behavior

Currently the setup described above generates two disconnected traces, one for each API Gateway -> Lambda pair.

### Code snippet

```ts
import { Logger } from "@aws-lambda-powertools/logger";
import { Tracer } from "@aws-lambda-powertools/tracer";

const logger = new Logger();
const tracer = new Tracer();

export const handler = async (event: { userId: number }) => {
	const parent = tracer.getSegment();
	const segment = parent?.addNewSubsegment("### functionA handler");
	segment && tracer.setSegment(segment);

	await fetch(`${process.env.API_URL}/functionB`, {
		method: "POST",
		body: JSON.stringify({ userId: event.userId }),
	});

	segment?.close();
	parent && tracer.setSegment(parent);

	return {
		statusCode: 200,
	};
};
```

### Steps to Reproduce

1. Deploy the infrastructure below
<details>

```ts
/// <reference path="./.sst/platform/config.d.ts" />

export default $config({
	app(input) {
		return {
			name: "missing-trace",
			removal: input?.stage === "production" ? "retain" : "remove",
			home: "aws",
		};
	},
	async run() {
		$transform(sst.aws.Function, (args) => {
			args.permissions = [
				{
					actions: [
						"xray:PutTraceSegments",
						"xray:PutTelemetryRecords",
						"xray:GetSamplingRules",
						"xray:GetSamplingTargets",
						"xray:GetSamplingStatisticSummaries",
					],
					resources: ["*"],
				},
			];
			args.transform = {
				function(args, opts, name) {
					args.tracingConfig = {
						mode: "Active",
					};
				},
			};
		});

		const apiB = new sst.aws.ApiGatewayV1("ApiB", {
			transform: {
				stage(args, opts, name) {
					args.xrayTracingEnabled = true;
				},
			},
		});

		apiB.route("POST /functionB", {
			handler: "src/functionB.handler",
			runtime: "nodejs22.x",
			timeout: "30 seconds",
			memory: "256 MB",
			logging: {
				retention: "1 day",
			},
		});

		apiB.deploy();

		const apiA = new sst.aws.ApiGatewayV1("ApiA", {
			transform: {
				stage(args, opts, name) {
					args.xrayTracingEnabled = true;
				},
			},
		});

		apiA.route("POST /functionA", {
			handler: "src/functionA.handler",
			runtime: "nodejs22.x",
			timeout: "30 seconds",
			memory: "256 MB",
			logging: {
				retention: "1 day",
			},
			environment: {
				API_URL: apiB.url,
			},
		});

		apiA.deploy();
	},
});
```

</details>

2. Make a request to the first API Gateway endpoint (i.e. `http POST https://api-id.execute-api.eu-west-1.amazonaws.com/stage/functionA userId=1`
3. Observe the traces

### Possible Solution

Our implementation of the `fetch` module diverges significantly from the [one in `aws-xray-sdk-node-fetch`](https://github.com/aws/aws-xray-sdk-node/blob/master/sdk_contrib/fetch/lib/fetch_p.js). Their implementation relies on monkey patching, which as far as I can tell would only work with CJS.

On our side we decided (#1619) to instead [use the `node:diagnostics_channel`](https://github.com/nodejs/undici/blob/main/docs/docs/api/DiagnosticsChannel.md) which is the recommended way to instrument requests made with `fetch`.

During the implementation, we followed the [types](https://github.com/nodejs/undici/blob/main/types/diagnostics-channel.d.ts) present in `@types/node` which suggest it's not possible to modify the `Request` object when instrumenting.

[HIDDEN]

To make this work, we should construct the header to include the `Root`, `Parent`, and `Sampled` fields and add it to the request. I made a PoC of this and I already got it working. The screenshot at the top of the issue comes from a request instrumented with Tracer using Fetch.

### Powertools for AWS Lambda (TypeScript) version

latest

### AWS Lambda function runtime

22.x

### Packaging format used

npm

### Execution logs

```Shell

```

### Additional contract requirements

A Fetch request instrumented by Tracer must include an `X-Amzn-Trace-Id` header. Its `Root` field must identify the active X-Ray trace, its `Parent` field must identify the outgoing request's parent segment, and its `Sampled` field must reflect whether that trace is sampled. The fields may appear in any order.
