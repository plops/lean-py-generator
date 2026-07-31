# Lean 4 Python Transpiler (`lean-py-generator`)

`lean-py-generator` ist ein nativer, in **Lean 4** geschriebener Transpiler, der dynamische Lisp S-Expression AST-Formen in idiomatischen, typsicheren Python 3 Quellcode sowie in Jupyter Notebook (`.ipynb`) Dateien übersetzt. 

Das Projekt ersetzt die bisherige Common Lisp Implementierung (`cl-py-generator` / `cl-cl-generator`) durch eine eigenständige, kompilierte Executable ohne Abhängigkeit von einem Lisp-Compiler (z.B. SBCL) und bietet durch Lean 4 formale Korrektheitsbeweise für AST-Hilfsfunktionen und Präzedenzregeln.

---

## Voraussetzungen (Prerequisites)

Um das Projekt zu bauen und auszuführen, werden folgende Werkzeuge benötigt:

1. **Lean 4 Toolchain Manager (`elan`)**:
   Falls `elan` noch nicht installiert ist, kann es wie folgt installiert werden:
   ```bash
   curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y
   export PATH="$HOME/.elan/bin:$PATH"
   ```

2. **Python 3** (für die Ausführung generierter Python-Skripte):
   ```bash
   python3 --version
   ```

3. **Formatierungswerkzeuge (Optional)**:
   - **`ruff`**: Zur automatischen Codeformatierung generierter `.py` Dateien.
   - **`jq`**: Zur formatierten JSON-Ausgabe generierter `.ipynb` Notebooks.

---

## Kompilierung & Bauen (Build)

Das Projekt wird mit dem Lean-Build-System **Lake** kompiliert:

1. Stellen Sie sicher, dass `elan` und `lake` im `PATH` vorhanden sind:
   ```bash
   export PATH="$HOME/.elan/bin:$PATH"
   ```

2. Bauen Sie das Projekt:
   ```bash
   lake build
   ```

Nach erfolgreichem Build befindet sich die ausführbare Binärdatei unter:
```text
./.lake/build/bin/lean-py-generator
```

---

## Nutzung & Ausführung (Usage)

### 1. Ausführen der Testsuite & Demos
Starten Sie die kompilierte Binärdatei direkt:
```bash
./.lake/build/bin/lean-py-generator
```

Das Programm führt automatisch folgende Schritte aus:
- Ausführung der **27 Transpiler-Unit- & Integrationstests** (portiert aus `transpiler-tests.lisp`).
- Validierung der Python 3 Laufzeitausführung via Subprozess.
- Erstellung einer formatierten Python-Beispieldatei (`output_sample.py`) via `writeSource` & `ruff format`.
- Erstellung eines formatierten Jupyter Notebooks (`output_sample.ipynb`) via `writeNotebook` & `jq`.

---

## Code-Beispiel (Code Usage in Lean 4)

Sie können die `PyGenerator`-Bibliothek in eigenen Lean 4 Modulen einbinden:

```lean
import PyGenerator.AST
import PyGenerator.Emitter
import PyGenerator.Writer

open PyGenerator

def main : IO Unit := do
  -- 1. Definieren eines Lisp S-Expression AST
  let ast := SExpr.list [
    SExpr.sym "def", SExpr.sym "add", SExpr.list [SExpr.sym "a", SExpr.sym "b"],
    SExpr.list [
      SExpr.sym "declare",
      SExpr.list [SExpr.sym "type", SExpr.sym "int", SExpr.sym "a"],
      SExpr.list [SExpr.sym "type", SExpr.sym "int", SExpr.sym "b"],
      SExpr.list [SExpr.sym "values", SExpr.sym "int"]
    ],
    SExpr.list [SExpr.sym "return", SExpr.list [SExpr.sym "+", SExpr.sym "a", SExpr.sym "b"]]
  ]

  -- 2. Emission als Python String
  let pyCode := emitPy ast { level := 0 }
  IO.println pyCode
  -- Ausgabe:
  -- def add(a: int, b: int) -> int:
  --     return a + b

  -- 3. Quellcode in Datei schreiben (inkl. ruff formatierung)
  writeSource "math_helper" ast

  -- 4. Jupyter Notebook (.ipynb) schreiben (inkl. jq formatierung)
  let nbCells := [
    SExpr.list [SExpr.sym "markdown", SExpr.str "# Math Helpers Demo"],
    SExpr.list [SExpr.sym "python", ast]
  ]
  writeNotebook "demo_notebook.ipynb" nbCells
```

---

## Modulstruktur (Architecture)

| Datei | Beschreibung |
| :--- | :--- |
| **`PyGenerator/AST.lean`** | `SExpr` Induktions-Datentyp, Predicates, Pair-Grouping & formaler Beweis (`groupPairs_length_le`). |
| **`PyGenerator/Precedence.lean`** | 15-Stufen Präzedenztabelle, Assoziativität & formaler Fallback-Beweis (`lookupAssociativity_default`). |
| **`PyGenerator/Declarations.lean`** | Typdeklarierungs-Parser (`consumeDeclare`) und Lambda-Listen-Parser (`parseOrdinaryLambdaList`). |
| **`PyGenerator/Emitter.lean`** | Core Emitter Engine (`emitPy`), F-Strings, Präzedenz-Minimierung (`paren*`), Kontrollfluss, Klassen & Operatoren. |
| **`PyGenerator/Writer.lean`** | Dateiausgabe mit automatischer `ruff format` & `jq` Jupyter Notebook JSON Formatierung. |
| **`PyGenerator/Tests.lean`** | Transpiler-Testrunner mit 27 Tests & Python 3 Subprozess-Ausführungsprüfer. |
| **`Main.lean`** | Einstiegspunkt für die ausführbare CLI-Binärdatei. |

---

## Tests Ausführen

Um die Tests nach Änderungen am Code neu zu bauen und auszuführen:
```bash
export PATH="$HOME/.elan/bin:$PATH"
lake build && ./.lake/build/bin/lean-py-generator
```
