Library sometimes flips boolean values
Somewhat regularly parquet-go will flip boolean values. The test at the bottom reproduces this issue.

Some things I've noticed:
- the issue occurs even if i test with the `purego` tag
- if i don't call `w.Flush()` in the write loop and allow `w.Close()` to flush the issue does not occur
- if i don't randomize the bool set to true the issue does not occur

```
type Bools struct {
	A bool
	B bool
}

func TestBools(t *testing.T) {
	f, err := os.CreateTemp(t.TempDir(), "data.parquet")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	w := parquet.NewGenericWriter[*Bools](f)

	// write some data
	for i := 0; i < 100; i++ {
		// set one random bool true
		st := &Bools{}
		n := rand.Intn(2)
		switch n {
		case 0:
			st.A = true
		case 1:
			st.B = true
		}
		w.Write([]*Bools{st})
		if i%10 == 0 {
			w.Flush()
		}
	}
	w.Close()

	stat, err := f.Stat()
	if err != nil {
		t.Fatal(err)
	}

	pf, err := parquet.OpenFile(f, stat.Size())
	if err != nil {
		t.Fatal(err)
	}

	r := parquet.NewGenericReader[*Bools](pf)
	for {
		sts := make([]*Bools, 1)
		_, err := r.Read(sts)
		st := sts[0]
		if st != nil {
			if st.A && st.B {
				t.Fatal("both true")
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
	}
}
```

### Additional contract requirements

A write/read round trip must preserve boolean values; flushing during repeated writes must not cause values to change.
