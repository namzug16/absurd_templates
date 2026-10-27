import 'dart:io';

import 'package:test/test.dart';

final _absScript = File('bin/abs.dart').absolute.path;
final _packageConfig = File('.dart_tool/package_config.json').absolute.path;

Future<ProcessResult> _runAbs(
  Directory projectDirectory, [
  List<String> arguments = const [],
]) => Process.run(Platform.resolvedExecutable, [
  '--packages=$_packageConfig',
  _absScript,
  ...arguments,
], workingDirectory: projectDirectory.path);

void main() {
  late Directory projectDirectory;

  setUp(() async {
    projectDirectory = await Directory.systemTemp.createTemp('abs_cli_');
    addTearDown(() => projectDirectory.delete(recursive: true));
  });

  void writeProjectFile(String path, String contents) {
    File('${projectDirectory.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  test('generates the configured output file', () async {
    writeProjectFile('abs.yaml', '''
input: components
output: lib/generated/html.dart
class: Html
''');
    writeProjectFile('components/layout/primary.html', '''
<x-props title="String" content="Fragment"></x-props>
<title>{{ title }}</title><main>{{ content }}</main>''');
    writeProjectFile('components/notes.txt', 'ignored');

    final result = await _runAbs(projectDirectory);

    expect(result.stderr, '');
    expect(result.exitCode, 0);
    expect(result.stdout, contains('generated lib/generated/html.dart'));
    final library = File(
      '${projectDirectory.path}/lib/generated/html.dart',
    ).readAsStringSync();
    expect(library, contains('abstract final class Html {'));
    expect(library, contains('static const layout = _Html\$layout();'));
  });

  test('defaults the class name to Components', () async {
    writeProjectFile('abs.yaml', 'input: components\noutput: out.dart\n');
    writeProjectFile('components/header.html', '<header></header>');

    final result = await _runAbs(projectDirectory);

    expect(result.exitCode, 0);
    expect(
      File('${projectDirectory.path}/out.dart').readAsStringSync(),
      contains('abstract final class Components {'),
    );
  });

  test('reports errors and exits with 1', () async {
    writeProjectFile('abs.yaml', 'input: components\n');

    final result = await _runAbs(projectDirectory);

    expect(result.exitCode, 1);
    expect(result.stderr, '''
error: "output" is required (see "abs help")
  --> abs.yaml:1:1
  |
1 | input: components
  | ^
''');
  });

  test('committed examples/generated/html.dart is up to date', () async {
    final generatedFile = File('examples/generated/html.dart');
    final committedLibrary = generatedFile.readAsStringSync();

    final result = await _runAbs(Directory('examples'));

    expect(result.exitCode, 0);
    expect(
      generatedFile.readAsStringSync(),
      committedLibrary,
      reason: 'run abs in examples/ and commit the result',
    );
  });

  group('abs check', () {
    setUp(() {
      writeProjectFile('abs.yaml', 'input: components\noutput: out.dart\n');
      writeProjectFile(
        'components/ok.html',
        '<x-props name="String"></x-props>{{ name }}',
      );
    });

    test('maps Dart errors back to the template line', () async {
      writeProjectFile('components/broken.html', '''
<x-props
  name="Strng"
  users="List&lt;({String name})>"
></x-props>
<x-for in="users" as="user">
  <li>{{ user.nmae }}</li>
</x-for>
''');

      final result = await _runAbs(projectDirectory, ['check']);

      expect(result.exitCode, 1);
      expect(
        result.stdout,
        contains('''
error: Undefined class 'Strng'.
  --> components/broken.html:2:9
  |
2 |   name="Strng"
  |         ^
'''),
      );
      expect(
        result.stdout,
        contains('''
  --> components/broken.html:6:10
  |
6 |   <li>{{ user.nmae }}</li>
  |          ^
'''),
      );
      expect(
        result.stdout,
        endsWith('2 errors and 0 warnings in 2 templates\n'),
      );
      expect(File('${projectDirectory.path}/out.dart').existsSync(), isFalse);
    });

    test('checks only the given files', () async {
      writeProjectFile('components/broken.html', '{{ missing }}');

      final result = await _runAbs(projectDirectory, [
        'check',
        'components/ok.html',
      ]);

      expect(result.stdout, 'abs check: 1 template OK\n');
      expect(result.exitCode, 0);
    });

    test('rejects files outside the input directory', () async {
      final result = await _runAbs(projectDirectory, ['check', 'other.html']);

      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('"other.html" is not inside the input directory "components"'),
      );
    });
  });
}
