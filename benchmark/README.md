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
  abs                2.61 µs     382,525  baseline      ████████████████
  jinja              5.33 µs     187,486  2.0x slower   ████████████████████████████████
  mustache           2.44 µs     410,580  1.1x faster   ███████████████

table: 1000 rows with a loop, an index and a condition
  engine     time per render   renders/s  vs abs
  abs                1.56 ms         639  baseline      █████████████
  jinja              3.87 ms         258  2.5x slower   ████████████████████████████████
  mustache           1.86 ms         537  1.2x slower   ███████████████

page: a layout composing 100 card components
  engine     time per render   renders/s  vs abs
  abs               265.8 µs       3,762  baseline      █
  jinja              8.20 ms         122  30.8x slower  ████████████████████████████████
  mustache          258.1 µs       3,874  1.0x faster   █
```

Jinja falls furthest behind on `page`, where it includes the card template
100 times per render. Mustache renders about as fast as abs.
