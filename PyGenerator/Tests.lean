import PyGenerator.AST
import PyGenerator.Emitter
import PyGenerator.Writer
import Lean

open Lean

namespace PyGenerator

structure TestCase where
  name : String
  input : SExpr
  expected : String
  execTest : Bool := false
  expectedOutput : Option String := none

def testSuite : List TestCase := [
  { name := "simple-addition", input := SExpr.list [SExpr.sym "+", SExpr.int 1, SExpr.int 2], expected := "1 + 2" },
  { name := "function-definition", input := SExpr.list [SExpr.sym "def", SExpr.sym "foo", SExpr.list [SExpr.sym "x"], SExpr.list [SExpr.sym "return", SExpr.sym "x"]], expected := "def foo(x):\n    return x" },
  { name := "setf-multiple", input := SExpr.list [SExpr.sym "setf", SExpr.sym "a", SExpr.int 1, SExpr.sym "b", SExpr.int 2], expected := "a = 1\nb = 2" },
  { name := "assignment-basic", input := SExpr.list [SExpr.sym "=", SExpr.sym "a", SExpr.int 1], expected := "a = 1" },
  { name := "list-literal", input := SExpr.list [SExpr.sym "list", SExpr.int 1, SExpr.int 2], expected := "[1, 2]" },
  { name := "tuple-literal", input := SExpr.list [SExpr.sym "tuple", SExpr.int 1, SExpr.int 2, SExpr.int 3], expected := "(1, 2, 3)" },
  { name := "paren-literal", input := SExpr.list [SExpr.sym "paren", SExpr.sym "a", SExpr.sym "b"], expected := "(a, b)" },
  { name := "ntuple-literal", input := SExpr.list [SExpr.sym "ntuple", SExpr.sym "a", SExpr.sym "b", SExpr.sym "c"], expected := "a, b, c" },
  { name := "curly-literal", input := SExpr.list [SExpr.sym "curly", SExpr.int 1, SExpr.int 2, SExpr.int 3], expected := "{1, 2, 3}" },
  { name := "dict-literal", input := SExpr.list [SExpr.sym "dict", SExpr.str "a", SExpr.int 1, SExpr.str "b", SExpr.int 2], expected := "{(\"a\"): (1), (\"b\"): (2)}" },
  { name := "dictionary-constructor", input := SExpr.list [SExpr.sym "dict*", SExpr.key "a", SExpr.int 1, SExpr.key "b", SExpr.int 2], expected := "dict(a=1, b=2)" },
  { name := "incf-basic", input := SExpr.list [SExpr.sym "incf", SExpr.sym "a", SExpr.int 2], expected := "a += 2" },
  { name := "decf-basic", input := SExpr.list [SExpr.sym "decf", SExpr.sym "a", SExpr.int 3], expected := "a -= 3" },
  { name := "aref-index", input := SExpr.list [SExpr.sym "aref", SExpr.sym "arr", SExpr.int 1], expected := "arr[1]" },
  { name := "for-loop", input := SExpr.list [SExpr.sym "for", SExpr.list [SExpr.sym "i", SExpr.list [SExpr.sym "range", SExpr.int 5]], SExpr.list [SExpr.sym "print", SExpr.sym "i"]], expected := "for i in range(5):\n    print(i)" },
  { name := "while-loop", input := SExpr.list [SExpr.sym "while", SExpr.list [SExpr.sym "<", SExpr.sym "i", SExpr.int 5], SExpr.list [SExpr.sym "incf", SExpr.sym "i"]], expected := "while i < 5:\n    i += 1" },
  { name := "if-else", input := SExpr.list [SExpr.sym "if", SExpr.list [SExpr.sym ">", SExpr.sym "x", SExpr.int 0], SExpr.list [SExpr.sym "return", SExpr.int 1], SExpr.list [SExpr.sym "return", SExpr.int 0]], expected := "if x > 0:\n    return 1\nelse:\n    return 0" },
  { name := "cond-form", input := SExpr.list [SExpr.sym "cond", SExpr.list [SExpr.list [SExpr.sym "<", SExpr.sym "x", SExpr.int 0], SExpr.list [SExpr.sym "return", SExpr.int (-1)]], SExpr.list [SExpr.sym "t", SExpr.list [SExpr.sym "return", SExpr.int 1]]], expected := "if x < 0:\n    return -1\nelse:\n    return 1" },
  { name := "when-form", input := SExpr.list [SExpr.sym "when", SExpr.list [SExpr.sym ">", SExpr.sym "x", SExpr.int 0], SExpr.list [SExpr.sym "print", SExpr.sym "x"]], expected := "if x > 0:\n    print(x)" },
  { name := "unless-form", input := SExpr.list [SExpr.sym "unless", SExpr.list [SExpr.sym "<=", SExpr.sym "x", SExpr.int 0], SExpr.list [SExpr.sym "print", SExpr.sym "x"]], expected := "if not (x <= 0):\n    print(x)" },
  { name := "import-statement", input := SExpr.list [SExpr.sym "import", SExpr.sym "os", SExpr.list [SExpr.sym "sys", SExpr.sym "s"]], expected := "import os\nimport s as sys" },
  { name := "import-from-statement", input := SExpr.list [SExpr.sym "import-from", SExpr.sym "math", SExpr.sym "sqrt", SExpr.sym "sin"], expected := "from math import sqrt, sin" },
  { name := "try-except-block", input := SExpr.list [SExpr.sym "try", SExpr.list [SExpr.sym "print", SExpr.sym "x"], SExpr.list [SExpr.list [SExpr.sym "as", SExpr.sym "Exception", SExpr.sym "e"], SExpr.list [SExpr.sym "print", SExpr.sym "e"]]], expected := "try:\n    print(x)\nexcept Exception as e:\n    print(e)" },
  { name := "fstring-formatting", input := SExpr.str "hello {name}", expected := "f\"hello {name}\"" },
  { name := "explicit-raw-triple-string", input := SExpr.list [SExpr.sym "string", SExpr.key "raw", SExpr.key "triple", SExpr.str "line1\nline2"], expected := "r\"\"\"line1\nline2\"\"\"" },
  { name := "def-type-annotations", input := SExpr.list [
      SExpr.sym "def", SExpr.sym "calc", SExpr.list [SExpr.sym "x", SExpr.sym "y"],
      SExpr.list [SExpr.sym "declare", SExpr.list [SExpr.sym "type", SExpr.sym "int", SExpr.sym "x"], SExpr.list [SExpr.sym "type", SExpr.sym "float", SExpr.sym "y"], SExpr.list [SExpr.sym "values", SExpr.sym "float"]],
      SExpr.list [SExpr.sym "return", SExpr.list [SExpr.sym "+", SExpr.sym "x", SExpr.sym "y"]]
    ], expected := "def calc(x: int, y: float) -> float:\n    return x + y" },
  { name := "python-execution-test", input := SExpr.list [
      SExpr.sym "progn",
      SExpr.list [SExpr.sym "=", SExpr.sym "x", SExpr.int 10],
      SExpr.list [SExpr.sym "=", SExpr.sym "y", SExpr.int 20],
      SExpr.list [SExpr.sym "print", SExpr.list [SExpr.sym "+", SExpr.sym "x", SExpr.sym "y"]]
    ], expected := "x = 10\ny = 20\nprint(x + y)", execTest := true, expectedOutput := some "30\n" }
]

