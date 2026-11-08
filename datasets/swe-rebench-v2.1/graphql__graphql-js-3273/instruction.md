Unknown argument "includeDeprecated" on field "__Directive.args"
With the [update](https://github.com/opencollective/opencollective-api/pull/5191) to 15.5.0, we need to implement our own script to fetch the GraphQL schema (`get-graphql-schema` that we were using doesn't seem to be maintained anymore).

I'm using the following script to achieve that:

```bash
npm run script scripts/update-graphql-schemas.ts http://localhost:3060/graphql/v1
```

```ts
// scripts/update-graphql-schemas.ts

import * as fs from 'fs';
import * as path from 'path';

import { buildClientSchema } from 'graphql/utilities/buildClientSchema';
import { getIntrospectionQuery } from 'graphql/utilities/getIntrospectionQuery';
import { printSchema } from 'graphql/utilities/printSchema';
import fetch from 'node-fetch';

interface Options {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  headers?: { [key: string]: string };
  json?: boolean;
}

/**
 *
 * Fetch remote schema and turn it into string
 *
 * @param endpoint
 * @param options
 */
export async function getRemoteSchema(
  endpoint: string,
  options: Options,
): Promise<{ status: 'ok'; schema: string } | { status: 'err'; message: string }> {
  try {
    const introspectionQuery = getIntrospectionQuery({ inputValueDeprecation: true });
    const { data, errors } = await fetch(endpoint, {
      method: options.method,
      headers: options.headers,
      body: JSON.stringify({ query: introspectionQuery }),
    }).then(res => res.json());

    if (errors) {
      return { status: 'err', message: JSON.stringify(errors, null, 2) };
    }

    if (options.json) {
      return {
        status: 'ok',
        schema: JSON.stringify(data, null, 2),
      };
    } else {
      const schema = buildClientSchema(data);
      return {
        status: 'ok',
        schema: printSchema(schema),
      };
    }
  } catch (err) {
    return { status: 'err', message: err.message };
  }
}

/**
 *
 * Prints schema to file.
 *
 * @param dist
 * @param schema
 */
export function printToFile(
  dist: string,
  schema: string,
): { status: 'ok'; path: string } | { status: 'err'; message: string } {
  try {
    const output = path.resolve(process.cwd(), dist);

    if (!fs.existsSync(output)) {
      console.error(`${output} does not exists`);
      process.exit(1);
    }
    fs.writeFileSync(output, schema);

    return { status: 'ok', path: output };
  } catch (err) {
    return { status: 'err', message: err.message };
  }
}

export async function main(endpoint): Promise<void> {
  /* Headers */
  const defaultHeaders = {
    'Content-Type': 'application/json',
  };

  /* Fetch schema */
  const schema = await getRemoteSchema(endpoint, {
    method: 'POST',
    headers: defaultHeaders,
    json: false,
  });

  if (schema.status === 'err') {
    console.error(schema.message);
  } else {
    console.log(schema.schema);
  }
}

main(process.argv[2]);
```

This script works fine without `inputValueDeprecation: true` passed to `getIntrospectionQuery`, but whenever I try to add this option the script fails with the following message:
```
[
  {
    "message": "Unknown argument \"includeDeprecated\" on field \"__Directive.args\".",
    "locations": [
      {
        "line": 16,
        "column": 16
      }
    ],
    "extensions": {
      "code": "GRAPHQL_VALIDATION_FAILED",
      "exception": {
        "stacktrace": [
          "GraphQLError: Unknown argument \"includeDeprecated\" on field \"__Directive.args\".",
          "    at Object.Argument (/home/user/Workspace/Projects/opencollective/opencollective-api/node_modules/graphql/validation/rules/KnownArgumentNamesRule.js:46:29)",
          "    at Object.enter (/home/user/Workspace/Projects/opencollective/opencollective-api/node_modules/graphql/language/visitor.js:323:29)",
          "    at Object.enter (/home/user/Workspace/Projects/opencollective/opencollective-api/node_modules/graphql/utilities/TypeInfo.js:370:25)",
          "    at visit (/home/user/Workspace/Projects/opencollective/opencollective-api/node_modules/graphql/language/visitor.js:243:26)",
          "    at Object.validate (/home/user/Workspace/Projects/opencollective/opencollective-api/node_modules/graphql/validation/validate.js:69:24)",
          "    at validate (/home/user/Workspace/Projects/opencollective/opencollective-api/node_modules/apollo-server-core/src/requestPipeline.ts:510:14)",
          "    at Object.<anonymous> (/home/user/Workspace/Projects/opencollective/opencollective-api/node_modules/apollo-server-core/src/requestPipeline.ts:296:32)",
          "    at Generator.next (<anonymous>)",
          "    at fulfilled (/home/user/Workspace/Projects/opencollective/opencollective-api/node_modules/apollo-server-core/dist/requestPipeline.js:5:58)",
          "    at processTicksAndRejections (internal/process/task_queues.js:93:5)"
        ]
      }
    }
  }
]
```

# Context

Followup on https://github.com/graphql/graphql-js/issues/2834

### Additional contract requirements

- The introspection field `__Directive.args` accepts an optional argument `includeDeprecated: Boolean = false`.
- When `includeDeprecated` is `true`, `__Directive.args` returns all of the directive's arguments; when it is `false` or omitted, it returns only the directive's non-deprecated arguments.
- `getIntrospectionQuery({ inputValueDeprecation: true })` returns a query that requests input-value deprecation information, including the deprecated arguments of directives, so that the generated query is valid against the introspection schema.
