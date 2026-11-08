Fails to parse multipart message due to Content-Type header case sensitivity
## Version

0.3.1

## Test Case

```elixir
  test "parses multipart emails with case insensitive Content-Type header" do
    raw =
      """
      Content-type: multipart/alternative; boundary=banana
      Mime-Version: 1.0

      --banana
      Content-Type: text/plain; charset=utf-8

      Hi

      --banana--
      """

    message =
      raw
      |> String.replace("\n", "\r\n")
      |> Mail.Parsers.RFC2822.parse()

    refute message.parts == [] # <-- I'd expect this to have one plain text part
  end
```

## Expected Behavior

I can parse a multipart email whose content type header's case is `Content-type`.

## Actual Behavior

I can't. Only emails where the header case is exactly `Content-Type` will be parsed.

Email headers [aren't required to be case sensitive](https://stackoverflow.com/a/6143644/1432982), and indeed I've observed mail servers in the wild sending messages with headers like `Content-type` instead of `Content-Type`. When this happens, elixir-mail fails to parse the message as multipart.

This relates to #148
