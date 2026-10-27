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
        templateDirectory: 'components',
      ),
      throwsA(
        isA<Diagnostic>().having(
          (d) => d.message,
          'message',
          'components/pages/user.html and components/pages/user/ would both '
              'become Html.pages.user; rename one of them',
        ),
      ),
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
