final _nonTabPattern = RegExp(r'[^\t]');

/// An error or warning, optionally pointing at a line of a file.
///
/// Thrown as an exception by the compiler; [format] renders it as:
///
/// ```text
/// error: <message>
///   --> components/pages/users.html:12:27
///    |
/// 12 |         <li>{{ user.nmae }}</li>
///    |                ^
/// ```
final class Diagnostic implements Exception {
  const Diagnostic(
    this.message, {
    this.severity = 'error',
    this.path,
    this.line,
    this.column,
    this.lineText,
  });

  final String message;
  final String severity;
  final String? path;
  final int? line;
  final int? column;
  final String? lineText;

  bool get isError => severity == 'error';

  String format() {
    final output = StringBuffer('$severity: $message');
    if (path != null) output.write('\n  --> $path');
    if (line != null) output.write(':$line:$column');
    if (lineText case final lineText? when line != null && column != null) {
      final gutter = ' ' * '$line'.length;
      final caretIndentation = lineText
          .substring(0, (column! - 1).clamp(0, lineText.length))
          .replaceAll(_nonTabPattern, ' ');
      output
        ..write('\n$gutter |')
        ..write('\n$line | $lineText')
        ..write('\n$gutter | $caretIndentation^');
    }
    return output.toString();
  }

  @override
  String toString() => format();
}
