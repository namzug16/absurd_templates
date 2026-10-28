import 'dart:io';

import 'package:absurd_templates/absurd_templates.dart';
import 'package:test/test.dart';

const _specTemplates = {
  'footer.html':
      '<x-props note="String"></x-props><footer>&copy; {{ note }}</footer>',
  'pages/user-page.html': '''
<x-props name="String" active="bool"></x-props>
<p>{{ name }}<x-if case="active">!</x-if></p>''',
  'pages/admin/dashboard.html': '<b>admin</b>',
  'text.html': '<x-props value="String"></x-props>{{ value }}',
  'pages/list.html':
      '<x-props items="List<Fragment>"></x-props><ul>{{ items }}</ul>',
  'ui/badge.html':
      '<x-props label="String" count="int" note="String?"></x-props>'
      '<b>{{ label }}: {{ count }}{{ note }}</b>',
  'pages/badges.html': '''
<x-props counts="List<int>"></x-props>
<x-for in="counts" as="count"><x-fragment _="/ui/badge.html" label="Tom & Jerry's" count="{{ count }}" /></x-for>''',
  'ui/option.html': '''
<x-props
  extra="Map<String, String>?"
  isSelected="bool"
  selected="Map<String, String>"
></x-props>
<p class="option" ...extra ?isSelected:...selected ?!isSelected:title="idle">''',
  'pages/users.html': '''
<x-props
  title="String"
  users="List<({String name, bool active})>"
  footer="Fragment?"
></x-props>
<h1>{{ title }}</h1>
<x-for in="users" as="user" indexed="1" index-as="number"><x-if case="user.active"><li>{{ number }}. {{ user.name }}</li></x-if></x-for>
{{ footer }}''',
};

