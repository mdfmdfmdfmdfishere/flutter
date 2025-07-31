// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/inheritance_manager3.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/resolver/extension_member_resolver.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/resolver.dart';

/// A resolver for [FunctionReference] nodes.
///
/// This resolver is responsible for writing a given [FunctionReference] as a
/// [ConstructorReference] or as a [TypeLiteral], depending on how a function
/// reference's `function` resolves.
class FunctionReferenceResolver {
  /// The resolver driving this participant.
  final ResolverVisitor _resolver;

  /// Helper for extension method resolution.
  final ExtensionMemberResolver _extensionResolver;

  /// The type representing the type 'type'.
  final InterfaceType _typeType;

  FunctionReferenceResolver(this._resolver)
      : _extensionResolver = _resolver.extensionResolver,
        _typeType = _resolver.typeProvider.typeType;

  ErrorReporter get _errorReporter => _resolver.errorReporter;

  void resolve(FunctionReferenceImpl node) {
    var function = node.function;
    node.typeArguments?.accept(_resolver);

    if (function is SimpleIdentifierImpl) {
      _resolveSimpleIdentifierFunction(node, function);
    } else if (function is PrefixedIdentifierImpl) {
      _resolvePrefixedIdentifierFunction(node, function);
    } else if (function is PropertyAccessImpl) {
      _resolvePropertyAccessFunction(node, function);
    } else if (function is ConstructorReferenceImpl) {
      var typeArguments = node.typeArguments;
      if (typeArguments != null) {
        // Something like `List.filled<int>`.
        _resolver.analyzeExpression(function, _resolver.operations.unknownType);
        _resolver.popRewrite();
        // We can safely assume `function.constructorName.name` is non-null
        // because if no name had been given, the construct would have been
        // interpreted as a type literal (e.g. `List<int>`).
        _errorReporter.atNode(
          typeArguments,
          CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_CONSTRUCTOR,
          arguments: [
            function.constructorName.type.qualifiedName,
            function.constructorName.name!.name
          ],
        );
        _resolve(node: node, rawType: function.staticType);
      }
    } else {
      // TODO(srawlins): Handle `function` being a [SuperExpression].

      _resolver.analyzeExpression(function, _resolver.operations.unknownType);
      function = _resolver.popRewrite()!;
      var functionType = function.staticType;
      if (functionType == null) {
        _resolveDisallowedExpression(node, functionType);
      } else if (functionType is FunctionType) {
        _resolve(node: node, rawType: functionType);
      } else {
        var callMethod = _getCallMethod(node, function.staticType);
        if (callMethod is MethodElement2) {
          _resolveAsImplicitCallReference(node, callMethod);
          return;
        } else {
          _resolveDisallowedExpression(node, functionType);
        }
      }
    }
  }

  /// Checks for a type instantiation of a `dynamic`-typed expression.
  ///
  /// Returns `true` if an error was reported, and resolution can stop.
  bool _checkDynamicTypeInstantiation(FunctionReferenceImpl node,
      PrefixedIdentifierImpl function, Element2 prefixElement) {
    DartType? prefixType;
    if (prefixElement is VariableElement2) {
      prefixType = prefixElement.type;
    } else if (prefixElement is PropertyAccessorElement2) {
      var variable = prefixElement.variable3;
      if (variable == null) {
        return false;
      }
      prefixType = variable.type;
    }

    if (prefixType is DynamicType) {
      _errorReporter.atNode(
        function,
        CompileTimeErrorCode.GENERIC_METHOD_TYPE_INSTANTIATION_ON_DYNAMIC,
      );
      node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
      return true;
    }
    return false;
  }

