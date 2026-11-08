Add an `also` method akin to Kotlins `also`
# Brief Description
I would like to propose a new function `also` that takes a function with a single dataframe for input, runs the function on the chained dataframe, and returns the input dataframe.

I would love to take a whack at implementing this if you're interested incorporating it into the library.

As I've been trying to adopt chaining as much as possible, I've routinely bumped into scenarios where I need to break the chain for one reason or another. This API would eliminate most reasons for breaking the chain

This function is inspired by Kotlin's `also` function.  If we were to mimic Kotlin's `also`, the signature would look something like

`also: (f: T -> None) -> T`

It would behave very similar to `pipe` or `then`, but can be used on functions that do not return anything. This can be very useful for any sort of side-effect operations within a long chain, such as periodic logging or debugging.

# Example API

<!-- One of the selling points of pyjanitor is the API. Hence, we guard the API very carefully, and want to
make sure that it is accessible and understandable to many people. Please provide a few examples of what the API
of the new function you're proposing will look like. We have provided an example that you should modify. -->

Below are some examples of how this API would simplify code I've written in the past.

### print the df while processing.
```python
# instead of defining an extra function
def print_and(df):
    print(df)
    return df

df.groupby(["column1"]).agg(sum).then(print_and).then(my_transform)

# or breaking the chain up
df_tmp = df.groupby(["column1"]).agg(sum)
print(df_tmp)
df_tmp.then(my_transform)

# you could just inline the print statement
df.groupby(["column1"]).agg(sum).also(print).then(my_transform)
```

### Insert a breakpoint while debugging, but keep going when you're done
Similar to above, to add a breakpoint for debugging, you would either have to create a new `pipe` compatible function or break the chain into smaller steps.

Instead, you could chain a breakpoint like so

```python
df.groupby(["column1"]).agg(sum).also(lambda x: breakpoint()).then(my_transform)
```

### Save a midpoint of a processing chain and then keep going

Another possibility would be running IO in the middle of the chain.  Often, a midpoint in the chain is just as important as the end result.  `also` would allow me to save the results and keep going without breaking a chain.

```
df.groupby(["column1"]).agg(sum).also(lambda x: x.to_csv("filename.csv)).then(my_transform)
```

### pipe-dream: Save a midpoint as a variable

I haven't figured out how to get this to work given Python's scoping rules, maybe the new `:=` operator will make this possible.

This could be really helpful in scenarios where you're running groupbys or other aggregations and want to join those back into an ungrouped frame.

```
df.groupby(["column1"]).agg(sum).also(lambda x: df_mid = x).then(my_transform).assign(original_var = df_mid)
```
