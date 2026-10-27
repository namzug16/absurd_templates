import 'dart:io';

import 'package:absurd_templates_benchmark/scenarios.dart';

const _warmUpDuration = Duration(milliseconds: 500);
const _measuredDuration = Duration(seconds: 2);
const _rendersBetweenClockReads = 20;
const _barWidth = 32;

void main() {
  final scenarios = loadScenarios();
  final isAheadOfTimeCompiled = const bool.fromEnvironment('dart.vm.product');
  stdout
    ..writeln()
    ..writeln('Absurd Templates vs Jinja vs Mustache')
    ..writeln(
      'Dart ${Platform.version.split(' ').first} '
      '(${isAheadOfTimeCompiled ? 'AOT' : 'JIT'}), '
      '${Platform.operatingSystem}, '
      '${_measuredDuration.inSeconds} s per engine after a '
      '${_warmUpDuration.inMilliseconds} ms warm-up',
    );

  for (final scenario in scenarios) {
    _checkEnginesAgree(scenario);
    final microsecondsByEngine = {
      for (final engineName in engineNames)
        engineName: _measureMicrosecondsPerRender(
          scenario.renderByEngine[engineName]!,
        ),
    };
    _printScenario(scenario, microsecondsByEngine);
  }
  stdout.writeln();
}

/// Stops before timing anything if an engine renders different HTML, since
/// comparing the speed of different pages would mean nothing.
void _checkEnginesAgree(Scenario scenario) {
  final expectedHtml = withoutWhitespaceBetweenTags(
    scenario.renderByEngine['abs']!(),
  );
  for (final engineName in engineNames) {
    final html = withoutWhitespaceBetweenTags(
      scenario.renderByEngine[engineName]!(),
    );
    if (html != expectedHtml) {
      stderr.writeln(
        'benchmark: "${scenario.name}" renders different HTML with '
        '$engineName than with abs; run "dart test" to see the difference',
      );
      exit(1);
    }
  }
}

double _measureMicrosecondsPerRender(String Function() render) {
  // Summing lengths keeps the compiler from skipping renders as unused.
  var renderedLength = 0;
  final warmUp = Stopwatch()..start();
  while (warmUp.elapsed < _warmUpDuration) {
    renderedLength += render().length;
  }
  var renderCount = 0;
  final measured = Stopwatch()..start();
  while (measured.elapsed < _measuredDuration) {
    for (var index = 0; index < _rendersBetweenClockReads; index++) {
      renderedLength += render().length;
    }
    renderCount += _rendersBetweenClockReads;
  }
  if (renderedLength == 0) throw StateError('nothing was rendered');
  return measured.elapsedMicroseconds / renderCount;
}

void _printScenario(
  Scenario scenario,
  Map<String, double> microsecondsByEngine,
) {
  final absMicroseconds = microsecondsByEngine['abs']!;
  final slowestMicroseconds = microsecondsByEngine.values.reduce(
    (slowest, microseconds) => microseconds > slowest ? microseconds : slowest,
  );
  stdout
    ..writeln()
    ..writeln('${scenario.name}: ${scenario.description}')
    ..writeln(
      '  ${'engine'.padRight(10)}${'time per render'.padLeft(16)}'
      '${'renders/s'.padLeft(12)}  vs abs',
    );
  for (final MapEntry(key: engineName, value: microseconds)
      in microsecondsByEngine.entries) {
    final barLength = (microseconds / slowestMicroseconds * _barWidth)
        .round()
        .clamp(1, _barWidth);
    final comparison = switch (microseconds / absMicroseconds) {
      _ when engineName == 'abs' => 'baseline',
      >= 1 && final ratio => '${ratio.toStringAsFixed(1)}x slower',
      final ratio => '${(1 / ratio).toStringAsFixed(1)}x faster',
    };
    stdout.writeln(
      '  ${engineName.padRight(10)}'
      '${_formatDuration(microseconds).padLeft(16)}'
      '${_formatThousands(1e6 / microseconds).padLeft(12)}  '
      '${comparison.padRight(14)}${'█' * barLength}',
    );
  }
}

String _formatDuration(double microseconds) => switch (microseconds) {
  < 10 => '${microseconds.toStringAsFixed(2)} µs',
  < 1000 => '${microseconds.toStringAsFixed(1)} µs',
  _ => '${(microseconds / 1000).toStringAsFixed(2)} ms',
};

String _formatThousands(double value) => value
    .round()
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
