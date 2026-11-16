Check sufficient utxo confirmations exist before submitting send request
I tried sending funds with collaberative transaction enabled.
The interface indicated that a CoinJoin was in progress...
After some time, the 'Joining...' status indicator disapeared from the dashboard.
The CoinJoin was not successful.
After some time, I realised it was most likely because the UTXO being spent was still unconfirmed.

My suggestion is to add a check, prior to processing the send request, to verify that the UTXO(s) being spent have sufficient confirmations.

### Additional contract requirements

- Add a public hook `useCoinjoinPreconditionSummary(utxos: Utxos): CoinjoinPreconditionSummary` in `src/hooks/CoinjoinPrecondition.ts`.
- Export a public constant `COINJOIN_PRECONDITIONS` from the same module with the values `MIN_NUMBER_OF_UTXOS = 1`, `MIN_CONFIRMATIONS_OF_SINGLE_UTXO = 5`, and `MIN_OVERALL_REMAINING_RETRIES = 1`.
- The returned `CoinjoinPreconditionSummary` has the fields `isFulfilled: boolean`, `numberOfMissingUtxos: number`, `amountOfMissingConfirmations: number`, and `amountOfMissingOverallRetries: number`.
- UTXOs that are frozen or time-locked are not eligible and are excluded from the summary.
- `numberOfMissingUtxos` is how many more eligible UTXOs are needed to reach `MIN_NUMBER_OF_UTXOS`.
- `amountOfMissingConfirmations` is how many more confirmations the most-confirmed eligible UTXO needs to reach `MIN_CONFIRMATIONS_OF_SINGLE_UTXO`.
- `amountOfMissingOverallRetries` is how many more retries the eligible UTXOs collectively need to reach `MIN_OVERALL_REMAINING_RETRIES`.
- `isFulfilled` is true only when all three pre-conditions are met.
- An empty or insufficient set of UTXOs yields an unfulfilled summary with the appropriate missing counts and does not throw.
- A collaborative send request is not processed while the pre-conditions are not fulfilled.
