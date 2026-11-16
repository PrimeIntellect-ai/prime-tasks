Pause governance
As a DAO, we would like to vote to pause governance for a certain period of time. During this frozen period no proposals can be made or executed, and voting is disabled.

Talking with @ben2x4 made me realize that this a simple and very important feature... and useful in a number of cases.

### Additional contract requirements

- Add a public execute message variant `PauseDAO { expiration: Expiration }` to the DAO's `ExecuteMsg` (module `contracts/cw3-dao/src/msg.rs`), where `Expiration` is the `cw_utils::Expiration` type. It pauses DAO governance until the given expiration.
- The pause can only be triggered by the DAO contract itself. A call from any other sender is rejected with `ContractError::Unauthorized` (module `contracts/cw3-dao/src/error.rs`).
- While the DAO is paused, proposing, voting, executing and closing proposals are rejected with `ContractError::Paused` (module `contracts/cw3-dao/src/error.rs`).
- A successful pause emits a response event with the attribute `action=pause_dao` and an `expiration` attribute.
- `Expiration` may be either height-based (`Expiration::AtHeight`) or time-based (`Expiration::AtTime`); both forms pause governance until the corresponding block height or block time is reached.
- Once the pause expiration has passed, governance resumes.


- - After the pause expiration has passed, voting on an already executed proposal is rejected with `ContractError::NotOpen`, executing it is rejected with `ContractError::WrongExecuteStatus`, and closing it is rejected with `ContractError::WrongCloseStatus`.
