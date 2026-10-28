import 'package:absurd_templates/src/diagnostic.dart';
import 'package:absurd_templates/src/template.dart';
import 'package:test/test.dart';

void main() {
  test('compiles props, interpolation and loops with source markers', () {
    final compiled = compileTemplate('''
<x-props
  title="String"
  users="List<({String name, bool active})>"
  footer="Fragment?"
></x-props>

<h1>{{ title }}</h1>
<x-for in="users" as="user" indexed="1" index-as="number">
<x-if case="user.active"><li>{{ number }}. {{ user.name }}</li></x-if>
</x-for>
''', 'users.html');

    expect(compiled.parameters, '''
{
    required String title, // users.html:2:10
    required List<({String name, bool active})> users, // users.html:3:10
    Fragment? footer, // users.html:4:11
  }''');
    expect(compiled.body, r'''
$out.write('<h1>');
_$write($out, title); // users.html:7:8
$out.write('</h1>\n');
{
  var number = 1; // users.html:8:1
  for (final user in (users)) { // users.html:8:12
    if (user.active) { // users.html:9:13
      $out.write('<li>');
      _$write($out, number); // users.html:9:33
      $out.write('. ');
      _$write($out, user.name); // users.html:9:47
      $out.write('</li>');
    }
    $out.write('\n');
    number++; // users.html:8:1
  }
}
''');
  });

  test('compiles <x-fragment> into a call with one argument per prop', () {
    final compiled = compileTemplate(
      '<x-props position="int"></x-props>\n'
          '<p><x-fragment _="/ui/label.html" text="it\'s" '
          'position="{{ position }}" /></p>',
      'a.html',
      accessPathByTemplatePath: {'ui/label.html': 'Html.ui.label'},
    );
    expect(compiled.body, r'''
$out.write('<p>');
_$write($out, Html.ui.label( // a.html:2:4
  text: 'it\'s', // a.html:2:41
  position: position, // a.html:2:57
)); // a.html:2:4
$out.write('</p>');
''');
    expect(compiled.renderedFragments.single, (
      templatePath: 'ui/label.html',
      line: 2,
      column: 4,
      lineText:
          '<p><x-fragment _="/ui/label.html" text="it\'s" '
          'position="{{ position }}" /></p>',
    ));
  });

  test('compiles <x-slot> into a Fragment argument', () {
    final compiled = compileTemplate(
      '<x-props title="String" users="List<String>"></x-props>\n'
          '<div>\n'
          '  <x-fragment _="/layout/card.html" title="{{ title }}">\n'
          '    <x-slot name="body">\n'
          '      <x-for in="users" as="user">\n'
          '        <p>{{ user }}</p>\n'
          '      </x-for>\n'
          '    </x-slot>\n'
          '    <x-slot name="footer"><b>{{ title }}</b></x-slot>\n'
          '  </x-fragment>\n'
          '</div>',
      'a.html',
      accessPathByTemplatePath: {'layout/card.html': 'Html.layout.card'},
    );
    expect(compiled.body, r'''
$out.write('<div>\n  ');
_$write($out, Html.layout.card( // a.html:3:3
  title: title, // a.html:3:44
  body: Fragment._(($out) { // a.html:4:19
    for (final user in (users)) { // a.html:5:18
      $out.write('        <p>');
      _$write($out, user); // a.html:6:15
      $out.write('</p>\n');
    }
  }),
  footer: Fragment._(($out) { // a.html:9:19
    $out.write('<b>');
    _$write($out, title); // a.html:9:33
    $out.write('</b>');
  }),
)); // a.html:3:3
$out.write('</div>');
''');
    expect(compiled.renderedFragments.single.templatePath, 'layout/card.html');
  });

  test('removes lines that only hold a directive tag', () {
    final compiled = compileTemplate(
      '<x-props a="bool"></x-props>\n'
          '<ul>\n  <x-if case="a">\n    <li>a</li>\n  </x-if>\n</ul>',
      'a.html',
    );
    expect(compiled.body, r'''
$out.write('<ul>\n');
if (a) { // a.html:3:15
  $out.write('    <li>a</li>\n');
}
$out.write('</ul>');
''');
  });

  test('wraps ?condition:attribute in an if, whitespace included', () {
    final compiled = compileTemplate(
      '<x-props isLoading="bool" hasTooltip="bool" tooltip="String">'
          '</x-props>\n'
          '<button type="button"\n  ?isLoading:disabled\n'
          '  ?hasTooltip:title="{{ tooltip }}">Save</button>',
      'a.html',
    );
    expect(compiled.body, r'''
$out.write('<button type="button"');
if (isLoading) { // a.html:3:4
  $out.write('\n  disabled');
}
if (hasTooltip) { // a.html:4:4
  $out.write('\n  title="');
  _$write($out, tooltip); // a.html:4:25
  $out.write('"');
}
$out.write('>Save</button>');
''');
  });

  test('?!condition:attribute renders when false; both may share a name', () {
    final compiled = compileTemplate(
      '<x-props isOn="bool"></x-props>'
          '<p ?isOn:class="on" ?!isOn:class="off">',
      'a.html',
    );
    expect(compiled.body, r'''
$out.write('<p');
if (isOn) { // a.html:1:36
  $out.write(' class="on"');
}
if (!isOn) { // a.html:1:54
  $out.write(' class="off"');
}
$out.write('>');
''');
  });

  test('...map writes its entries; ?condition:...map only when true', () {
    final compiled = compileTemplate(
      '<x-props isOn="bool" a="Map<String, String>" b="Map<String, String>">'
          '</x-props>'
          '<p id="x" ?isOn:class="on" ...a\n  ?!isOn:...b>',
      'a.html',
    );
    expect(compiled.body, r'''
final $attributeNames0 = <String, bool>{'id': false};
$out.write('<p id="x"');
if (isOn) { // a.html:1:91
  _$addConditionalAttributeName($attributeNames0, 'class');
  $out.write(' class="on"');
}
_$writeAttributes($out, a, $attributeNames0); // a.html:1:110
if (!isOn) { // a.html:2:5
  _$writeAttributes($out, b, $attributeNames0); // a.html:2:13
}
$out.write('>');
''');
  });

  test('text may hold "..." that is not a spread of a variable', () {
    final compiled = compileTemplate(
      '<x-props m="Map<String, String>"></x-props>'
          '<p>Wait... ...more</p><script>f(...m, [ ...m ])</script>',
      'a.html',
    );
    expect(compiled.body, contains('Wait... ...more'));
  });

  test('leaves a "<" that does not start a tag as text', () {
    final compiled = compileTemplate('<script>i<n</script>', 'a.html');
    expect(
      compiled.body,
      r"$out.write('<script>i<n</script>');"
      '\n',
    );
  });

  test('never reads tags inside <script> and <style>', () {
    const script =
        '<script>if (i<n ?a:b>c) x = "\'";</script>'
        '<STYLE>a<b{}</STYLE>';
    final compiled = compileTemplate(script, 'a.html');
    expect(
      compiled.body,
      '\$out.write(${"'"}${script.replaceAll("'", r"\'")}${"'"});\n',
    );
  });

  test('<x-if-not> renders its children when the condition is false', () {
    final compiled = compileTemplate(
      '<x-props user="({bool active})"></x-props>'
          '<x-if-not case="user.active">off</x-if-not>',
      'a.html',
    );
    expect(compiled.body, r'''
if (!user.active) { // a.html:1:59
  $out.write('off');
}
''');
  });

  test('escapes Dart string syntax in literal HTML', () {
    final compiled = compileTemplate(r"<p>it's $5 \o/</p>", 'a.html');
    expect(compiled.parameters, '');
    expect(
      compiled.body,
      r"$out.write('<p>it\'s \$5 \\o/</p>');"
      '\n',
    );
  });

  test('leaves directives inside HTML comments untouched', () {
    final compiled = compileTemplate('<!-- <x-if> {{ x }} -->', 'a.html');
    expect(
      compiled.body,
      r"$out.write('<!-- <x-if> {{ x }} -->');"
      '\n',
    );
  });

  test('errors show the path, line, column and source line', () {
    expect(
      () => compileTemplate(
        '<x-props a="bool"></x-props>\n'
            '<ul>\n  <x-if case="a">\n    <li>\n  </x-for>\n',
        'fragments/list.html',
      ),
      throwsA(
        isA<Diagnostic>().having((d) => d.format(), 'format()', '''
error: </x-for> found while <x-if> from line 3 is still open; close it with </x-if> first
  --> fragments/list.html:5:3
  |
5 |   </x-for>
  |   ^'''),
      ),
    );
  });

  group('fails fast on', () {
    // Template source -> expected message fragment, line and column.
    final invalidTemplates = {
      '<p></p><x-props a="int"></x-props>': (
        '<x-props> must be the first thing',
        1,
        8,
      ),
      '<x-props a="int">': ('must be closed right away with </x-props>', 1, 1),
      '<x-props\n  a\n></x-props>': ('parameter "a" needs a Dart type', 2, 3),
      '<x-props a="List&lt;String>"></x-props>': (
        'write the type of "a" as plain Dart',
        1,
        13,
      ),
      '<x-props class="int"></x-props>': (
        '"class" is not a valid parameter',
        1,
        17,
      ),
      '<x-props a="int" a="int"></x-props>': ('"a" is declared twice', 1, 18),
      '<x-for in="xs"></x-for>': ('needs a non-empty "as" attribute', 1, 1),
      '<x-for in="xs" as="x" indexed="1"></x-for>': (
        'needs a non-empty "index-as"',
        1,
        1,
      ),
      '<x-for in="xs" as="x" indexed="a" index-as="i"></x-for>': (
        '"indexed" must be an integer such as 0 or 1, got "a"',
        1,
        32,
      ),
      '<x-for in="xs" as="x" key="k"></x-for>': (
        'does not support the "key" attribute; supported attributes: in, as',
        1,
        28,
      ),
      '<x-for in="xs" as="my item"></x-for>': (
        '"my item" is not a valid variable name for "as"',
        1,
        20,
      ),
      '<x-if></x-if>': ('<x-if> needs a non-empty "case" attribute', 1, 1),
      '<x-if-not></x-if-not>': ('<x-if-not> needs a non-empty "case"', 1, 1),
      '<x-props a="bool"></x-props><x-if-not case="a"></x-if>': (
        '</x-if> found while <x-if-not> from line 1 is still open',
        1,
        48,
      ),
      '<x-props a="bool"></x-props>\n<x-if case="a">': (
        '<x-if> is never closed; add </x-if>',
        2,
        1,
      ),
      '<x-props a="int"></x-props>{{ a + 1 }}': (
        '"{{ }}" only accepts a variable or its fields, like user or '
            'user.name, got "a + 1"',
        1,
        31,
      ),
      '<x-props a="int"></x-props>\n  {{ b }}': (
        '"b" is not declared; declare it in <x-props> or as an <x-for> '
            'variable. Declared here: a',
        2,
        6,
      ),
      '<x-props a="bool?"></x-props><x-if case="a != null"></x-if>': (
        '"case" only accepts a variable or its fields',
        1,
        42,
      ),
      '<x-props xs="List<int>"></x-props><x-for in="xs.reversed.toList()" as="x"></x-for>':
          ('"in" only accepts a variable or its fields', 1, 46),
      '<x-props xs="List<int>"></x-props><x-for in="xs" as="x"></x-for>{{ x }}':
          ('"x" is not declared', 1, 68),
      '<x-props xs="List<int>"></x-props><x-for in="xs" as="x" indexed="1" index-as="x"></x-for>':
          ('"index-as" and "as" must name different variables', 1, 79),
      '</x-if>': ('</x-if> has no matching <x-if>', 1, 1),
      '<x-include></x-include>': (
        'supported directives are <x-props>, <x-for>, <x-if>, <x-if-not>, '
            '<x-fragment> and <x-slot>',
        1,
        1,
      ),
      '<x-if case="a" />': ('<x-if> cannot end with />', 1, 1),
      '<x-fragment />': ('<x-fragment> needs a non-empty "_"', 1, 1),
      '<x-fragment _="ui/label.html" />': ('starting with / and ending', 1, 16),
      '<x-fragment _="/missing.html" />': (
        'there is no template /missing.html',
        1,
        16,
      ),
      '<x-fragment _="/ui/label.html">': ('<x-fragment> is never closed', 1, 1),
      '<x-fragment _="/ui/label.html" /></x-fragment>': (
        '</x-fragment> has no matching <x-fragment>',
        1,
        34,
      ),
      '<x-fragment _="/ui/label.html">\n  <p>hi</p></x-fragment>': (
        '<x-fragment> can only contain <x-slot> tags',
        2,
        3,
      ),
      '<x-slot name="a"></x-slot>': (
        '<x-slot> only goes directly inside <x-fragment>',
        1,
        1,
      ),
      '<x-fragment _="/ui/label.html"><x-slot name="a"><x-slot name="b">'
          '</x-slot></x-slot></x-fragment>': (
        '<x-slot> only goes directly inside <x-fragment>',
        1,
        49,
      ),
      '<x-fragment _="/ui/label.html"><x-slot></x-slot></x-fragment>': (
        '<x-slot> needs a non-empty "name"',
        1,
        32,
      ),
      '<x-fragment _="/ui/label.html"><x-slot name="a" as="b"></x-slot>'
          '</x-fragment>': (
        '<x-slot> does not support the "as" attribute',
        1,
        53,
      ),
      '<x-fragment _="/ui/label.html"><x-slot name="a-b"></x-slot>'
          '</x-fragment>': (
        '"a-b" is not a valid prop name',
        1,
        46,
      ),
      '<x-fragment _="/ui/label.html" text="a"><x-slot name="text"></x-slot>'
          '</x-fragment>': (
        'prop "text" is already passed to this <x-fragment>',
        1,
        55,
      ),
      '<x-fragment _="/ui/label.html"><x-slot name="a" /></x-fragment>': (
        '<x-slot> cannot end with />',
        1,
        32,
      ),
      '<x-fragment _="/ui/label.html"><x-slot name="a"></x-fragment>': (
        '</x-fragment> found while <x-slot> from line 1 is still open',
        1,
        49,
      ),
      '<x-props a="int"></x-props><x-fragment _="/ui/label.html" a={{ a }} />':
          ('quote {{ }} values, like a="{{ a }}"', 1, 59),
      '<x-props a="int"></x-props><x-fragment _="/ui/label.html" a="#{{ a }}" />':
          ('must be plain text or exactly one quoted {{ }}', 1, 62),
      '<x-fragment _="/ui/label.html" text="{{ b }}" />': (
        '"b" is not declared',
        1,
        41,
      ),
      '<x-fragment _="/ui/label.html" text="Tom &amp; Jerry" />': (
        'write "&amp;" in prop "text" as the plain character',
        1,
        42,
      ),
      '<x-fragment _="/ui/label.html" active />': (
        'prop "active" needs a value',
        1,
        32,
      ),
      '<x-fragment _="/ui/label.html" user-name="Ada" />': (
        '"user-name" is not a valid prop name',
        1,
        43,
      ),
      '<x-props a="bool"></x-props><button <x-if case="a">disabled</x-if>>': (
        '<x-if> cannot go inside an HTML tag',
        1,
        37,
      ),
      '<button ?disabled>': (
        '"?disabled" is not a conditional attribute',
        1,
        9,
      ),
      '<button ?isLoading:disabled>': ('"isLoading" is not declared', 1, 10),
      '<button ?!isLoading:disabled>': ('"isLoading" is not declared', 1, 11),
      '<button ?!:disabled>': ('"?!:disabled" is not a conditional', 1, 9),
      '<x-props a="bool"></x-props><p class="b" ?a:CLASS="c">': (
        '"CLASS" is also a plain attribute in this tag',
        1,
        42,
      ),
      '<x-props a="bool" t="String"></x-props><p ?a:title={{ t }}>': (
        'quote {{ }} values, like ?a:title="{{ title }}"',
        1,
        43,
      ),
      '<x-props t="String"></x-props><p class={{ t }}>': (
        'quote {{ }} values, like class="{{ class }}"',
        1,
        34,
      ),
      '<x-props t="String"></x-props><p class=a{{t}}>': (
        'quote {{ }} values, like class="{{ class }}"',
        1,
        34,
      ),
      '<x-props t="String"></x-props><p {{ t }}>': (
        '{{ }} inside an HTML tag only goes in a quoted attribute value',
        1,
        34,
      ),
      '<x-props t="String"></x-props><p{{t}}>': (
        '{{ }} inside an HTML tag only goes in a quoted attribute value',
        1,
        31,
      ),
      '<x-props m="Map<String, String>"></x-props><p ...m="x">': (
        '"...m" takes no value',
        1,
        47,
      ),
      '<p ...m>': ('"m" is not declared', 1, 7),
      '<x-props a="bool"></x-props><p ?a:...m>': ('"m" is not declared', 1, 38),
      '<x-props m="Map<String, String>"></x-props><p ...m.keys.first()>': (
        '"...attributes" only accepts a variable or its fields',
        1,
        50,
      ),
      '<x-props m="Map<String, String>"></x-props><p>\n  ...m</p>': (
        '"...m" only works inside an HTML tag',
        2,
        3,
      ),
      '<x-props m="Map<String, String>" a="bool"></x-props>'
          '<x-if ...m case="a">': (
        '"...m" only works on HTML tags, not on <x-if>',
        1,
        59,
      ),
      '<x-if case="a>': ('malformed <x-...> tag', 1, 1),
      'a\n  {{ name': ('"{{" is never closed with "}}"', 2, 3),
      '{{ }}': ('"{{ }}" is empty', 1, 1),
      '<x-props a="int"></x-props><script>var n = {{ a }};</script>': (
        '"{{ }}" cannot go inside <script> or <style>',
        1,
        44,
      ),
      '<x-props a="int"></x-props><STYLE>p { order: {{ a }} }</STYLE>': (
        '"{{ }}" cannot go inside <script> or <style>',
        1,
        46,
      ),
      '<!-- comment': ('"<!--" is never closed', 1, 1),
    };
    for (final MapEntry(key: source, value: (message, line, column))
        in invalidTemplates.entries) {
      test(source, () {
        expect(
          () => compileTemplate(
            source,
            'a.html',
            accessPathByTemplatePath: {'ui/label.html': 'Html.ui.label'},
          ),
          throwsA(
            isA<Diagnostic>()
                .having((d) => d.message, 'message', contains(message))
                .having((d) => d.path, 'path', 'a.html')
                .having((d) => d.line, 'line', line)
                .having((d) => d.column, 'column', column),
          ),
        );
      });
    }
  });
}
