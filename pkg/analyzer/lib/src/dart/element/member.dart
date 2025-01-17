// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_algebra.dart';
import 'package:analyzer/src/generated/engine.dart' show AnalysisContext;
import 'package:analyzer/src/generated/java_engine.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/utilities_dart.dart';
import 'package:meta/meta.dart';

/**
 * A constructor element defined in a parameterized type where the values of the
 * type parameters are known.
 */
class ConstructorMember extends ExecutableMember implements ConstructorElement {
  /**
   * Initialize a newly created element to represent a constructor, based on
   * the [declaration], and applied [substitution].
   */
  ConstructorMember(
    ConstructorElement declaration,
    MapSubstitution substitution,
  ) : super(declaration, substitution);

  @deprecated
  @override
  ConstructorElement get baseElement => declaration;

  @override
  ConstructorElement get declaration => super.declaration as ConstructorElement;

  @override
  ClassElement get enclosingElement => declaration.enclosingElement;

  @override
  bool get isConst => declaration.isConst;

  @override
  bool get isConstantEvaluated => declaration.isConstantEvaluated;

  @override
  bool get isDefaultConstructor => declaration.isDefaultConstructor;

  @override
  bool get isFactory => declaration.isFactory;

  @override
  int get nameEnd => declaration.nameEnd;

  @override
  int get periodOffset => declaration.periodOffset;

  @override
  ConstructorElement get redirectedConstructor {
    var element = this.declaration.redirectedConstructor;
    if (element == null) {
      return null;
    }

    ConstructorElement declaration;
    MapSubstitution substitution;
    if (element is ConstructorMember) {
      declaration = element._declaration;
      var map = <TypeParameterElement, DartType>{};
      var elementMap = element._substitution.map;
      for (var typeParameter in elementMap.keys) {
        var type = elementMap[typeParameter];
        map[typeParameter] = _substitution.substituteType(type);
      }
      substitution = Substitution.fromMap(map);
    } else {
      declaration = element;
      substitution = _substitution;
    }

    return ConstructorMember(declaration, substitution);
  }

  @override
  T accept<T>(ElementVisitor<T> visitor) =>
      visitor.visitConstructorElement(this);

  @override
  String toString() {
    ConstructorElement declaration = this.declaration;
    List<ParameterElement> parameters = this.parameters;
    FunctionType type = this.type;

    StringBuffer buffer = StringBuffer();
    if (type != null) {
      buffer.write(type.returnType);
      buffer.write(' ');
    }
    buffer.write(declaration.enclosingElement.displayName);
    String name = displayName;
    if (name != null && name.isNotEmpty) {
      buffer.write('.');
      buffer.write(name);
    }
    buffer.write('(');
    int parameterCount = parameters.length;
    for (int i = 0; i < parameterCount; i++) {
      if (i > 0) {
        buffer.write(', ');
      }
      buffer.write(parameters[i]);
    }
    buffer.write(')');
    return buffer.toString();
  }

  /**
   * If the given [constructor]'s type is different when any type parameters
   * from the defining type's declaration are replaced with the actual type
   * arguments from the [definingType], create a constructor member representing
   * the given constructor. Return the member that was created, or the original
   * constructor if no member was created.
   */
  static ConstructorElement from(
      ConstructorElement constructor, InterfaceType definingType) {
    if (constructor == null || definingType.typeArguments.isEmpty) {
      return constructor;
    }
    FunctionType baseType = constructor.type;
    if (baseType == null) {
      // TODO(brianwilkerson) We need to understand when this can happen.
      return constructor;
    }
    return ConstructorMember(
      constructor,
      Substitution.fromInterfaceType(definingType),
    );
  }
}

/**
 * An executable element defined in a parameterized type where the values of the
 * type parameters are known.
 */
abstract class ExecutableMember extends Member implements ExecutableElement {
  FunctionType _type;

  /**
   * Initialize a newly created element to represent a callable element (like a
   * method or function or property), based on the [declaration], and applied
   * [substitution].
   */
  ExecutableMember(
    ExecutableElement declaration,
    MapSubstitution substitution,
  ) : super(declaration, substitution);

  @deprecated
  @override
  ExecutableElement get baseElement => declaration;

  @override
  ExecutableElement get declaration => super.declaration as ExecutableElement;

  @override
  bool get hasImplicitReturnType => declaration.hasImplicitReturnType;

  @override
  bool get isAbstract => declaration.isAbstract;

