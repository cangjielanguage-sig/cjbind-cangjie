package cjbind.ir

import std.collection.ArrayList
import cjbind.clang
import cjbind.result.Result
import std.ast.{Tokens, ToTokens, Token, TokenKind}
import std.collection.{collectArray, collectArrayList}

public class Var <: ClangSubItemParser<Var> {
    public let name: String
    public let ty: TypeId
    public let val: ?VarType
    public let isConst: Bool

    public init(
        name: String,
        ty: TypeId,
        val: ?VarType,
        isConst: Bool
    ) {
        if (name.isEmpty()) {
            throw Exception("Var name can't be empty")
        }

        this.name = name
        this.ty = ty
        this.val = val
        this.isConst = isConst
    }

    // cjlint-ignore -start !G.FUN.01
    public static func parse(cursor: clang.Cursor, ctx: CjbindContext): Result<ParseResult<Var>, ParseError> {
        let k = cursor.kind()
        if (k == clang.CXCursorKind_CXCursor_MacroDefinition) {
            if (cursor.isMacroFunctionLike()) {
                return Err(ParseError.Continue)
            }

            // TODO: add expr eval, only use clang eval as fallback
            let (name, value) = match (parseMacroClangFallback(ctx, cursor)) {
                case Some(v) => v
                case None => return Err(ParseError.Continue)
            }

            if (name.isEmpty()) {
                throw Exception("Macro name can't be empty")
            }

            let previouslyDefined = ctx.parsedMacro(name)
            ctx.noteParsedMacro(name, value)

            if (previouslyDefined) {
                eprintln("Warning: Macro `${name}` is already defined")
                return Err(ParseError.Continue)
            }

            let (typeKind, val) = match (value) {
                case MacroEvalResult.EvalResultInt(it) => 
                    match (it) {
                        case Ints.Int(v) => (TypeKind.TypeKindInt(IntKindI64), VarType.VarInt(it))
                        case Ints.UInt(v) => (TypeKind.TypeKindInt(IntKindU64), VarType.VarInt(it))
                    }
                case MacroEvalResult.EvalFloat(it) => (TypeKind.TypeKindFloat(FloatKindDouble), VarType.VarFloat(it))
                case MacroEvalResult.EvalStr(it) =>
                    let charTy = Item.builtinType(
                        TypeKind.TypeKindInt(TypeKindIntKind.IntKindU8),
                        true,
                        ctx
                    )
                    (TypeKind.TypeKindPointer(charTy), VarType.VarString(it))
                // FIXME: didn't consider for now as clang didn't provide these
                case _ => throw Exception("unreachable")
            }

            let ty = Item.builtinType(typeKind, true, ctx)

            return Ok(
                ParseResult.New(
                    Var(name, ty, Some(val), true),
                    Some(cursor)
                )
            )
        } else if (k == clang.CXCursorKind_CXCursor_VarDecl) {
            let name = cursor.spelling()
            if (name.isEmpty()) {
                return Err(ParseError.Continue)
            }

            let ty = cursor.curType()
            let isConst = ty.isConst() || ([clang.CXTypeKind_CXType_ConstantArray,
                clang.CXTypeKind_CXType_IncompleteArray].contains(ty.kind()) &&
                ty.elemType().flatMap({
                et => et.isConst()
            }).getOrDefault {=> false})

            let tyId = match (Item.fromTy(ty, cursor, None, ctx)) {
                case Ok(v) => v
                case Err(e) => return Err(e)
            }

            if (!isConst) {
                let value = StringBuilder()
                for (clangToken in clang.RawTokens(cursor)) {
                    value.append(clangToken.spelling())
                    value.append(" ")
                }
                let varr = Var(name, tyId, VarType.VarRawString(value.toString()), isConst)
                return Ok(ParseResult.New(varr, Some(cursor)))
            }

            let canonicalTy = ctx.safeResolveType(tyId).flatMap {
                t => t.safeCanonicalType(ctx)
            }

            let isInteger = canonicalTy.flatMap {
                t => t.isInteger()
            }.getOrDefault {=> false}
            let isFloat = canonicalTy.flatMap {
                t => t.isFloat()
            }.getOrDefault {=> false}
            let isArray = canonicalTy.flatMap {
                t => t.isArray()
            }.getOrDefault {=> false}

            let value: ?VarType = if (isArray) {
                var vt = Option<VarType>.None

                // For array variables with initialization lists, we need to get the initializer cursor
                let initializerCursor = cursor.varDeclInitializer()
                if (initializerCursor.isValid() && 
                    initializerCursor.kind() == clang.CXCursorKind_CXCursor_InitListExpr) {
                    // For InitListExpr, we need to manually evaluate each element
                    let children = initializerCursor.collectChildren()

                    // Try integer array first
                    let intValues = collectIntegerValues(children)
                    if (intValues.isSome()) {
                        vt = VarType.VarIntArray(intValues.getOrThrow().toArray())
                    }
                    
                    // Try float array
                    let floatValues = collectFloatValues(children)
                    if (floatValues.isSome()) {
                        vt = VarType.VarFloatArray(floatValues.getOrThrow().toArray())
                    }
                }

                vt
            }  else if (isInteger) {
                let kind = match (canonicalTy.getOrThrow().kind) {
                    case TypeKind.TypeKindInt(k) => k
                    case _ => throw Exception("Should be int type")
                }

                let iv = cursor.evalutate().asInt()
                if (iv.isNone() || !kind.signednessMatches(iv.getOrThrow().toInts().isNonNegative())) {
                    None
                } else {
                    let kv = iv.getOrThrow().toInts()
                    match (kind) {
                        case IntKindBool => VarType.VarBool(!kv.isZero())
                        case _ => VarType.VarInt(kv)
                    }
                }
            } else if (isFloat) {
                cursor.evalutate().asDouble().flatMap {
                    fv => VarType.VarFloat(fv)
                }
            } else {
                cursor.evalutate().asLiteralString().flatMap {
                    sv => VarType.VarString(sv)
                }
            }

            let varr = Var(name, tyId, value, isConst)
            return Ok(ParseResult.New(varr, Some(cursor)))
        } else {
            return Err(ParseError.Continue)
        }
    }
    // cjlint-ignore -end
}