  List<DartType> _checkTypeArguments(
    TypeArgumentList typeArgumentList,
    String? name,
    List<TypeParameterElement2> typeParameters,
    CompileTimeErrorCode errorCode,
  ) {
    if (typeArgumentList.arguments.length != typeParameters.length) {
      if (name == null &&
          errorCode ==
              CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_FUNCTION) {
        errorCode = CompileTimeErrorCode
            .WRONG_NUMBER_OF_TYPE_ARGUMENTS_ANONYMOUS_FUNCTION;
        _errorReporter.atNode(
          typeArgumentList,
          errorCode,
          arguments: [typeParameters.length, typeArgumentList.arguments.length],
        );
      } else {
        assert(name != null);
        _errorReporter.atNode(
          typeArgumentList,
          errorCode,
          arguments: [
            name!,
            typeParameters.length,
            typeArgumentList.arguments.length
          ],
        );
      }
      return List.filled(typeParameters.length, DynamicTypeImpl.instance);
    } else {
      return typeArgumentList.arguments
          .map((typeAnnotation) => typeAnnotation.typeOrThrow)
          .toList();
    }
  }

  ExecutableElement2? _getCallMethod(
      FunctionReferenceImpl node, DartType? type) {
    if (type is! InterfaceTypeImpl) {
      return null;
    }
    var callMethodName = Name(
        _resolver.definingLibrary.source.uri, MethodElement2.CALL_METHOD_NAME);
    if (type.nullabilitySuffix == NullabilitySuffix.question) {
      // If the interface type is nullable, only an applicable extension method
      // applies.
      return _extensionResolver
          .findExtension(type, node, callMethodName)
          .getter2;
    }
    // Otherwise, a 'call' method on the interface, or on an applicable
    // extension method applies.
    return type.lookUpMethod3(
            MethodElement2.CALL_METHOD_NAME, type.element3.library2) ??
        _extensionResolver.findExtension(type, node, callMethodName).getter2;
  }

  void _reportInvalidAccessToStaticMember(
    SimpleIdentifier nameNode,
    ExecutableElement2 element, {
    required bool implicitReceiver,
  }) {
    var enclosingElement = element.enclosingElement2!;
    if (implicitReceiver) {
      if (_resolver.enclosingExtension != null) {
        _resolver.errorReporter.atNode(
          nameNode,
          CompileTimeErrorCode
              .UNQUALIFIED_REFERENCE_TO_STATIC_MEMBER_OF_EXTENDED_TYPE,
          arguments: [enclosingElement.displayName],
        );
      } else {
        _resolver.errorReporter.atNode(
          nameNode,
          CompileTimeErrorCode.UNQUALIFIED_REFERENCE_TO_NON_LOCAL_STATIC_MEMBER,
          arguments: [enclosingElement.displayName],
        );
      }
    } else if (enclosingElement is ExtensionElement2 &&
        enclosingElement.name3 == null) {
      _resolver.errorReporter.atNode(
        nameNode,
        CompileTimeErrorCode
            .INSTANCE_ACCESS_TO_STATIC_MEMBER_OF_UNNAMED_EXTENSION,
        arguments: [
          nameNode.name,
          element.kind.displayName,
        ],
      );
    } else {
      // It is safe to assume that `enclosingElement.name` is non-`null` because
      // it can only be `null` for extensions, and we handle that case above.
      _resolver.errorReporter.atNode(
        nameNode,
        CompileTimeErrorCode.INSTANCE_ACCESS_TO_STATIC_MEMBER,
        arguments: [
          nameNode.name,
          element.kind.displayName,
          enclosingElement.name3!,
          enclosingElement is MixinElement2
              ? 'mixin'
              : enclosingElement.kind.displayName,
        ],
      );
    }
  }