  @override
  bool get isAsynchronous => declaration.isAsynchronous;

  @override
  bool get isExternal => declaration.isExternal;

  @override
  bool get isGenerator => declaration.isGenerator;

  @override
  bool get isOperator => declaration.isOperator;

  @override
  bool get isSimplyBounded => declaration.isSimplyBounded;

  @override
  bool get isStatic => declaration.isStatic;

  @override
  bool get isSynchronous => declaration.isSynchronous;

  @override
  List<ParameterElement> get parameters {
    return declaration.parameters.map((p) {
      if (p is FieldFormalParameterElement) {
        return FieldFormalParameterMember(p, _substitution);
      }
      return ParameterMember(p, _substitution);
    }).toList();
  }

  @override
  DartType get returnType => type.returnType;

  @override
  FunctionType get type {
    if (_type != null) return _type;

    return _type = _substitution.substituteType(declaration.type);
  }

  @override
  List<TypeParameterElement> get typeParameters {
    return TypeParameterMember.from(
      declaration.typeParameters,
      _substitution,
    );
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    // TODO(brianwilkerson) We need to finish implementing the accessors used
    // below so that we can safely invoke them.
    super.visitChildren(visitor);
    safelyVisitChildren(parameters, visitor);
  }

  static ExecutableElement from2(
    ExecutableElement element,
    MapSubstitution substitution,
  ) {
    var combined = substitution;
    if (element is ExecutableMember) {
      ExecutableMember member = element;
      element = member.declaration;
      var map = <TypeParameterElement, DartType>{};
      map.addAll(member._substitution.map);
      map.addAll(substitution.map);
      combined = Substitution.fromMap(map);
    }

    if (combined.map.isEmpty) {
      return element;
    }

    if (element is ConstructorElement) {
      return ConstructorMember(element, combined);
    } else if (element is MethodElement) {
      return MethodMember(element, combined);
    } else if (element is PropertyAccessorElement) {
      return PropertyAccessorMember(element, combined);
    } else {
      throw UnimplementedError('(${element.runtimeType}) $element');
    }
  }
}

/**
 * A parameter element defined in a parameterized type where the values of the
 * type parameters are known.
 */
class FieldFormalParameterMember extends ParameterMember
    implements FieldFormalParameterElement {
  /**
   * Initialize a newly created element to represent a field formal parameter,
   * based on the [declaration], with applied [substitution].
   */
  FieldFormalParameterMember(
    FieldFormalParameterElement declaration,
    MapSubstitution substitution,
  ) : super(declaration, substitution);

  @override
  FieldElement get field {
    var field = (declaration as FieldFormalParameterElement).field;
    if (field == null) {
      return null;
    }

    return FieldMember(field, _substitution);
  }

  @override
  bool get isCovariant => declaration.isCovariant;

  @override
  T accept<T>(ElementVisitor<T> visitor) =>
      visitor.visitFieldFormalParameterElement(this);
}

/**
 * A field element defined in a parameterized type where the values of the type
 * parameters are known.
 */
class FieldMember extends VariableMember implements FieldElement {
  /**
   * Initialize a newly created element to represent a field, based on the
   * [declaration], with applied [substitution].
   */
  FieldMember(
    FieldElement declaration,
    MapSubstitution substitution,
  ) : super(declaration, substitution);

  @deprecated
  @override
  FieldElement get baseElement => declaration;

  @override
  FieldElement get declaration => super.declaration as FieldElement;

  @override
  Element get enclosingElement => declaration.enclosingElement;

  @override
  PropertyAccessorElement get getter {
    var baseGetter = declaration.getter;
    if (baseGetter == null) {
      return null;
    }
    return PropertyAccessorMember(baseGetter, _substitution);
  }

  @override
  bool get isCovariant => declaration.isCovariant;

  @override
  bool get isEnumConstant => declaration.isEnumConstant;

  @override
  PropertyAccessorElement get setter {
    var baseSetter = declaration.setter;
    if (baseSetter == null) {
      return null;
    }
    return PropertyAccessorMember(baseSetter, _substitution);
  }

  @override
  T accept<T>(ElementVisitor<T> visitor) => visitor.visitFieldElement(this);

  @override
  String toString() => '$type $displayName';

