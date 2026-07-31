# Implementation Plan: Lean 4 Python Transpiler (`lean-py-generator`)

## Overview
This plan outlines the architecture, requirements, design choices, formal verification targets, and implementation steps for building a native Lean 4 Python code transpiler (`lean-py-generator`). This transpiler replaces the SBCL Common Lisp dependency (`cl-py-generator` / `cl-cl-generator`) with a standalone, type-safe, compiled Lean 4 executable while introducing proof-oriented enhancements.

---

## Context & Key Source Files

An AI agent working on this task should inspect the following key files:

| File Path | Description |
| :--- | :--- |
| `plan/20260731_01/prompt.txt` | Initial user prompt outlining objectives, dependencies, and delivery deliverables. |
| `plan/20260731_01/lean-proto.md` | Prototype Lean 4 transpiler script demonstrating AST design, emission rules, and architectural trade-offs. |
| `deps.md` | External tool and repository specifications (`leanprover/lean4`, `plops/cl-py-generator`, `plops/cl-cl-generator`, etc.). |
| `/workspace/src/cl-cl-generator/example/03_py_meta/transpiler-tests.lisp` | Complete Common Lisp test suite containing test cases for Python code emission. |
| `/workspace/src/cl-cl-generator/example/03_py_meta/py.lisp` | Original Common Lisp `emit-py` implementation reference. |
| `/workspace/src/cl-cl-generator/example/03_py_meta/gen.lisp` | Meta-generator definition for Lisp-to-Python DSL forms. |

---

## Architectural Enhancements & Proposed Features

Beyond the baseline requirements in `lean-proto.md`, the following enhancements are implemented:

1. **Modular Lean 4 Project Structure (`Lake`)**:
   - `PyGenerator/AST.lean`: S-expression representation (`SExpr`), utilities, and AST helper proofs.
   - `PyGenerator/Precedence.lean`: Precedence table and associativity mapping with formal verification lemmas.
   - `PyGenerator/Declarations.lean`: Type table parsing (`consumeDeclare`) and lambda list parsing (`parseOrdinaryLambdaList`).
   - `PyGenerator/Emitter.lean`: Pure Python string generator (`emitPy`) supporting all control flow, collection, f-string, and operator forms.
   - `PyGenerator/Writer.lean`: File output, subprocess execution for `ruff format`, and Jupyter Notebook `.ipynb` JSON emission.
   - `PyGenerator/Tests.lean`: Automated test runner executing converted test cases from `transpiler-tests.lisp`.
   - `Main.lean`: CLI binary entry point.

2. **Formal Verification (Proofs in Lean 4)**:
   - Prove structural properties of helper functions (e.g. `groupPairs` length invariant `(groupPairs l).length * 2 <= l.length`).
   - Prove precedence lookup completeness and associativity determinism.
   - Eliminate `partial` where possible or isolate non-structural recursion cleanly.

3. **AST Construction Ergonomics (Lean 4 DSL Macros)**:
   - Provide clean syntactic helpers (e.g., notation for `sym`, `str`, `int`, `list`) to avoid verbose nested `SExpr.list [SExpr.sym ...]` constructors.

4. **Integration with Container Tooling**:
   - Automatic execution of `ruff format` via `IO.Process.run` to validate syntax and auto-format output Python files.
   - Jupyter Notebook pretty-printing with `jq`.

---

## Conventional Commit Guidelines

All git commits must follow the **Conventional Commits** specification:

### Commit Format
```text
<type>(<scope>): <short summary>

<detailed description of changes and rationale>
```

### Allowed Types
- `feat`: A new feature or module addition.
- `fix`: A bug fix in transpilation or formatting.
- `test`: Adding or modifying unit / integration tests.
- `docs`: Documentation updates (`deps.md`, `plan.md`, `task.md`, `walkthrough.md`).
- `refactor`: Code restructuring without functional changes.
- `build`: Lake build system or Docker/elan environment changes.

### Example Commit
```text
feat(ast): implement SExpr inductive type and verified helper utilities

Introduce the fundamental SExpr data structure representing dynamic Lisp-like AST nodes.
Add verified helper functions for list pairing (`groupPairs`) and positional/keyword argument extraction (`splitArgs`).
Include formal proof for length upper bounds of `groupPairs`.
```

---

## Verification & Testing Workflow

1. **Unit Testing**: Lean unit test definitions in `PyGenerator/Tests.lean` covering arithmetic, control flow, functions, classes, collections, decorators, and try/except blocks.
2. **Integration Testing**:
   - Emit Python source files to disk and verify formatting with `ruff format`.
   - Emit Jupyter notebooks to disk and verify JSON validity with `jq`.
   - Execute generated Python files with `python3` to confirm runtime correctness.
