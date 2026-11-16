Allow defer statements after error checking
It is good practice to defer a close statement for a HTTP response body after the error check as discussed in https://stackoverflow.com/questions/33238518/what-could-happen-if-i-dont-close-response-body-in-golang#33238755

In my opinion, this defer statement should logically be part of the block where the body originates so I think we should allow the following:

```go
resp, err := client.Do(req)
if err != nil {
    return err
}
defer resp.Body.Close()
```

instead of enforcing the following:

```go
resp, err := client.Do(req)
if err != nil {
    return err
}

defer resp.Body.Close()
```
