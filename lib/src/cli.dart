import 'dart:convert';
import 'dart:io';

import 'check.dart';
import 'diagnostic.dart';
import 'generator.dart';

const _configFileName = 'abs.yaml';
const _configKeys = {'input', 'output', 'class'};

/// A top-level `key: value` line of abs.yaml: the value is double-quoted,
/// single-quoted or plain text, optionally followed by a `# comment`.
final _configLinePattern = RegExp(
  r"""^([A-Za-z_][\w-]*):"""
  r"""(?:[ \t]+(?:"([^"]*)"|'([^']*)'|([^\s#"'\[\]{}&*!|>%@`](?:[^#]|(?<=\S)#)*?)))?"""
  r"""(?:[ \t]+#.*)?[ \t]*$""",
);

/// Version of abs; keep it equal to the version in pubspec.yaml.
const absVersion = '0.1.0';

/// The help text; [canVendor] is false in a vendored copy.
String _usage({required bool canVendor}) =>
    '''
Absurd Templates $absVersion: compiles HTML templates into one self-contained Dart file.

Usage:
  abs                        Generate the output file configured in abs.yaml.
  abs check [file.html ...]  Check templates without writing anything: syntax,
                             naming conflicts and Dart errors (types, undefined
                             names). Checks every template when no file is
                             given. Exits with 1 when there are errors.
  abs init                   Create a commented abs.yaml in this directory.
${canVendor ? _vendorUsage : ''}  abs version                Print the version of abs.
  abs help                   Show this message.

abs.yaml, in the directory where abs runs:
  input: fragments                 # directory scanned for .html templates
  output: lib/generated/html.dart  # file to generate
  class: Html                      # optional, defaults to Fragments
''';

const _initialConfig = '''
# Absurd Templates configuration. abs reads this file from the directory it
# runs in.
#
#   abs                    generate the Dart file below from the templates
#   abs check [file.html]  check templates for errors without writing anything
#   abs help               list every command

# Required. Directory scanned recursively for .html templates. Each file
# becomes a method and each subdirectory a namespace, in camelCase:
#   fragments/header.html           -> Fragments.header()
#   fragments/pages/user-page.html  -> Fragments.pages.userPage(...)
input: fragments

# Required. The one self-contained Dart file to generate, including the
# Fragment type, so no runtime package is needed. abs only overwrites files
# it generated itself.
output: lib/generated/html.dart

# Optional. Name of the generated entry class. Defaults to Fragments.
# class: Html
''';

typedef _Project = ({
  String inputDirectory,
  String outputFile,
  String className,
  Map<String, String> templateSourceByPath,
});

const _vendorUsage = '''
  abs vendor [file.dart]     Copy abs into this project as one Dart file with
                             no dependencies, tool/abs.dart by default; run it
                             with "dart run tool/abs.dart". Run it again with
                             a newer abs to update the copy.
''';

