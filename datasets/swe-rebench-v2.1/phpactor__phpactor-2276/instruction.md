Strange completion from 2022.11.12 onwards.
When I am entering a string with quotes as an argument to a method, after closing the string with a quote the LSP will provide completions.

A screenshot of just before I close the quote:

![Screenshot 2023-05-06 160418 phpactor before completion](https://user-images.githubusercontent.com/216721/236644911-3449cfb5-8017-457d-8a19-2a560e8aac1d.png)

and just after I close the quote:

![Screenshot 2023-05-06 160606 phpactor after completion](https://user-images.githubusercontent.com/216721/236644939-4b7db6d5-217f-4a95-acf2-a227e7923b44.png)

The provided completions are the names of the arguments of the method  [I assume for named arguments](https://www.php.net/manual/en/functions.arguments.php#functions.named-arguments), but not useful in this context.

The named arguments do work as expected:

![Screenshot 2023-05-06 165217 phpactor named argument as expected](https://user-images.githubusercontent.com/216721/236646184-41fb1631-42d6-4f66-a42d-36f5a83d61a3.png)

Thank you 🙇