def runTests : IO Nat := do
  IO.println "==============================================="
  IO.println " Running lean-py-generator Transpiler Test Suite"
  IO.println "==============================================="

  let mut failed := 0

  for tc in testSuite do
    let actual := emitPy tc.input { level := 0 }
    let normalizedActual := actual.trimAscii.toString
    let normalizedExpected := tc.expected.trimAscii.toString

    if normalizedActual == normalizedExpected then
      IO.println s!"[PASS] {tc.name}"
    else
      IO.println s!"[FAIL] {tc.name}"
      IO.println s!"  Expected: {tc.expected}"
      IO.println s!"  Actual  : {actual}"
      failed := failed + 1

    if tc.execTest then
      let tmpPy := s!"/tmp/test_{tc.name}.py"
      IO.FS.writeFile tmpPy actual
      let resStdout ← IO.Process.run { cmd := "/usr/bin/python3", args := #[tmpPy] }
      if let some expOut := tc.expectedOutput then
        if resStdout == expOut then
          IO.println s!"[PASS-EXEC] {tc.name} execution output match"
        else
          IO.println s!"[FAIL-EXEC] {tc.name} output mismatch"
          IO.println s!"  Expected Output: {expOut}"
          IO.println s!"  Actual Output  : {resStdout}"
          failed := failed + 1
      if ← System.FilePath.pathExists tmpPy then
        IO.FS.removeFile tmpPy

  IO.println "-----------------------------------------------"
  if failed == 0 then
    IO.println s!"All {testSuite.length} tests passed successfully!"
  else
    IO.println s!"Test suite completed with {failed} failures."

  return failed

end PyGenerator
