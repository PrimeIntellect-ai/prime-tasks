Add a way to view internal variables value
Just as `await mock.setVariable('_myVar', 123);`
I believe we should have: `await mock.getVariable('_myVar');` that returns the current value of the variable

### Additional contract requirements

- A mock contract exposes `getVariable(variableName: string, mappingKeys?: (string | number)[]): Promise<unknown>`. `mappingKeys` is an optional array of keys used to read mapping or nested-mapping variables; it is omitted for simple variables.
- Integer values, including integer members of structs, are returned as ethers `BigNumber` instances, matching the values returned by ethers contract getters.
