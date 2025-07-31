// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';

/// The target of a `call` instruction in the IR.
sealed class CallDescriptor {
  String get name;
  List<DartType> get typeArguments;
}

/// Call descriptor for a call that resolves to a specific element (i.e., a
/// non-dynamic call).
class ElementCallDescriptor extends CallDescriptor {
  final ExecutableElement2 element;

  @override
  final List<DartType> typeArguments;

  ElementCallDescriptor(this.element, {this.typeArguments = const []});

  @override
  String get name => element.lookupName!;

  @override
  String toString() => switch (element.enclosingElement2) {
        InstanceElement2(name3: var typeName) =>
          '${typeName ?? '<unnamed>'}.${element.name3!}',
        _ => element.name3!
      };
}
