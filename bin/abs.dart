import 'dart:io';

import 'package:absurd_templates/absurd_templates.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _configFileName = 'abs.yaml';
const _configKeys = {'input', 'output', 'class'};
const _usage = '''
Absurd Templates: compiles HTML templates into one self-contained Dart file.

Usage:
  abs                        Generate the output file configured in abs.yaml.
  abs help                   Show this message.

abs.yaml, in the directory where abs runs:
  input: components                # directory scanned for .html templates
  output: lib/generated/html.dart  # file to generate
  class: Html                      # optional, defaults to Components
''';

typedef _Project = ({
  String inputDirectory,
  String outputFile,
  String className,
  Map<String, String> templateSourceByPath,
});

Future<void> main(List<String> arguments) async {
  try {
    switch (arguments) {
      case []:
        _generate(_loadProject());
      case ['help' || '--help' || '-h']:
        stdout.write(_usage);
      default:
        throw Diagnostic(
          'unknown command "abs ${arguments.join(' ')}"; run "abs help"',
        );
    }
  } on Diagnostic catch (diagnostic) {
    stderr.writeln(diagnostic.format());
    exitCode = 1;
  }
}

void _generate(_Project project) {
  final stopwatch = Stopwatch()..start();
  final String library;
  try {
    library = generateDartLibrary(
      templateSourceByPath: project.templateSourceByPath,
      className: project.className,
      templateDirectory: project.inputDirectory,
    );
  } on Diagnostic catch (diagnostic) {
    stderr.writeln(diagnostic.format());
    exitCode = 1;
    return;
  }
  File(project.outputFile)
    ..createSync(recursive: true)
    ..writeAsStringSync(library);
  stdout.writeln(
    'abs: generated ${project.outputFile} from '
    '${project.templateSourceByPath.length} templates in '
    '${stopwatch.elapsedMilliseconds}ms',
  );
}

_Project _loadProject() {
  final configFile = File(_configFileName);
  if (!configFile.existsSync()) {
    throw Diagnostic(
      '$_configFileName not found in ${Directory.current.path}; run abs '
      'from the directory that contains it, or create it (see "abs help")',
    );
  }
  final configSource = configFile.readAsStringSync();

  Diagnostic configError(String message, [YamlNode? node]) {
    final start = node?.span.start;
    return Diagnostic(
      message,
      path: _configFileName,
      line: start == null ? null : start.line + 1,
      column: start == null ? null : start.column + 1,
      lineText: start == null
          ? null
          : configSource.split('\n').elementAtOrNull(start.line),
    );
  }

  final YamlNode config;
  try {
    config = loadYamlNode(configSource);
  } on YamlException catch (error) {
    final start = error.span?.start;
    throw Diagnostic(
      'invalid YAML: ${error.message}',
      path: _configFileName,
      line: start == null ? null : start.line + 1,
      column: start == null ? null : start.column + 1,
      lineText: start == null
          ? null
          : configSource.split('\n').elementAtOrNull(start.line),
    );
  }
  final configMap = config is YamlMap
      ? config
      : throw configError(
          'must be a map with "input" and "output" keys (see "abs help")',
        );
  for (final key in configMap.nodes.keys.cast<YamlNode>()) {
    if (!_configKeys.contains(key.value)) {
      throw configError(
        'unknown key "${key.value}"; supported keys: ${_configKeys.join(', ')}',
        key,
      );
    }
  }

  String stringValue(String key, {String? defaultValue}) {
    final node = configMap.nodes[key];
    final value = node?.value ?? defaultValue;
    if (value is! String || value.isEmpty) {
      throw configError(
        node == null
            ? '"$key" is required (see "abs help")'
            : '"$key" must be a non-empty string',
        node ?? configMap,
      );
    }
    return value;
  }

  final inputDirectory = p.normalize(stringValue('input'));
  final outputFile = stringValue('output');
  final className = stringValue('class', defaultValue: 'Components');
  if (!Directory(inputDirectory).existsSync()) {
    throw configError(
      'input directory "$inputDirectory" does not exist',
      configMap.nodes['input'],
    );
  }
  return (
    inputDirectory: inputDirectory,
    outputFile: outputFile,
    className: className,
    templateSourceByPath: {
      for (final entity in Directory(inputDirectory).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.html'))
          p.split(p.relative(entity.path, from: inputDirectory)).join('/'):
              entity.readAsStringSync(),
    },
  );
}
