import PyGenerator.Emitter
import Lean

open Lean

namespace PyGenerator

/-- Write source code to file and execute ruff code formatter if available -/
def writeSource (name : String) (code : SExpr) (dir : Option String := none) (ignoreHash : Bool := false) : IO Unit := do
  let targetDir := dir.getD "."
  let filePath := if name.endsWith ".py" then s!"{targetDir}/{name}" else s!"{targetDir}/{name}.py"
  let codeStr := emitPy code { level := 0 }
  
  IO.FS.writeFile filePath codeStr

  -- Run ruff format on generated Python file
  let ruffPath := "/usr/bin/ruff"
  if ← System.FilePath.pathExists ruffPath then
    let _ ← IO.Process.run { cmd := ruffPath, args := #["format", filePath] }
  else
    let localRuff := "/workspace/.venv/bin/ruff"
    if ← System.FilePath.pathExists localRuff then
      let _ ← IO.Process.run { cmd := localRuff, args := #["format", filePath] }

/-- Jupyter Notebook Cell Data -/
structure NotebookCell where
  cell_type : String
  metadata : Json := Json.obj []
  execution_count : Option Nat := none
  outputs : List Json := []
  source : List String
deriving ToJson

/-- Write SExpr structure to Jupyter Notebook (.ipynb) format using jq formatting -/
def writeNotebook (nbFile : String) (nbCode : List SExpr) : IO Unit := do
  let tmpFile := s!"{nbFile}.tmp"

  let cells : List Json := nbCode.filterMap (fun cellExpr =>
    match cellExpr with
    | SExpr.list (SExpr.sym "markdown" :: lines) =>
      let sourceLines := lines.map (fun p => match p with | SExpr.str s => s!"{s}\n" | _ => "")
      some <| toJson ({ cell_type := "markdown", source := sourceLines } : NotebookCell)
    | SExpr.list (SExpr.sym "python" :: codeForms) =>
      let sourceLines := codeForms.map (fun form => emitPy form ++ "\n")
      some <| toJson ({ cell_type := "code", execution_count := none, outputs := [], source := sourceLines } : NotebookCell)
    | _ => none
  )

  let notebookJson := Json.obj [
    ("cells", Json.arr cells.toArray),
    ("metadata", Json.obj [
      ("kernelspec", Json.obj [
        ("display_name", "Python 3"),
        ("language", "python"),
        ("name", "python3")
      ])
    ]),
    ("nbformat", 4),
    ("nbformat_minor", 2)
  ]

  IO.FS.writeFile tmpFile notebookJson.pretty

  let jqPath := "/usr/bin/jq"
  if ← System.FilePath.pathExists jqPath then
    let out ← IO.Process.run { cmd := jqPath, args := #["-M", ".", tmpFile], stdout := .piped }
    IO.FS.writeFile nbFile out.stdout
  else
    IO.FS.writeFile nbFile notebookJson.pretty

  if ← System.FilePath.pathExists tmpFile then
    IO.FS.removeFile tmpFile

end PyGenerator
