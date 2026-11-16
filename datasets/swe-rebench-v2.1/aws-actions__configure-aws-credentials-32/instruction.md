Option to set external-id when assuming role
For cases where roles can only be assumed on condition an expected external-id is passed in.

### Additional contract requirements

- A workflow can provide an external ID using the `role-external-id` input. When provided, its value is passed as `ExternalId` in the STS role-assumption request.