  /// Resolves [node]'s static type, as an instantiated function type, and type
  /// argument types, using [rawType] as the uninstantiated function type.
  void _resolve({
    required FunctionReferenceImpl node,
    required DartType? rawType,
    String? name,
  }) {
    if (rawType == null) {
      node.recordStaticType(DynamicTypeImpl.instance, resolver: _resolver);
    }

    if (rawType is InvalidType) {
      node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
      return;
    }

    if (rawType is TypeParameterTypeImpl) {
      // If the type of the function is a type parameter, the tearoff is
      // disallowed, reported in [_resolveDisallowedExpression]. Use the type
      // parameter's bound here in an attempt to assign the intended types.
      rawType = rawType.element3.bound;
    }

    if (rawType is FunctionType) {
      // A FunctionReference with type arguments and with a
      // ConstructorReference child is invalid. E.g. `List.filled<int>`.
      // [CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_CONSTRUCTOR] is
      // reported elsewhere; don't check type arguments here.
      if (node.function is ConstructorReference) {
        node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
      } else {
        var typeArguments = node.typeArguments;
        if (typeArguments == null) {
          node.recordStaticType(rawType, resolver: _resolver);
        } else {
          var typeArgumentTypes = _checkTypeArguments(
            typeArguments,
            name,
            rawType.typeParameters,
            CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_FUNCTION,
          );

          var invokeType = rawType.instantiate(typeArgumentTypes);
          node.typeArgumentTypes = typeArgumentTypes;
          node.recordStaticType(invokeType, resolver: _resolver);
        }
      }
    } else {
      if (_resolver.isConstructorTearoffsEnabled) {
        // Only report constructor tearoff-related errors if the constructor
        // tearoff feature is enabled.
        _errorReporter.atNode(
          node.function,
          CompileTimeErrorCode.DISALLOWED_TYPE_INSTANTIATION_EXPRESSION,
        );
        node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
      } else if (rawType is DynamicType) {
        node.recordStaticType(DynamicTypeImpl.instance, resolver: _resolver);
      } else {
        node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
      }
    }
  }

  void _resolveAsImplicitCallReference(
      FunctionReferenceImpl node, MethodElement2 callMethod) {
    // `node<...>` is to be treated as `node.call<...>`.
    var callMethodType = callMethod.type;
    var typeArgumentTypes = _checkTypeArguments(
      // `node.typeArguments`, coming from the parser, is never null.
      node.typeArguments!, MethodElement2.CALL_METHOD_NAME,
      callMethodType.typeParameters,
      CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS_FUNCTION,
    );
    var callReference = ImplicitCallReferenceImpl(
      expression: node.function,
      element: callMethod,
      typeArguments: node.typeArguments,
      typeArgumentTypes: typeArgumentTypes,
    );
    _resolver.replaceExpression(node, callReference);
    var instantiatedType = callMethodType.instantiate(typeArgumentTypes);
    callReference.recordStaticType(instantiatedType, resolver: _resolver);
  }

  void _resolveConstructorReference(FunctionReferenceImpl node) {
    // TODO(srawlins): Rewrite and resolve [node] as a constructor reference.
    node.function.accept(_resolver);
    node.setPseudoExpressionStaticType(DynamicTypeImpl.instance);
  }

  /// Resolves [node] as a [TypeLiteral] referencing an interface type directly
  /// (not through a type alias).
  void _resolveDirectTypeLiteral(FunctionReferenceImpl node,
      IdentifierImpl name, InterfaceElementImpl2 element) {
    var typeArguments = _checkTypeArguments(
      // `node.typeArguments`, coming from the parser, is never null.
      node.typeArguments!, name.name,
      element.typeParameters2,
      CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS,
    );
    var type = element.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
    _resolveTypeLiteral(node: node, instantiatedType: type, name: name);
  }

  /// Resolves [node] as a type instantiation on an illegal expression.
  ///
  /// This function attempts to give [node] a static type, to continue working
  /// with what the user may be intending.
  void _resolveDisallowedExpression(
      FunctionReferenceImpl node, DartType? rawType) {
    if (_resolver.isConstructorTearoffsEnabled) {
      // Only report constructor tearoff-related errors if the constructor
      // tearoff feature is enabled.
      _errorReporter.atNode(
        node.function,
        CompileTimeErrorCode.DISALLOWED_TYPE_INSTANTIATION_EXPRESSION,
      );
    }
    _resolve(node: node, rawType: rawType);
  }

