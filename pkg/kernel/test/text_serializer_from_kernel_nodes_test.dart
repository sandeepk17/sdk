// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.text_serializer_from_kernel_nodes_test;

import 'package:kernel/ast.dart';
import 'package:kernel/text/serializer_combinators.dart';
import 'package:kernel/text/text_reader.dart';
import 'package:kernel/text/text_serializer.dart';

void main() {
  initializeSerializers();
  test();
}

// Wrappers for testing.
Statement readStatement(String input, DeserializationState state) {
  TextIterator stream = new TextIterator(input, 0);
  stream.moveNext();
  Statement result = statementSerializer.readFrom(stream, state);
  if (stream.moveNext()) {
    throw StateError("extra cruft in basic literal");
  }
  return result;
}

String writeStatement(Statement statement, SerializationState state) {
  StringBuffer buffer = new StringBuffer();
  statementSerializer.writeTo(buffer, statement, state);
  return buffer.toString();
}

class TestCase {
  final String name;
  final Node node;
  final SerializationState serializationState;
  final DeserializationState deserializationState;
  final String expectation;

  TestCase(
      {this.name,
      this.node,
      this.expectation,
      SerializationState serializationState,
      DeserializationState deserializationState})
      : this.serializationState =
            serializationState ?? new SerializationState(null),
        this.deserializationState = deserializationState ??
            new DeserializationState(null, new CanonicalName.root());
}

