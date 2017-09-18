import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:html/parser.dart' show parse;
import 'package:source_span/source_span.dart' show SourceFile;
import 'package:source_maps/refactor.dart';


class AnnotationArgs {
  final List<Expression> positional;
  final Map<String, Expression> named;

  AnnotationArgs(this.positional, this.named);
}


class Prop {
  final String name;
  final TypeName type;
  final Expression initializer;

  Prop(this.name, this.type, this.initializer);
}


class Data {
  final String name;
  final Expression initializer;

  Data(this.name, this.initializer);
}


class Computed {
  final String name;
  bool hasSetter;

  Computed(this.name);
}


class Method {
  final String name;
  final List<FormalParameter> params;

  Method(this.name, this.params);
}


class VueClassInfo {
  List<Prop> props = [];
  List<Data> data = [];
  Map<String, Computed> computed = {};
  List<Method> methods = [];

  VueClassInfo();
}


class VuedartApplyTransform {
  final BarbackSettings settings;
  final Transform transform;

  SourceFile source;
  Asset primary;
  TextEditTransaction rewriter;
  CompilationUnit unit;

  List<ClassDeclaration> components = [];

  VuedartApplyTransform(this.settings, this.transform):
    primary = transform.primaryInput;

  void error(AstNode node, String error) {
    var span = source.span(node.offset, node.end);
    transform.logger.error(span.message(error), asset: primary.id);
  }

  Annotation getAnn(AnnotatedNode node, List<String> annotations) {
    var it = node.metadata.where((ann) => annotations.contains(ann.name.name));
    return it.isNotEmpty ? it.first : null;
  }

  Annotation getVueAnn(ClassDeclaration cls) =>
    getAnn(cls, ['VueApp', 'VueComponent', 'VueMixin']);
  bool containsVueAnn(ClassDeclaration cls) => getVueAnn(cls) != null;

  AnnotationArgs getAnnArgs(Annotation ann) {
    var positional = <Expression>[];
    var named = <String, Expression>{};

    for (var arg in ann.arguments.arguments) {
      if (arg is NamedExpression) {
        named[arg.name.label.name] = arg.expression;
      } else {
        positional.add(arg);
      }
    }

    return new AnnotationArgs(positional, named);
  }

  String computedGet(String name) => 'vuedart_INTERNAL_cg_$name';
  String computedSet(String name) => 'vuedart_INTERNAL_cs_$name';
  String method(String name) => 'vuedart_INTERAL_m_$name';

  String methodParams(List<FormalParameter> params) =>
    params.map((p) => p.identifier.name).join(', ');

  String sourceOrNull(AstNode node) => node?.toSource() ?? 'null';

  String codegenProp(Prop prop) =>
    ''' '${prop.name}': new VueProp((_) => true, ${sourceOrNull(prop.initializer)}), ''';

  String codegenData(Data data) =>
    ''' '${data.name}': ${sourceOrNull(data.initializer)}, ''';

  String codegenComputed(Computed computed) =>
    '''
  '${computed.name}': new VueComputed(
    (_) => vueGetObj(_).${computedGet(computed.name)}(),
    ${computed.hasSetter
      ? '(_,__) => vueGetObj(_).${computedSet(computed.name)}(__)'
      : 'null'}),
    ''';

  String codegenMethod(Method meth) =>
    '''
    '${meth.name}': (_, ${methodParams(meth.params)}) =>
              vueGetObj(_).${method(meth.name)}(${methodParams(meth.params)}),
    ''';

  void processField(FieldDeclaration member, VueClassInfo info) {
    var ann = getAnn(member, ['prop', 'data', 'ref']);
    if (ann == null) return;

    var fields = member.fields;
    var type = fields.type;
    var typestring = type.toSource();

    for (var decl in member.fields.variables) {
      var name = decl.name.name;

      if (ann.name.name == 'ref') {
        rewriter.edit(fields.offset, fields.end+1, '''
$typestring get $name => \$ref('$name');
        ''');
      } else {
        rewriter.edit(fields.offset, fields.end+1, '''
$typestring get $name => vuedart_get('$name');
void set $name($typestring value) => vuedart_set('$name', value);
        ''');

        switch (ann.name.name) {
        case 'prop':
          info.props.add(new Prop(name, type, decl.initializer));
          break;
        case 'data':
          info.data.add(new Data(name, decl.initializer));
          break;
        }
      }
    }
  }

  void processMethod(MethodDeclaration member, VueClassInfo info) {
    var ann = getAnn(member, ['computed', 'method']);
    if (ann == null) return;

    if ((ann.name.name == 'computed' && !member.isGetter && !member.isSetter) ||
        (ann.name.name == 'method' && (member.isGetter || member.isSetter))) {
      error(member, 'annotation on invalid member');
      return;
    }

    var name = member.name.name;
    var typestring = member.returnType?.name?.name ?? '';

    if (member.isGetter) {
      rewriter.edit(member.offset, member.end, '''
$typestring ${computedGet(name)}() ${member.body.toSource()}
$typestring get $name => vuedart_get('$name');
      ''');
      info.computed[name] = new Computed(name);
    } else if (member.isSetter) {
      if (!info.computed.containsKey(name)) {
        error(member, 'computed setters must follow getters');
        return;
      }

      info.computed[name].hasSetter = true;
      rewriter.edit(member.offset, member.end, '''
$typestring ${computedSet(name)}${member.parameters.toSource()}
  ${member.body.toSource()}
$typestring set $name($typestring value) => vuedart_set('$name', value);
      ''');
    } else {
      rewriter.edit(member.offset, member.end, '''
$typestring ${method(name)}${member.parameters.toSource()}
  ${member.body.toSource()}
$typestring $name${member.parameters.toSource()} =>
  vuedart_get('$name')(${methodParams(member.parameters.parameters)});
        ''');
      info.methods.add(new Method(name, member.parameters.parameters));
    }
  }

