`.openapi()` does not exist when extending zod with `extendZodWithOpenApi`
Since `4.2.1` (https://github.com/samchungy/zod-openapi/pull/393) the extended types are not being supplied when extending zod with `extendZodWithOpenApi`.

Downgrading to `4.2.0` fixes this issue.
