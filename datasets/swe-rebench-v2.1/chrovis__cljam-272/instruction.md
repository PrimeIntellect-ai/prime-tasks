Case insensitive support for NaN/Infinity
The current cljam implementation of VCF reader throws if it encounters a lowercased `nan` as a `Float` value.

The VCF spec says that the  lexical syntax of `Float` [allows for case insensitive `[-+]?(INF|INFINITY|NAN)`](https://github.com/samtools/hts-specs/blob/7cfd7893b0f6d6ee23474847f0239c47524c7f22/VCFv4.4.tex#L98-L99), and in practice, there are sometimes VCFs out there (e.g. some of [ToMMo’s VCFs](https://jmorp.megabank.tohoku.ac.jp/downloads)) that contain such values.
