multi-line (folded) HTTP header wrongly parsed
According to [RFC2616](https://www.ietf.org/rfc/rfc2616.txt) 2.2., the parsed value of a folded header is supposed to have continuations intact or replaced with a single SP though waitress strips them all (see [this](https://github.com/Pylons/waitress/blob/master/waitress/parser.py#L274)).

This behaviour keep developers from dealing with folded headers that are rendered with meaningful occurrences of continuations.

>   HTTP/1.1 header field values can be folded onto multiple lines if the
>   continuation line begins with a space or horizontal tab. All linear
>   white space, including folding, has the same semantics as SP. A
>   recipient MAY replace any linear white space with a single SP before
>   interpreting the field value or forwarding the message downstream.
>
>       LWS            = [CRLF] 1*( SP | HT )
