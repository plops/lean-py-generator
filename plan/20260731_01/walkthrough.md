# Walkthrough & Project Report: Lean 4 Python Transpiler (`lean-py-generator`)

## Overview

The `lean-py-generator` project provides a native, compiled Lean 4 transpiler that converts dynamic Common Lisp S-expression ASTs into idiomatic, type-hinted Python source code and Jupyter Notebook `.ipynb` files. This replaces the legacy Common Lisp dependency (`cl-py-generator` / `cl-cl-generator`) with a standalone executable while introducing formal verification guarantees in Lean 4.

---

## What Was Implemented

The Lean 4 transpiler has been structured into modular components under the `PyGenerator` package:

1. **AST Representation & Verified Helpers (`PyGenerator/AST.lean`)**:
   - `SExpr`: Inductive algebraic data type (`sym`, `str`, `int`, `float`, `key`, `list`).
   - `groupPairs`: Grouping mechanism for key-value dictionary and assignment pairs.
   - `groupPairs_length_le`: Formal Lean 4 proof theorem verifying `(groupPairs l).length * 2 <= l.length`.
   - `splitArgs`: Positional vs keyword argument separator for function calls.

2. **Operator Precedence & Verification (`PyGenerator/Precedence.lean`)**:
   - `precedenceTable`: Complete 15-level operator precedence and associativity specification matching Python syntax.
   - `lookupPrecedence` & `lookupAssociativity`: Operator rank lookup and associativity determination.
   - `lookupAssociativity_default`: Formal proof theorem guaranteeing deterministic left-associativity fallback for unrecognized symbols.

3. **Declarations & Lambda List Parser (`PyGenerator/Declarations.lean`)**:
   - `consumeDeclare`: Parsing `declare (type ...)` annotations, capture lists, and `values` return type hints.
   - `parseOrdinaryLambdaList`: Parsing positional, `&optional`, `&rest`, and `&key` parameter specifications.

4. **Pure Python Emitter (`PyGenerator/Emitter.lean`)**:
   - `emitPy`: Core recursive code generation engine supporting:
     - Literals, collections (`list`, `tuple`, `dict`, `dict*`, `curly`), and index/slice operations.
     - Indentation blocks (`body`, `indent`, `progn`), cell export comments (`# export`).
     - Control flow (`if`, `cond`, `when`, `unless`, `for`, `while`, `try/except/finally`).
     - Function declarations (`def`), lambdas (`lambda`), classes (`class`), and decorators (`decorated`).
     - String expressions (`fstring`, `fstring3`, `raw`, `bytes`, `triple`).
     - Precedence-aware parens (`paren*`) eliminating redundant parens based on operator ranks.

5. **Formatter & File Output Writer (`PyGenerator/Writer.lean`)**:
   - `writeSource`: Emits `.py` files and invokes `ruff format` via `IO.Process.run`.
   - `writeNotebook`: Serializes `.ipynb` notebook structures using `Lean.Json` and pretty-prints output via `jq`.

6. **Comprehensive Test Runner (`PyGenerator/Tests.lean` & `Main.lean`)**:
   - Automated test suite porting test cases from `/workspace/src/cl-cl-generator/example/03_py_meta/transpiler-tests.lisp`.
   - Includes real-time Python execution validation (`/usr/bin/python3`).

---

## Test Results & Verification

All 27 transpiler unit and integration tests passed cleanly:

```text
=== Lean 4 Python Transpiler (lean-py-generator) ===
===============================================
 Running lean-py-generator Transpiler Test Suite
===============================================
[PASS] simple-addition
[PASS] function-definition
[PASS] setf-multiple
[PASS] assignment-basic
[PASS] list-literal
[PASS] tuple-literal
[PASS] paren-literal
[PASS] ntuple-literal
[PASS] curly-literal
[PASS] dict-literal
[PASS] dictionary-constructor
[PASS] incf-basic
[PASS] decf-basic
[PASS] aref-index
[PASS] for-loop
[PASS] while-loop
[PASS] if-else
[PASS] cond-form
[PASS] when-form
[PASS] unless-form
[PASS] import-statement
[PASS] import-from-statement
[PASS] try-except-block
[PASS] fstring-formatting
[PASS] explicit-raw-triple-string
[PASS] def-type-annotations
[PASS] python-execution-test
[PASS-EXEC] python-execution-test execution output match
-----------------------------------------------
All 27 tests passed successfully!

Writing sample Python script via writeSource (with ruff formatting)...
Writing sample Jupyter Notebook via writeNotebook (with jq formatting)...
Successfully generated output_sample.py and output_sample.ipynb!
```

### Verified Sample Output Files
- `output_sample.py`: Python code formatted by `ruff format` and successfully executed with `python3` output `hypot(3, 4) = 5.0`.
- `output_sample.ipynb`: Formatted Jupyter Notebook JSON verified by `jq`.

---

## Learnings & Possible Enhancements

1. **Static AST vs. Untyped SExpr**:
   - Currently `SExpr` is dynamically typed (similar to Common Lisp).
   - *Future Enhancement*: Define a strongly-typed `PyAST` (distinguishing `Expr` vs `Stmt`) to prevent malformed ASTs at compile time in Lean.

2. **Macro DSL Ergonomics**:
   - Custom Lean 4 syntax macros could be introduced (e.g. `s!(def foo (x) (+ x 1))`) to allow concise syntax when defining AST templates in Lean.

3. **Formal Verification Expansion**:
   - Additional proofs can be written to guarantee that `emitPy` always produces balanced parentheses or valid Python token sequences.

---

## Installed Container Tooling

The following tools and programs were installed/verified in the Ubuntu Docker container for this project:

| Tool | Version / Location | Purpose |
| :--- | :--- | :--- |
| `elan` | Lean Version Manager (`~/.elan/bin/elan`) | Toolchain manager for Lean 4. |
| `lean` | Lean 4 Compiler (`v4.32.2`) | Compiles Lean 4 modules and typechecks formal proofs. |
| `lake` | Lean Build System (`v5.0.0`) | Package and executable build manager. |
| `python3` | Python Interpreter (`v3.14.4`) | Executes generated Python code for validation. |
| `ruff` | Python Formatter (`v0.16.1`) | Formats output `.py` files. |
| `jq` | JSON Processor (`v1.8.1`) | Formats Jupyter Notebook `.ipynb` files. |
