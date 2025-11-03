;; Zig syntax highlighting queries for tree-sitter
;; These queries map syntax nodes to semantic highlight groups

; Keywords
[
  "const"
  "var"
  "fn"
  "pub"
  "return"
  "if"
  "else"
  "switch"
  "for"
  "while"
  "break"
  "continue"
  "defer"
  "errdefer"
  "try"
  "catch"
  "orelse"
  "unreachable"
  "async"
  "await"
  "suspend"
  "resume"
  "comptime"
  "inline"
  "export"
  "extern"
  "packed"
  "align"
  "linksection"
  "threadlocal"
  "allowzero"
  "volatile"
  "noalias"
  "struct"
  "enum"
  "union"
  "error"
  "opaque"
  "test"
  "anytype"
] @keyword

; Control flow keywords
[
  "and"
  "or"
] @keyword.operator

; Built-in functions (compile-time)
[
  "@import"
  "@cImport"
  "@cInclude"
  "@cDefine"
  "@cUndef"
  "@as"
  "@bitCast"
  "@alignCast"
  "@intCast"
  "@floatCast"
  "@intToFloat"
  "@floatToInt"
  "@boolToInt"
  "@errSetCast"
  "@truncate"
  "@alignOf"
  "@sizeOf"
  "@bitSizeOf"
  "@typeInfo"
  "@typeName"
  "@TypeOf"
  "@hasDecl"
  "@hasField"
  "@fieldParentPtr"
  "@byteOffsetOf"
  "@bitOffsetOf"
  "@embedFile"
  "@errorName"
  "@tagName"
  "@This"
  "@returnAddress"
  "@src"
  "@frame"
  "@frameAddress"
  "@frameSize"
  "@call"
  "@fieldParentPtr"
  "@memcpy"
  "@memset"
  "@min"
  "@max"
  "@panic"
  "@compileError"
  "@compileLog"
  "@setEvalBranchQuota"
  "@setFloatMode"
  "@setRuntimeSafety"
  "@setCold"
  "@addWithOverflow"
  "@subWithOverflow"
  "@mulWithOverflow"
  "@shlWithOverflow"
  "@atomicLoad"
  "@atomicStore"
  "@atomicRmw"
  "@cmpxchgWeak"
  "@cmpxchgStrong"
  "@fence"
  "@prefetch"
] @function.builtin

; Function definitions
(FnProto
  name: (IDENTIFIER) @function.definition)

; Function calls
(CallExpression
  function: (IDENTIFIER) @function.call)

; Types - built-in primitive types
[
  "void"
  "bool"
  "i8" "u8"
  "i16" "u16"
  "i32" "u32"
  "i64" "u64"
  "i128" "u128"
  "isize" "usize"
  "f16" "f32" "f64" "f128"
  "c_short" "c_ushort"
  "c_int" "c_uint"
  "c_long" "c_ulong"
  "c_longlong" "c_ulonglong"
  "c_longdouble"
  "comptime_int"
  "comptime_float"
  "noreturn"
  "type"
  "anyerror"
  "anyframe"
  "anyopaque"
] @type.builtin

; Type definitions
(ContainerDecl
  (ContainerDeclType
    (IDENTIFIER) @type.definition))

; Constants
(IDENTIFIER) @constant
  (#match? @constant "^[A-Z][A-Z0-9_]*$")

; String literals
[
  (STRINGLITERALSINGLE)
  (STRINGLITERAL)
  (STRINGLITERALMULTILINE)
] @string

; Character literals
(CHARLITERAL) @string.special

; Number literals
[
  (INTEGER)
  (FLOAT)
] @number

; Boolean literals
[
  "true"
  "false"
] @constant.builtin

; Null literal
"null" @constant.builtin

; Undefined literal
"undefined" @constant.builtin

; Comments
[
  (LINECOMMENT)
  (doc_comment)
] @comment

; Operators
[
  "+"
  "-"
  "*"
  "/"
  "%"
  "**"
  "++"
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  "<<"
  ">>"
  "&"
  "|"
  "^"
  "~"
  "="
  "+="
  "-="
  "*="
  "/="
  "%="
  "<<="
  ">>="
  "&="
  "|="
  "^="
  "!"
  ".."
  "..."
  ".*"
  ".*?"
  "?"
  "=>"
] @operator

; Punctuation delimiters
[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  ","
  ";"
  ":"
  "."
] @punctuation.delimiter

; Error nodes - highlight parse errors
(ERROR) @error
