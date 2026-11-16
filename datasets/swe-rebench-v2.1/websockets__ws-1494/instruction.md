Close frame spanning multiple packets is not handled correctly
- [x] I've searched for any related issues and avoided creating a duplicate
      issue.

#### Description
A close frame which has been split over multiple TCP packets, for example <header><payload> is not handled correctly.  The payload is never read and `conclude` event not emitted.

#### Reproducible in:

- version: 6.1.2
- Node.js version(s): 10.12
- OS version(s): Linux; Fedora 29

#### Steps to reproduce:

1. Establish a websocket session

2. Send a close frame from the server as two separate packets

#### Expected result:

1. Close frame is parsed correctly and `conclude` event is emitted from receiver

#### Actual result:

1. Close frame is not parsed and `conclude` is never emitted