void test() {
  List<String> failures = [];
  List<TestCase> tests = <TestCase>[
    new TestCase(
        name: "let dynamic x = 42 in x;",
        node: () {
          VariableDeclaration x = new VariableDeclaration("x",
              type: const DynamicType(), initializer: new IntLiteral(42));
          return new ExpressionStatement(new Let(x, new VariableGet(x)));
        }(),
        expectation: ""
            "(expr (let (var \"x^0\" (dynamic) (int 42) ())"
            " (get-var \"x^0\" _)))"),
    new TestCase(
        name: "let dynamic x = 42 in let Bottom x^0 = null in x;",
        node: () {
          VariableDeclaration outterLetVar = new VariableDeclaration("x",
              type: const DynamicType(), initializer: new IntLiteral(42));
          VariableDeclaration innerLetVar = new VariableDeclaration("x",
              type: const BottomType(), initializer: new NullLiteral());
          return new ExpressionStatement(new Let(outterLetVar,
              new Let(innerLetVar, new VariableGet(outterLetVar))));
        }(),
        expectation: ""
            "(expr (let (var \"x^0\" (dynamic) (int 42) ())"
            " (let (var \"x^1\" (bottom) (null) ())"
            " (get-var \"x^0\" _))))"),
    new TestCase(
        name: "let dynamic x = 42 in let Bottom x^0 = null in x^0;",
        node: () {
          VariableDeclaration outterLetVar = new VariableDeclaration("x",
              type: const DynamicType(), initializer: new IntLiteral(42));
          VariableDeclaration innerLetVar = new VariableDeclaration("x",
              type: const BottomType(), initializer: new NullLiteral());
          return new ExpressionStatement(new Let(outterLetVar,
              new Let(innerLetVar, new VariableGet(innerLetVar))));
        }(),
        expectation: ""
            "(expr (let (var \"x^0\" (dynamic) (int 42) ())"
            " (let (var \"x^1\" (bottom) (null) ())"
            " (get-var \"x^1\" _))))"),
    () {
      VariableDeclaration x =
          new VariableDeclaration("x", type: const DynamicType());
      return new TestCase(
          name: "/* suppose: dynamic x; */ x = 42;",
          node: new ExpressionStatement(new VariableSet(x, new IntLiteral(42))),
          expectation: "(expr (set-var \"x^0\" (int 42)))",
          serializationState: new SerializationState(
            new SerializationEnvironment(null)
              ..addBinder(x, "x^0")
              ..close(),
          ),
          deserializationState: new DeserializationState(
              new DeserializationEnvironment(null)
                ..addBinder("x^0", x)
                ..close(),
              new CanonicalName.root()));
    }(),
    () {
      Field field = new Field(new Name("field"), type: const DynamicType());
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          fields: <Field>[field]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();
      return new TestCase(
          name: "/* suppose top-level: dynamic field; */ field;",
          node: new ExpressionStatement(new StaticGet(field)),
          expectation: ""
              "(expr (get-static \"package:foo/bar.dart::@fields::field\"))",
          serializationState: new SerializationState(null),
          deserializationState: new DeserializationState(null, component.root));
    }(),
    () {
      Field field = new Field(new Name("field"), type: const DynamicType());
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          fields: <Field>[field]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();
      return new TestCase(
          name: "/* suppose top-level: dynamic field; */ field = 1;",
          node:
              new ExpressionStatement(new StaticSet(field, new IntLiteral(1))),
          expectation: ""
              "(expr"
              " (set-static \"package:foo/bar.dart::@fields::field\" (int 1)))",
          serializationState: new SerializationState(null),
          deserializationState: new DeserializationState(null, component.root));
    }(),
    () {
      Procedure topLevelProcedure = new Procedure(
          new Name("foo"),
          ProcedureKind.Method,
          new FunctionNode(null, positionalParameters: <VariableDeclaration>[
            new VariableDeclaration("x", type: const DynamicType())
          ]),
          isStatic: true);
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          procedures: <Procedure>[topLevelProcedure]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();
      return new TestCase(
          name: "/* suppose top-level: foo(dynamic x) {...}; */ foo(42);",
          node: new ExpressionStatement(new StaticInvocation.byReference(
              topLevelProcedure.reference,
              new Arguments(<Expression>[new IntLiteral(42)]),
              isConst: false)),
          expectation: ""
              "(expr (invoke-static \"package:foo/bar.dart::@methods::foo\""
              " () ((int 42)) ()))",
          serializationState: new SerializationState(null),
          deserializationState: new DeserializationState(null, component.root));
    }(),
    () {
      Procedure factoryConstructor = new Procedure(
          new Name("foo"), ProcedureKind.Factory, new FunctionNode(null),
          isStatic: true, isConst: true);
      Class klass =
          new Class(name: "A", procedures: <Procedure>[factoryConstructor]);
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          classes: <Class>[klass]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();
      return new TestCase(
          name: ""
              "/* suppose A { const A(); const factory A.foo() = A; } */"
              " const A.foo();",
          node: new ExpressionStatement(new StaticInvocation.byReference(
              factoryConstructor.reference, new Arguments([]),
              isConst: true)),
          expectation: ""
              "(expr (invoke-const-static"
              " \"package:foo/bar.dart::A::@factories::foo\""
              " () () ()))",
          serializationState: new SerializationState(null),
          deserializationState: new DeserializationState(null, component.root));
    }(),
    () {
      Field field = new Field(new Name("field"), type: const DynamicType());
      Class klass = new Class(name: "A", fields: <Field>[field]);
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          classes: <Class>[klass]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();

      VariableDeclaration x =
          new VariableDeclaration("x", type: const DynamicType());
      return new TestCase(
          name: "/* suppose A {dynamic field;} A x; */ x.{A::field};",
          node: new ExpressionStatement(new DirectPropertyGet.byReference(
              new VariableGet(x), field.reference)),
          expectation: ""
              "(expr (get-direct-prop (get-var \"x^0\" _)"
              " \"package:foo/bar.dart::A::@fields::field\"))",
          serializationState:
              new SerializationState(new SerializationEnvironment(null)
                ..addBinder(x, "x^0")
                ..close()),
          deserializationState: new DeserializationState(
              new DeserializationEnvironment(null)
                ..addBinder("x^0", x)
                ..close(),
              component.root));
    }(),
    () {
      Field field = new Field(new Name("field"), type: const DynamicType());
      Class klass = new Class(name: "A", fields: <Field>[field]);
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          classes: <Class>[klass]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();

      VariableDeclaration x =
          new VariableDeclaration("x", type: const DynamicType());
      return new TestCase(
          name: "/* suppose A {dynamic field;} A x; */ x.{A::field} = 42;",
          node: new ExpressionStatement(new DirectPropertySet.byReference(
              new VariableGet(x), field.reference, new IntLiteral(42))),
          expectation: ""
              "(expr (set-direct-prop (get-var \"x^0\" _)"
              " \"package:foo/bar.dart::A::@fields::field\" (int 42)))",
          serializationState:
              new SerializationState(new SerializationEnvironment(null)
                ..addBinder(x, "x^0")
                ..close()),
          deserializationState: new DeserializationState(
              new DeserializationEnvironment(null)
                ..addBinder("x^0", x)
                ..close(),
              component.root));
    }(),
    () {
      Procedure method = new Procedure(
          new Name("foo"), ProcedureKind.Method, new FunctionNode(null),
          isStatic: true, isConst: true);
      Class klass = new Class(name: "A", procedures: <Procedure>[method]);
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          classes: <Class>[klass]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();

      VariableDeclaration x =
          new VariableDeclaration("x", type: const DynamicType());
      return new TestCase(
          name: "/* suppose A {foo() {...}} A x; */ x.{A::foo}();",
          node: new ExpressionStatement(new DirectMethodInvocation.byReference(
              new VariableGet(x), method.reference, new Arguments([]))),
          expectation: ""
              "(expr (invoke-direct-method (get-var \"x^0\" _)"
              " \"package:foo/bar.dart::A::@methods::foo\""
              " () () ()))",
          serializationState:
              new SerializationState(new SerializationEnvironment(null)
                ..addBinder(x, "x^0")
                ..close()),
          deserializationState: new DeserializationState(
              new DeserializationEnvironment(null)
                ..addBinder("x^0", x)
                ..close(),
              component.root));
    }(),
    () {
      Constructor constructor =
          new Constructor(new FunctionNode(null), name: new Name("foo"));
      Class klass =
          new Class(name: "A", constructors: <Constructor>[constructor]);
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          classes: <Class>[klass]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();
      return new TestCase(
          name: "/* suppose A {A.foo();} */ new A();",
          node: new ExpressionStatement(new ConstructorInvocation.byReference(
              constructor.reference, new Arguments([]))),
          expectation: ""
              "(expr (invoke-constructor"
              " \"package:foo/bar.dart::A::@constructors::foo\""
              " () () ()))",
          serializationState: new SerializationState(null),
          deserializationState: new DeserializationState(null, component.root));
    }(),
    () {
      Constructor constructor = new Constructor(new FunctionNode(null),
          name: new Name("foo"), isConst: true);
      Class klass =
          new Class(name: "A", constructors: <Constructor>[constructor]);
      Library library = new Library(
          new Uri(scheme: "package", path: "foo/bar.dart"),
          classes: <Class>[klass]);
      Component component = new Component(libraries: <Library>[library]);
      component.computeCanonicalNames();
      return new TestCase(
          name: "/* suppose A {const A.foo();} */ const A();",
          node: new ExpressionStatement(new ConstructorInvocation.byReference(
              constructor.reference, new Arguments([]),
              isConst: true)),
          expectation: ""
              "(expr (invoke-const-constructor"
              " \"package:foo/bar.dart::A::@constructors::foo\""
              " () () ()))",
          serializationState: new SerializationState(null),
          deserializationState: new DeserializationState(null, component.root));
    }(),
    () {
      TypeParameter outterParam =
          new TypeParameter("T", const DynamicType(), const DynamicType());
      TypeParameter innerParam =
          new TypeParameter("T", const DynamicType(), const DynamicType());
      return new TestCase(
          name: "/* T Function<T>(T Function<T>()); */",
          node: new ExpressionStatement(new TypeLiteral(new FunctionType(
              [
                new FunctionType(
                    [],
                    new TypeParameterType(innerParam, Nullability.legacy),
                    Nullability.legacy,
                    typeParameters: [innerParam])
              ],
              new TypeParameterType(outterParam, Nullability.legacy),
              Nullability.legacy,
              typeParameters: [outterParam]))),
          expectation: ""
              "(expr (type (-> (\"T^0\") ((dynamic)) ((dynamic)) "
              "((-> (\"T^1\") ((dynamic)) ((dynamic)) () () () "
              "(par \"T^1\" _))) () () (par \"T^0\" _))))",
          serializationState:
              new SerializationState(new SerializationEnvironment(null)),
          deserializationState: new DeserializationState(
              new DeserializationEnvironment(null), null));
    }(),
  ];
  for (TestCase testCase in tests) {
    String roundTripInput =
        writeStatement(testCase.node, testCase.serializationState);
    if (roundTripInput != testCase.expectation) {
      failures.add(''
          '* initial serialization for test "${testCase.name}"'
          ' gave output "${roundTripInput}"');
    }

    TreeNode deserialized =
        readStatement(roundTripInput, testCase.deserializationState);
    String roundTripOutput =
        writeStatement(deserialized, testCase.serializationState);
    if (roundTripOutput != roundTripInput) {
      failures.add(''
          '* input "${testCase.name}" gave output "${roundTripOutput}"');
    }
  }
  if (failures.isNotEmpty) {
    print('Round trip failures:');
    failures.forEach(print);
    throw StateError('Round trip failures');
  }
}