void main() {
  test('generated library compiles and renders', () async {
    final directory = await Directory.systemTemp.createTemp('abs_generator_');
    addTearDown(() => directory.delete(recursive: true));
    File('${directory.path}/html.dart').writeAsStringSync(
      generateDartLibrary(
        templateSourceByPath: _specTemplates,
        className: 'Html',
      ),
    );
    File('${directory.path}/main.dart').writeAsStringSync(r'''
import 'dart:convert';

import 'html.dart';

void main() {
  const htmlEscape = HtmlEscape(
    HtmlEscapeMode(escapeLtGt: true, escapeQuot: true, escapeApos: true),
  );
  for (final text in [
    String.fromCharCodes([for (var code = 0; code < 128; code++) code]),
    '',
    'plain text',
    '&&<<>>""\'\'',
    'é ñ 中文 😀 <😀> &😀&',
  ]) {
    if (Html.text(value: text).toHtml() != htmlEscape.convert(text)) {
      print('escaping differs from HtmlEscape for ${jsonEncode(text)}');
    }
  }
  final users = Html.pages.users(
    title: 'Users',
    users: [(name: 'Ada', active: true), (name: 'Grace', active: false), (name: 'Linus', active: true)],
    footer: Html.footer(note: '<Ada & Grace>'),
  );
  print(users.toHtml());
  print(Html.pages.userPage(name: "O'Neil", active: true).toHtml());
  print(Html.pages.admin.dashboard().toHtml());
  print(Html.pages.list(items: [Html.pages.admin.dashboard(), Html.pages.admin.dashboard()]).toHtml());
  print(Html.pages.badges(counts: [1, 2]).toHtml());
  print(Html.ui.option(extra: {'data-value': '"<a>'}, isSelected: true, selected: {'aria-selected': 'true'}).toHtml());
  print(Html.ui.option(isSelected: false, selected: {'title': 'never rendered'}).toHtml());
  print(Html.ui.option(isSelected: true, selected: {'title': 'once'}).toHtml());
  for (final (extra, isSelected) in [({'CLASS': 'a'}, true), ({'data-a': 'a', 'aria-selected': 'b'}, true), ({'a b': 'c'}, true), ({'Title': 'a'}, false)]) {
    try {
      Html.ui.option(extra: extra, isSelected: isSelected, selected: {'aria-selected': 'true'}).toHtml();
    } on ArgumentError catch (error) {
      print(error.message);
    }
  }
}
''');

    final result = await Process.run(Platform.resolvedExecutable, [
      '${directory.path}/main.dart',
    ]);

    expect(result.stderr, '');
    expect(result.stdout, '''
<h1>Users</h1>
<li>1. Ada</li><li>3. Linus</li>
<footer>&copy; &lt;Ada &amp; Grace&gt;</footer>
<p>O&#39;Neil!</p>
<b>admin</b>
<ul><b>admin</b><b>admin</b></ul>
<b>Tom &amp; Jerry&#39;s: 1</b><b>Tom &amp; Jerry&#39;s: 2</b>
<p class="option" data-value="&quot;&lt;a&gt;" aria-selected="true">
<p class="option" title="idle">
<p class="option" title="once">
is already an attribute of this tag and browsers keep only the first; compute one value in Dart and pass it in
is already an attribute of this tag and browsers keep only the first; compute one value in Dart and pass it in
is not a valid HTML attribute name
is already an attribute of this tag and browsers keep only the first; compute one value in Dart and pass it in
''');
  });

  test('nested namespace classes are private', () {
    final library = generateDartLibrary(
      templateSourceByPath: {'pages/admin/dashboard.html': ''},
      className: 'Html',
    );
    expect(library, contains('static const pages = _Html\$pages();'));
    expect(
      library,
      contains('_Html\$pages\$admin get admin => const _Html\$pages\$admin();'),
    );
  });

  test('conflicts name both paths and the Dart access path', () {
    expect(
      () => generateDartLibrary(
        templateSourceByPath: {'pages/user.html': '', 'pages/user/a.html': ''},
        className: 'Html',
        templateDirectory: 'fragments',
      ),
      throwsA(
        isA<Diagnostic>().having(
          (d) => d.message,
          'message',
          'fragments/pages/user.html and fragments/pages/user/ would both '
              'become Html.pages.user; rename one of them',
        ),
      ),
    );
  });

  group('rejects templates that render themselves', () {
    final messageByTemplates = {
      'directly': (
        {'a.html': '<x-fragment _="/a.html" />'},
        'closes the cycle /a.html -> /a.html',
      ),
      'through other templates': (
        {
          'a.html': '<x-fragment _="/b.html" />',
          'b.html': '<p>\n  <x-fragment _="/c.html" /></p>',
          'c.html': '<x-fragment _="/a.html" />',
        },
        'closes the cycle /a.html -> /b.html -> /c.html -> /a.html',
      ),
    };
    for (final MapEntry(key: description, value: (templates, message))
        in messageByTemplates.entries) {
      test(description, () {
        expect(
          () => generateDartLibrary(
            templateSourceByPath: templates,
            className: 'Html',
            templateDirectory: 'fragments',
          ),
          throwsA(
            isA<Diagnostic>()
                .having((d) => d.message, 'message', contains(message))
                .having(
                  (d) => d.path,
                  'path',
                  'fragments/${templates.keys.last}',
                )
                .having((d) => d.line, 'line', 1)
                .having((d) => d.column, 'column', 1),
          ),
        );
      });
    }
  });

  test('allows rendering the same template twice without a cycle', () {
    expect(
      generateDartLibrary(
        templateSourceByPath: {
          'a.html': '<x-fragment _="/b.html" /><x-fragment _="/c.html" />',
          'b.html': '<x-fragment _="/c.html" />',
          'c.html': '<p>c</p>',
        },
        className: 'Html',
      ),
      contains('_\$write(\$out, Html.c( // a.html:1:27'),
    );
  });

  group('fails fast on', () {
    final conflicts = {
      'a file and directory with the same name': {
        'pages/user.html': '',
        'pages/user/profile.html': '',
      },
      'names that collide after conversion': {
        'user-page.html': '',
        'user_page.html': '',
      },
      'directories that collide after conversion': {
        'admin-area/a.html': '',
        'admin_area/b.html': '',
      },
      'names that are not Dart identifiers': {'404.html': ''},
      'reserved Dart names': {'switch.html': ''},
    };
    for (final MapEntry(key: description, value: templates)
        in conflicts.entries) {
      test(description, () {
        expect(
          () => generateDartLibrary(
            templateSourceByPath: templates,
            className: 'Html',
          ),
          throwsA(isA<Diagnostic>()),
        );
      });
    }

    test('invalid class names', () {
      expect(
        () =>
            generateDartLibrary(templateSourceByPath: {}, className: 'my-html'),
        throwsA(isA<Diagnostic>()),
      );
    });
  });
}
