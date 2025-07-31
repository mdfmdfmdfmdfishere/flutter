// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/visitor2.dart';

/// Union of a set of names.
class ElementNameUnion {
  static const _maxLength = 63;

  /// The 0-th element is the length of the longest name in the union.
  ///
  /// Each following element is a bit mask for the A-Z letters in any name at
  /// this position. There are only 26 letters, so they fit into 30 bits.
  final Uint32List mask;

  ElementNameUnion.empty() : mask = Uint32List(1 + _maxLength);

  /// Constructs the union during reading from summary.
  ElementNameUnion.read(this.mask);

  void add(String name) {
    // If already overflow, no reason adding anything.
    if (mask[0] >= _maxLength) {
      return;
    }

    var index = 1;
    var codeUnits = name.codeUnits;
    for (var i = 0; i < codeUnits.length; i++) {
      var char = codeUnits[i];
      if (0x41 <= char && char <= 0x5A) {
        mask[index++] |= 1 << (char - 0x41);
      } else if (0x61 <= char && char <= 0x7A) {
        mask[index++] |= 1 << (char - 0x61);
      }
      if (index > _maxLength) {
        mask[0] = _maxLength;
        return;
      }
    }

    // Update the length.
    var length = index - 1;
    var maxLength = mask[0];
    if (maxLength < length) {
      mask[0] = length;
    }
  }

  /// Returns `true` if this union might contain a name that matches [pattern],
  /// and `false` if there is definitely no such name. So, it can have false
  /// positives, but no false negatives.
  ///
  /// Specifically, that there might be a name that contains all characters
  /// from `A-Z` and `a-z` sets from [pattern], in the same order. Other
  /// characters are ignored.
  bool contains(String pattern) {
    // If overflow, then contains any name.
    var maxLength = mask[0];
    if (maxLength >= _maxLength) {
      return true;
    }

    var index = 1;
    for (var i = 0; i < pattern.length; i++) {
      var patternChar = pattern.codeUnitAt(i);
      int patternMask;
      if (0x41 <= patternChar && patternChar <= 0x5A) {
        patternMask = 1 << (patternChar - 0x41);
      } else if (0x61 <= patternChar && patternChar <= 0x7A) {
        patternMask = 1 << (patternChar - 0x61);
      } else {
        continue;
      }
      while (true) {
        if (index > maxLength) {
          return false;
        }
        var indexMask = mask[index++];
        if ((indexMask & patternMask) != 0) {
          break;
        }
      }
    }

    return true;
  }

  static ElementNameUnion forLibrary(LibraryElement2 libraryElement) {
    var result = ElementNameUnion.empty();
    libraryElement.accept2(
      _ElementVisitor2(result),
    );
    return result;
  }

  static bool _hasInterestingElements(Element2 element) {
    if (element is ExecutableElement2) {
      return false;
    }
    return true;
  }

  static bool _isInterestingElement(Element2 element) {
    return element.enclosingElement2 is LibraryElement2 ||
        element is FieldElement2 ||
        element is MethodElement2 ||
        element is PropertyAccessorElement2;
  }
}

class _ElementVisitor2 extends GeneralizingElementVisitor2<void> {
  final ElementNameUnion union;

  _ElementVisitor2(this.union);

  @override
  void visitElement(Element2 element) {
    if (ElementNameUnion._isInterestingElement(element)) {
      var name = element.name3;
      if (name != null) {
        union.add(name);
      }
    }

    if (ElementNameUnion._hasInterestingElements(element)) {
      super.visitElement(element);
    }
  }
}
