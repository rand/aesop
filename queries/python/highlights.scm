;; Python syntax highlighting queries for tree-sitter

; Keywords
[
  "and"
  "as"
  "assert"
  "async"
  "await"
  "break"
  "class"
  "continue"
  "def"
  "del"
  "elif"
  "else"
  "except"
  "finally"
  "for"
  "from"
  "global"
  "if"
  "import"
  "in"
  "is"
  "lambda"
  "nonlocal"
  "not"
  "or"
  "pass"
  "raise"
  "return"
  "try"
  "while"
  "with"
  "yield"
] @keyword

; Function definitions
(function_definition
  name: (identifier) @function.definition)

; Class definitions
(class_definition
  name: (identifier) @type.definition)

; Function calls
(call
  function: (identifier) @function.call)

; Method calls
(call
  function: (attribute
    attribute: (identifier) @function.call))

; Built-in functions
((identifier) @function.builtin
  (#match? @function.builtin "^(abs|all|any|ascii|bin|bool|breakpoint|bytearray|bytes|callable|chr|classmethod|compile|complex|delattr|dict|dir|divmod|enumerate|eval|exec|filter|float|format|frozenset|getattr|globals|hasattr|hash|help|hex|id|input|int|isinstance|issubclass|iter|len|list|locals|map|max|memoryview|min|next|object|oct|open|ord|pow|print|property|range|repr|reversed|round|set|setattr|slice|sorted|staticmethod|str|sum|super|tuple|type|vars|zip|__import__)$"))

; Decorators
(decorator
  "@" @operator
  (identifier) @function.builtin)

; Built-in types
((identifier) @type.builtin
  (#match? @type.builtin "^(bool|bytes|dict|float|int|list|object|set|str|tuple|type)$"))

; Constants
((identifier) @constant
  (#match? @constant "^[A-Z][A-Z0-9_]*$"))

; Special variables
((identifier) @constant.builtin
  (#match? @constant.builtin "^__(name|file|doc|package|loader|spec|path|cached|version|author|all|dict|class|module|code|self|init|new|del|repr|str|bytes|format|lt|le|eq|ne|gt|ge|hash|bool|getattr|setattr|delattr|dir|get|set|delete|init_subclass|set_name|class_getitem|mro_entries|call|len|length_hint|getitem|setitem|delitem|missing|iter|reversed|next|contains|add|sub|mul|matmul|truediv|floordiv|mod|divmod|pow|lshift|rshift|and|xor|or|neg|pos|abs|invert|complex|int|float|index|round|trunc|floor|ceil|enter|exit|await|aiter|anext|aenter|aexit|match_args|annotations|mro|subclasses|signature)__$"))

; Self parameter
((identifier) @constant.builtin
  (#eq? @constant.builtin "self"))

; Cls parameter
((identifier) @constant.builtin
  (#eq? @constant.builtin "cls"))

; None, True, False
[
  "None"
  "True"
  "False"
] @constant.builtin

; String literals
[
  (string)
  (concatenated_string)
] @string

; Format strings
(string
  (interpolation) @punctuation.special)

; Docstrings
(expression_statement
  (string) @comment)

; Number literals
[
  (integer)
  (float)
] @number

; Comments
(comment) @comment

; Imports
(import_statement
  name: (dotted_name) @keyword)

(import_from_statement
  module_name: (dotted_name) @keyword)

; Parameters
(parameters
  (identifier) @variable)

(default_parameter
  name: (identifier) @variable)

(typed_parameter
  (identifier) @variable)

(typed_default_parameter
  name: (identifier) @variable)

; Keyword arguments
(keyword_argument
  name: (identifier) @variable)

; Operators
[
  "+"
  "-"
  "*"
  "**"
  "/"
  "//"
  "%"
  "@"
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
  "//="
  "%="
  "@="
  "&="
  "|="
  "^="
  ">>="
  "<<="
  "**="
  "->"
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
  ":"
  ";"
  "."
] @punctuation.delimiter

; Error nodes
(ERROR) @error