  void _resolveExtensionOverride(
    FunctionReferenceImpl node,
    PropertyAccessImpl function,
    ExtensionOverride override,
  ) {
    var propertyName = function.propertyName;
    var result =
        _extensionResolver.getOverrideMember(override, propertyName.name);
    var member = result.getter2;

    if (member == null) {
      node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
      return;
    }

    if (member.isStatic) {
      _resolver.errorReporter.atNode(
        function.propertyName,
        CompileTimeErrorCode.EXTENSION_OVERRIDE_ACCESS_TO_STATIC_MEMBER,
      );
      // Continue to resolve type.
    }

    if (function.isCascaded) {
      _resolver.errorReporter.atToken(
        override.name,
        CompileTimeErrorCode.EXTENSION_OVERRIDE_WITH_CASCADE,
      );
      // Continue to resolve type.
    }

    if (member is PropertyAccessorElement2) {
      _resolve(node: node, rawType: member.returnType);
      return;
    }

    _resolve(node: node, rawType: member.type, name: propertyName.name);
  }

  /// Resolve a possible function tearoff of a [FunctionTypedElement2] receiver.
  ///
  /// There are three possible valid cases: tearing off the `call` method of a
  /// function element, tearing off an extension element declared on [Function],
  /// and tearing off an extension element declared on a function type.
  Element2? _resolveFunctionTypeFunction(
    ExpressionImpl receiver,
    SimpleIdentifier methodName,
    FunctionTypeImpl receiverType,
  ) {
    var methodElement = _resolver.typePropertyResolver
        .resolve(
          receiver: receiver,
          receiverType: receiverType,
          name: methodName.name,
          propertyErrorEntity: methodName,
          nameErrorEntity: methodName,
        )
        .getter2;
    if (methodElement != null && methodElement.isStatic) {
      _reportInvalidAccessToStaticMember(methodName, methodElement,
          implicitReceiver: false);
    }
    return methodElement;
  }

  void _resolvePrefixedIdentifierFunction(
      FunctionReferenceImpl node, PrefixedIdentifierImpl function) {
    var prefixElement = function.prefix.scopeLookupResult!.getter2;

    if (prefixElement == null) {
      _errorReporter.atNode(
        function.prefix,
        CompileTimeErrorCode.UNDEFINED_IDENTIFIER,
        arguments: [function.name],
      );
      function.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
      node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
      return;
    }

    function.prefix.element = prefixElement;
    function.prefix.setPseudoExpressionStaticType(
        prefixElement is PromotableElement2
            ? _resolver.localVariableTypeProvider
                .getType(function.prefix, isRead: true)
            : prefixElement.referenceType);
    var functionName = function.identifier.name;

    if (prefixElement is PrefixElement2) {
      var functionElement = prefixElement.scope.lookup(functionName).getter2;
      if (functionElement == null) {
        _errorReporter.atNode(
          function.identifier,
          CompileTimeErrorCode.UNDEFINED_PREFIXED_NAME,
          arguments: [functionName, function.prefix.name],
        );
        function.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
        node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
        return;
      } else {
        _resolveReceiverPrefix(node, prefixElement, function, functionElement);
        return;
      }
    }

    if (_checkDynamicTypeInstantiation(node, function, prefixElement)) {
      return;
    }

    if (prefixElement is TopLevelFunctionElement &&
        functionName == MethodElement2.CALL_METHOD_NAME) {
      _resolve(
        node: node,
        rawType: prefixElement.type,
        name: functionName,
      );
      return;
    }

    var propertyType = _resolveTypeProperty(
      receiver: function.prefix,
      name: function.identifier,
      nameErrorEntity: function,
    );

    var callMethod = _getCallMethod(node, propertyType);
    if (callMethod is MethodElement2) {
      _resolveAsImplicitCallReference(node, callMethod);
      return;
    }

    if (propertyType is FunctionType) {
      function.setPseudoExpressionStaticType(propertyType);
      _resolve(
        node: node,
        rawType: propertyType,
        name: functionName,
      );
      return;
    }

    if (propertyType != null) {
      // If the property is unknown, [UNDEFINED_GETTER] is reported elsewhere.
      // If it is known, we must report the bad type instantiation here.
      _errorReporter.atNode(
        function.identifier,
        CompileTimeErrorCode.DISALLOWED_TYPE_INSTANTIATION_EXPRESSION,
      );
    }
    _resolver.analyzeExpression(function, _resolver.operations.unknownType);
    _resolver.popRewrite();
    node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
  }

