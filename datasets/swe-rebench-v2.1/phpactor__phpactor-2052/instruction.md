False positive for unused import
I found a false positive for unused import.
Compact use in a namespaced file will trigger an *Unused import* diagnostic on the last namespace part.

I've written the unit test for this case (here is the [commit](https://github.com/Nicals/phpactor/commit/9443934c386fb1d81c1a0f706ff2ac3007c2a049)).
In this case, the diagnostic is:
```
Phpactor\WorseReflection\Core\Diagnostics^ {#160
  -diagnostics: array:1 [
    0 => Phpactor\WorseReflection\Bridge\TolerantParser\Diagnostics\UnusedImportDiagnostic^ {#543
      -range: Phpactor\TextDocument\ByteOffsetRange^ {#540
        -start: Phpactor\TextDocument\ByteOffset^ {#538
          -offset: 44
        }
        -end: Phpactor\TextDocument\ByteOffset^ {#541
          -offset: 48
        }
      }
      -name: "Foobar"
    }
  ]
}
```

I'm not familiar with this codebase, I might take some time to make a PR about this if I find some time but it won't be soon.