/// Runs the abs command line with [arguments]. [vendor] runs `abs vendor`;
/// a vendored copy has none.
Future<void> runAbs(
  List<String> arguments, {
  void Function(List<String> arguments)? vendor,
}) async {
  try {
    switch (arguments) {
      case []:
        _generate(_loadProject());
      case ['check', ...final files]:
        exitCode = await _check(_loadProject(), files);
      case ['init']:
        _init();
      case ['vendor', ...final vendorArguments]:
        if (vendor == null) {
          throw Diagnostic(
            'this is a vendored copy of abs $absVersion, which cannot vendor '
            'itself; to update it, run "abs vendor" with an installed abs',
          );
        }
        vendor(vendorArguments);
      case ['version' || '--version']:
        stdout.writeln(absVersion);
      case ['help' || '--help' || '-h']:
        stdout.write(_usage(canVendor: vendor != null));
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

void _init() {
  final configFile = File(_configFileName);
  if (configFile.existsSync()) {
    throw Diagnostic(
      '$_configFileName already exists in ${Directory.current.path}; '
      'abs init does not overwrite it',
      path: _configFileName,
    );
  }
  configFile.writeAsStringSync(_initialConfig);
  stdout.writeln(
    'abs: created $_configFileName; put your .html templates in fragments/ '
    'and run abs',
  );
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
  final outputFile = File(project.outputFile);
  if (outputFile.existsSync() && !_startsWithGeneratedHeader(outputFile)) {
    throw Diagnostic(
      '${project.outputFile} already exists and was not generated by abs, so '
      'abs will not overwrite it; point "output" in $_configFileName at '
      'another file, or delete this one if it really should be replaced',
      path: project.outputFile,
    );
  }
  // Leaving an unchanged file alone keeps watchers from rebuilding.
  final isUnchanged =
      outputFile.existsSync() && outputFile.readAsStringSync() == library;
  if (!isUnchanged) {
    outputFile
      ..createSync(recursive: true)
      ..writeAsStringSync(library);
  }
  stdout.writeln(
    'abs: ${isUnchanged ? 'unchanged' : 'generated'} ${project.outputFile} '
    'from ${project.templateSourceByPath.length} templates in '
    '${stopwatch.elapsedMilliseconds}ms',
  );
}

bool _startsWithGeneratedHeader(File file) {
  final handle = file.openSync();
  try {
    // Bytes, not text, so a binary file cannot fail to decode.
    final header = handle.readSync(generatedFileHeader.length);
    return utf8.decode(header, allowMalformed: true) == generatedFileHeader;
  } finally {
    handle.closeSync();
  }
}

Future<int> _check(_Project project, List<String> files) async {
  final checkedTemplatePaths = files.isEmpty
      ? project.templateSourceByPath.keys.toList()
      : {for (final file in files) _templatePathOf(project, file)}.toList();
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
  if (!file.endsWith('.html')) {
    throw Diagnostic('"$file" is not a template: templates end with .html');
  }
  final absoluteInputDirectory = Directory.current.uri
      .resolveUri(Uri.directory(project.inputDirectory))
      .toFilePath();
  final absoluteFile = Directory.current.uri
      .resolveUri(Uri.file(file))
      .toFilePath();
  if (!absoluteFile.startsWith(absoluteInputDirectory)) {
    throw Diagnostic(
      '"$file" is not inside the input directory "${project.inputDirectory}" '
      'configured in $_configFileName',
    );
  }
  final templatePath = _toTemplatePath(
    absoluteFile.substring(absoluteInputDirectory.length),
  );
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
  final configLines = configFile.readAsStringSync().split('\n');

  Diagnostic configError(String message, {int lineIndex = 0}) => Diagnostic(
    message,
    path: _configFileName,
    line: lineIndex + 1,
    column: 1,
    lineText: configLines[lineIndex].trimRight(),
  );

  final valueByKey = <String, ({String value, int lineIndex})>{};
  for (final (lineIndex, line) in configLines.indexed) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) continue;
    final match =
        _configLinePattern.firstMatch(line.trimRight()) ??
        (throw configError(
          'expected a "key: value" line; $_configFileName only holds '
          'top-level keys with plain or quoted text values',
          lineIndex: lineIndex,
        ));
    final key = match[1]!;
    if (!_configKeys.contains(key)) {
      throw configError(
        'unknown key "$key"; supported keys: ${_configKeys.join(', ')}',
        lineIndex: lineIndex,
      );
    }
    if (valueByKey.containsKey(key)) {
      throw configError('"$key" is set twice', lineIndex: lineIndex);
    }
    valueByKey[key] = (
      value: match[2] ?? match[3] ?? match[4] ?? '',
      lineIndex: lineIndex,
    );
  }

  String stringValue(String key, {String? defaultValue}) {
    final entry = valueByKey[key];
    // The default only applies when the key is absent, not when it is empty.
    final value = entry == null ? defaultValue : entry.value;
    if (value == null || value.isEmpty) {
      throw configError(
        entry == null
            ? '"$key" is required (see "abs help")'
            : '"$key" must be a non-empty string',
        lineIndex: entry?.lineIndex ?? 0,
      );
    }
    return value;
  }

  final inputDirectory = _normalizeDirectory(stringValue('input'));
  final outputFile = stringValue('output');
  final className = stringValue('class', defaultValue: 'Fragments');
  if (!Directory(inputDirectory).existsSync()) {
    throw configError(
      'input directory "$inputDirectory" does not exist',
      lineIndex: valueByKey['input']!.lineIndex,
    );
  }
  return (
    inputDirectory: inputDirectory,
    outputFile: outputFile,
    className: className,
    templateSourceByPath: {
      for (final entity in Directory(inputDirectory).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.html'))
          _toTemplatePath(entity.path.substring(inputDirectory.length + 1)):
              entity.readAsStringSync(),
    },
  );
}

/// [path] relative to the input directory, with "/" as separator on every
/// platform.
String _toTemplatePath(String path) =>
    path.split(Platform.pathSeparator).join('/');

/// [directory] without "." and ".." segments or a trailing separator, such
/// as "fragments" for "./fragments/".
String _normalizeDirectory(String directory) {
  final normalized = Uri.directory(directory).normalizePath().toFilePath();
  return normalized.length > 1 && normalized.endsWith(Platform.pathSeparator)
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}
