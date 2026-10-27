# Absurd Templates

HTML-first templates for Dart. `abs` compiles a directory of `.html` files
into **one self-contained Dart file** with typed component functions and its
own `Fragment` type. No runtime package needed.

## Install

```sh
dart pub global activate --source path .
# or, fastest startup:
dart compile exe bin/abs.dart -o abs
```

## Configure

`abs.yaml` in your project root:

```yaml
input: components             # required, scanned recursively for .html
output: lib/generated/html.dart # required
class: Html                   # optional, defaults to Components
```

Run `abs` to generate the output file.

## Checking templates

```sh
abs check                              # every template
abs check components/pages/users.html  # only these files
```

`abs check` writes nothing. It reports syntax errors, naming conflicts and
Dart errors such as unknown types, undefined names and typos in fields, all
mapped back to the template. It exits with 1 when there are errors:

```text
error: The getter 'nmae' isn't defined for the type '({bool active, String name})'.
  --> components/pages/users.html:12:16
   |
12 |         <li>{{ user.nmae }}</li>
   |                ^

abs check: 1 error and 0 warnings in 1 template
```

Every statement in the generated file that comes from template code ends in
a `// components/pages/users.html:12:16` comment, so errors reported against
the generated file also lead back to the template.

## Templates

```html
<x-props
  title="String"
  users="List&lt;({String name, bool active})>"
  footer="Fragment?"
></x-props>

<section>
  <h1>{{ title }}</h1>
  <x-for in="users" as="user" indexed="1" index-as="number">
    <x-if case="user.active">
      <li>{{ number }}. {{ user.name }}</li>
    </x-if>
  </x-for>
  {{ footer }}
</section>
```

- `<x-props>` must come first; attribute = parameter name, value = Dart type.
  Nullable types become optional parameters, all others are `required`.
- `{{ }}`, `in="..."` and `case="..."` accept only a declared variable or its
  fields (`title`, `user.name`, `pair.$1`), never other Dart code: compute
  values in Dart and pass them in as props.
- `{{ value }}` escapes values; `Fragment` values are inserted as HTML; `null`
  renders nothing, so `{{ footer }}` handles an optional `Fragment?`; lists
  such as `List<Fragment>` render each item in order.
- Escaping makes values safe as HTML text and inside quoted attributes, not
  as URLs: `href="{{ url }}"` with `javascript:alert(1)` still runs code.
  Check URLs used in `href`, `src` or `action` in Dart before passing them in.
- `<x-for in as [indexed index-as]>` and `<x-if case>` render only their children.
  A directive tag alone on its line is removed together with that line.
- Directives inside `<!-- -->` are left alone.

## Generated API

`components/pages/user-page.html` becomes `Html.pages.userPage(...)`, returning
a `Fragment`. Call `.toHtml()` to render. Name collisions (after camelCase
conversion) and file/directory clashes are errors.

```dart
final page = Html.layout.primary(
  title: 'Users',
  content: Html.pages.users(title: 'Users', users: users),
);
final String html = page.toHtml();
```

## Example

[`examples/`](examples) has components, their generated
[`html.dart`](examples/generated/html.dart) and a [`main.dart`](examples/main.dart)
that renders them:

```sh
cd examples && abs && dart main.dart
```
