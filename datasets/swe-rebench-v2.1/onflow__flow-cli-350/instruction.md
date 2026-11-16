Getter methods ByName() for contracts, accounts, networks does not return error in config package
### Instructions

pkg/flowkit/config there are getters for getting configured contracts, networks, accounts. These return an empty pointer if they are not found. It is tempting to then chain together method calls. However if you have then misconfigured things you will get not so nice error messages.

Should we fix this so that these return error as seond argument?

### Additional contract requirements

The getters live in package `pkg/flowkit/config` and return the found value together with an error as the second return value:

- `Accounts.ByName(name string) (*Account, error)` returns the account whose name matches `name`. When no account with that name exists it returns a nil account and an error whose message is `account with name %s is not present in configuration`, with `%s` replaced by the requested name.
- `Networks.ByName(name string) (*Network, error)` returns the network whose name matches `name`. When no network with that name exists it returns a nil network and an error whose message is `network named %s does not exist in configuration`, with `%s` replaced by the requested name.
- `Contracts.ByName(name string) (*Contract, error)` returns the contract whose name matches `name`. When no contract with that name exists it returns a nil contract and an error whose message is `contract named %s does not exist in configuration`, with `%s` replaced by the requested name.
- `Contracts.ByNameAndNetwork(name string, network string) (*Contract, error)` returns the contract matching both `name` and `network`. If no entry matches the requested network, it returns the base contract found by name with the requested network attached. When no contract with that name exists it returns a nil contract and an error whose message is `contract named %s does not exist in configuration`, with `%s` replaced by the requested name.