  void _resolvePropertyAccessFunction(
      FunctionReferenceImpl node, PropertyAccessImpl function) {
    _resolver.analyzeExpression(function, _resolver.operations.unknownType);
    _resolver.popRewrite();
    var callMethod = _getCallMethod(node, function.staticType);
    if (callMethod is MethodElement2) {
      _resolveAsImplicitCallReference(node, callMethod);
      return;
    }
    var target = function.realTarget;

    TypeImpl targetType;
    if (target is SuperExpressionImpl) {
      targetType = target.typeOrThrow;
    } else if (target is ThisExpressionImpl) {
      targetType = target.typeOrThrow;
    } else if (target is SimpleIdentifierImpl) {
      var targetElement = target.scopeLookupResult!.getter2;
      if (targetElement is VariableElement2OrMember) {
        targetType = targetElement.type;
      } else if (targetElement is PropertyAccessorElement2OrMember) {
        var variable = targetElement.variable3;
        if (variable == null) {
          node.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
          return;
        }
        targetType = variable.type;
      } else {
        // TODO(srawlins): Can we get here?
        node.setPseudoExpressionStaticType(DynamicTypeImpl.instance);
        return;
      }
    } else if (target is ExtensionOverrideImpl) {
      _resolveExtensionOverride(node, function, target);
      return;
    } else {
      var targetType = target.staticType;
      if (targetType is DynamicType) {
        _errorReporter.atNode(
          node,
          CompileTimeErrorCode.GENERIC_METHOD_TYPE_INSTANTIATION_ON_DYNAMIC,
        );
        node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
        return;
      } else if (targetType is InvalidType) {
        node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
        return;
      }
      var functionType = _resolveTypeProperty(
        receiver: target,
        name: function.propertyName,
        nameErrorEntity: function,
      );

      if (functionType is FunctionType) {
        function.setPseudoExpressionStaticType(functionType);
        _resolve(
          node: node,
          rawType: functionType,
          name: function.propertyName.name,
        );
        return;
      } else if (functionType != null) {
        // If the property is unknown, [UNDEFINED_GETTER] is reported elsewhere.
        // If it is known, we must report the bad type instantiation here.
        _errorReporter.atNode(
          function.propertyName,
          CompileTimeErrorCode.DISALLOWED_TYPE_INSTANTIATION_EXPRESSION,
        );
      }

      node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
      return;
    }

    var propertyElement = _resolver.typePropertyResolver
        .resolve(
          receiver: function.realTarget,
          receiverType: targetType,
          name: function.propertyName.name,
          propertyErrorEntity: function.propertyName,
          nameErrorEntity: function,
        )
        .getter2;

    if (propertyElement is TypeParameterElement2) {
      _resolve(node: node, rawType: propertyElement!.type);
      return;
    }

    _resolve(
      node: node,
      rawType: function.staticType,
      name: propertyElement?.name3,
    );
  }

