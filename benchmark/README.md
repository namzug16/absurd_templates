# Benchmark

Renders the same three pages with Absurd Templates (`abs`),
[Jinja](https://pub.dev/packages/jinja) and
[Mustache](https://pub.dev/packages/mustache_template), all in Dart:

- `card`: one small component.
- `table`: 1000 rows with a loop, an index and a condition.
- `page`: a layout composing 100 cards (Jinja `include`, Mustache partials,
  `List<Fragment>` in abs).

The templates are side by side in `templates/`. Every value is HTML-escaped
and contains characters that need escaping. Before timing, the runner stops
if any engine renders different HTML from abs (whitespace between tags
aside). `dart test` runs the same check.

Jinja and Mustache parse their templates once, before timing, so only
rendering is measured. abs has nothing to parse at run time.

## Run

```sh
cd benchmark
dart pub get
dart run absurd_templates:abs        # regenerate lib/absurd.dart after changing abs
dart compile exe bin/benchmark.dart -o /tmp/abs_benchmark && /tmp/abs_benchmark
```

`dart run bin/benchmark.dart` also works, but it measures the JIT, not the
AOT code a deployed server runs.

## Results

Apple M1, one run:

```text
Absurd Templates vs Jinja vs Mustache
Dart 3.13.4 (AOT), macos, 2 s per engine after a 500 ms warm-up

card: one small component
  engine     time per render   renders/s  vs abs
  abs                0.99 µs   1,005,723  baseline      ██████
  jinja              5.30 µs     188,775  5.3x slower   ████████████████████████████████
  mustache           2.43 µs     412,245  2.4x slower   ███████████████

table: 1000 rows with a loop, an index and a condition
  engine     time per render   renders/s  vs abs
  abs               622.2 µs       1,607  baseline      █████
  jinja              3.88 ms         258  6.2x slower   ████████████████████████████████
  mustache           1.85 ms         541  3.0x slower   ███████████████

page: a layout composing 100 card components
  engine     time per render   renders/s  vs abs
  abs                97.0 µs      10,313  baseline      █
  jinja              8.22 ms         122  84.8x slower  ████████████████████████████████
  mustache          255.9 µs       3,907  2.6x slower   █
```

Jinja falls furthest behind on `page`, where it includes the card template
100 times per render.
