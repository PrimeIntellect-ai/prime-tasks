Cover quotes for the `plain text` version
> #2933 covered only the `HTML` version
>
> We need to cover the `plain text` version like
>
> ```eml
> Message-ID: <ZE3RJQg@mail.flowcrypt.test>
> Subject: Re: quotes
> To: Den <den@flowcrypt.test>
> Content-Type: text/plain; charset="UTF-8"
> Content-Transfer-Encoding: quoted-printable
>
> Reply from Android
>
> Regards,
>
> Den at FlowCrypt
>
> On 2025-02-20 at 13:13, Den<denbond7@flowcrypt.test> wrote:
> rrr
>
> =D1=87=D1=82, 20 =D0=BB=D1=8E=D1=82. 2025=E2=80=AF=D1=80. =D0=BE 13:12 De=
> n at FlowCrypt <den@flowcrypt.test> =D0=BF=D0=B8=D1=88=D0=B5:
> >
> > Reply 1
> >
> >
> > On Thu, Feb 20, 2025 at 1:10=E2=80=AFPM Den<denbond7@flowcrypt=
> l.test> wrote:
> > >
> > > eee
> > >
> > > --
> > > Regards,
> > > Den
> >
> >
> >
> > --
> > Regards,
> > Den at FlowCrypt
>
>
>
> --
> Regards,
> Den
> ```
>
> for a separate PR

 _Originally posted by @DenBond7 in [#2902](https://github.com/FlowCrypt/flowcrypt-android/issues/2902#issuecomment-2671255632)_

### Additional contract requirements

- The plain-text body must be converted to HTML and exposed as a `PLAIN_HTML` message block.
- Each quoted reply level (a run of lines prefixed with `>`) must be rendered as a `<blockquote>` element. Quote levels must be nested: a deeper quote level appears inside the `<blockquote>` of the shallower level that precedes it.
- The complete text of each quote level must be preserved inside its `<blockquote>`, not only the first line.


- For a plain-text message containing quoted replies, the processed result must contain exactly one message block, of type `PLAIN_HTML`.
