/// Dart words that cannot be used as generated method or parameter names.
const reservedDartNames = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
  'hashCode', 'noSuchMethod', 'runtimeType', 'toString',
};

final _identifierPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
final _directiveStartPattern = RegExp(r'<!--|\{\{|</?x-');
const _attributeSource =
    r'''[^\s=/>"']+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?''';
final _openTagPattern = RegExp('<x-([a-z-]+)((?:\\s+$_attributeSource)*)\\s*>');
final _closeTagPattern = RegExp(r'</x-([a-z-]+)\s*>');
final _attributePattern = RegExp(
  r'''([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
);
final _leadingWhitespacePattern = RegExp(r'\s*');
final _restOfBlankLinePattern = RegExp(r'[ \t]*(\r?\n|$)');
final _trailingIndentationPattern = RegExp(r'[ \t]*$');

/// A template compiled into the parameter list and body of a Dart function.
///
/// [body] holds statements that write the rendered HTML into a
/// `StringBuffer` named `$out`, using the generated `_$write` helper.
typedef CompiledTemplate = ({String parameters, String body});

/// Compiles one template [source]; [templatePath] is only used in errors.
///
/// Throws a [FormatException] with `path:line` on any invalid markup.
CompiledTemplate compileTemplate(String source, String templatePath) {
  final body = StringBuffer();
  final pendingText = StringBuffer();
  final openDirectives = <({String name, String? indexVariable, int offset})>[];
  var parameters = '';
  var position = 0;
  var indentLevel = 0;

  Never fail(String message, int offset) {
    final line = '\n'.allMatches(source.substring(0, offset)).length + 1;
    throw FormatException('$templatePath:$line: $message');
  }

  void emit(String statement) {
    body.writeln('${'  ' * indentLevel}$statement');
  }

  void flushText() {
    if (pendingText.isEmpty) return;
    emit('\$out.write(${_dartStringLiteral(pendingText.toString())});');
    pendingText.clear();
  }

  /// Returns where to continue after the tag at [tagStart]..[tagEnd].
  ///
  /// A tag alone on its line takes the whole line with it, so directives
  /// do not leave blank lines in the rendered HTML.
  int positionAfterDirectiveTag(int tagStart, int tagEnd) {
    final lineStart = source.lastIndexOf('\n', tagStart) + 1;
    final restOfLine = _restOfBlankLinePattern.matchAsPrefix(source, tagEnd);
    if (restOfLine == null ||
        source.substring(lineStart, tagStart).trim().isNotEmpty) {
      return tagEnd;
    }
    final text = pendingText.toString();
    pendingText
      ..clear()
      ..write(text.replaceFirst(_trailingIndentationPattern, ''));
    return restOfLine.end;
  }

  String requiredAttribute(
    Map<String, String?> attributes,
    String name,
    int offset,
  ) {
    final value = attributes[name]?.trim();
    if (value == null || value.isEmpty) {
      fail('missing "$name" attribute', offset);
    }
    return value;
  }

  String identifierAttribute(
    Map<String, String?> attributes,
    String name,
    int offset,
  ) {
    final value = requiredAttribute(attributes, name, offset);
    if (!_isValidName(value)) {
      fail('"$value" is not a valid Dart variable name', offset);
    }
    return value;
  }

  while (true) {
    final match = _directiveStartPattern
        .allMatches(source, position)
        .firstOrNull;
    if (match == null) {
      pendingText.write(source.substring(position));
      break;
    }
    pendingText.write(source.substring(position, match.start));
    final offset = match.start;

    switch (match[0]) {
      case '<!--':
        final end = source.indexOf('-->', match.end);
        if (end == -1) fail('unclosed HTML comment', offset);
        pendingText.write(source.substring(offset, end + 3));
        position = end + 3;

      case '{{':
        final end = source.indexOf('}}', match.end);
        if (end == -1) fail('unclosed "{{"', offset);
        final expression = source.substring(match.end, end).trim();
        if (expression.isEmpty) fail('empty "{{ }}"', offset);
        flushText();
        emit('_\$write(\$out, $expression);');
        position = end + 2;

      case '</x-':
        final tag =
            _closeTagPattern.matchAsPrefix(source, offset) ??
            fail('malformed closing tag', offset);
        if (openDirectives.lastOrNull?.name != tag[1]) {
          fail('unexpected </x-${tag[1]}>', offset);
        }
        position = positionAfterDirectiveTag(offset, tag.end);
        flushText();
        final directive = openDirectives.removeLast();
        if (directive.indexVariable case final indexVariable?) {
          emit('$indexVariable++;');
          indentLevel--;
          emit('}');
        }
        indentLevel--;
        emit('}');

      default:
        final tag =
            _openTagPattern.matchAsPrefix(source, offset) ??
            fail('malformed <x-...> tag', offset);
        final attributes = _parseAttributes(
          tag[2]!,
          (message) => fail(message, offset),
        );
        position = tag.end;

        switch (tag[1]) {
          case 'props':
            if (source.substring(0, offset).trim().isNotEmpty) {
              fail('<x-props> must be at the start of the template', offset);
            }
            final closeTag = _closeTagPattern.matchAsPrefix(
              source,
              _leadingWhitespacePattern.matchAsPrefix(source, position)!.end,
            );
            if (closeTag == null || closeTag[1] != 'props') {
              fail('<x-props> must be followed by </x-props>', offset);
            }
            final declarations = [
              for (final MapEntry(key: name, value: type) in attributes.entries)
                if (!_isValidName(name))
                  fail('"$name" is not a valid Dart parameter name', offset)
                else if (type == null || type.trim().isEmpty)
                  fail('parameter "$name" needs a type', offset)
                else if (type.trim().endsWith('?'))
                  '${type.trim()} $name'
                else
                  'required ${type.trim()} $name',
            ];
            if (declarations.isNotEmpty) {
              parameters = '{${declarations.join(', ')}}';
            }
            pendingText.clear();
            position = _leadingWhitespacePattern
                .matchAsPrefix(source, closeTag.end)!
                .end;

          case 'for':
            position = positionAfterDirectiveTag(offset, tag.end);
            flushText();
            _rejectUnknownAttributes(
              attributes,
              {'in', 'as', 'indexed', 'index-as'},
              fail,
              offset,
            );
            final iterable = requiredAttribute(attributes, 'in', offset);
            final itemVariable = identifierAttribute(attributes, 'as', offset);
            String? indexVariable;
            if (attributes.containsKey('indexed') ||
                attributes.containsKey('index-as')) {
              final start =
                  int.tryParse(
                    requiredAttribute(attributes, 'indexed', offset),
                  ) ??
                  fail('"indexed" must be an integer', offset);
              indexVariable = identifierAttribute(
                attributes,
                'index-as',
                offset,
              );
              emit('{');
              indentLevel++;
              emit('var $indexVariable = $start;');
            }
            emit('for (final $itemVariable in ($iterable)) {');
            indentLevel++;
            openDirectives.add((
              name: 'for',
              indexVariable: indexVariable,
              offset: offset,
            ));

          case 'if':
            position = positionAfterDirectiveTag(offset, tag.end);
            flushText();
            _rejectUnknownAttributes(attributes, {'case'}, fail, offset);
            final condition = requiredAttribute(attributes, 'case', offset);
            emit('if ($condition) {');
            indentLevel++;
            openDirectives.add((
              name: 'if',
              indexVariable: null,
              offset: offset,
            ));

          default:
            fail('unknown directive <x-${tag[1]}>', offset);
        }
    }
  }

  if (openDirectives.lastOrNull case final unclosed?) {
    fail('<x-${unclosed.name}> is never closed', unclosed.offset);
  }
  flushText();
  return (parameters: parameters, body: body.toString());
}

bool _isValidName(String name) =>
    _identifierPattern.hasMatch(name) && !reservedDartNames.contains(name);

Map<String, String?> _parseAttributes(
  String source,
  Never Function(String) fail,
) {
  final attributes = <String, String?>{};
  for (final match in _attributePattern.allMatches(source)) {
    final name = match[1]!;
    if (attributes.containsKey(name)) fail('duplicate attribute "$name"');
    final value = match[2] ?? match[3] ?? match[4];
    attributes[name] = value == null ? null : _decodeEntities(value);
  }
  return attributes;
}

void _rejectUnknownAttributes(
  Map<String, String?> attributes,
  Set<String> allowed,
  Never Function(String, int) fail,
  int offset,
) {
  for (final name in attributes.keys) {
    if (!allowed.contains(name)) fail('unknown attribute "$name"', offset);
  }
}

String _decodeEntities(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}