  /**
   * If the given [field]'s type is different when any type parameters from the
   * defining type's declaration are replaced with the actual type arguments
   * from the [definingType], create a field member representing the given
   * field. Return the member that was created, or the base field if no member
   * was created.
   */
  static FieldElement from(FieldElement field, InterfaceType definingType) {
    if (field == null || definingType.typeArguments.isEmpty) {
      return field;
    }
    return FieldMember(
      field,
      Substitution.fromInterfaceType(definingType),
    );
  }

  static FieldElement from2(
    FieldElement element,
    MapSubstitution substitution,
  ) {
    if (substitution.map.isEmpty) {
      return element;
    }
    return FieldMember(element, substitution);
  }
}

/**
 * An element defined in a parameterized type where the values of the type
 * parameters are known.
 */
abstract class Member implements Element {
  /**
   * The element on which the parameterized element was created.
   */
  final Element _declaration;

  /**
   * The substitution for type parameters referenced in the base element.
   */
  final MapSubstitution _substitution;

  /**
   * Initialize a newly created element to represent a member, based on the
   * [declaration], and applied [_substitution].
   */
  Member(this._declaration, this._substitution) {
    if (_declaration is Member) {
      throw StateError('Members must be created from a declarations.');
    }
  }

  /**
   * Return the element on which the parameterized element was created.
   */
  @Deprecated('Use Element.declaration instead')
  Element get baseElement => _declaration;

  @override
  AnalysisContext get context => _declaration.context;

  @override
  Element get declaration => _declaration;

  @override
  String get displayName => _declaration.displayName;

  @override
  String get documentationComment => _declaration.documentationComment;

  @override
  bool get hasAlwaysThrows => _declaration.hasAlwaysThrows;

  @override
  bool get hasDeprecated => _declaration.hasDeprecated;

  @override
  bool get hasFactory => _declaration.hasFactory;

  @override
  bool get hasIsTest => _declaration.hasIsTest;

  @override
  bool get hasIsTestGroup => _declaration.hasIsTestGroup;

  @override
  bool get hasJS => _declaration.hasJS;

  @override
  bool get hasLiteral => _declaration.hasLiteral;

  @override
  bool get hasMustCallSuper => _declaration.hasMustCallSuper;

  @override
  bool get hasNonVirtual => _declaration.hasNonVirtual;

  @override
  bool get hasOptionalTypeArgs => _declaration.hasOptionalTypeArgs;

  @override
  bool get hasOverride => _declaration.hasOverride;

  @override
  bool get hasProtected => _declaration.hasProtected;

  @override
  bool get hasRequired => _declaration.hasRequired;

  @override
  bool get hasSealed => _declaration.hasSealed;

  @override
  bool get hasVisibleForTemplate => _declaration.hasVisibleForTemplate;

  @override
  bool get hasVisibleForTesting => _declaration.hasVisibleForTesting;

  @override
  int get id => _declaration.id;

  @override
  bool get isPrivate => _declaration.isPrivate;

  @override
  bool get isPublic => _declaration.isPublic;

  @override
  bool get isSynthetic => _declaration.isSynthetic;

  @override
  ElementKind get kind => _declaration.kind;

  @override
  LibraryElement get library => _declaration.library;

  @override
  Source get librarySource => _declaration.librarySource;

  @override
  ElementLocation get location => _declaration.location;

  @override
  List<ElementAnnotation> get metadata => _declaration.metadata;

  @override
  String get name => _declaration.name;

  @override
  int get nameLength => _declaration.nameLength;

  @override
  int get nameOffset => _declaration.nameOffset;

  @override
  AnalysisSession get session => _declaration.session;

  @override
  Source get source => _declaration.source;

  /**
   * The substitution for type parameters referenced in the base element.
   */
  MapSubstitution get substitution => _substitution;

  @override
  E getAncestor<E extends Element>(Predicate<Element> predicate) =>
      declaration.getAncestor(predicate);

  @override
  String getExtendedDisplayName(String shortName) =>
      _declaration.getExtendedDisplayName(shortName);

  @override
  bool isAccessibleIn(LibraryElement library) =>
      _declaration.isAccessibleIn(library);

  /**
   * Use the given [visitor] to visit all of the [children].
   */
  void safelyVisitChildren(List<Element> children, ElementVisitor visitor) {
    // TODO(brianwilkerson) Make this private
    if (children != null) {
      for (Element child in children) {
        child.accept(visitor);
      }
    }
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    // There are no children to visit
  }
}

/**
 * A method element defined in a parameterized type where the values of the type
 * parameters are known.
 */
