import 'dart:math';

import 'diagnostic.dart';

/// Dart words that cannot be used as generated method or parameter names.
const reservedDartNames = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
  'hashCode', 'noSuchMethod', 'runtimeType', 'toString',
};

final _identifierPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
// A variable followed by fields: user, user.name, pair.$1.
final _valuePathPattern = RegExp(
  r'^[a-zA-Z][a-zA-Z0-9_]*(?:\.(?:[a-zA-Z_][a-zA-Z0-9_]*|\$[0-9]+))*$',
);
// A lone "<" starts an HTML tag, which may hold ?condition:attribute.
final _directiveStartPattern = RegExp(r'<!--|\{\{|</?x-|<(?=[a-zA-Z])');
const _attributeSource =
    r'''[^\s=/>"']+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?''';
final _openTagPattern = RegExp(
  '<x-([a-z-]+)((?:\\s+$_attributeSource)*)\\s*(/?)>',
);
final _closeTagPattern = RegExp(r'</x-([a-z-]+)\s*>');
final _htmlTagNamePattern = RegExp(r'<[a-zA-Z][^\s/>]*');
final _directiveInsideTagPattern = RegExp(r'</?x-[a-z-]*');
// Elements whose content is code, where a "<" never starts a tag.
final _rawTextClosingTagPattern = RegExp(
  r'</(script|style)\b',
  caseSensitive: false,
);
final _rawTextOpeningTagNamePattern = RegExp(
  r'^<(script|style)$',
  caseSensitive: false,
);
final _conditionalAttributeNamePattern = RegExp(r'^\?(!?)([^:!]+):(.+)$');
// ...attributes or ?condition:...attributes.
final _spreadAttributeNamePattern = RegExp(r'^(?:\?!?[^:!]+:)?\.\.\.');
// A spread starting a word, like the one in "<p>...attributes</p>".
final _spreadInTextPattern = RegExp(
  r'(?<![^\s>])\.\.\.([a-zA-Z][a-zA-Z0-9_]*)(?:\.(?:[a-zA-Z_][a-zA-Z0-9_]*|\$[0-9]+))*',
);
final _attributePattern = RegExp(
  r'''([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
);
final _wholeInterpolationPattern = RegExp(r'^\{\{(.*)\}\}$');
final _htmlEntityPattern = RegExp(
  r'&(?:[a-zA-Z][a-zA-Z0-9]*|#[0-9]+|#[xX][0-9a-fA-F]+);',
);
final _leadingWhitespacePattern = RegExp(r'\s*');
final _restOfBlankLinePattern = RegExp(r'[ \t]*(\r?\n|$)');
final _trailingIndentationPattern = RegExp(r'[ \t]*$');

/// A template compiled into the parameter list and body of a Dart function.
///
/// [body] holds statements that write the rendered HTML into a
/// `StringBuffer` named `$out`, using the generated `_$write` helper.
/// Statements with user code end in a `// path:line:column` comment pointing
/// back at the template, so Dart errors can be traced to their source.
///
/// Each `<x-slot>` inside a `<x-fragment>` becomes a `Fragment._` closure
/// passed as the prop it names.
///
/// [renderedFragments] lists every `<x-fragment>` in the template, so the
/// generator can reject templates that render each other in a cycle.
typedef CompiledTemplate = ({
  String parameters,
  String body,
  List<RenderedFragment> renderedFragments,
});

/// A `<x-fragment>` tag: the template it renders, relative to the input
/// directory, and where the tag is.
typedef RenderedFragment = ({
  String templatePath,
  int line,
  int column,
  String lineText,
});

typedef _Attribute = ({String? value, int offset});

const _forUsage =
    '<x-for in="items" as="item"> or '
    '<x-for in="items" as="item" index-from="1" index-as="position">';
const _ifUsage = '<x-if case="condition">';
const _ifNotUsage = '<x-if-not case="condition">';
const _fragmentUsage = '<x-fragment template="/ui/label.html" text="Users" />';
const _slotUsage =
    '<x-fragment template="/layout/primary.html"><x-slot name="content">...</x-slot>'
    '</x-fragment>';
const _conditionalAttributeUsage =
    '?isDisabled:disabled, ?isActive:class="active" or ?!isActive:class="idle"';
const _spreadAttributeUsage =
    '...extraAttributes or ?isSelected:...selectedAttributes';
const _interpolationInTagUsage =
    '{{ }} inside an HTML tag only goes in a quoted attribute value, like '
    'title="{{ title }}"; pass extra attributes as a map, like '
    '$_spreadAttributeUsage';
const _nameRules =
    'use a Dart identifier that starts with a letter, contains only '
    'letters, digits and "_", and is not a reserved word';

/// Compiles one template [source]. [templatePath] is used in diagnostics and
/// source markers.
///
/// [accessPathByTemplatePath] maps every template path, relative to the input
/// directory, to the Dart expression that calls it, such as `Html.ui.label`;
/// `<x-fragment>` tags are resolved against it. Null skips resolving them,
/// for checking syntax when template names conflict.
///
/// [propNamesByTemplatePath], from [propNamesOfTemplates], lets
/// `<x-fragment>` reject props the rendered template does not declare.
///
/// Throws a [Diagnostic] pointing at the offending line on invalid markup.
CompiledTemplate compileTemplate(
  String source,
  String templatePath, {
  Map<String, String>? accessPathByTemplatePath,
  Map<String, Set<String>> propNamesByTemplatePath = const {},
}) {
  final body = StringBuffer();
  final renderedFragments = <RenderedFragment>[];
  final pendingText = StringBuffer();
  final openDirectives =
      <({String name, String? indexVariable, int offset, int variableCount})>[];
  // The template each open <x-fragment> renders and the prop names already
  // passed to it, innermost last.
  final openFragments =
      <({String templatePath, Set<String> passedPropNames})>[];
  // Props, then the variables of each enclosing <x-for>, innermost last.
  final variablesInScope = <String>[];
  final lineStartOffsets = [0, for (final m in '\n'.allMatches(source)) m.end];
  var parameters = '';
  var position = 0;
  var indentLevel = 0;
  // Where the content of the current <script> or <style> ends.
  var rawTextEnd = 0;
  // Numbers each tag's set of attribute names, so their variables differ.
  var spreadTagCount = 0;

  ({int line, int column, String lineText}) locate(int offset) {
    final lineIndex = lineStartOffsets.lastIndexWhere((s) => s <= offset);
    final lineStart = lineStartOffsets[lineIndex];
    final lineEnd = lineIndex + 1 < lineStartOffsets.length
        ? lineStartOffsets[lineIndex + 1] - 1
        : source.length;
    return (
      line: lineIndex + 1,
      column: offset - lineStart + 1,
      lineText: source.substring(lineStart, lineEnd).trimRight(),
    );
  }

  Never fail(String message, int offset) {
    final location = locate(offset);
    throw Diagnostic(
      message,
      path: templatePath,
      line: location.line,
      column: location.column,
      lineText: location.lineText,
    );
  }

  String sourceMarker(int offset) {
    final location = locate(offset);
    return '// $templatePath:${location.line}:${location.column}';
  }

  void emit(String statement, {int? sourceOffset}) {
    final marker = sourceOffset == null ? '' : ' ${sourceMarker(sourceOffset)}';
    body.writeln('${'  ' * indentLevel}$statement$marker');
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

  /// Fails unless [value] is a declared variable, optionally followed by
  /// fields; templates hold no other logic.
  void requireValuePath(String value, int offset, String where) {
    if (!_valuePathPattern.hasMatch(value)) {
      fail(
        '$where only accepts a variable or its fields, like user or '
        'user.name, got "$value"; compute anything else in Dart and pass it '
        'in as a prop',
        offset,
      );
    }
    final variable = value.split('.').first;
    if (!variablesInScope.contains(variable)) {
      fail(
        '"$variable" is not declared; '
        '${_didYouMean(variable, variablesInScope)}declare it in <x-props> '
        'or as an <x-for> variable. '
        '${variablesInScope.isEmpty ? 'Nothing is declared here' : 'Declared here: ${variablesInScope.toSet().join(', ')}'}',
        offset,
      );
    }
  }

  void rejectUnknownAttributes(
    Map<String, _Attribute> attributes,
    String directive,
    List<String> supported,
  ) {
    for (final MapEntry(key: name, value: attribute) in attributes.entries) {
      if (!supported.contains(name)) {
        fail(
          '<x-$directive> does not support the "$name" attribute; '
          'supported attributes: ${supported.join(', ')}',
          attribute.offset,
        );
      }
    }
  }

  ({String value, int offset}) requiredAttribute(
    Map<String, _Attribute> attributes,
    String name, {
    required String directive,
    required String usage,
    required int tagOffset,
  }) {
    final attribute = attributes[name];
    final value = attribute?.value?.trim();
    if (value == null || value.isEmpty) {
      fail(
        '<x-$directive> needs a non-empty "$name" attribute; usage: $usage',
        attribute?.offset ?? tagOffset,
      );
    }
    return (value: value, offset: attribute!.offset);
  }

  String variableAttribute(
    Map<String, _Attribute> attributes,
    String name, {
    required int tagOffset,
  }) {
    final attribute = requiredAttribute(
      attributes,
      name,
      directive: 'for',
      usage: _forUsage,
      tagOffset: tagOffset,
    );
    if (!_isValidName(attribute.value)) {
      fail(
        '"${attribute.value}" is not a valid variable name for "$name"; '
        '$_nameRules',
        attribute.offset,
      );
    }
    return attribute.value;
  }

  /// Fails when the template at [renderedTemplatePath] has no [propName]
  /// prop. Templates whose props are unknown are left to the Dart analyzer.
  void requireDeclaredProp(
    String renderedTemplatePath,
    String propName,
    int offset,
  ) {
    final propNames = propNamesByTemplatePath[renderedTemplatePath];
    if (propNames == null || propNames.contains(propName)) return;
    fail(
      '/$renderedTemplatePath has no prop "$propName"; '
      '${_didYouMean(propName, propNames)}'
      '${propNames.isEmpty ? 'it takes no props' : 'its props are ${propNames.join(', ')}'}',
      offset,
    );
  }

  /// The Dart value passed for the [name] prop of the `<x-fragment>` that
  /// renders [renderedTemplatePath]: a string literal, or the variable in
  /// `{{ }}` as it is.
  String fragmentArgument(
    String renderedTemplatePath,
    String name,
    _Attribute attribute,
  ) {
    if (!_isValidName(name)) {
      fail('"$name" is not a valid prop name; $_nameRules', attribute.offset);
    }
    requireDeclaredProp(renderedTemplatePath, name, attribute.offset);
    final value =
        attribute.value ??
        fail(
          'prop "$name" needs a value, like $name="text" or '
          '$name="{{ variable }}"',
          attribute.offset,
        );
    if (_wholeInterpolationPattern.firstMatch(value) case final match?) {
      final expression = match[1]!.trim();
      final expressionOffset =
          attribute.offset + value.indexOf(expression, '{{'.length);
      requireValuePath(expression, expressionOffset, '"{{ }}"');
      return expression;
    }
    if (value.contains('{{') || value.contains('}}')) {
      fail(
        'prop "$name" must be plain text or exactly one quoted {{ }}, like '
        '$name="{{ variable }}"; build mixed text in Dart and pass it in',
        attribute.offset,
      );
    }
    if (_htmlEntityPattern.firstMatch(value) case final entity?) {
      fail(
        'write "${entity[0]}" in prop "$name" as the plain character; HTML '
        'entities are not decoded and would be escaped again',
        attribute.offset + entity.start,
      );
    }
    return _dartStringLiteral(value);
  }

  /// Compiles the `{{ }}` at [offset], which must close before [limit],
  /// and returns where it ends.
  int writeInterpolation(int offset, int limit) {
    final expressionStart = offset + '{{'.length;
    final end = source.indexOf('}}', expressionStart);
    if (end == -1 || end + '}}'.length > limit) {
      fail('"{{" is never closed with "}}"', offset);
    }
    final expression = source.substring(expressionStart, end).trim();
    if (expression.isEmpty) {
      fail('"{{ }}" is empty; put a variable inside, e.g. {{ title }}', offset);
    }
    final expressionOffset = source.indexOf(expression, expressionStart);
    requireValuePath(expression, expressionOffset, '"{{ }}"');
    flushText();
    emit('_\$write(\$out, $expression);', sourceOffset: expressionOffset);
    return end + '}}'.length;
  }

  /// Writes the source from [start] to [end] as text, compiling its `{{ }}`.
  void writeTextWithInterpolations(int start, int end) {
    var position = start;
    while (true) {
      final interpolationStart = source.indexOf('{{', position);
      if (interpolationStart == -1 || interpolationStart >= end) break;
      pendingText.write(source.substring(position, interpolationStart));
      position = writeInterpolation(interpolationStart, end);
    }
    pendingText.write(source.substring(position, end));
  }

  /// Returns where the HTML tag at [tagStart] ends, or null when the "<" does
  /// not start a tag, like `a<b` in text.
  int? htmlTagEnd(int tagStart) {
    String? openQuote;
    for (var index = tagStart + 1; index < source.length; index++) {
      final character = source[index];
      if (openQuote != null) {
        if (character == openQuote) openQuote = null;
      } else if (character == '"' || character == "'") {
        openQuote = character;
      } else if (character == '>') {
        return index + 1;
      } else if (character == '<') {
        if (_directiveInsideTagPattern.matchAsPrefix(source, index)
            case final directive?) {
          fail(
            '${directive[0]}> cannot go inside an HTML tag, it would make '
            'invalid HTML; make the attribute conditional instead, like '
            '$_conditionalAttributeUsage',
            index,
          );
        }
        return null;
      }
    }
    return null;
  }

  /// Writes the HTML tag from [tagStart] to [tagEnd], wrapping each
  /// `?condition:attribute` in an `if`. The whitespace before it goes inside
  /// the `if`, so a false condition leaves no gap. Each `...attributes` map
  /// is written by `_$writeAttributes`, which checks its names at run time.
  void writeHtmlTag(int tagStart, int tagEnd) {
    final nameEnd = _htmlTagNamePattern.matchAsPrefix(source, tagStart)!.end;
    final attributes = [
      for (final match in _attributePattern.allMatches(
        source.substring(nameEnd, tagEnd - '>'.length),
      ))
        (match: match, offset: nameEnd + match.start),
    ];
    final plainAttributeNames = {
      for (final (:match, offset: _) in attributes)
        if (!match[1]!.startsWith('?') && !match[1]!.startsWith('...'))
          match[1]!.toLowerCase(),
    };
    // Conditional attributes join it only when they render.
    String? writtenNamesVariable;
    if (attributes.any(
      (attribute) => _spreadAttributeNamePattern.hasMatch(attribute.match[1]!),
    )) {
      writtenNamesVariable = '\$attributeNames${spreadTagCount++}';
      final plainNameEntries = [
        for (final name in plainAttributeNames)
          '${_dartStringLiteral(name)}: false',
      ];
      flushText();
      emit(
        'final $writtenNamesVariable = '
        '<String, bool>{${plainNameEntries.join(', ')}};',
      );
    }
    if (source.substring(tagStart, nameEnd).contains('{{')) {
      fail(_interpolationInTagUsage, tagStart);
    }
    var textStart = tagStart;
    for (final (:match, :offset) in attributes) {
      final rawName = match[1]!;
      if (rawName.contains('{{')) fail(_interpolationInTagUsage, offset);
      // Unquoted, the spaces in {{ name }} would split the value, and spaces
      // in the value would add attributes of their own.
      if (match[4]?.contains('{{') ?? false) {
        final attributeName =
            _conditionalAttributeNamePattern.firstMatch(rawName)?[3] ?? rawName;
        fail(
          'quote {{ }} values, like $rawName="{{ $attributeName }}"',
          offset,
        );
      }
      if (!rawName.startsWith('?') && !rawName.startsWith('...')) continue;
      var negation = '';
      String? condition;
      var conditionOffset = offset;
      var attributeName = rawName;
      if (rawName.startsWith('?')) {
        final conditionalName =
            _conditionalAttributeNamePattern.firstMatch(rawName) ??
            fail(
              '"$rawName" is not a conditional attribute; write it as '
              '?condition:attribute, like $_conditionalAttributeUsage',
              offset,
            );
        negation = conditionalName[1]!;
        condition = conditionalName[2]!;
        attributeName = conditionalName[3]!;
        conditionOffset = offset + '?'.length + negation.length;
        requireValuePath(condition, conditionOffset, '"?condition:"');
      }
      final attributeOffset = offset + rawName.length - attributeName.length;
      final spreadMap = attributeName.startsWith('...')
          ? attributeName.substring('...'.length)
          : null;
      final spreadMapOffset = attributeOffset + '...'.length;
      if (spreadMap != null) {
        if (match[0]!.length != rawName.length) {
          fail(
            '"$attributeName" takes no value; it writes every entry of the '
            'Map<String, String> as an attribute, like $_spreadAttributeUsage',
            offset,
          );
        }
        requireValuePath(spreadMap, spreadMapOffset, '"...attributes"');
      } else if (plainAttributeNames.contains(attributeName.toLowerCase())) {
        // Conditional ones may share a name: each condition picks one value.
        fail(
          '"$attributeName" is also a plain attribute in this tag and '
          'browsers keep only the first; compute one value in Dart and pass '
          'it in',
          offset,
        );
      }
      var whitespaceStart = offset;
      while (whitespaceStart > textStart &&
          source[whitespaceStart - 1].trim().isEmpty) {
        whitespaceStart--;
      }
      writeTextWithInterpolations(textStart, whitespaceStart);
      flushText();
      if (condition != null) {
        emit('if ($negation$condition) {', sourceOffset: conditionOffset);
        indentLevel++;
      }
      if (spreadMap != null) {
        // _$writeAttributes puts a space before each entry, so an empty map
        // leaves no gap.
        emit(
          '_\$writeAttributes(\$out, $spreadMap, $writtenNamesVariable);',
          sourceOffset: spreadMapOffset,
        );
      } else {
        if (writtenNamesVariable != null) {
          emit(
            '_\$addConditionalAttributeName($writtenNamesVariable, '
            '${_dartStringLiteral(attributeName.toLowerCase())});',
          );
        }
        pendingText.write(source.substring(whitespaceStart, offset));
        pendingText.write(attributeName);
        writeTextWithInterpolations(
          offset + rawName.length,
          offset + match.end - match.start,
        );
        flushText();
      }
      if (condition != null) {
        indentLevel--;
        emit('}');
      }
      textStart = offset + match.end - match.start;
    }
    writeTextWithInterpolations(textStart, tagEnd);
  }

  /// Writes the text from [start] to [end], failing on a `...attributes`
  /// that only works inside an HTML tag. Code in `<script>` and `<style>`
  /// may spread its own variables.
  void writeText(int start, int end) {
    if (start >= rawTextEnd) {
      for (final spread in _spreadInTextPattern.allMatches(
        source.substring(start, end),
      )) {
        if (variablesInScope.contains(spread[1])) {
          fail(
            '"${spread[0]}" only works inside an HTML tag, like '
            '<div ${spread[0]}>; here it would render as text',
            start + spread.start,
          );
        }
      }
    }
    pendingText.write(source.substring(start, end));
  }

  while (true) {
    // An open <x-fragment> holds only <x-slot> tags and whitespace.
    if (openDirectives.lastOrNull?.name == 'fragment') {
      position = _leadingWhitespacePattern.matchAsPrefix(source, position)!.end;
      if (position < source.length &&
          !source.startsWith('<x-slot', position) &&
          !source.startsWith('</x-fragment', position)) {
        fail(
          '<x-fragment> can only contain <x-slot> tags; put content in a '
          'slot, like $_slotUsage',
          position,
        );
      }
    }
    final match = _directiveStartPattern
        .allMatches(source, position)
        .firstOrNull;
    if (match == null) {
      writeText(position, source.length);
      break;
    }
    writeText(position, match.start);
    final offset = match.start;

    switch (match[0]) {
      case '<!--':
        final end = source.indexOf('-->', match.end);
        if (end == -1) {
          fail('HTML comment "<!--" is never closed with "-->"', offset);
        }
        pendingText.write(source.substring(offset, end + 3));
        position = end + 3;

      case '{{':
        // HTML escaping does not make a value safe as code.
        if (offset < rawTextEnd) {
          fail(
            '"{{ }}" cannot go inside <script> or <style>, where HTML '
            'escaping does not make values safe; put the value in a quoted '
            'data- attribute, like <div data-name="{{ name }}">, and read it '
            'from the script',
            offset,
          );
        }
        position = writeInterpolation(offset, source.length);

      case '<':
        final tagEnd = offset < rawTextEnd ? null : htmlTagEnd(offset);
        if (tagEnd == null) {
          pendingText.write('<');
          position = offset + 1;
        } else {
          writeHtmlTag(offset, tagEnd);
          position = tagEnd;
          final tagName = _htmlTagNamePattern.matchAsPrefix(
            source,
            offset,
          )![0]!;
          if (_rawTextOpeningTagNamePattern.hasMatch(tagName)) {
            rawTextEnd =
                _rawTextClosingTagPattern
                    .allMatches(source, tagEnd)
                    .firstOrNull
                    ?.start ??
                source.length;
          }
        }

      case '</x-':
        final tag =
            _closeTagPattern.matchAsPrefix(source, offset) ??
            fail(
              'malformed closing tag; expected </x-for>, </x-if>, '
              '</x-if-not>, </x-fragment> or </x-slot>',
              offset,
            );
        final innermost = openDirectives.lastOrNull;
        if (innermost == null) {
          fail('</x-${tag[1]}> has no matching <x-${tag[1]}>', offset);
        }
        if (innermost.name != tag[1]) {
          fail(
            '</x-${tag[1]}> found while <x-${innermost.name}> from line '
            '${locate(innermost.offset).line} is still open; '
            'close it with </x-${innermost.name}> first',
            offset,
          );
        }
        position = positionAfterDirectiveTag(offset, tag.end);
        flushText();
        openDirectives.removeLast();
        variablesInScope.length -= innermost.variableCount;
        if (innermost.indexVariable case final indexVariable?) {
          emit('$indexVariable++;', sourceOffset: innermost.offset);
          indentLevel--;
          emit('}');
        }
        indentLevel--;
        switch (innermost.name) {
          case 'fragment':
            openFragments.removeLast();
            emit('));', sourceOffset: innermost.offset);
          case 'slot':
            emit('}),');
          default:
            emit('}');
        }

      default:
        final tag =
            _openTagPattern.matchAsPrefix(source, offset) ??
            fail(
              'malformed <x-...> tag; check that the directive name is '
              'lowercase, every attribute value is quoted and the tag ends '
              'with ">"',
              offset,
            );
        final tagName = tag[1]!;
        final attributes = _parseAttributes(
          tag[2]!,
          offset + '<x-'.length + tagName.length,
          fail,
        );
        for (final MapEntry(key: name, value: attribute)
            in attributes.entries) {
          if (_spreadAttributeNamePattern.hasMatch(name)) {
            fail(
              '"$name" only works on HTML tags, not on <x-$tagName>; '
              '${tagName == 'fragment' ? 'give the template a Map<String, String> prop and pass the map to it as one' : 'put it on the HTML tag inside'}',
              attribute.offset,
            );
          }
        }
        final isSelfClosing = tag[3]!.isNotEmpty;
        if (tagName != 'fragment' && isSelfClosing) {
          fail(
            '<x-$tagName> cannot end with />; close it with </x-$tagName>',
            offset,
          );
        }
        position = tag.end;

        switch (tagName) {
          case 'props':
            if (source.substring(0, offset).trim().isNotEmpty) {
              fail(
                '<x-props> must be the first thing in the template; only '
                'whitespace may come before it',
                offset,
              );
            }
            final closeTag = _closeTagPattern.matchAsPrefix(
              source,
              _leadingWhitespacePattern.matchAsPrefix(source, position)!.end,
            );
            if (closeTag == null || closeTag[1] != 'props') {
              fail(
                '<x-props> must be closed right away with </x-props>; '
                'it cannot contain content',
                offset,
              );
            }
            final declarations = [
              for (final MapEntry(key: name, value: attribute)
                  in attributes.entries)
                if (!_isValidName(name))
                  fail(
                    '"$name" is not a valid parameter name; $_nameRules',
                    attribute.offset,
                  )
                else if (name == 'template')
                  fail(
                    '"template" cannot be a prop name, since '
                    '<x-fragment template="..."> holds the path of the '
                    'template to render; rename the prop',
                    attribute.offset,
                  )
                else if (attribute.value?.contains('&') ?? false)
                  fail(
                    'write the type of "$name" as plain Dart, such as '
                    'List<String>; HTML entities like &lt; are not decoded',
                    attribute.offset,
                  )
                else if (attribute.value?.trim() case final type?
                    when type.isNotEmpty)
                  '    ${type.endsWith('?') ? '' : 'required '}$type $name, '
                      '${sourceMarker(attribute.offset)}'
                else
                  fail(
                    'parameter "$name" needs a Dart type, e.g. $name="String"',
                    attribute.offset,
                  ),
            ];
            variablesInScope.addAll(attributes.keys);
            if (declarations.isNotEmpty) {
              parameters = '{\n${declarations.join('\n')}\n  }';
            }
            pendingText.clear();
            position = _leadingWhitespacePattern
                .matchAsPrefix(source, closeTag.end)!
                .end;

          case 'for':
            position = positionAfterDirectiveTag(offset, tag.end);
            flushText();
            rejectUnknownAttributes(attributes, 'for', const [
              'in',
              'as',
              'index-from',
              'index-as',
            ]);
            final iterable = requiredAttribute(
              attributes,
              'in',
              directive: 'for',
              usage: _forUsage,
              tagOffset: offset,
            );
            final itemVariable = variableAttribute(
              attributes,
              'as',
              tagOffset: offset,
            );
            String? indexVariable;
            int? start;
            if (attributes.containsKey('index-from') ||
                attributes.containsKey('index-as')) {
              final indexFrom = requiredAttribute(
                attributes,
                'index-from',
                directive: 'for',
                usage: _forUsage,
                tagOffset: offset,
              );
              start =
                  int.tryParse(indexFrom.value) ??
                  fail(
                    '"index-from" must be an integer such as 0 or 1, '
                    'got "${indexFrom.value}"',
                    indexFrom.offset,
                  );
              indexVariable = variableAttribute(
                attributes,
                'index-as',
                tagOffset: offset,
              );
              if (indexVariable == itemVariable) {
                fail(
                  '"index-as" and "as" must name different variables, '
                  'both are "$indexVariable"',
                  attributes['index-as']!.offset,
                );
              }
            }
            requireValuePath(iterable.value, iterable.offset, '"in"');
            if (indexVariable != null) {
              emit('{');
              indentLevel++;
              emit('var $indexVariable = $start;', sourceOffset: offset);
            }
            emit(
              'for (final $itemVariable in (${iterable.value})) {',
              sourceOffset: iterable.offset,
            );
            indentLevel++;
            final loopVariables = [itemVariable, ?indexVariable];
            variablesInScope.addAll(loopVariables);
            openDirectives.add((
              name: 'for',
              indexVariable: indexVariable,
              offset: offset,
              variableCount: loopVariables.length,
            ));

          case 'if' || 'if-not':
            position = positionAfterDirectiveTag(offset, tag.end);
            flushText();
            rejectUnknownAttributes(attributes, tagName, const ['case']);
            final condition = requiredAttribute(
              attributes,
              'case',
              directive: tagName,
              usage: tagName == 'if' ? _ifUsage : _ifNotUsage,
              tagOffset: offset,
            );
            requireValuePath(condition.value, condition.offset, '"case"');
            final negation = tagName == 'if' ? '' : '!';
            emit(
              'if ($negation${condition.value}) {',
              sourceOffset: condition.offset,
            );
            indentLevel++;
            openDirectives.add((
              name: tagName,
              indexVariable: null,
              offset: offset,
              variableCount: 0,
            ));

          case 'fragment':
            final fragmentPath = requiredAttribute(
              attributes,
              'template',
              directive: 'fragment',
              usage: _fragmentUsage,
              tagOffset: offset,
            );
            if (!fragmentPath.value.startsWith('/') ||
                !fragmentPath.value.endsWith('.html')) {
              fail(
                '"template" must be the path of a template from the input '
                'directory, starting with / and ending with .html, like '
                '"/ui/label.html"; got "${fragmentPath.value}"',
                fragmentPath.offset,
              );
            }
            final renderedTemplatePath = fragmentPath.value.substring(1);
            final accessPath = accessPathByTemplatePath == null
                ? ''
                : accessPathByTemplatePath[renderedTemplatePath] ??
                      fail(
                        'there is no template ${fragmentPath.value} in the '
                        'input directory; '
                        '${_didYouMean(fragmentPath.value, [for (final templatePath in accessPathByTemplatePath.keys) '/$templatePath'])}'
                        'paths start at the input directory',
                        fragmentPath.offset,
                      );
            final arguments = [
              for (final MapEntry(key: name, value: attribute)
                  in attributes.entries)
                if (name != 'template')
                  '$name: '
                      '${fragmentArgument(renderedTemplatePath, name, attribute)}, '
                      '${sourceMarker(attribute.offset)}',
            ];
            flushText();
            emit('_\$write(\$out, $accessPath(', sourceOffset: offset);
            indentLevel++;
            arguments.forEach(emit);
            if (isSelfClosing) {
              indentLevel--;
              emit('));', sourceOffset: offset);
            } else {
              openFragments.add((
                templatePath: renderedTemplatePath,
                passedPropNames: attributes.keys.toSet(),
              ));
              openDirectives.add((
                name: 'fragment',
                indexVariable: null,
                offset: offset,
                variableCount: 0,
              ));
            }
            final location = locate(offset);
            renderedFragments.add((
              templatePath: renderedTemplatePath,
              line: location.line,
              column: location.column,
              lineText: location.lineText,
            ));

          case 'slot':
            if (openDirectives.lastOrNull?.name != 'fragment') {
              fail(
                '<x-slot> only goes directly inside <x-fragment>, like '
                '$_slotUsage',
                offset,
              );
            }
            rejectUnknownAttributes(attributes, 'slot', const ['name']);
            final slotName = requiredAttribute(
              attributes,
              'name',
              directive: 'slot',
              usage: _slotUsage,
              tagOffset: offset,
            );
            if (!_isValidName(slotName.value)) {
              fail(
                '"${slotName.value}" is not a valid prop name; $_nameRules',
                slotName.offset,
              );
            }
            requireDeclaredProp(
              openFragments.last.templatePath,
              slotName.value,
              slotName.offset,
            );
            if (!openFragments.last.passedPropNames.add(slotName.value)) {
              fail(
                'prop "${slotName.value}" is already passed to this '
                '<x-fragment>; pass each prop once',
                slotName.offset,
              );
            }
            position = positionAfterDirectiveTag(offset, tag.end);
            emit(
              '${slotName.value}: Fragment._((\$out) {',
              sourceOffset: slotName.offset,
            );
            indentLevel++;
            openDirectives.add((
              name: 'slot',
              indexVariable: null,
              offset: offset,
              variableCount: 0,
            ));

          default:
            fail(
              '<x-$tagName> is not a directive; supported directives are '
              '<x-props>, <x-for>, <x-if>, <x-if-not>, <x-fragment> and '
              '<x-slot>',
              offset,
            );
        }
    }
  }

  if (openDirectives.lastOrNull case final unclosed?) {
    fail(
      '<x-${unclosed.name}> is never closed; add </x-${unclosed.name}>',
      unclosed.offset,
    );
  }
  flushText();
  return (
    parameters: parameters,
    body: body.toString(),
    renderedFragments: renderedFragments,
  );
}

/// The names of the props each template declares, by template path, for
/// [compileTemplate]. Templates whose `<x-props>` is malformed are left out,
/// so nothing is checked against them.
Map<String, Set<String>> propNamesOfTemplates(
  Map<String, String> templateSourceByPath,
) => {
  for (final MapEntry(key: templatePath, value: source)
      in templateSourceByPath.entries)
    templatePath: ?_declaredPropNames(source),
};

Set<String>? _declaredPropNames(String source) {
  final start = _leadingWhitespacePattern.matchAsPrefix(source)!.end;
  if (!source.startsWith('<x-props', start)) return {};
  final tag = _openTagPattern.matchAsPrefix(source, start);
  if (tag == null || tag[1] != 'props') return null;
  return {for (final match in _attributePattern.allMatches(tag[2]!)) match[1]!};
}

/// `did you mean "x"? ` for the candidate closest to [name], or nothing
/// when none is close enough to be a typo of it.
String _didYouMean(String name, Iterable<String> candidates) {
  String? closest;
  // A typo changes a few characters, and never every one of them.
  var closestDistance = min(max(1, name.length ~/ 3), name.length - 1) + 1;
  for (final candidate in candidates.toSet()) {
    final distance = _editDistance(name, candidate);
    if (distance < closestDistance) {
      closest = candidate;
      closestDistance = distance;
    }
  }
  return closest == null ? '' : 'did you mean "$closest"? ';
}

/// How many characters to insert, delete, replace or swap with their
/// neighbor to turn [from] into [to].
int _editDistance(String from, String to) {
  final distances = [
    for (var fromIndex = 0; fromIndex <= from.length; fromIndex++)
      [
        for (var toIndex = 0; toIndex <= to.length; toIndex++)
          fromIndex == 0 ? toIndex : (toIndex == 0 ? fromIndex : 0),
      ],
  ];
  for (var fromIndex = 1; fromIndex <= from.length; fromIndex++) {
    for (var toIndex = 1; toIndex <= to.length; toIndex++) {
      final isSame = from[fromIndex - 1] == to[toIndex - 1];
      var distance = min(
        min(
              distances[fromIndex - 1][toIndex],
              distances[fromIndex][toIndex - 1],
            ) +
            1,
        distances[fromIndex - 1][toIndex - 1] + (isSame ? 0 : 1),
      );
      if (fromIndex > 1 &&
          toIndex > 1 &&
          from[fromIndex - 1] == to[toIndex - 2] &&
          from[fromIndex - 2] == to[toIndex - 1]) {
        distance = min(distance, distances[fromIndex - 2][toIndex - 2] + 1);
      }
      distances[fromIndex][toIndex] = distance;
    }
  }
  return distances[from.length][to.length];
}

bool _isValidName(String name) =>
    _identifierPattern.hasMatch(name) && !reservedDartNames.contains(name);

/// Parses the attributes of a tag; [sourceOffset] is where [source] starts
/// in the template, so each attribute knows its offset (its value's, if any).
Map<String, _Attribute> _parseAttributes(
  String source,
  int sourceOffset,
  Never Function(String, int) fail,
) {
  final attributes = <String, _Attribute>{};
  for (final match in _attributePattern.allMatches(source)) {
    final name = match[1]!;
    final nameOffset = sourceOffset + match.start;
    if (attributes.containsKey(name)) {
      fail('attribute "$name" is declared twice', nameOffset);
    }
    // Unquoted, the spaces in {{ name }} would split it into three attributes.
    if (match[4]?.startsWith('{{') ?? false) {
      fail('quote {{ }} values, like $name="{{ $name }}"', nameOffset);
    }
    final rawValue = match[2] ?? match[3] ?? match[4];
    attributes[name] = rawValue == null
        ? (value: null, offset: nameOffset)
        : (
            value: rawValue,
            offset:
                nameOffset +
                match[0]!.indexOf(rawValue, match[0]!.indexOf('=') + 1),
          );
  }
  return attributes;
}

String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}