  Future readTemplateString(Annotation ann, String path) async {
    var relhtmlpath = path.substring(2);
    var htmlasset;

    if (relhtmlpath == '') {
      htmlasset = primary.id.changeExtension('.html');
    } else {
      htmlasset = new AssetId(primary.id.package,
                              primary.id.path + '/../' + relhtmlpath);
    }

    if (await transform.hasInput(htmlasset)) {
      var doc = parse(await transform.readInputAsString(htmlasset));
      return new Future.value(doc.body.children[0].innerHtml);
    } else {
      error(ann, 'template file $relhtmlpath does not exist');
      return new Future.value();
    }
  }

  Future processClass(ClassDeclaration cls) async {
    var ann = getVueAnn(cls);
    var args = getAnnArgs(ann);
    var info = new VueClassInfo();

    for (var member in cls.members) {
      if (member is FieldDeclaration) {
        processField(member, info);
      } else if (member is MethodDeclaration) {
        processMethod(member, info);
      }
    }

    var opts = '''
  data: {${info.data.map(codegenData).join('\n')}},
  computed: {${info.computed.values.map(codegenComputed).join('\n')}},
  methods: {${info.methods.map(codegenMethod).join('\n')}},
    ''';
    var code;

    if (ann.name.name == 'VueComponent' || ann.name.name == 'VueMixin') {
      var name = null, creator = null;

      if (ann.name.name == 'VueComponent') {
        if (args.positional.length != 1) {
          error(ann, 'invalid number of arguments to VueComponent');
          return new Future.value();
        }

        name = "'${(args.positional[0] as StringLiteral).stringValue}'";
        creator = '(context) => new ${cls.name.name}(context)';
        components.add(cls);
      }

      var template = args.named['template'] as StringLiteral;
      var templateString;

      if (template == null) {
        templateString = 'null';
      } else {
        templateString = template.stringValue;

        if (templateString.startsWith('<<')) {
          templateString = await readTemplateString(ann, templateString) ?? '';
        }

        templateString = 'r"""${templateString.replaceAll('"""', '\\"""')}"""';
      }

      var mixins = (args.named['mixins'] as ListLiteral)?.elements ?? [];

      code = '''
static VueComponentConstructor constructor = new VueComponentConstructor(
  name: $name,
  creator: $creator,
  template: $templateString,
  props: {${info.props.map(codegenProp).join('\n')}},
  mixins: [${mixins.map((mixin) => '${mixin.name}.constructor').join(', ')}],
$opts
);
      ''';

      if (ann.name.name == 'VueMixin') {
        rewriter.edit(cls.end-1, cls.end-1, r'''
  dynamic vuedart_get(String key);
  void vuedart_set(String key, dynamic value);
  dynamic $ref(String name);
        ''');
      }
    } else {
      if (!args.named.containsKey('el')) {
        error(ann, 'VueApp annotations need el key');
        return new Future.value();
      }

      code = '''
@override
VueAppConstructor get constructor => new VueAppConstructor(
  el: ${args.named['el'].toSource()},
$opts
);
      ''';
    }

    rewriter.edit(cls.end-1, cls.end-1, code);
  }

  Future apply() async {
    var contents = await primary.readAsString();
    source = new SourceFile.fromString(contents);
    rewriter = new TextEditTransaction(contents, source);

    try {
      unit = parseCompilationUnit(contents, name: primary.id.path);
    } catch (ex) {
      // Just ignore it; it will propagate to the Dart compiler anyway.
      transform.logger.warning('Error parsing ${primary.id.path}', asset: primary.id);
      transform.addOutput(primary);
      return new Future.value();
    }

    var classes = unit.declarations.where((d) => d is ClassDeclaration &&
                                                 containsVueAnn(d))
                                          .map((d) => d as ClassDeclaration).toList();
    if (classes.isEmpty) {
      transform.addOutput(primary);
      return new Future.value();
    }

    for (var cls in classes) {
      await processClass(cls);
    }

    rewriter.edit(unit.end, unit.end, '''
@initMethod
void vuedart_INTERNAL_init() {
${components.map((comp) =>
      "  VueComponentBase.register(${comp.name.name}.constructor);").join('\n')}
}
    ''');

    var printer = rewriter.commit();
    printer.build(null);
    // print(printer.text);
    transform.addOutput(new Asset.fromString(primary.id, printer.text));

    return new Future.value();
  }
}


class DartTransformer extends Transformer {
  final BarbackSettings _settings;

  DartTransformer.asPlugin(this._settings);

  String get allowedExtensions => '.dart';

  Future apply(Transform transform) async =>
    await new VuedartApplyTransform(_settings, transform).apply();
}