  void _resolveReceiverPrefix(
    FunctionReferenceImpl node,
    PrefixElement2 prefixElement,
    PrefixedIdentifierImpl prefix,
    Element2 element,
  ) {
    if (element is MultiplyDefinedElement2) {
      MultiplyDefinedElement2 multiply = element;
      element = multiply.conflictingElements2[0];

      // TODO(srawlins): Add a resolution test for this case.
    }

    // Classes and type aliases are checked first so as to include a
    // PropertyAccess parent check, which does not need to be done for
    // functions.
    if (element is InterfaceElement2 || element is TypeAliasElement2) {
      // A type-instantiated constructor tearoff like `prefix.C<int>.name` is
      // initially represented as a [PropertyAccess] with a
      // [FunctionReference] 'target'.
      if (node.parent is PropertyAccess) {
        _resolveConstructorReference(node);
        return;
      } else if (element is InterfaceElementImpl2) {
        _resolver.analyzeExpression(
            node.function, _resolver.operations.unknownType);
        _resolver.popRewrite();
        _resolveDirectTypeLiteral(node, prefix, element);
        return;
      } else if (element is TypeAliasElementImpl2) {
        _resolver.analyzeExpression(prefix, _resolver.operations.unknownType);
        _resolver.popRewrite();
        _resolveTypeAlias(node: node, element: element, typeAlias: prefix);
        return;
      }
    } else if (element is ExecutableElement2) {
      _resolver.analyzeExpression(
          node.function, _resolver.operations.unknownType);
      _resolver.popRewrite();
      var callMethod = _getCallMethod(node, node.function.staticType);
      if (callMethod is MethodElement2) {
        _resolveAsImplicitCallReference(node, callMethod);
        return;
      }
      _resolve(
        node: node,
        rawType: node.function.typeOrThrow as FunctionType,
        name: element.name3,
      );
      return;
    } else if (element is ExtensionElement2) {
      prefix.identifier.element = element;
      prefix.identifier.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
      prefix.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
      _resolveDisallowedExpression(node, InvalidTypeImpl.instance);
      return;
    }

    assert(
      false,
      'Member of prefixed element, $prefixElement, is not a class, mixin, '
      'type alias, or executable element: $element (${element.runtimeType})',
    );
    node.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
  }

