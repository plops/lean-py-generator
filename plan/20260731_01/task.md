# Sequential Task List: Lean 4 Python Transpiler (`lean-py-generator`)

Each task must be executed sequentially. After completing each task, run the corresponding validation command before proceeding to the next step.

---

### Task 1: Environment & Lake Package Setup
- **Goal**: Initialize the Lake build system configuration and Lean toolchain setup in `/workspace/src/lean-py-generator`.
- **Files**:
  - `lean-toolchain`
  - `lakefile.toml` or `lakefile.lean`
- **Validation**:
  - Run `export PATH="$HOME/.elan/bin:$PATH" && lake build`
- **Git Commit**: `build(environment): initialize Lean 4 Lake project configuration`

---

### Task 2: AST Definition & Helper Proofs
- **Goal**: Implement `PyGenerator/AST.lean` with `SExpr` inductive type, helper functions (`groupPairs`, `splitArgs`), notation macros, and proof lemmas.
- **Files**:
  - `PyGenerator/AST.lean`
- **Validation**:
  - Run `lake build` (Lean typechecker verifies proofs compile cleanly).
- **Git Commit**: `feat(ast): implement SExpr AST and verified helper functions`

---

### Task 3: Operator Precedence & Verification
- **Goal**: Implement `PyGenerator/Precedence.lean` with operator precedence table, associativity rules, lookup functions, and verification lemmas.
- **Files**:
  - `PyGenerator/Precedence.lean`
- **Validation**:
  - Run `lake build`.
- **Git Commit**: `feat(precedence): implement operator precedence and associativity table`

---

### Task 4: Declaration & Lambda List Parser
- **Goal**: Implement `PyGenerator/Declarations.lean` with `consumeDeclare` for type/capture/values annotation extraction and `parseOrdinaryLambdaList` for positional, optional, rest, and keyword arguments.
- **Files**:
  - `PyGenerator/Declarations.lean`
- **Validation**:
  - Run `lake build`.
- **Git Commit**: `feat(declarations): implement declaration and lambda list parsers`

---

### Task 5: Python Emitter Engine
- **Goal**: Implement `PyGenerator/Emitter.lean` with `emitPy`, `emitDefun`, `emitParenStar`, `emitInfixOperator`, `parseAndEmitFString`, and `parseExplicitString`.
- **Files**:
  - `PyGenerator/Emitter.lean`
- **Validation**:
  - Run `lake build`.
- **Git Commit**: `feat(emitter): implement core Python code generator`

---

### Task 6: File & Jupyter Notebook Writer
- **Goal**: Implement `PyGenerator/Writer.lean` with `writeSource` (invoking `ruff format`) and `writeNotebook` (serializing JSON with `jq`).
- **Files**:
  - `PyGenerator/Writer.lean`
- **Validation**:
  - Run `lake build`.
- **Git Commit**: `feat(writer): implement source file and Jupyter notebook formatting writer`

---

### Task 7: Comprehensive Test Suite & CLI
- **Goal**: Port test cases from `transpiler-tests.lisp` into `PyGenerator/Tests.lean` and construct CLI entry point `Main.lean`.
- **Files**:
  - `PyGenerator/Tests.lean`
  - `Main.lean`
- **Validation**:
  - Run `lake build`.
- **Git Commit**: `feat(tests): add unit and integration test suite ported from transpiler-tests.lisp`

---

### Task 8: Verification & Execution
- **Goal**: Build binary executable, run test suite, emit sample `.py` and `.ipynb` files, format with `ruff` and `jq`, and execute generated Python scripts with `python3`.
- **Validation**:
  - Run `./.lake/build/bin/lean-py-generator`
  - Verify zero test failures and check formatted outputs.
- **Git Commit**: `test(verification): validate test suite and emitted python script execution`

---

### Task 9: Final Documentation & Walkthrough
- **Goal**: Create comprehensive walkthrough document in `plan/20260731_01/walkthrough.md`.
- **Files**:
  - `plan/20260731_01/walkthrough.md`
- **Validation**:
  - Check file exists and contains full summary, test output, learnings, and container tool recommendations.
- **Git Commit**: `docs(walkthrough): add final walkthrough report for lean-py-generator`
