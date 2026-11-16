`access(account)` bug in contract update validator
Account access is not being resolved properly in the staged contract update validator.  Even if the contract is being deployed to an account with access, the checker reports that it is missing `account` access for the staged contract.