  void _resolveSimpleIdentifierFunction(
      FunctionReferenceImpl node, SimpleIdentifierImpl function) {
    var element = function.scopeLookupResult!.getter2;

    if (element == null) {
      TypeImpl receiverType;
      var enclosingClass = _resolver.enclosingClass;
      if (enclosingClass != null) {
        receiverType = enclosingClass.thisType;
      } else {
        var enclosingExtension = _resolver.enclosingExtension;
        if (enclosingExtension != null) {
          receiverType = enclosingExtension.extendedType;
        } else {
          _errorReporter.atNode(
            function,
            CompileTimeErrorCode.UNDEFINED_IDENTIFIER,
            arguments: [function.name],
          );
          function.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
          node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
          return;
        }
      }

      var result = _resolver.typePropertyResolver.resolve(
        receiver: null,
        receiverType: receiverType,
        name: function.name,
        propertyErrorEntity: function,
        nameErrorEntity: function,
      );

      var method = result.getter2;
      if (method != null) {
        if (method.isStatic) {
          _reportInvalidAccessToStaticMember(function, method,
              implicitReceiver: true);
          // Continue to assign types.
        }

        if (method is PropertyAccessorElement2OrMember) {
          function.element = method;
          function.setPseudoExpressionStaticType(method.returnType);
          var variable = method.variable3;
          if (variable != null) {
            _resolve(node: node, rawType: variable.type);
          } else {
            function.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
            node.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
          }
          return;
        }

        function.element = method;
        function.setPseudoExpressionStaticType(method.type);
        _resolve(node: node, rawType: method.type, name: function.name);
        return;
      } else {
        _resolver.errorReporter.atNode(
          function,
          CompileTimeErrorCode.UNDEFINED_METHOD,
          arguments: [function.name, receiverType],
        );
        function.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
        node.recordStaticType(InvalidTypeImpl.instance, resolver: _resolver);
        return;
      }
    }

    // Classes and type aliases are checked first so as to include a
    // PropertyAccess parent check, which does not need to be done for
    // functions.
    if (element is InterfaceElement2 || element is TypeAliasElement2) {
      // A type-instantiated constructor tearoff like `C<int>.name` or
      // `prefix.C<int>.name` is initially represented as a [PropertyAccess]
      // with a [FunctionReference] target.
      if (node.parent is PropertyAccess) {
        if (element is TypeAliasElementImpl2 &&
            element.aliasedType is FunctionType) {
          function.element = element;
          _resolveTypeAlias(node: node, element: element, typeAlias: function);
        } else {
          _resolveConstructorReference(node);
        }
        return;
      } else if (element is InterfaceElementImpl2) {
        function.element = element;
        _resolveDirectTypeLiteral(node, function, element);
        return;
      } else if (element is TypeAliasElementImpl2) {
        function.element = element;
        _resolveTypeAlias(node: node, element: element, typeAlias: function);
        return;
      }
    } else if (element is MethodElement2) {
      function.element = element;
      function.setPseudoExpressionStaticType(element.type);
      _resolve(node: node, rawType: element.type, name: element.name3);
      return;
    } else if (element is LocalFunctionElement) {
      function.element = element;
      function.setPseudoExpressionStaticType(element.type);
      _resolve(node: node, rawType: element.type, name: element.name3);
      return;
    } else if (element is TopLevelFunctionElement) {
      function.element = element;
      function.setPseudoExpressionStaticType(element.type);
      _resolve(node: node, rawType: element.type, name: element.name3);
      return;
    } else if (element is PropertyAccessorElement2) {
      function.element = element;
      var variable = element.variable3;
      if (variable == null) {
        function.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
        return;
      }
      function.setPseudoExpressionStaticType(variable.type);
      var callMethod = _getCallMethod(node, variable.type);
      if (callMethod is MethodElement2) {
        _resolveAsImplicitCallReference(node, callMethod);
        return;
      }
      _resolve(node: node, rawType: element.returnType);
      return;
    } else if (element is ExecutableElement2) {
      function.element = element;
      function.setPseudoExpressionStaticType(element.type);
      _resolve(node: node, rawType: element.type);
      return;
    } else if (element is VariableElement2) {
      function.element = element;
      function.setPseudoExpressionStaticType(element.type);
      var callMethod = _getCallMethod(node, element.type);
      if (callMethod is MethodElement2) {
        _resolveAsImplicitCallReference(node, callMethod);
        return;
      }
      _resolve(node: node, rawType: element.type);
      return;
    } else if (element is ExtensionElement2) {
      function.element = element;
      function.setPseudoExpressionStaticType(InvalidTypeImpl.instance);
      _resolveDisallowedExpression(node, InvalidTypeImpl.instance);
      return;
    } else {
      _resolveDisallowedExpression(node, DynamicTypeImpl.instance);
      return;
    }
  }

  /// Returns the element that represents the property named [propertyName] on
  /// [classElement].
  ExecutableElement2? _resolveStaticElement(
      InterfaceElement2 classElement, SimpleIdentifier propertyName) {
    String name = propertyName.name;
    ExecutableElement2? element;
    if (propertyName.inSetterContext()) {
      element = classElement.getSetter2(name);
    }
    element ??= classElement.getGetter2(name);
    element ??= classElement.getMethod2(name);
    if (element != null && element.isAccessibleIn2(_resolver.definingLibrary)) {
      return element;
    }
    return null;
  }