class MethodMember extends ExecutableMember implements MethodElement {
  /**
   * Initialize a newly created element to represent a method, based on the
   * [declaration], with applied [substitution].
   */
  MethodMember(
    MethodElement declaration,
    MapSubstitution substitution,
  ) : super(declaration, substitution);

  @deprecated
  @override
  MethodElement get baseElement => declaration;

  @override
  MethodElement get declaration => super.declaration as MethodElement;

  @override
  Element get enclosingElement => declaration.enclosingElement;

  @override
  T accept<T>(ElementVisitor<T> visitor) => visitor.visitMethodElement(this);

  @override
  String toString() {
    MethodElement declaration = this.declaration;
    List<ParameterElement> parameters = this.parameters;
    FunctionType type = this.type;

    StringBuffer buffer = StringBuffer();
    if (type != null) {
      buffer.write(type.returnType);
      buffer.write(' ');
    }
    buffer.write(declaration.enclosingElement.displayName);
    buffer.write('.');
    buffer.write(declaration.displayName);
    int typeParameterCount = typeParameters.length;
    if (typeParameterCount > 0) {
      buffer.write('<');
      for (int i = 0; i < typeParameterCount; i++) {
        if (i > 0) {
          buffer.write(', ');
        }
        // TODO(scheglov) consider always using TypeParameterMember
        var typeParameter = typeParameters[i];
        if (typeParameter is TypeParameterElementImpl) {
          typeParameter.appendTo(buffer);
        } else
          (typeParameter as TypeParameterMember).appendTo(buffer);
      }
      buffer.write('>');
    }
    buffer.write('(');
    String closing;
    ParameterKind kind = ParameterKind.REQUIRED;
    int parameterCount = parameters.length;
    for (int i = 0; i < parameterCount; i++) {
      if (i > 0) {
        buffer.write(', ');
      }
      ParameterElement parameter = parameters[i];
      // ignore: deprecated_member_use_from_same_package
      ParameterKind parameterKind = parameter.parameterKind;
      if (parameterKind != kind) {
        if (closing != null) {
          buffer.write(closing);
        }
        if (parameter.isOptionalPositional) {
          buffer.write('[');
          closing = ']';
        } else if (parameter.isNamed) {
          buffer.write('{');
          closing = '}';
        } else {
          closing = null;
        }
      }
      kind = parameterKind;
      parameter.appendToWithoutDelimiters(buffer);
    }
    if (closing != null) {
      buffer.write(closing);
    }
    buffer.write(')');
    return buffer.toString();
  }

  /**
   * If the given [method]'s type is different when any type parameters from the
   * defining type's declaration are replaced with the actual type arguments
   * from the [definingType], create a method member representing the given
   * method. Return the member that was created, or the base method if no member
   * was created.
   */
  static MethodElement from(MethodElement method, InterfaceType definingType) {
    if (method == null || definingType.typeArguments.isEmpty) {
      return method;
    }

    return MethodMember(
      method,
      Substitution.fromInterfaceType(definingType),
    );
  }

  static MethodElement from2(
    MethodElement element,
    MapSubstitution substitution,
  ) {
    if (substitution.map.isEmpty) {
      return element;
    }
    return MethodMember(element, substitution);
  }
}

/**
 * A parameter element defined in a parameterized type where the values of the
 * type parameters are known.
 */
class ParameterMember extends VariableMember
    with ParameterElementMixin
    implements ParameterElement {
  /**
   * Initialize a newly created element to represent a parameter, based on the
   * [declaration], with applied [substitution]. If [type] is passed it will
   * represent the already substituted type.
   */
  ParameterMember(
    ParameterElement declaration,
    MapSubstitution substitution, [
    DartType type,
  ]) : super._(declaration, substitution, type);

  @deprecated
  @override
  ParameterElement get baseElement => declaration;

  @override
  ParameterElement get declaration => super.declaration as ParameterElement;

  @override
  String get defaultValueCode => declaration.defaultValueCode;

  @override
  Element get enclosingElement => declaration.enclosingElement;

  @override
  int get hashCode => declaration.hashCode;

  @override
  bool get isCovariant => declaration.isCovariant;

  @override
  bool get isInitializingFormal => declaration.isInitializingFormal;

  @deprecated
  @override
  ParameterKind get parameterKind => declaration.parameterKind;

  @override
  List<ParameterElement> get parameters {
    DartType type = this.type;
    if (type is FunctionType) {
      return type.parameters;
    }
    return const <ParameterElement>[];
  }

  @override
  List<TypeParameterElement> get typeParameters {
    return TypeParameterMember.from(
      declaration.typeParameters,
      _substitution,
    );
  }

  @override
  T accept<T>(ElementVisitor<T> visitor) => visitor.visitParameterElement(this);

  @override
  E getAncestor<E extends Element>(Predicate<Element> predicate) {
    Element element = declaration.getAncestor(predicate);
    if (element is ExecutableElement) {
      return ExecutableMember.from2(element, _substitution) as E;
    }
    return element as E;
  }

  @override
  String toString() {
    ParameterElement declaration = this.declaration;
    String left = "";
    String right = "";
    while (true) {
      if (declaration.isNamed) {
        left = "{";
        right = "}";
      } else if (declaration.isOptionalPositional) {
        left = "[";
        right = "]";
      }
      break;
    }
    return '$left$type ${declaration.displayName}$right';
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    super.visitChildren(visitor);
    safelyVisitChildren(parameters, visitor);
  }
}

