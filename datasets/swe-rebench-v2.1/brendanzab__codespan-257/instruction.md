Support collapsing multi line output
Love the library, but there's an issue when using it with long multi-line spans--it shows *every* line!

I believe the lines that would need to be changed are these: [HIDDEN]

![image](https://user-images.githubusercontent.com/3190756/65933210-8c18aa80-e3c5-11e9-9a50-521b37ba0bf5.png)

rustc, on the other hand, will collapse multiple line spans:

https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=0d4c7f47b06cefb15528f7106766d5f7

![image](https://user-images.githubusercontent.com/3190756/65933307-e0238f00-e3c5-11e9-97c6-930e20f50be6.png)

Does codespan support this?
