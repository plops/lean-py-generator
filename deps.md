# Dependencies and Repositories

This document tracks all external tools, libraries, and core dependencies along with their GitHub organization and repository identifiers to allow structured querying via DeepWiki MCP.

| Component | GitHub Repo / Identifier | Purpose / Role in Project |
| :--- | :--- | :--- |
| **Lean 4 Toolchain** | `leanprover/lean4` | Native Lean 4 compiler, runtime, standard library, and proof assistant. |
| **Elan Version Manager** | `leanprover/elan` | Lean 4 toolchain manager for version control and Lake package builds. |
| **cl-py-generator** | `plops/cl-py-generator` | Primary reference Common Lisp S-expression to Python transpiler architecture and test suite (`transpiler-tests.lisp`). |
| **cl-cl-generator** | `plops/cl-cl-generator` | Meta-generator reference powering `cl-py-generator` in `example/03_py_meta`. |
| **Ruff Formatter** | `astral-sh/ruff` | Fast Python code formatter executed via `IO.Process.run` on emitted Python source files. |
| **jq JSON Processor** | `jqlang/jq` | Command-line JSON processor used for pretty-printing Jupyter Notebook (`.ipynb`) outputs. |
