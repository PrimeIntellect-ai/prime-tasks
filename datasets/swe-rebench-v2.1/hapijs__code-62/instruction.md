Proposal: error type
Hi,

I'd like to simplify some of my checks on async errors, so an API like that would help :
`asyncTask((err, value) => expect(err).to.be.an.error('with that message'))`

Thoughts ?

### Additional contract requirements

The expect-chain error assertion must accept an Error value and reject a value that is not an error. When supplied a message string, it must require the Error's message to equal that string. The assertion must respect the existing `.not` modifier.