  void _resolveTypeAlias({
    required FunctionReferenceImpl node,
    required TypeAliasElementImpl2 element,
    required IdentifierImpl typeAlias,
  }) {
    var typeArguments = _checkTypeArguments(
      // `node.typeArguments`, coming from the parser, is never null.
      node.typeArguments!, element.name3,
      element.typeParameters2,
      CompileTimeErrorCode.WRONG_NUMBER_OF_TYPE_ARGUMENTS,
    );
    var type = element.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
    _resolveTypeLiteral(node: node, instantiatedType: type, name: typeAlias);
  }

  void _resolveTypeLiteral({
    required FunctionReferenceImpl node,
    required TypeImpl instantiatedType,
    required IdentifierImpl name,
  }) {
    // TODO(srawlins): set the static element of [typeName].
    // This involves a fair amount of resolution, as [name] may be a prefixed
    // identifier, etc. [NamedType]s should be resolved in [ResolutionVisitor],
    // and this could be done for nodes like this via [AstRewriter].
    var typeName = name.toNamedType(
      typeArguments: node.typeArguments,
      question: null,
    );
    typeName.type = instantiatedType;
    var typeLiteral = TypeLiteralImpl(
      typeName: typeName,
    );
    _resolver.replaceExpression(node, typeLiteral);
    typeLiteral.recordStaticType(_typeType, resolver: _resolver);
  }

  /// Resolves [name] as a property on [receiver].
  ///
  /// Returns `null` if [receiver]'s type is `null`, a [TypeParameterType],
  /// or a type alias for a non-interface type.
  DartType? _resolveTypeProperty({
    required ExpressionImpl receiver,
    required SimpleIdentifierImpl name,
    required SyntacticEntity nameErrorEntity,
  }) {
    if (receiver is IdentifierImpl) {
      var receiverElement = receiver.element;
      if (receiverElement is InterfaceElement2) {
        var element = _resolveStaticElement(receiverElement, name);
        name.element = element;
        return element?.referenceType;
      } else if (receiverElement is TypeAliasElement2) {
        var aliasedType = receiverElement.aliasedType;
        if (aliasedType is InterfaceType) {
          var element = _resolveStaticElement(aliasedType.element3, name);
          name.element = element;
          return element?.referenceType;
        } else {
          return null;
        }
      }
    }

    var receiverType = receiver.staticType;
    if (receiverType == null) {
      return null;
    } else if (receiverType is TypeParameterTypeImpl) {
      return null;
    } else if (receiverType is FunctionTypeImpl) {
      if (name.name == MethodElement2.CALL_METHOD_NAME) {
        return receiverType;
      }
      var element = _resolveFunctionTypeFunction(receiver, name, receiverType);
      name.element = element;
      return element?.referenceType;
    }

    var element = _resolver.typePropertyResolver
        .resolve(
          receiver: receiver,
          receiverType: receiverType,
          name: name.name,
          propertyErrorEntity: name,
          nameErrorEntity: nameErrorEntity,
        )
        .getter2;
    name.element = element;
    if (element != null && element.isStatic) {
      _reportInvalidAccessToStaticMember(name, element,
          implicitReceiver: false);
    }
    return element?.referenceType;
  }
}

extension on Element2 {
  /// Returns the 'type' of `this`, when accessed as a "reference", not
  /// immediately followed by parentheses and arguments.
  ///
  /// For all elements that don't have a type (for example, [LibraryElement2]),
  /// `null` is returned. For [PropertyAccessorElement2], the return value is
  /// returned. For all other elements, their `type` property is returned.
  DartType? get referenceType {
    if (this is ConstructorElement2) {
      return (this as ConstructorElement2).type;
    } else if (this is TopLevelFunctionElement) {
      return (this as TopLevelFunctionElement).type;
    } else if (this is PropertyAccessorElement2) {
      return (this as PropertyAccessorElement2).returnType;
    } else if (this is MethodElement2) {
      return (this as MethodElement2).type;
    } else if (this is VariableElement2) {
      return (this as VariableElement2).type;
    } else {
      return null;
    }
  }
}
