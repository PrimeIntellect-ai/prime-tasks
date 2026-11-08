[es] Issues with conjugation parsing
I'm using the Spanish Wiktionary extract from Kaikki (specifically https://kaikki.org/dictionary/downloads/es/es-extract.jsonl). I noticed some inconsistencies in the extracted verb conjugations.

**First**: There are some verbs where the form contains footnotes (e.g., a reference for vos) in the verb form. In the English extract these are provided as tags.
**Second**: There are "forms" where there is a text, e.g., at the bottom of `hablar` for the negative imperative form:

```
shape: (123, 5)
┌────────┬─────────────────────────────────┬─────────────┬─────────────────────┬────────────────────────┐
│ verb   ┆ form                            ┆ mode        ┆ tense               ┆ person                 │
│ ---    ┆ ---                             ┆ ---         ┆ ---                 ┆ ---                    │
│ str    ┆ str                             ┆ enum        ┆ str                 ┆ enum                   │
╞════════╪═════════════════════════════════╪═════════════╪═════════════════════╪════════════════════════╡
...
│ hablar ┆ hablásᵛᵒˢ                       ┆ indicative  ┆ present             ┆ second-person-singular │
│ hablar ┆ hablas^(tú)                     ┆ indicative  ┆ present             ┆ second-person-singular │
...
│ hablar ┆ hables^(tú)                     ┆ subjunctive ┆ present             ┆ second-person-singular │
│ hablar ┆ hablésᵛᵒˢ²                      ┆ subjunctive ┆ present             ┆ second-person-singular │
...
│ hablar ┆ hayas^(tú) hablado              ┆ subjunctive ┆ present perfect     ┆ second-person-singular │
│ hablar ┆ hayásᵛᵒˢ² hablado               ┆ subjunctive ┆ present perfect     ┆ second-person-singular │
...
│ hablar ┆ habláᵛᵒˢ                        ┆ imperative  ┆ affirmative         ┆ second-person-singular │
│ hablar ┆ habla^(tú)                      ┆ imperative  ┆ affirmative         ┆ second-person-singular │
...
│ hablar ┆ Se emplea el presente del modo… ┆ imperative  ┆ negative            ┆ second-person-singular │
└────────┴─────────────────────────────────┴─────────────┴─────────────────────┴────────────────────────┘
```

I can deal with both the first and second issue in my application, if you tell me that this won't change and is to be expected.

**Third**: For some verbs the conjugation tables aren't parsed correctly which leads to missing tags on each form. For `hablar` it works well. For `amar` for example it does not (even though `amar` is the _paradigm_ by which `hablar` is conjugated):

