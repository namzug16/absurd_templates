import 'dart:io';

import 'package:absurd_templates/absurd_templates.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _configFileName = 'abs.yaml';

void main(List<String> arguments) {
  try {
    final stopwatch = Stopwatch()..start();
    final config = loadYaml(File(_configFileName).readAsStringSync());
    if (config is! YamlMap) {
      throw const FormatException('$_configFileName must be a YAML map');
    }
    for (final key in config.keys) {
      if (!const {'input', 'output', 'class'}.contains(key)) {
        throw FormatException('$_configFileName: unknown key "$key"');
      }
    }
    final inputDirectory = _requiredString(config, 'input');
    final outputFile = _requiredString(config, 'output');
    final className = config['class'] ?? 'Components';
    if (className is! String) {
      throw const FormatException('$_configFileName: "class" must be a string');
    }

    final templateSourceByPath = {
      for (final entity in Directory(inputDirectory).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.html'))
          p.split(p.relative(entity.path, from: inputDirectory)).join('/'):
              entity.readAsStringSync(),
    };
    final library = generateDartLibrary(
      templateSourceByPath: templateSourceByPath,
      className: className,
    );
    File(outputFile)
      ..createSync(recursive: true)
      ..writeAsStringSync(library);
    stdout.writeln(
      'abs: generated $outputFile from ${templateSourceByPath.length} '
      'templates in ${stopwatch.elapsedMilliseconds}ms',
    );
  } on YamlException catch (error) {
    stderr.writeln('abs: $_configFileName: $error');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('abs: ${error.message}');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('abs: ${error.message}: ${error.path}');
    exitCode = 1;
  }
}

String _requiredString(YamlMap config, String key) {
  final value = config[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$_configFileName: "$key" is required');
  }
  return value;
}
