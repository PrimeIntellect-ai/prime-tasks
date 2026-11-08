Failing transform of the d3 module
Hello,

I found a bug in the transform of the next ES code https://sucrase.io/#compareWithTypeScript=true&compressedCode=H4sIAHD13mAAA2WNzQqDMBAG7z7FdzREiofSQyUtXvoewSQgaFLWbLDUvnvjz6k97S7DzNr5GSjCWKd5iHDsu9gHj47Hiccy6YHtVGGbwQm8C%2BSDkCEU6gq9N3Ze1yYTspHJ4zEEHS%2Fnlki%2FTo7CXwdKKXA2Xe%2BtySJwR4K6oVzDUkEmLAtqsbHrL9srZTreS3mUJ7Fboik%2BX9IsTqnaAAAA

The code is taken from `d3-array` module, https://github.com/d3/d3-array/blob/main/src/cumsum.js
Sucrase can't transpile d3-array
Over here at @toucantoco we're using Sucrase and we're quite happy with it, thanks for maintaining it! However after a deps update we can't run the tests anymore because it looks like Sucrase can't properly transpile [this file](https://github.com/d3/d3-array/blob/416f657e932690f5e023f9ced6f7cadf118b00ac/src/cumsum.js)

As you can see in [this Sucrase playground](https://sucrase.io/#selectedTransforms=typescript&compressedCode=H4sIAHoYlWEAA2WNzQqDMBAG7z7FdzREiofSQyUtXvoewSQgaFLWbLDUvnvjz6k97S7DzNr5GSjCWKd5iHDsu9gHj47Hiccy6YHtVGGbwQm8C%2BSDkCEU6gq9N3Ze1yYTspHJ4zEEHS%2Fnlki%2FTo7CXwdKKXA2Xe%2BtySJwR4K6oVzDUkEmLAtqsbHrL9srZTreS3mUJ7Fboik%2BX9IsTqnaAAAA) by checking and unchecking this `typescript` option, Sucrase fails when TS is on

However this is valid TS, and as you can see in [this TS playground](https://www.typescriptlang.org/play?ssl=6&ssc=1&pln=6&pc=2#code/KYDwDg9gTgLgBAE2AMwIYFcA29noHYDGMAlhHnAegLYDO1AFAG6qbrA0A0czrwEyASjgBvAFBxuqKHDpU4AXjgAGLsTxIQC5QG5xcKMBjoo5AGKYIqGADYALAEEoUVAE8AdMigQqTFm06SvPwK8or4SMhqwAh6EgD83AoAfHD0snAA1IoZjHAAPnnKArFwAFyJ8ilp1JnZPGz8TKrqoBkZXPXsQgVFAroAvkA), this properly transpiles to JS, and if `noImplicitAny` is set to `false` there is no error

I don't know why this happens when running our tests since [@sucrase/jest-plugin precises](https://github.com/alangpierce/sucrase/tree/main/integrations/jest-plugin) that a `.js` will not be transpiles with the typescript option

Anyway just wanted to give you a heads up on this, I have no idea how to fix it yet but I can try if you guys are too busy
