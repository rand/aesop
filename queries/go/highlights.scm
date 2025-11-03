;; Go syntax highlighting queries for tree-sitter

; Keywords
[
  "break"
  "case"
  "chan"
  "const"
  "continue"
  "default"
  "defer"
  "else"
  "fallthrough"
  "for"
  "func"
  "go"
  "goto"
  "if"
  "import"
  "interface"
  "map"
  "package"
  "range"
  "return"
  "select"
  "struct"
  "switch"
  "type"
  "var"
] @keyword

; Function definitions
(function_declaration
  name: (identifier) @function.definition)

; Method definitions
(method_declaration
  name: (field_identifier) @function.definition)

; Function calls
(call_expression
  function: (identifier) @function.call)

; Method calls
(call_expression
  function: (selector_expression
    field: (field_identifier) @function.call))

; Built-in functions
((identifier) @function.builtin
  (#match? @function.builtin "^(append|cap|close|complex|copy|delete|imag|len|make|new|panic|print|println|real|recover)$"))

; Types - built-in
[
  "bool"
  "byte"
  "complex64"
  "complex128"
  "error"
  "float32"
  "float64"
  "int"
  "int8"
  "int16"
  "int32"
  "int64"
  "rune"
  "string"
  "uint"
  "uint8"
  "uint16"
  "uint32"
  "uint64"
  "uintptr"
] @type.builtin

; Type definitions
(type_spec
  name: (type_identifier) @type.definition)

; Type references
(type_identifier) @type.definition

; Constants
((identifier) @constant
  (#match? @constant "^[A-Z][A-Z0-9_]*$"))

; Nil
(nil) @constant.builtin

; Boolean literals
[
  "true"
  "false"
] @constant.builtin

; Iota
(iota) @constant.builtin

; String literals
[
  (interpreted_string_literal)
  (raw_string_literal)
] @string

; Rune literals
(rune_literal) @string.special

; Number literals
[
  (int_literal)
  (float_literal)
  (imaginary_literal)
] @number

; Comments
(comment) @comment

; Package clause
(package_clause
  (package_identifier) @keyword)

; Import
(import_spec
  path: (interpreted_string_literal) @string)

; Field names
(field_declaration
  name: (field_identifier) @variable)

; Parameter names
(parameter_declaration
  name: (identifier) @variable)

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
  "<<"
  ">>"
  "&^"
  "="
  ":="
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
  "&^="
  "<-"
  "++"
  "--"
  "..."
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
  ":"
  "."
] @punctuation.delimiter

; Error nodes
(ERROR) @error
