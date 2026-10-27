import 'package:absurd_templates/src/template.dart';
import 'package:test/test.dart';

void main() {
  test('compiles props, interpolation, loops and conditions', () {
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

    expect(
      compiled.parameters,
      '{required String title, '
      'required List<({String name, bool active})> users, '
      'Fragment? footer}',
    );
    expect(compiled.body, r'''
$out.write('<h1>');
_$write($out, title);
$out.write('</h1>\n');
{
  var number = 1;
  for (final user in (users)) {
    $out.write('\n');
    if (user.active) {
      $out.write('<li>');
      _$write($out, number);
      $out.write('. ');
      _$write($out, user.name);
      $out.write('</li>');
    }
    $out.write('\n');
    number++;
  }
}
$out.write('\n');
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

  group('fails fast on', () {
    final invalidTemplates = {
      '<p></p><x-props a="int"></x-props>': 'a.html:1: <x-props> must be at',
      '<x-props a="int">': 'a.html:1: <x-props> must be followed',
      '<x-props a></x-props>': 'parameter "a" needs a type',
      '<x-props class="int"></x-props>':
          '"class" is not a valid Dart parameter',
      '<x-props a="int" a="int"></x-props>': 'duplicate attribute "a"',
      '<x-for in="xs"></x-for>': 'missing "as" attribute',
      '<x-for in="xs" as="x" indexed="1"></x-for>': 'missing "index-as"',
      '<x-for in="xs" as="x" indexed="a" index-as="i"></x-for>':
          '"indexed" must be an integer',
      '<x-for in="xs" as="x" key="k"></x-for>': 'unknown attribute "key"',
      '<x-if></x-if>': 'missing "case" attribute',
      '\n<x-if case="a">': 'a.html:2: <x-if> is never closed',
      '<x-if case="a"></x-for>': 'unexpected </x-for>',
      '<x-include></x-include>': 'unknown directive <x-include>',
      '{{ name': 'unclosed "{{"',
      '{{ }}': 'empty "{{ }}"',
      '<!-- comment': 'unclosed HTML comment',
    };
    for (final MapEntry(key: source, value: error)
        in invalidTemplates.entries) {
      test(source, () {
        expect(
          () => compileTemplate(source, 'a.html'),
          throwsA(
            isA<FormatException>().having(
              (exception) => exception.message,
              'message',
              contains(error),
            ),
          ),
        );
      });
    }
  });
}