/**
 * A property accessor element defined in a parameterized type where the values
 * of the type parameters are known.
 */
class PropertyAccessorMember extends ExecutableMember
    implements PropertyAccessorElement {
  /**
   * Initialize a newly created element to represent a property, based on the
   * [declaration], with applied [substitution].
   */
  PropertyAccessorMember(
    PropertyAccessorElement declaration,
    MapSubstitution substitution,
  ) : super(declaration, substitution);

  @deprecated
  @override
  PropertyAccessorElement get baseElement => declaration;

  @override
  PropertyAccessorElement get correspondingGetter {
    return PropertyAccessorMember(
      declaration.correspondingGetter,
      _substitution,
    );
  }

  @override
  PropertyAccessorElement get correspondingSetter {
    return PropertyAccessorMember(
      declaration.correspondingSetter,
      _substitution,
    );
  }

  @override
  PropertyAccessorElement get declaration =>
      super.declaration as PropertyAccessorElement;

  @override
  Element get enclosingElement => declaration.enclosingElement;

  @override
  bool get isGetter => declaration.isGetter;

  @override
  bool get isSetter => declaration.isSetter;

  @override
  PropertyInducingElement get variable {
    PropertyInducingElement variable = declaration.variable;
    if (variable is FieldElement) {
      return FieldMember(variable, _substitution);
    }
    return variable;
  }

  @override
  T accept<T>(ElementVisitor<T> visitor) =>
      visitor.visitPropertyAccessorElement(this);

  @override
  String toString() {
    PropertyAccessorElement declaration = this.declaration;
    List<ParameterElement> parameters = this.parameters;
    FunctionType type = this.type;

    StringBuffer builder = StringBuffer();
    if (type != null) {
      builder.write(type.returnType);
      builder.write(' ');
    }
    if (isGetter) {
      builder.write('get ');
    } else {
      builder.write('set ');
    }
    builder.write(declaration.enclosingElement.displayName);
    builder.write('.');
    builder.write(declaration.displayName);
    builder.write('(');
    int parameterCount = parameters.length;
    for (int i = 0; i < parameterCount; i++) {
      if (i > 0) {
        builder.write(', ');
      }
      builder.write(parameters[i]);
    }
    builder.write(')');
    return builder.toString();
  }

  /**
   * If the given [accessor]'s type is different when any type parameters from
   * the defining type's declaration are replaced with the actual type
   * arguments from the [definingType], create an accessor member representing
   * the given accessor. Return the member that was created, or the base
   * accessor if no member was created.
   */
  static PropertyAccessorElement from(
      PropertyAccessorElement accessor, InterfaceType definingType) {
    if (accessor == null || definingType.typeArguments.isEmpty) {
      return accessor;
    }

    return PropertyAccessorMember(
      accessor,
      Substitution.fromInterfaceType(definingType),
    );
  }
}

/**
 * A type parameter defined inside of another parameterized type, where the
 * values of the enclosing type parameters are known.
 *
 * For example:
 *
 *     class C<T> {
 *       S m<S extends T>(S s);
 *     }
 *
 * If we have `C<num>.m` and we ask for the type parameter "S", we should get
 * `<S extends num>` instead of `<S extends T>`. This is how the parameter
 * and return types work, see: [FunctionType.parameters],
 * [FunctionType.returnType], and [ParameterMember].
 */
class TypeParameterMember extends Member implements TypeParameterElement {
  DartType _bound;
  DartType _type;

