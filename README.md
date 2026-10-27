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

Run `abs`.

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
- `{{ expr }}` escapes values; `Fragment` values are inserted as HTML; `null`
  renders nothing.
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
