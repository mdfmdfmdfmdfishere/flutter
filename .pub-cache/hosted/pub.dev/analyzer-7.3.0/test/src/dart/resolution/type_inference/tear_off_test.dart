// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/error/codes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../context_collection_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(TearOffTest);
  });
}

@reflectiveTest
class TearOffTest extends PubPackageResolutionTest {
  test_empty_contextNotInstantiated() async {
    await assertErrorsInCode('''
T f<T>(T x) => x;

void test() {
  U Function<U>(U) context;
  context = f; // 1
}
''', [
      error(WarningCode.UNUSED_LOCAL_VARIABLE, 52, 7),
    ]);

    var node = findNode.simple('f; // 1');
    assertResolvedNodeText(node, r'''
SimpleIdentifier
  token: f
  parameter: <null>
  staticElement: <testLibraryFragment>::@function::f
  element: <testLibrary>::@function::f
  staticType: T Function<T>(T)
''');
  }

  test_empty_notGeneric() async {
    await assertErrorsInCode('''
int f(int x) => x;

void test() {
  int Function(int) context;
  context = f; // 1
}
''', [
      error(WarningCode.UNUSED_LOCAL_VARIABLE, 54, 7),
    ]);

    var node = findNode.simple('f; // 1');
    assertResolvedNodeText(node, r'''
SimpleIdentifier
  token: f
  parameter: <null>
  staticElement: <testLibraryFragment>::@function::f
  element: <testLibrary>::@function::f
  staticType: int Function(int)
''');
  }

  test_notEmpty_instanceMethod() async {
    await assertNoErrorsInCode('''
class C {
  T f<T>(T x) => x;
}

int Function(int) test() {
  return new C().f;
}
''');

    var node = findNode.functionReference('f;');
    assertResolvedNodeText(node, r'''
FunctionReference
  function: PropertyAccess
    target: InstanceCreationExpression
      keyword: new
      constructorName: ConstructorName
        type: NamedType
          name: C
          element: <testLibraryFragment>::@class::C
          element2: <testLibrary>::@class::C
          type: C
        staticElement: <testLibraryFragment>::@class::C::@constructor::new
        element: <testLibraryFragment>::@class::C::@constructor::new#element
      argumentList: ArgumentList
        leftParenthesis: (
        rightParenthesis: )
      staticType: C
    operator: .
    propertyName: SimpleIdentifier
      token: f
      staticElement: <testLibraryFragment>::@class::C::@method::f
      element: <testLibraryFragment>::@class::C::@method::f#element
      staticType: T Function<T>(T)
    staticType: T Function<T>(T)
  staticType: int Function(int)
  typeArgumentTypes
    int
''');
  }

  test_notEmpty_localFunction() async {
    await assertNoErrorsInCode('''
int Function(int) test() {
  T f<T>(T x) => x;
  return f;
}
''');

    var node = findNode.functionReference('f;');
    assertResolvedNodeText(node, r'''
FunctionReference
  function: SimpleIdentifier
    token: f
    staticElement: f@31
    element: f@31
    staticType: T Function<T>(T)
  staticType: int Function(int)
  typeArgumentTypes
    int
''');
  }

  test_notEmpty_staticMethod() async {
    await assertNoErrorsInCode('''
class C {
  static T f<T>(T x) => x;
}

int Function(int) test() {
  return C.f;
}
''');

    var node = findNode.functionReference('f;');
    assertResolvedNodeText(node, r'''
FunctionReference
  function: PrefixedIdentifier
    prefix: SimpleIdentifier
      token: C
      staticElement: <testLibraryFragment>::@class::C
      element: <testLibrary>::@class::C
      staticType: null
    period: .
    identifier: SimpleIdentifier
      token: f
      staticElement: <testLibraryFragment>::@class::C::@method::f
      element: <testLibraryFragment>::@class::C::@method::f#element
      staticType: T Function<T>(T)
    staticElement: <testLibraryFragment>::@class::C::@method::f
    element: <testLibraryFragment>::@class::C::@method::f#element
    staticType: T Function<T>(T)
  staticType: int Function(int)
  typeArgumentTypes
    int
''');
  }

  test_notEmpty_superMethod() async {
    await assertNoErrorsInCode('''
class C {
  T f<T>(T x) => x;
}

class D extends C {
  int Function(int) test() {
    return super.f;
  }
}
''');

    var node = findNode.functionReference('f;');
    assertResolvedNodeText(node, r'''
FunctionReference
  function: PropertyAccess
    target: SuperExpression
      superKeyword: super
      staticType: D
    operator: .
    propertyName: SimpleIdentifier
      token: f
      staticElement: <testLibraryFragment>::@class::C::@method::f
      element: <testLibraryFragment>::@class::C::@method::f#element
      staticType: T Function<T>(T)
    staticType: T Function<T>(T)
  staticType: int Function(int)
  typeArgumentTypes
    int
''');
  }

  test_notEmpty_topLevelFunction() async {
    await assertNoErrorsInCode('''
T f<T>(T x) => x;

int Function(int) test() {
  return f;
}
''');

    var node = findNode.functionReference('f;');
    assertResolvedNodeText(node, r'''
FunctionReference
  function: SimpleIdentifier
    token: f
    staticElement: <testLibraryFragment>::@function::f
    element: <testLibrary>::@function::f
    staticType: T Function<T>(T)
  staticType: int Function(int)
  typeArgumentTypes
    int
''');
  }

  test_null_notTearOff() async {
    await assertNoErrorsInCode('''
T f<T>(T x) => x;

void test() {
  f(0);
}
''');

    var node = findNode.singleMethodInvocation;
    assertResolvedNodeText(node, r'''
MethodInvocation
  methodName: SimpleIdentifier
    token: f
    staticElement: <testLibraryFragment>::@function::f
    element: <testLibrary>::@function::f
    staticType: T Function<T>(T)
  argumentList: ArgumentList
    leftParenthesis: (
    arguments
      IntegerLiteral
        literal: 0
        parameter: ParameterMember
          base: <testLibraryFragment>::@function::f::@parameter::x
          substitution: {T: int}
        staticType: int
    rightParenthesis: )
  staticInvokeType: int Function(int)
  staticType: int
  typeArgumentTypes
    int
''');
  }
}