  TypeParameterMember(TypeParameterElement declaration,
      MapSubstitution substitution, this._bound)
      : super(declaration, substitution) {
    _type = TypeParameterTypeImpl(this);
  }

  @deprecated
  @override
  TypeParameterElement get baseElement => declaration;

  @override
  DartType get bound => _bound;

  @override
  TypeParameterElement get declaration =>
      super.declaration as TypeParameterElement;

  @override
  Element get enclosingElement => declaration.enclosingElement;

  @override
  int get hashCode => declaration.hashCode;

  @override
  TypeParameterType get type => _type;

  @override
  bool operator ==(Object other) {
    return declaration == other;
  }

  @override
  T accept<T>(ElementVisitor<T> visitor) =>
      visitor.visitTypeParameterElement(this);

  void appendTo(StringBuffer buffer) {
    buffer.write(displayName);
    if (bound != null) {
      buffer.write(" extends ");
      buffer.write(bound);
    }
  }

  @override
  TypeParameterType instantiate({
    @required NullabilitySuffix nullabilitySuffix,
  }) {
    return TypeParameterTypeImpl(this, nullabilitySuffix: nullabilitySuffix);
  }

  @override
  String toString() {
    var buffer = StringBuffer();
    appendTo(buffer);
    return buffer.toString();
  }

  static List<TypeParameterElement> from(
    List<TypeParameterElement> elements,
    MapSubstitution substitution,
  ) {
    if (substitution.map.isEmpty) {
      return elements;
    }

    // Create type formals with specialized bounds.
    // For example `<U extends T>` where T comes from an outer scope.
    var newElements = List<TypeParameterElement>(elements.length);
    var newTypes = List<TypeParameterType>(elements.length);
    for (int i = 0; i < newElements.length; i++) {
      var element = elements[i];
      var bound = element.bound;
      if (bound != null) {
        bound = substitution.substituteType(bound);
        element = TypeParameterMember(element, substitution, bound);
      }
      newElements[i] = element;
      newTypes[i] = newElements[i].instantiate(
        nullabilitySuffix: NullabilitySuffix.none,
      );
    }

    // Update bounds to reference new TypeParameterMember(s).
    var substitution2 = Substitution.fromPairs(elements, newTypes);
    for (var newElement in newElements) {
      if (newElement is TypeParameterMember) {
        newElement._bound = substitution2.substituteType(newElement.bound);
      }
    }
    return newElements;
  }
}

/**
 * A variable element defined in a parameterized type where the values of the
 * type parameters are known.
 */
abstract class VariableMember extends Member implements VariableElement {
  DartType _type;

  /**
   * Initialize a newly created element to represent a variable, based on the
   * [declaration], with applied [substitution].
   */
  VariableMember(
    VariableElement declaration,
    MapSubstitution substitution, [
    DartType type,
  ])  : _type = type,
        super(declaration, substitution);

  // TODO(jmesserly): this is temporary to allow the ParameterMember subclass.
  // Apparently mixins don't work with optional params.
  VariableMember._(VariableElement declaration, MapSubstitution substitution,
      [DartType type])
      : this(declaration, substitution, type);

  @deprecated
  @override
  VariableElement get baseElement => declaration;

  @override
  DartObject get constantValue => declaration.constantValue;

  @override
  VariableElement get declaration => super.declaration as VariableElement;

  @override
  bool get hasImplicitType => declaration.hasImplicitType;

  @override
  FunctionElement get initializer {
    //
    // Elements within this element should have type parameters substituted,
    // just like this element.
    //
    throw UnsupportedError('initializer');
    //    return getBaseElement().getInitializer();
  }

  @override
  bool get isConst => declaration.isConst;

  @override
  bool get isConstantEvaluated => declaration.isConstantEvaluated;

  @override
  bool get isFinal => declaration.isFinal;

  @override
  bool get isLate => declaration.isLate;

  @override
  bool get isStatic => declaration.isStatic;

  @override
  DartType get type {
    if (_type != null) return _type;

    return _type = _substitution.substituteType(declaration.type);
  }

  @override
  DartObject computeConstantValue() => declaration.computeConstantValue();

  @override
  void visitChildren(ElementVisitor visitor) {
    // TODO(brianwilkerson) We need to finish implementing the accessors used
    // below so that we can safely invoke them.
    super.visitChildren(visitor);
    declaration.initializer?.accept(visitor);
  }
}