```
shape: (138, 5)
┌──────┬──────────────────┬─────────────┬──────────────────────────┬────────────┐
│ verb ┆ form             ┆ mode        ┆ tense                    ┆ person     │
│ ---  ┆ ---              ┆ ---         ┆ ---                      ┆ ---        │
│ str  ┆ str              ┆ enum        ┆ str                      ┆ enum       │
╞══════╪══════════════════╪═════════════╪══════════════════════════╪════════════╡
│ amar ┆ amando           ┆ impersonal  ┆ gerund                   ┆ impersonal │
│ amar ┆ habiendo amado   ┆ impersonal  ┆ gerund                   ┆ impersonal │
│ amar ┆ haber amado      ┆ impersonal  ┆ infinitive               ┆ impersonal │
│ amar ┆ amar             ┆ impersonal  ┆ infinitive               ┆ impersonal │
│ amar ┆ amado            ┆ impersonal  ┆ participle               ┆ impersonal │
│ amar ┆ amaré            ┆ indicative  ┆ future                   ┆ null       │
│ amar ┆ amarás           ┆ indicative  ┆ future                   ┆ null       │
│ amar ┆ amarás           ┆ indicative  ┆ future                   ┆ null       │
│ amar ┆ amará            ┆ indicative  ┆ future                   ┆ null       │
│ amar ┆ amaremos         ┆ indicative  ┆ future                   ┆ null       │
│ amar ┆ amaréis          ┆ indicative  ┆ future                   ┆ null       │
│ amar ┆ amarán           ┆ indicative  ┆ future                   ┆ null       │
│ amar ┆ habrá amado      ┆ indicative  ┆ future compound          ┆ null       │
│ amar ┆ habrás amado     ┆ indicative  ┆ future compound          ┆ null       │
│ amar ┆ habré amado      ┆ indicative  ┆ future compound          ┆ null       │
│ amar ┆ habrás amado     ┆ indicative  ┆ future compound          ┆ null       │
│ amar ┆ habremos amado   ┆ indicative  ┆ future compound          ┆ null       │
│ amar ┆ habréis amado    ┆ indicative  ┆ future compound          ┆ null       │
│ amar ┆ habrán amado     ┆ indicative  ┆ future compound          ┆ null       │
│ amar ┆ hubieron amado   ┆ indicative  ┆ past anterior            ┆ null       │
│ amar ┆ hubisteis amado  ┆ indicative  ┆ past anterior            ┆ null       │
│ amar ┆ hubimos amado    ┆ indicative  ┆ past anterior            ┆ null       │
│ amar ┆ hubo amado       ┆ indicative  ┆ past anterior            ┆ null       │
│ amar ┆ hubiste amado    ┆ indicative  ┆ past anterior            ┆ null       │
│ amar ┆ hube amado       ┆ indicative  ┆ past anterior            ┆ null       │
│ amar ┆ hubiste amado    ┆ indicative  ┆ past anterior            ┆ null       │
│ amar ┆ amabais          ┆ indicative  ┆ past imperfect           ┆ null       │
│ amar ┆ amaba            ┆ indicative  ┆ past imperfect           ┆ null       │
│ amar ┆ amabas           ┆ indicative  ┆ past imperfect           ┆ null       │
│ amar ┆ amabas           ┆ indicative  ┆ past imperfect           ┆ null       │
│ amar ┆ amaba            ┆ indicative  ┆ past imperfect           ┆ null       │
│ amar ┆ amaban           ┆ indicative  ┆ past imperfect           ┆ null       │
│ amar ┆ amábamos         ┆ indicative  ┆ past imperfect           ┆ null       │
│ amar ┆ habías amado     ┆ indicative  ┆ pluperfect               ┆ null       │
│ amar ┆ había amado      ┆ indicative  ┆ pluperfect               ┆ null       │
│ amar ┆ habías amado     ┆ indicative  ┆ pluperfect               ┆ null       │
│ amar ┆ había amado      ┆ indicative  ┆ pluperfect               ┆ null       │
│ amar ┆ habíamos amado   ┆ indicative  ┆ pluperfect               ┆ null       │
│ amar ┆ habíais amado    ┆ indicative  ┆ pluperfect               ┆ null       │
│ amar ┆ habían amado     ┆ indicative  ┆ pluperfect               ┆ null       │
│ amar ┆ aman             ┆ indicative  ┆ present                  ┆ null       │
│ amar ┆ amáis            ┆ indicative  ┆ present                  ┆ null       │
│ amar ┆ amamos           ┆ indicative  ┆ present                  ┆ null       │
│ amar ┆ ama              ┆ indicative  ┆ present                  ┆ null       │
│ amar ┆ amás             ┆ indicative  ┆ present                  ┆ null       │
│ amar ┆ amas             ┆ indicative  ┆ present                  ┆ null       │
│ amar ┆ amo              ┆ indicative  ┆ present                  ┆ null       │
│ amar ┆ amaron           ┆ indicative  ┆ present perfect          ┆ null       │
│ amar ┆ amé              ┆ indicative  ┆ present perfect          ┆ null       │
│ amar ┆ amaste           ┆ indicative  ┆ present perfect          ┆ null       │
│ amar ┆ amaste           ┆ indicative  ┆ present perfect          ┆ null       │
│ amar ┆ amó              ┆ indicative  ┆ present perfect          ┆ null       │
│ amar ┆ amamos           ┆ indicative  ┆ present perfect          ┆ null       │
│ amar ┆ amasteis         ┆ indicative  ┆ present perfect          ┆ null       │
│ amar ┆ has amado        ┆ indicative  ┆ present perfect compound ┆ null       │
│ amar ┆ he amado         ┆ indicative  ┆ present perfect compound ┆ null       │
│ amar ┆ has amado        ┆ indicative  ┆ present perfect compound ┆ null       │
│ amar ┆ han amado        ┆ indicative  ┆ present perfect compound ┆ null       │
│ amar ┆ habéis amado     ┆ indicative  ┆ present perfect compound ┆ null       │
│ amar ┆ hemos amado      ┆ indicative  ┆ present perfect compound ┆ null       │
│ amar ┆ ha amado         ┆ indicative  ┆ present perfect compound ┆ null       │
│ amar ┆ amarías          ┆ conditional ┆ conditional              ┆ null       │
│ amar ┆ amarían          ┆ conditional ┆ conditional              ┆ null       │
│ amar ┆ amaríais         ┆ conditional ┆ conditional              ┆ null       │
│ amar ┆ amaríamos        ┆ conditional ┆ conditional              ┆ null       │
│ amar ┆ amaría           ┆ conditional ┆ conditional              ┆ null       │
│ amar ┆ amarías          ┆ conditional ┆ conditional              ┆ null       │
│ amar ┆ amaría           ┆ conditional ┆ conditional              ┆ null       │
│ amar ┆ habríamos amado  ┆ conditional ┆ conditional compound     ┆ null       │
│ amar ┆ habrían amado    ┆ conditional ┆ conditional compound     ┆ null       │
│ amar ┆ habría amado     ┆ conditional ┆ conditional compound     ┆ null       │
│ amar ┆ habríais amado   ┆ conditional ┆ conditional compound     ┆ null       │
│ amar ┆ habrías amado    ┆ conditional ┆ conditional compound     ┆ null       │
│ amar ┆ habrías amado    ┆ conditional ┆ conditional compound     ┆ null       │
│ amar ┆ habría amado     ┆ conditional ┆ conditional compound     ┆ null       │
│ amar ┆ amare            ┆ subjunctive ┆ future                   ┆ null       │
│ amar ┆ amareis          ┆ subjunctive ┆ future                   ┆ null       │
│ amar ┆ amáremos         ┆ subjunctive ┆ future                   ┆ null       │
│ amar ┆ amares           ┆ subjunctive ┆ future                   ┆ null       │
│ amar ┆ amares           ┆ subjunctive ┆ future                   ┆ null       │
│ amar ┆ amare            ┆ subjunctive ┆ future                   ┆ null       │
│ amar ┆ amaren           ┆ subjunctive ┆ future                   ┆ null       │
│ amar ┆ hubieren amado   ┆ subjunctive ┆ future compound          ┆ null       │
│ amar ┆ hubiere amado    ┆ subjunctive ┆ future compound          ┆ null       │
│ amar ┆ hubieres amado   ┆ subjunctive ┆ future compound          ┆ null       │
│ amar ┆ hubieres amado   ┆ subjunctive ┆ future compound          ┆ null       │
│ amar ┆ hubiere amado    ┆ subjunctive ┆ future compound          ┆ null       │
│ amar ┆ hubiereis amado  ┆ subjunctive ┆ future compound          ┆ null       │
│ amar ┆ hubiéremos amado ┆ subjunctive ┆ future compound          ┆ null       │
│ amar ┆ amase            ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amaran           ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amara            ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amases           ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amases           ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amaras           ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amaras           ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amara            ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amaseis          ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amase            ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amasen           ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amáramos         ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amásemos         ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ amarais          ┆ subjunctive ┆ past imperfect           ┆ null       │
│ amar ┆ hubieses amado   ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubieras amado   ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubieses amado   ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubierais amado  ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubieseis amado  ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubieran amado   ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubiésemos amado ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubieras amado   ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubiéramos amado ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubiese amado    ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubiera amado    ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubiese amado    ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubiera amado    ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ hubiesen amado   ┆ subjunctive ┆ pluperfect               ┆ null       │
│ amar ┆ ames             ┆ subjunctive ┆ present                  ┆ null       │
│ amar ┆ amen             ┆ subjunctive ┆ present                  ┆ null       │
│ amar ┆ ames             ┆ subjunctive ┆ present                  ┆ null       │
│ amar ┆ ame              ┆ subjunctive ┆ present                  ┆ null       │
│ amar ┆ améis            ┆ subjunctive ┆ present                  ┆ null       │
│ amar ┆ amemos           ┆ subjunctive ┆ present                  ┆ null       │
│ amar ┆ ame              ┆ subjunctive ┆ present                  ┆ null       │
│ amar ┆ amés             ┆ subjunctive ┆ present                  ┆ null       │
│ amar ┆ hayamos amado    ┆ subjunctive ┆ present perfect          ┆ null       │
│ amar ┆ haya amado       ┆ subjunctive ┆ present perfect          ┆ null       │
│ amar ┆ hayáis amado     ┆ subjunctive ┆ present perfect          ┆ null       │
│ amar ┆ haya amado       ┆ subjunctive ┆ present perfect          ┆ null       │
│ amar ┆ hayas amado      ┆ subjunctive ┆ present perfect          ┆ null       │
│ amar ┆ hayas amado      ┆ subjunctive ┆ present perfect          ┆ null       │
│ amar ┆ hayan amado      ┆ subjunctive ┆ present perfect          ┆ null       │
│ amar ┆ ama              ┆ imperative  ┆ present                  ┆ null       │
│ amar ┆ amá              ┆ imperative  ┆ present                  ┆ null       │
│ amar ┆ ame              ┆ imperative  ┆ present                  ┆ null       │
│ amar ┆ amemos           ┆ imperative  ┆ present                  ┆ null       │
│ amar ┆ amad             ┆ imperative  ┆ present                  ┆ null       │
│ amar ┆ amen             ┆ imperative  ┆ present                  ┆ null       │
└──────┴──────────────────┴─────────────┴──────────────────────────┴────────────┘
```

