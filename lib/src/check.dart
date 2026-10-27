import 'dart:io';

import 'diagnostic.dart';
import 'generator.dart';
import 'template.dart';

final _sourceMarkerPattern = RegExp(r'// (.+\.html):(\d+):(\d+)$');

/// Checks the templates at [checkedTemplatePaths] for syntax errors and Dart
/// errors (types, undefined names...), and all of [templateSourceByPath] for
/// naming conflicts. Writes nothing; returns every problem found.
///
/// Paths are relative to [templateDirectory], as in [generateDartLibrary].
Future<List<Diagnostic>> checkTemplates({
  required Map<String, String> templateSourceByPath,
  required Iterable<String> checkedTemplatePaths,
  required String className,
  String templateDirectory = '',
}) async {
  final diagnostics = <Diagnostic>[];
  var namesAreValid = true;
  try {
    checkTemplateNames(
      templatePaths: templateSourceByPath.keys,
      className: className,
      templateDirectory: templateDirectory,
    );
  } on Diagnostic catch (diagnostic) {
    diagnostics.add(diagnostic);
    namesAreValid = false;
  }

  final compilableSourceByPath = <String, String>{};
  for (final templatePath in checkedTemplatePaths) {
    final source = templateSourceByPath[templatePath]!;
    try {
      compileTemplate(
        source,
        displayTemplatePath(templateDirectory, templatePath),
      );
      compilableSourceByPath[templatePath] = source;
    } on Diagnostic catch (diagnostic) {
      diagnostics.add(diagnostic);
    }
  }

  if (namesAreValid && compilableSourceByPath.isNotEmpty) {
    diagnostics.addAll(
      await _analyzeGeneratedLibrary(
        generateDartLibrary(
          templateSourceByPath: compilableSourceByPath,
          className: className,
          templateDirectory: templateDirectory,
        ),
        {
          for (final MapEntry(key: templatePath, value: source)
              in compilableSourceByPath.entries)
            displayTemplatePath(templateDirectory, templatePath): source,
        },
      ),
    );
  }
  return diagnostics;
}

/// Runs `dart analyze` on [library] and maps each error and warning back to
/// the template line named by the nearest source marker.
Future<List<Diagnostic>> _analyzeGeneratedLibrary(
  String library,
  Map<String, String> templateSourceByDisplayPath,
) async {
  final directory = await Directory.systemTemp.createTemp('abs_check_');
  try {
    final libraryFile = File('${directory.path}/check.dart')
      ..writeAsStringSync(library);
    final ProcessResult result;
    try {
      result = await Process.run('dart', [
        'analyze',
        '--format=machine',
        libraryFile.path,
      ]);
    } on ProcessException catch (error) {
      return [
        Diagnostic(
          'could not run "dart analyze" to type-check templates '
          '(${error.message}); make sure "dart" is on your PATH',
        ),
      ];
    }
    final generatedLines = library.split('\n');
    return [
      for (final outputLine in '${result.stdout}\n${result.stderr}'.split('\n'))
        if (outputLine.split('|') case [
          final severity && ('ERROR' || 'WARNING'),
          _,
          _,
          _,
          final generatedLineNumber,
          _,
          _,
          ...final messageParts,
        ])
          _mapToTemplate(
            message: messageParts.join('|'),
            severity: severity.toLowerCase(),
            generatedLineNumber: int.parse(generatedLineNumber),
            generatedLines: generatedLines,
            templateSourceByDisplayPath: templateSourceByDisplayPath,
          ),
    ];
  } finally {
    await directory.delete(recursive: true);
  }
}

Diagnostic _mapToTemplate({
  required String message,
  required String severity,
  required int generatedLineNumber,
  required List<String> generatedLines,
  required Map<String, String> templateSourceByDisplayPath,
}) {
  // A statement's marker sits on its last line, at or below the error.
  for (
    var index = generatedLineNumber - 1;
    index < generatedLines.length;
    index++
  ) {
    final marker = _sourceMarkerPattern.firstMatch(generatedLines[index]);
    if (marker == null) continue;
    final path = marker[1]!;
    final line = int.parse(marker[2]!);
    return Diagnostic(
      message,
      severity: severity,
      path: path,
      line: line,
      column: int.parse(marker[3]!),
      lineText: templateSourceByDisplayPath[path]
          ?.split('\n')
          .elementAtOrNull(line - 1)
          ?.trimRight(),
    );
  }
  return Diagnostic(
    '$message (at line $generatedLineNumber of the generated code, outside '
    'any template; this is likely a bug in abs)',
    severity: severity,
  );
}
