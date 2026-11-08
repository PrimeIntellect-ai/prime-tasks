Desc command Error
Thanks for this awesome tool I've really enjoyed and appreciated it. Maybe I'm doing something wrong but I couldn't figure it out.

## Describe the bug
Desc command can't be executed properly, I've used it manually and I got always an error even if I use the tab key in which Evans assists me with a prompt, results don't change. [Here](https://github.com/cerezo074/GRPC/tree/main/Evans%20Reflection) you can reproduce it easily.

## To reproduce
Just type command desc with a message name like this **desc LanguageDetectorRequest**

## Expected behavior
Command desc show a table description
## Screenshots
<img width="1105" alt="Screen Shot 2021-02-14 at 8 57 54 PM" src="https://user-images.githubusercontent.com/73249966/107897548-5404ff80-6f07-11eb-892a-514b6ab498bb.png">

## Environment
- OS: Mac OS X 10.15.6 (19G73)
- Terminal: zsh 5.7.1 (x86_64-apple-darwin19.0)
- Evans version: 0.9.3
- `protoc` version: libprotoc 3.14.0
- `protoc` plugin version (if you are using):

## Additional context
protoc-gen-go-grpc 1.0.1
