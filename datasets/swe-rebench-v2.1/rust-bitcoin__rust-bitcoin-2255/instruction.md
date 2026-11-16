`Script::dust_value` method name disagrees with the documentation
Dust is a value that is not economically spendable and can not be broadcasted. The method is called `dust_value` which suggest it returns a value that is too small (and always returning 0 would be a valid implementation) but the documentation says "Returns the **minimum value* an output with this script should have in order **to be broadcastable** on today’s Bitcoin network." (emphasis mine) which implies it's a non-dust value.

Since writing a method that always returns 0 is useless I assume the documentation is right but the method is named incorrectly. I was not able to verify the implementation yet.

### Additional contract requirements

Rename the public `Script` method that reports this threshold to `minimal_non_dust`. With its default policy, it returns the minimum output value that is not dust and can be broadcast, rather than a value that is dust.
