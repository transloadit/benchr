# benchr

Benchmarks tusd using tus-js-client


To only see mbit/s:

```bash
tusd/run.sh 2>/dev/null
```

To see full debug output:

```bash
tusd/run.sh
```

To try a different scenario (for instance, sets a different tcp window size)

```bash
SCENARIO=2 tusd/run.sh 2>/dev/null
```
