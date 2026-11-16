Infer stream type for applicable streams
<!-- Use Discord for questions: https://discord.gg/bRCvFy9 -->

The library could easily infer some stream types, e.g. a stream would be input type `OggOpus` if `stream instanceof prism.opus.OggDemuxer` held. This would save from having to specify streamType so explicitly.

### Additional contract requirements

`createAudioResource` accepts a stream together with an optional `inputType` (a `StreamType`) and an optional `inlineVolume` flag.

When a stream is passed and no `inputType` is supplied, the stream type is inferred from the stream:
- a `prism.opus.Encoder` stream is inferred as `StreamType.Opus`;
- a `prism.opus.Decoder` stream is inferred as `StreamType.Raw`;
- a `prism.VolumeTransformer` stream is inferred as `StreamType.Raw`, and is treated as already providing volume handling;
- a `prism.opus.OggDemuxer` stream is inferred as `StreamType.Opus`;
- a `prism.opus.WebmDemuxer` stream is inferred as `StreamType.Opus`;
- any other stream is inferred as `StreamType.Arbitrary`.

An explicitly supplied `inputType` is used as-is and is never overridden by inference. A string input is always treated as `StreamType.Arbitrary`.

When `inlineVolume` is requested and the input stream does not already provide volume handling, an inline volume transformer is applied to the stream. When the input stream already provides volume handling, no additional inline volume transformer is applied and the existing one is used.
