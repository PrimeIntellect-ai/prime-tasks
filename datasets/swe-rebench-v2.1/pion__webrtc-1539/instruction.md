Make WithMediaEngine to receive a pointer
<!--
  Come join our community on Slack https://pion.ly/slack for quicker support and more resources

  We also provide a Knowledge Base https://pion.ly/knowledge-base that covers Pion and general WebRTC

  We maintain a FAQ of common issues and questions https://pion.ly/knowledge-base/pion-basics/faq/

  Please answer these questions before submitting your issue. Thanks!
-->

## Summary

Now that mediaengine allow to register and get ext map headers, api sould receive a pointer in order to use the ME outside Pion conext.

## Motivation

On pion-sfu the subscribers starts with not default codecs, once a user share it's media we need to register that media codec to not offer other codecs asside the one shared.

## Describe alternatives you've considered

No alternatives atm.

### Additional contract requirements

`WithMediaEngine` accepts a pointer to a `MediaEngine`. The API uses that same instance, not a snapshot, so changes made through the caller's pointer after API construction can affect API behavior, including the codecs offered by peer connections created through the API.
