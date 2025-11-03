;; C syntax highlighting queries for tree-sitter

; Keywords
[
  "auto"
  "break"
  "case"
  "const"
  "continue"
  "default"
  "do"
  "else"
  "enum"
  "extern"
  "for"
  "goto"
  "if"
  "inline"
  "register"
  "restrict"
  "return"
  "sizeof"
  "static"
  "struct"
  "switch"
  "typedef"
  "union"
  "volatile"
  "while"
] @keyword

; Storage classes
[
  "_Alignas"
  "_Alignof"
  "_Atomic"
  "_Bool"
  "_Complex"
  "_Generic"
  "_Imaginary"
  "_Noreturn"
  "_Static_assert"
  "_Thread_local"
] @keyword

; Function definitions
(function_definition
  declarator: (function_declarator
    declarator: (identifier) @function.definition))

(function_definition
  declarator: (pointer_declarator
    declarator: (function_declarator
      declarator: (identifier) @function.definition)))

; Function declarations
(declaration
  declarator: (function_declarator
    declarator: (identifier) @function.definition))

; Function calls
(call_expression
  function: (identifier) @function.call)

; Types - built-in
[
  "char"
  "double"
  "float"
  "int"
  "long"
  "short"
  "signed"
  "unsigned"
  "void"
] @type.builtin

; Type definitions
(type_definition
  declarator: (type_identifier) @type.definition)

; Struct definitions
(struct_specifier
  name: (type_identifier) @type.definition)

; Union definitions
(union_specifier
  name: (type_identifier) @type.definition)

; Enum definitions
(enum_specifier
  name: (type_identifier) @type.definition)

; Type references
(type_identifier) @type.definition

; Constants
((identifier) @constant
  (#match? @constant "^[A-Z][A-Z0-9_]*$"))

; NULL
((identifier) @constant.builtin
  (#eq? @constant.builtin "NULL"))

; String literals
[
  (string_literal)
  (system_lib_string)
] @string

; Character literals
(char_literal) @string.special

; Number literals
(number_literal) @number

; Comments
(comment) @comment

; Preprocessor
(preproc_directive) @keyword.operator
(preproc_include) @keyword.operator
(preproc_def) @keyword.operator
(preproc_function_def) @keyword.operator
(preproc_if) @keyword.operator
(preproc_ifdef) @keyword.operator
(preproc_else) @keyword.operator
(preproc_elif) @keyword.operator
(preproc_endif) @keyword.operator

; Preprocessor paths
(preproc_include
  path: (string_literal) @string)

(preproc_include
  path: (system_lib_string) @string)

; Preprocessor macros
(preproc_def
  name: (identifier) @constant)

(preproc_function_def
  name: (identifier) @function.builtin)

; Field names
(field_declaration
  declarator: (field_identifier) @variable)

; Parameters
(parameter_declaration
  declarator: (identifier) @variable)

(parameter_declaration
  declarator: (pointer_declarator
    declarator: (identifier) @variable))

; Operators
[
  "+"
  "-"
  "*"
  "/"
  "%"
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  "&&"
  "||"
  "!"
  "&"
  "|"
  "^"
  "~"
  "<<"
  ">>"
  "="
  "+="
  "-="
  "*="
  "/="
  "%="
  "&="
  "|="
  "^="
  "<<="
  ">>="
  "++"
  "--"
  "->"
  "."
  "?"
  ":"
] @operator

; Punctuation
[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  ","
  ";"
] @punctuation.delimiter

; Error nodes
(ERROR) @error
