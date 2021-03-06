@JS()
library vuedart_site.docs_navlist;

import 'dart:html';

import 'package:vue/vue.dart';

import 'package:vdmc/vdmc.dart';
import 'package:js/js.dart';


@anonymous
@JS()
class Entry {
  String title, addr;
  List<List<String>> contents;

  external factory Entry({String title, String addr, List<List<String>> contents});
}

@VueComponent(template: '<<', components: [MList, MListItem])
class AppNavlist extends VueComponentBase {
  @method
  String getUrl(Entry entry, [String ref = '']) =>
    '${entry.addr}${ref.isNotEmpty ? '#$ref' : ''}';

  @method
  bool isCurrentPage(Entry entry) =>
    window.location.pathname.endsWith('/${entry.addr}');

  @data
  List<Entry> entries = [
    new Entry(
      title: 'Intro',
      addr: 'intro.html',
      contents: [
        ['Welcome', 'welcome'],
        ['First steps', 'first-steps'],
        ['Declaring data', 'data'],
        ['Declaring methods', 'methods'],
        ['Declaring computed data', 'computed'],
        ['Watchers', 'watchers'],
        ['Using the VueDart CLI to create your projects', 'cli'],
      ],
    ),
    new Entry(
      title: 'Components',
      addr: 'components.html',
      contents: [
        ['Defining a component', 'component'],
        ['Declaring properties', 'props'],
        ['Scoped styles', 'scoped'],
        ['Mixins', 'mixins'],
        ['Lifecycle callbacks', 'lifecycle'],
        ['Accessing refs', 'refs'],
      ],
    ),
    new Entry(
      title: 'Advanced topics',
      addr: 'advanced.html',
      contents: [
        ['Bundling your assets via Aspen', 'assets'],
        ['Crossing the JavaScript and Dart boundary', 'boundary'],
        ['Events via \$emit, and other instance methods', 'instance'],
        ['Render functions', 'render'],
        ['Using the VueDart CLI to perform migrations', 'migrate'],
        ['Ignoring elements', 'ignore'],
      ],
    ),
    new Entry(
      title: 'Working with plugins',
      addr: 'plugins.html',
      contents: [
        ['How do plugins work in VueDart?', 'work'],
        ['VueRouter', 'vue-router'],
        ['VueMaterial', 'vuematerial'],
      ],
    ),
  ];
}