// cjlint-ignore -start !G.FUN.01
func parseMacroClangFallback(
    ctx: CjbindContext,
    cursor: clang.Cursor
): Option<(String, MacroEvalResult)> {
    let ftu = match (ctx.tryEnsureFallbackTranslationUnit()) {
        case Some(ftu) => ftu
        case None => return None
    }

    let contents = "int main() {{ ${cursor.spelling()}; }}"
    ftu.reparse(contents);

    let rootChildren = ftu.tu.cursor().collectChildren()
    let mainFunc = match (rootChildren.last) {
        case Some(m) => m
        case None => return None
    }
    let allStmts = mainFunc.collectChildren()
    let macroStmt = match (allStmts.first) {
        case Some(s) => s
        case None => return None
    }

    let parenExprs = macroStmt.collectChildren()
    let paren = match (parenExprs.first) {
        case Some(p) => p
        case None => return None
    }

    let evalutated = paren.evalutate()
    let evalutatedKind = evalutated.kind()

    if (evalutatedKind == clang.CXEvalResultKind_CXEval_Int) {
        match (evalutated.asInt()) {
            case Some(v) => 
            match (v) {
                case clang.EvalResultInt.Int(v) => return Some((cursor.spelling(), MacroEvalResult.EvalResultInt(Ints.Int(v))))
                case clang.EvalResultInt.UInt(v) => return Some((cursor.spelling(), MacroEvalResult.EvalResultInt(Ints.UInt(v))))
            }
            case None => return None
        }
    } else if (evalutatedKind == clang.CXEvalResultKind_CXEval_Float) {
        match (evalutated.asDouble()) {
            case Some(v) => return Some((cursor.spelling(), MacroEvalResult.EvalFloat(v)))
            case None => return None
        }
    } else if (evalutatedKind == clang.CXEvalResultKind_CXEval_StrLiteral) {
        match (evalutated.asLiteralString()) {
            case Some(v) => unsafe {
                // copy to prevent ref to freed memory
                let vv = LibC.mallocCString(v.toString())
                return Some((cursor.spelling(), MacroEvalResult.EvalStr(vv)))
            }
            case None => return None
        }
    }

    return None
}
// cjlint-ignore -end

// Helper functions to collect array values from InitListExpr children
func collectIntegerValues(children: ArrayList<clang.Cursor>): ?ArrayList<Int64> {
    let intValues = ArrayList<Int64>()
    
    for (child in children) {
        let evalResult = clang.EvalResult(child)
        let intValOpt = evalResult.asInt()
        if (intValOpt.isSome()) {
            match (intValOpt.getOrThrow()) {
                case clang.EvalResultInt.Int(v) =>intValues.add(v)
                case clang.EvalResultInt.UInt(v) =>intValues.add(Int64(v))
            }
        }
    }
    
    if (intValues.isEmpty()) {
        return None
    }
    return Some(intValues)
}

func collectFloatValues(children: ArrayList<clang.Cursor>): ?ArrayList<Float64> {
    let floatValues = ArrayList<Float64>()
    
    for (child in children) {
        let evalResult = clang.EvalResult(child)
        let floatValOpt = evalResult.asDouble()
        if (floatValOpt.isSome()) {
            floatValues.add(floatValOpt.getOrThrow())
        }
    }
    
    if (floatValues.isEmpty()) {
        return None
    }
    return Some(floatValues)
}

public enum Ints <: ToTokens {
    Int(Int64) |
    UInt(UInt64)

    public func toTokens(): Tokens {
        let tokens = Tokens()
        
        match (this) {
            case Int(v) => tokens.append(Token(TokenKind.INTEGER_LITERAL, "${v}"))
            case UInt(v) => tokens.append(Token(TokenKind.INTEGER_LITERAL, "${v}"))
        }

        return tokens
    }

    public func isNonNegative(): Bool {
        match (this) {
            case Int(v) => v >= 0
            case UInt(v) => true
        }
    }

    public func isZero(): Bool {
        match (this) {
            case Int(v) => v == 0
            case UInt(v) => v == 0
        }
    }
}

extend clang.EvalResultInt {
    public func toInts(): Ints {
        match (this) {
            case Int(v) => Ints.Int(v)
            case UInt(v) => Ints.UInt(v)
        }
    }
}

public enum VarType <: ToString{
    VarBool(Bool)
    | VarInt(Ints)
    | VarFloat(Float64)
    | VarChar(UInt8)
    | VarString(CString)
    | VarRawString(String)
    | VarIntArray(Array<Int64>)
    | VarFloatArray(Array<Float64>)

    public func toString(): String {
        match (this) {
            case VarBool(v) => "VarBool"
            case VarInt(v) => "VarInt"
            case VarFloat(v) => "VarFloat"
            case VarChar(v) => "VarChar"
            case VarString(v) => "VarString"
            case VarRawString(v) => "VarRawString"
            case VarIntArray(v) => "VarIntArray"
            case VarFloatArray(v) => "VarFloatArray"
        }
    }
}
