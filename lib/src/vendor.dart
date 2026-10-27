import 'dart:io';

import 'cli.dart';
import 'diagnostic.dart';
import 'vendored_source.dart';

const _defaultVendoredFile = 'tool/abs.dart';
final _vendoredHeaderPattern = RegExp(
  r'^// Absurd Templates (\d+)\.(\d+)\.(\d+), vendored by "abs vendor"\.',
);
final _checksumLinePattern = RegExp(r'^// Checksum: ([0-9a-f]{8})\.');

/// Runs `abs vendor [file.dart]`: writes the whole tool into this project as
/// one Dart file, or updates a copy that an older abs wrote.
///
/// Never overwrites a file that abs did not write, a copy that was edited by
/// hand, or a copy from a newer abs.
void vendorAbs(List<String> arguments) {
  final vendoredFile = switch (arguments) {
    [] => _defaultVendoredFile,
    [final path] when path.endsWith('.dart') => path,
    _ => throw Diagnostic(
      'usage: abs vendor [file.dart], such as "abs vendor tool/abs.dart"',
    ),
  };
  final content = vendoredFileContent(vendoredFile);
  final file = File(vendoredFile);
  if (!file.existsSync()) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    stdout.writeln(
      'abs: vendored abs $absVersion into $vendoredFile; run it with '
      '"dart run $vendoredFile", which works like abs',
    );
    return;
  }

  final existingContent = file.readAsStringSync();
  final existingLines = existingContent.split('\n');
  final version = _vendoredHeaderPattern.firstMatch(existingLines.first);
  if (version == null) {
    throw Diagnostic(
      '$vendoredFile already exists and was not written by "abs vendor", so '
      'abs will not overwrite it; vendor into another file, such as '
      '"abs vendor tool/absurd_templates.dart"',
      path: vendoredFile,
    );
  }
  final existingVersion = [version[1]!, version[2]!, version[3]!].join('.');
  if (_compareVersions(existingVersion, absVersion) > 0) {
    throw Diagnostic(
      '$vendoredFile is abs $existingVersion, newer than this abs '
      '$absVersion; update abs instead of downgrading the copy',
      path: vendoredFile,
    );
  }
  final checksum = _checksumLinePattern.firstMatch(
    existingLines.elementAtOrNull(1) ?? '',
  )?[1];
  if (checksum != _checksum(existingContent)) {
    throw Diagnostic(
      '$vendoredFile was edited after "abs vendor" wrote it, so abs will not '
      'overwrite those changes; move them out of the file, delete it and run '
      '"abs vendor" again',
      path: vendoredFile,
    );
  }
  if (existingContent == content) {
    stdout.writeln('abs: $vendoredFile is already abs $absVersion');
    return;
  }
  file.writeAsStringSync(content);
  stdout.writeln(
    'abs: updated $vendoredFile from abs $existingVersion to $absVersion',
  );
}

/// The vendored copy written to [vendoredFile]: a header, then the tool.
///
/// [version] is only for tests that need a copy from another version.
String vendoredFileContent(String vendoredFile, {String version = absVersion}) {
  final content = [
    '// Absurd Templates $version, vendored by "abs vendor". DO NOT EDIT.',
    '// Checksum: 00000000. "abs vendor" only replaces this file while it '
        'matches.',
    '// Works like abs, run where abs.yaml is: dart run $vendoredFile help',
    '// To update it, run with a newer abs: abs vendor $vendoredFile',
    '// ignore_for_file: type=lint, unused_element',
    '',
    vendoredSource,
  ].join('\n');
  return content.replaceFirst('00000000', _checksum(content));
}

/// FNV-1a hash of [content] without its checksum line or carriage returns,
/// so the checksum survives line-ending conversion by git.
String _checksum(String content) {
  final lines = content.replaceAll('\r', '').split('\n');
  if (lines.length > 1) lines.removeAt(1);
  var hash = 0x811c9dc5;
  for (final codeUnit in lines.join('\n').codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Compares two x.y.z versions like [Comparable.compareTo].
int _compareVersions(String version, String otherVersion) {
  final parts = version.split('.').map(int.parse).toList();
  final otherParts = otherVersion.split('.').map(int.parse).toList();
  for (var index = 0; index < 3; index++) {
    final comparison = parts[index].compareTo(otherParts[index]);
    if (comparison != 0) return comparison;
  }
  return 0;
}
