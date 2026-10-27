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
  abs check [file.html ...]  Check templates without writing anything: syntax,
                             naming conflicts and Dart errors (types, undefined
                             names). Checks every template when no file is
                             given. Exits with 1 when there are errors.
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
      case ['check', ...final files]:
        exitCode = await _check(_loadProject(), files);
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
    stderr
      ..writeln(diagnostic.format())
      ..writeln()
      ..writeln(
        'abs: nothing was generated; run "abs check" to list every problem',
      );
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

Future<int> _check(_Project project, List<String> files) async {
  final checkedTemplatePaths = files.isEmpty
      ? project.templateSourceByPath.keys.toList()
      : [for (final file in files) _templatePathOf(project, file)];
  final diagnostics = await checkTemplates(
    templateSourceByPath: project.templateSourceByPath,
    checkedTemplatePaths: checkedTemplatePaths,
    className: project.className,
    templateDirectory: project.inputDirectory,
  );
  for (final diagnostic in diagnostics) {
    stdout
      ..writeln(diagnostic.format())
      ..writeln();
  }
  final errorCount = diagnostics.where((d) => d.isError).length;
  final warningCount = diagnostics.length - errorCount;
  final templates = _plural(checkedTemplatePaths.length, 'template');
  stdout.writeln(
    diagnostics.isEmpty
        ? 'abs check: $templates OK'
        : 'abs check: ${_plural(errorCount, 'error')} and '
              '${_plural(warningCount, 'warning')} in $templates',
  );
  return errorCount == 0 ? 0 : 1;
}

String _plural(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

/// Converts a template file path given on the command line into its path
/// relative to the input directory.
String _templatePathOf(_Project project, String file) {
  final absoluteInputDirectory = p.absolute(project.inputDirectory);
  final absoluteFile = p.absolute(file);
  if (!file.endsWith('.html')) {
    throw Diagnostic('"$file" is not a template: templates end with .html');
  }
  if (!p.isWithin(absoluteInputDirectory, absoluteFile)) {
    throw Diagnostic(
      '"$file" is not inside the input directory "${project.inputDirectory}" '
      'configured in $_configFileName',
    );
  }
  final templatePath = p
      .split(p.relative(absoluteFile, from: absoluteInputDirectory))
      .join('/');
  if (!project.templateSourceByPath.containsKey(templatePath)) {
    throw Diagnostic('"$file" does not exist');
  }
  return templatePath;
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
