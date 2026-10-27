import 'package:absurd_templates/src/diagnostic.dart';
import 'package:absurd_templates/src/template.dart';
import 'package:test/test.dart';

void main() {
  test('compiles props, interpolation and loops with source markers', () {
    final compiled = compileTemplate('''
<x-props
  title="String"
  users="List&lt;({String name, bool active})>"
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

  test('removes lines that only hold a directive tag', () {
    final compiled = compileTemplate(
      '<ul>\n  <x-if case="a">\n    <li>a</li>\n  </x-if>\n</ul>',
      'a.html',
    );
    expect(compiled.body, r'''
$out.write('<ul>\n');
if (a) { // a.html:2:15
  $out.write('    <li>a</li>\n');
}
$out.write('</ul>');
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
        '<ul>\n  <x-if case="a">\n    <li>\n  </x-for>\n',
        'components/list.html',
      ),
      throwsA(
        isA<Diagnostic>().having((d) => d.format(), 'format()', '''
error: </x-for> found while <x-if> from line 2 is still open; close it with </x-if> first
  --> components/list.html:4:3
  |
4 |   </x-for>
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
      '\n<x-if case="a">': ('<x-if> is never closed; add </x-if>', 2, 1),
      '</x-if>': ('</x-if> has no matching <x-if>', 1, 1),
      '<x-include></x-include>': ('accept a Fragment parameter', 1, 1),
      '<x-if case="a>': ('malformed <x-...> tag', 1, 1),
      'a\n  {{ name': ('"{{" is never closed with "}}"', 2, 3),
      '{{ }}': ('"{{ }}" is empty', 1, 1),
      '<!-- comment': ('"<!--" is never closed', 1, 1),
    };
    for (final MapEntry(key: source, value: (message, line, column))
        in invalidTemplates.entries) {
      test(source, () {
        expect(
          () => compileTemplate(source, 'a.html'),
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
