Instance property must be an Array, not an Object
Elements that are defined as 0..* in resources must be JSON arrays in the instance, even if the cardinality has been constrained, or the array contains just one value. It appears array elements are being rendered as Objects rather than Arrays.

Example -- on master branch, at commit `https://github.com/standardhealth/fsh-mcode/commit/4948b6ebe0018ddf2f9d8d8c53a469de972f059d`

Example: `build\input\resources\Condition-mCODEComorbidConditionExample01.json`

IG Publisher reports:  `Condition.category | error | This property must be an Array, not an Object`
