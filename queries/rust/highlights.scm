;; Rust syntax highlighting queries for tree-sitter

; Keywords
[
  "as"
  "async"
  "await"
  "break"
  "const"
  "continue"
  "dyn"
  "else"
  "enum"
  "extern"
  "fn"
  "for"
  "if"
  "impl"
  "in"
  "let"
  "loop"
  "match"
  "mod"
  "move"
  "pub"
  "ref"
  "return"
  "self"
  "static"
  "struct"
  "super"
  "trait"
  "type"
  "union"
  "unsafe"
  "use"
  "where"
  "while"
] @keyword

; Storage modifiers
[
  "mut"
  "crate"
] @keyword.operator

; Function definitions
(function_item
  name: (identifier) @function.definition)

; Method definitions
(function_signature_item
  name: (identifier) @function.definition)

; Function calls
(call_expression
  function: (identifier) @function.call)

; Method calls
(call_expression
  function: (field_expression
    field: (field_identifier) @function.call))

; Macros
(macro_invocation
  macro: (identifier) @function.builtin
  "!" @punctuation.delimiter)

; Built-in macros
((identifier) @function.builtin
  (#match? @function.builtin "^(println|print|eprintln|eprint|format|panic|assert|debug_assert|vec|todo|unimplemented|unreachable)$"))

; Types - primitive
[
  "bool"
  "char"
  "str"
  "i8" "i16" "i32" "i64" "i128" "isize"
  "u8" "u16" "u32" "u64" "u128" "usize"
  "f32" "f64"
] @type.builtin

; Type definitions
(struct_item
  name: (type_identifier) @type.definition)

(enum_item
  name: (type_identifier) @type.definition)

(union_item
  name: (type_identifier) @type.definition)

(type_item
  name: (type_identifier) @type.definition)

; Type references
(type_identifier) @type.definition

; Lifetime annotations
(lifetime
  "'" @operator
  (identifier) @constant)

; Constants
((identifier) @constant
  (#match? @constant "^[A-Z][A-Z0-9_]*$"))

; Self
[
  "Self"
  "self"
] @constant.builtin

; Boolean literals
[
  "true"
  "false"
] @constant.builtin

; String literals
[
  (string_literal)
  (raw_string_literal)
] @string

; Character literals
(char_literal) @string.special

; Number literals
[
  (integer_literal)
  (float_literal)
] @number

; Comments
[
  (line_comment)
  (block_comment)
] @comment

; Doc comments
[
  (line_comment
    (doc_comment))
  (block_comment
    (doc_comment))
] @comment

; Attributes
(attribute_item) @keyword.operator
(inner_attribute_item) @keyword.operator

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
  "->"
  "=>"
  ".."
  "..="
  "::"
  "?"
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

; Special
[
  "_"
] @keyword

; Error nodes
(ERROR) @error
