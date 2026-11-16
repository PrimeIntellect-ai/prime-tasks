Improve `AND`, `OR` and `NOT` logical operations to support one or more attributes
# Current
As per current implementation, logical operations such as `OR` enforce users to provide more than one condition, if done otherwise an error is thrown `Value for operator "OR" must contain more than 1 attribute.`.

# Expectation
Instead of throwing an error when 1 or fewer conditions are provided, parse the input to be single or no condition.
