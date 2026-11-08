Crash in CCP instruction
CCP is not checking that the given range `c..c+d` is in range for the contract. Crash here: https://github.com/FuelLabs/fuel-vm/blob/20f1e9b888e359b9d1ac45214673e97277370543/fuel-vm/src/interpreter/blockchain.rs#L692

Needs a check and a test case.

### Additional contract requirements

CCP must safely handle a requested contract range `c..c+d` outside the contract bounds rather than crashing. A normal VM execution error is acceptable; successful zero-filling is not required.