`amar` does not include any person information (it should contain tags like `first-person`, `second-person`, `singular`, `plural` etc). It also does not contain the `compound` tag in all instances as one would expect going from the result from `hablar`. There for example we get the `compound` tag on `impersonal` forms, e.g.,:

```
┌────────┬─────────────────────────────────┬─────────────┬─────────────────────┬────────────────────────┐
│ verb   ┆ form                            ┆ mode        ┆ tense               ┆ person                 │
│ ---    ┆ ---                             ┆ ---         ┆ ---                 ┆ ---                    │
│ str    ┆ str                             ┆ enum        ┆ str                 ┆ enum                   │
╞════════╪═════════════════════════════════╪═════════════╪═════════════════════╪════════════════════════╡
│ hablar ┆ hablando                        ┆ impersonal  ┆ gerund              ┆ impersonal             │
│ hablar ┆ habiendo hablado                ┆ impersonal  ┆ gerund compound     ┆ impersonal             │
│ hablar ┆ hablar                          ┆ impersonal  ┆ infinitive          ┆ impersonal             │
│ hablar ┆ haber hablado                   ┆ impersonal  ┆ infinitive compound ┆ impersonal             │
...
│ hablar ┆ hablo                           ┆ indicative  ┆ present             ┆ first-person-singular  │
│ hablar ┆ hablásᵛᵒˢ                       ┆ indicative  ┆ present             ┆ second-person-singular │
│ hablar ┆ hablas^(tú)                     ┆ indicative  ┆ present             ┆ second-person-singular │
│ hablar ┆ habla                           ┆ indicative  ┆ present             ┆ third-person-singular  │
│ hablar ┆ hablamos                        ┆ indicative  ┆ present             ┆ first-person-plural    │
│ hablar ┆ habláis                         ┆ indicative  ┆ present             ┆ second-person-plural   │
│ hablar ┆ hablan                          ┆ indicative  ┆ present             ┆ third-person-plural    │
...
```

**Fourth**: There are some forms marked as archaic in the Spanish Wiktionary but these forms are not tagged as such in the extract. Is that something we could include?

### Additional contract requirements

- In a Spanish conjugation table, a row whose header carries a dagger suffix (`^†`, as in `Pretérito imperfecto^†`) marks every form in that row as archaic: each such form must include the `archaic` tag.
