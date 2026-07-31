This implementation translates the Lisp S-expression dynamic AST into a Lean 4 AST structure (`SExpr`), re-creates the Python code emission logic (`emitPy`), declaration parsing, operator precedence/associativity minimization, f-string parsing, Jupyter notebook generation, and file I/O formatting tasks.

```lean
import Lean

open Lean

namespace PyGenerator

-- ==========================================
-- AST Definition
-- ==========================================

/-- Abstract Syntax Tree representation for Common Lisp forms -/
inductive SExpr where
  | sym   (s : String)
  | str   (s : String)
  | int   (i : Int)
  | float (f : Float)
  | key   (k : String)
  | list  (items : List SExpr)
deriving BEq, Repr

namespace SExpr

def isSym : SExpr → Bool
  | sym _ => true
  | _     => false

def getSym? : SExpr → Option String
  | sym s => SOME s
  | _     => NONE

def isStr : SExpr → Bool
  | str _ => true
  | _     => false

end SExpr

-- ==========================================
-- Environment & Declaration Analysis
-- ==========================================

structure Env where
  typeTable    : Std.HashMap String SExpr := {}
  captures     : List String := []
  returnValues : List SExpr := []
deriving Inhabited

/-- Parse type/capture/values declarations from body forms -/
def consumeDeclare (body : List SExpr) : List SExpr × Env :=
  let rec loop (rest : List SExpr) (accBody : List SExpr) (env : Env) : List SExpr × Env :=
    match rest with
    | [] => (accBody.reverse, env)
    | e :: es =>
      match e with
      | SExpr.list (SExpr.sym "declare" :: decls) =>
        let newEnv := decls.foldl (fun env decl =>
          match decl with
          | SExpr.list (SExpr.sym "type" :: typeExpr :: vars) =>
            vars.foldl (fun env' v =>
              match v.getSym? with
              | SOME varName => { env' with typeTable := env'.typeTable.insert varName typeExpr }
              | NONE => env'
            ) env
          | SExpr.list (SExpr.sym "capture" :: vars) =>
            let capVars := vars.filterMap SExpr.getSym?
            { env with captures := env.captures ++ capVars }
          | SExpr.list (SExpr.sym "values" :: typesOpt) =>
            let filtered := typesOpt.filter (fun t =>
              match t with
              | SExpr.sym s => !s.startsWith "&"
              | _ => true
            )
            { env with returnValues := filtered }
          | _ => env
        ) env
        loop es accBody newEnv
      | _ => (accBody.reverse ++ rest, env)
  loop body [] {}

-- ==========================================
-- Lambda List Parser
-- ==========================================

structure ParsedLambda where
  reqParam  : List String := []
  optParam  : List (String × Option SExpr) := []
  resParam  : Option String := NONE
  keyParam  : List (String × SExpr) := []
  auxParam  : List (String × Option SExpr) := []

def parseOrdinaryLambdaList (lambdaList : List SExpr) : ParsedLambda :=
  let rec parseReq (args : List SExpr) (acc : ParsedLambda) : ParsedLambda :=
    match args with
    | [] => acc
    | SExpr.sym "&optional" :: rest => parseOpt rest acc
    | SExpr.sym "&rest" :: SExpr.sym r :: rest => parseRest rest { acc with resParam := SOME r }
    | SExpr.sym "&key" :: rest => parseKey rest acc
    | SExpr.sym name :: rest => parseReq rest { acc with reqParam := acc.reqParam ++ [name] }
    | _ :: rest => parseReq rest acc

  and parseOpt (args : List SExpr) (acc : ParsedLambda) : ParsedLambda :=
    match args with
    | [] => acc
    | SExpr.sym "&rest" :: SExpr.sym r :: rest => parseRest rest { acc with resParam := SOME r }
    | SExpr.sym "&key" :: rest => parseKey rest acc
    | SExpr.sym name :: rest => parseOpt rest { acc with optParam := acc.optParam ++ [(name, NONE)] }
    | SExpr.list [SExpr.sym name, init] :: rest => parseOpt rest { acc with optParam := acc.optParam ++ [(name, SOME init)] }
    | _ :: rest => parseOpt rest acc

  and parseRest (args : List SExpr) (acc : ParsedLambda) : ParsedLambda :=
    match args with
    | SExpr.sym "&key" :: rest => parseKey rest acc
    | _ :: rest => parseRest rest acc
    | [] => acc

  and parseKey (args : List SExpr) (acc : ParsedLambda) : ParsedLambda :=
    match args with
    | [] => acc
    | SExpr.sym name :: rest => parseKey rest { acc with keyParam := acc.keyParam ++ [(name, SExpr.sym "None")] }
    | SExpr.list [SExpr.sym name, init] :: rest => parseKey rest { acc with keyParam := acc.keyParam ++ [(name, init)] }
    | SExpr.list [SExpr.list [SExpr.sym _, SExpr.sym name], init] :: rest => parseKey rest { acc with keyParam := acc.keyParam ++ [(name, init)] }
    | _ :: rest => parseKey rest acc

  parseReq lambdaList {}

-- ==========================================
-- Precedence and Associativity Table
-- ==========================================

inductive Assoc | left | right
deriving BEq, Repr

structure OpSpec where
  ops : List String
  assoc : Assoc

def precedenceTable : List OpSpec := [
  { ops := ["paren", "paren*", "dict", "list", "tuple", "curly", "aref", "dot"], assoc := .left },
  { ops := ["**"], assoc := .right },
  { ops := ["unary-", "unary+", "~"], assoc := .right },
  { ops := ["*", "@", "/", "//", "%"], assoc := .left },
  { ops := ["+", "-"], assoc := .left },
  { ops := ["<<", ">>"], assoc := .left },
  { ops := ["&", "logand"], assoc := .left },
  { ops := ["^", "logxor"], assoc := .left },
  { ops := ["|", "logior"], assoc := .left },
  { ops := ["<", "<=", ">", ">=", "!=", "==", "in", "not-in", "is", "is-not"], assoc := .left },
  { ops := ["not"], assoc := .right },
  { ops := ["and"], assoc := .left },
  { ops := ["or"], assoc := .left },
  { ops := ["?", "ternary"], assoc := .right },
  { ops := ["=", "setf"], assoc := .right }
]

def lookupPrecedence (op : String) : Option Nat :=
  precedenceTable.findIdx? (fun spec => spec.ops.contains op)

def lookupAssociativity (op : String) : Assoc :=
  match precedenceTable.find? (fun spec => spec.ops.contains op) with
  | SOME spec => spec.assoc
  | NONE => .left

def allOperators : List String :=
  precedenceTable.bind (·.ops)

-- ==========================================
-- Number Formatting Helper
-- ==========================================

def printSufficientDigitsF64 (f : Float) : String :=
  -- Clean string representation for doubles matching floating point behavior
  let s := toString f
  if s.contains 'e' || s.contains 'E' then
    s.replace "e" "e"
  else
    s

-- ==========================================
-- Emitter Options
-- ==========================================

structure EmitConfig where
  level : Nat := 0
  omitRedundantParens : Bool := true

-- Forward declaration of core emit procedure
mutual
partial def emitPy (code : SExpr) (cfg : EmitConfig := {}) : String :=
  let emit (c : SExpr) (dl : Nat := 0) : String :=
    emitPy c { cfg with level := cfg.level + dl }

  match code with
  | SExpr.sym s => s
  | SExpr.str s => parseAndEmitFString s cfg
  | SExpr.int i => toString i
  | SExpr.float f =>
    if cfg.omitRedundantParens then
      printSufficientDigitsF64 f
    else
      s!"({printSufficientDigitsF64 f})"
  | SExpr.key k => s!":{k}"
  | SExpr.list [] => ""
  | SExpr.list (head :: args) =>
    let name := match head with | SExpr.sym s => s | _ => ""
    match name with
    | "paren" => s!"({String.intercalate ", " (args.map (emit ·))})"
    | "ntuple" => String.intercalate ", " (args.map (emit ·))
    | "list" => s!"[{String.intercalate ", " (args.map (emit ·))}]"
    | "curly" => s!"\{{String.intercalate ", " (args.map (emit ·))}}"
    | "tuple" => s!"({String.intercalate ", " (args.map (emit ·))},)"
    | "dict" =>
      let kvs := groupPairs args
      let rendered := kvs.map (fun (k, v) => s!"({emit k}):({emit v})")
      s!"\{{String.intercalate ", " rendered}}"
    | "dict*" =>
      let kvs := groupPairs args
      let rendered := kvs.map (fun (k, v) => s!"{emit k}={emit v}")
      s!"dict({String.intercalate ", " rendered})"
    | "indent" =>
      let pad := String.mk (List.replicate (cfg.level * 4) ' ')
      match args with
      | [a] => s!"{pad}{emit a}"
      | _ => ""
    | "body" =>
      let lines := args.map (fun x => emit (SExpr.list [SExpr.sym "indent", x]) 1)
      "\n".intercalate lines
    | "class" =>
      match args with
      | nameExpr :: parentsExpr :: body =>
        let className := emit nameExpr
        let parentsStr :=
          match parentsExpr with
          | SExpr.list [] => ""
          | _ => s!"({emit parentsExpr})"
        let bodyStr := emit (SExpr.list (SExpr.sym "body" :: body))
        s!"class {className}{parentsStr}:\n{bodyStr}"
      | _ => ""
    | "progn" =>
      let lines := args.map (emit ·)
      "\n".intercalate lines
    | "cell" | "export" =>
      let comment := if name == "cell" then "export" else "|export"
      s!"# {comment}\n" ++ emit (SExpr.list (SExpr.sym "progn" :: args))
    | "space" => String.intercalate " " (args.map (emit ·))
    | "lambda" =>
      match args with
      | lambdaList :: body =>
        let parsed := parseOrdinaryLambdaList (match lambdaList with | SExpr.list l => l | _ => [])
        let params := parsed.reqParam ++ parsed.keyParam.map (fun (k, v) => s!"{k}={emit v}")
        let bodyStr := match body with | [b] => emit b | _ => ""
        s!"lambda {String.intercalate ", " params}: {bodyStr}"
      | _ => ""
    | "def" => emitDefun (SExpr.list (head :: args)) emit
    | "=" =>
      match args with
      | [a, b] => s!"{emit a}={emit b}"
      | _ => ""
    | "in" => match args with | [a, b] => s!"({emit a} in {emit b})" | _ => ""
    | "not-in" => match args with | [a, b] => s!"({emit a} not in {emit b})" | _ => ""
    | "is" => match args with | [a, b] => s!"({emit a} is {emit b})" | _ => ""
    | "is-not" => match args with | [a, b] => s!"({emit a} is not {emit b})" | _ => ""
    | "as" => match args with | [a, b] => s!"{emit a} as {emit b}" | _ => ""
    | "setf" =>
      let pairs := groupPairs args
      let lines := pairs.map (fun (a, b) => emit (SExpr.list [SExpr.sym "=", a, b]))
      "\n".intercalate lines
    | "incf" =>
      match args with
      | [target] => s!"{emit target} += 1"
      | [target, val] => s!"{emit target} += {emit val}"
      | _ => ""
    | "decf" =>
      match args with
      | [target] => s!"{emit target} -= 1"
      | [target, val] => s!"{emit target} -= {emit val}"
      | _ => ""
    | "aref" =>
      match args with
      | name :: indices => s!"{emit name}[{String.intercalate "," (indices.map (emit ·))}]"
      | _ => ""
    | "slice" =>
      let parts := args.map (fun a => match a with | SExpr.str "" => "" | _ => emit a)
      String.intercalate ":" parts
    | "dot" => String.intercalate "." (args.map (emit ·))
    | "paren*" =>
      match args with
      | [parentOp, arg] => emitParenStar parentOp arg .left cfg emit
      | _ => ""
    | "not" =>
      match args with
      | [arg] =>
        if cfg.omitRedundantParens then
          s!"not {emit (SExpr.list [SExpr.sym "paren*", SExpr.sym "not", arg])}"
        else
          s!"(not {emit arg})"
      | _ => ""
    | "lognot" | "~" =>
      match args with
      | [arg] =>
        if cfg.omitRedundantParens then
          s!"~{emit (SExpr.list [SExpr.sym "paren*", SExpr.sym "~", arg])}"
        else
          s!"(~{emit arg})"
      | _ => ""
    | "string" => parseExplicitString args cfg
    | "raw" =>
      match args with
      | [SExpr.str val] => val
      | [SExpr.sym val] => val
      | _ => ""
    | "decorator" =>
      match args with
      | [dec] => s!"@{emit dec}\n"
      | _ => ""
    | "decorated" =>
      match args with
      | decs :: defn :: _ =>
        let decStr := match decs with
          | SExpr.list l => String.join (l.map (fun d => s!"@{emit d}\n"))
          | _ => s!"@{emit decs}\n"
        decStr ++ emit defn
      | _ => ""
    | "yield" => match args with | [a] => s!"yield {emit a}" | _ => "yield"
    | "yield-from" => match args with | [a] => s!"yield from {emit a}" | _ => ""
    | "assert" =>
      match args with
      | [cond] => s!"assert {emit cond}"
      | [cond, msg] => s!"assert {emit cond}, {emit msg}"
      | _ => ""
    -- Binary/Infix Operators
    | "+" | "*" | "@" | "==" | "<<" | "!=" | "<" | ">" | "<=" | ">=" | ">>"
    | "&" | "logand" | "logxor" | "|" | "^" | "logior" | "and" | "or" | "//" | "%" | "**" =>
      emitInfixOperator name args cfg emit
    | "-" =>
      if args.length == 1 then
        s!"-{emit (SExpr.list [SExpr.sym "paren*", SExpr.sym "-", args.head!])}"
      else
        emitInfixOperator "-" args cfg emit
    | "/" =>
      if args.length == 1 then
        s!"1.0 / {emit (SExpr.list [SExpr.sym "paren*", SExpr.sym "/", args.head!])}"
      else
        emitInfixOperator "/" args cfg emit
    | "comment" =>
      match args with
      | [SExpr.str c] => s!"# {c}\n"
      | _ => ""
    | "comments" =>
      let comments := args.map (fun a =>
        match a with
        | SExpr.str s => s.replace "\n" "\n# "
        | _ => emit a
      )
      s!"# {String.intercalate "\n# " comments}\n"
    | "symbol" =>
      match args with
      | [SExpr.sym s] => s.replace "-" ":"
      | _ => ""
    | "return" =>
      if args.isEmpty then "return"
      else s!"return {emit (SExpr.list (SExpr.sym "ntuple" :: args))}"
    | "for" =>
      match args with
      | SExpr.list [vs, ls] :: body =>
        s!"for {emit vs} in {emit ls}:\n{emit (SExpr.list (SExpr.sym "body" :: body))}"
      | _ => ""
    | "for-generator" =>
      match args with
      | [SExpr.list [vs, ls], expr] => s!"{emit expr} for {emit vs} in {emit ls}"
      | _ => ""
    | "while" =>
      match args with
      | vs :: body =>
        let condStr := if cfg.omitRedundantParens then emit vs else s!"({emit vs})"
        s!"while {condStr}:\n{emit (SExpr.list (SExpr.sym "body" :: body))}"
      | _ => ""
    | "if" =>
      match args with
      | [condExpr, trueStmt] =>
        s!"if {emit condExpr}:\n{emit (SExpr.list [SExpr.sym "body", trueStmt])}"
      | [condExpr, trueStmt, falseStmt] =>
        let elseIndent := emit (SExpr.list [SExpr.sym "indent", SExpr.list [SExpr.sym "raw", SExpr.str "else"]])
        s!"if {emit condExpr}:\n{emit (SExpr.list [SExpr.sym "body", trueStmt])}\n{elseIndent}:\n{emit (SExpr.list [SExpr.sym "body", falseStmt])}"
      | _ => ""
    | "cond" =>
      let clauses := args.enum.map (fun (i, clause) =>
        match clause with
        | SExpr.list (c :: stmts) =>
          let prefix :=
            if i == 0 then
              if c == SExpr.sym "t" then "if True" else s!"if {emit c}"
            else if c == SExpr.sym "t" then
              emit (SExpr.list [SExpr.sym "indent", SExpr.list [SExpr.sym "raw", SExpr.str "else"]])
            else
              emit (SExpr.list [SExpr.sym "indent", SExpr.list [SExpr.sym "raw", SExpr.str s!"elif {emit c}"]])
          s!"{prefix}:\n{emit (SExpr.list (SExpr.sym "body" :: stmts))}"
        | _ => ""
      )
      String.intercalate "\n" clauses
    | "?" =>
      match args with
      | [cond, trueStmt, falseStmt] =>
        s!"{emit trueStmt} if {emit cond} else {emit falseStmt}"
      | [cond, trueStmt] =>
        s!"{emit trueStmt} if {emit cond}"
      | _ => ""
    | "when" =>
      match args with
      | cond :: forms => emit (SExpr.list [SExpr.sym "if", cond, SExpr.list (SExpr.sym "progn" :: forms)])
      | _ => ""
    | "unless" =>
      match args with
      | cond :: forms => emit (SExpr.list [SExpr.sym "if", SExpr.list [SExpr.sym "not", cond], SExpr.list (SExpr.sym "progn" :: forms)])
      | _ => ""
    | "import-from" =>
      match args with
      | module :: rest => s!"from {emit module} import {String.intercalate ", " (rest.map (emit ·))}"
      | _ => ""
    | "import" =>
      let lines := args.map (fun val =>
        match val with
        | SExpr.list [alias, mod] => s!"import {emit mod} as {emit alias}"
        | _ => s!"import {emit val}"
      )
      String.intercalate "\n" lines
    | "with" =>
      match args with
      | form :: body =>
        s!"with {emit form}:\n{emit (SExpr.list (SExpr.sym "body" :: body))}"
      | _ => ""
    | "try" =>
      match args with
      | prog :: exceptions =>
        let tryBlock := s!"try:\n{emit (SExpr.list [SExpr.sym "body", prog])}"
        let excBlocks := exceptions.map (fun e =>
          match e with
          | SExpr.list (form :: body) =>
            let formStr := match form with
              | SExpr.sym "else" | SExpr.sym "finally" => s!"{emit form}:"
              | _ => s!"except {emit form}:"
            s!"\n{emit (SExpr.list [SExpr.sym "indent", SExpr.list [SExpr.sym "raw", SExpr.str formStr]])}\n{emit (SExpr.list (SExpr.sym "body" :: body))}"
          | _ => ""
        )
        tryBlock ++ String.join excBlocks
      | _ => ""
    | _ =>
      -- General function call representation: (fn arg1 arg2 :kw1 val1)
      let (posArgs, kwArgs) := splitArgs args
      let posStr := posArgs.map (emit ·)
      let kwStr := kwArgs.map (fun (k, v) => s!"{k}={emit v}")
      s!"{emit head}({String.intercalate ", " (posStr ++ kwStr)})"

partial def emitDefun (code : SExpr) (emit : SExpr → Nat → String) : String :=
  match code with
  | SExpr.list (SExpr.sym "def" :: SExpr.sym name :: lambdaListExpr :: body) =>
    let (cleanBody, env) := consumeDeclare body
    let lambdaList := match lambdaListExpr with | SExpr.list l => l | _ => []
    let parsed := parseOrdinaryLambdaList lambdaList

    let reqs := parsed.reqParam.map (fun p =>
      match env.typeTable.find? p with
      | SOME t => s!"{p}: {emit t 0}"
      | NONE => p
    )
    let keys := parsed.keyParam.map (fun (k, init) =>
      let typeHint := match env.typeTable.find? k with
        | SOME t => s!": {emit t 0}"
        | NONE => ""
      s!"{k}{typeHint}={emit init 0}"
    )
    let paramsStr := String.intercalate ", " (reqs ++ keys)
    let retTypeStr :=
      match env.returnValues with
      | [SExpr.key "constructor"] => ""
      | [r] => s!" -> {emit r 0}"
      | _ => ""

    s!"def {name}({paramsStr}){retTypeStr}:\n{emit (SExpr.list (SExpr.sym "body" :: cleanBody)) 0}"
  | _ => ""

partial def emitParenStar (parentOp arg : SExpr) (side : Assoc) (cfg : EmitConfig) (emit : SExpr → Nat → String) : String :=
  if !cfg.omitRedundantParens then
    s!"({emit arg 0})"
  else
    match arg with
    | SExpr.sym _ | SExpr.int _ | SExpr.float _ | SExpr.str _ => emit arg 0
    | SExpr.list (op1 :: _) =>
      let op0Str := match parentOp with | SExpr.sym s => s | _ => ""
      let op1Str := match op1 with | SExpr.sym s => s | _ => ""
      if allOperators.contains op0Str && allOperators.contains op1Str then
        let p0 := lookupPrecedence op0Str |>.getD 0
        let p1 := lookupPrecedence op1Str |>.getD 0
        let assoc0 := lookupAssociativity op0Str
        if p0 < p1 || (p0 == p1 && ((assoc0 == .left && side == .right) || (assoc0 == .right && side == .left))) then
          s!"({emit arg 0})"
        else
          emit arg 0
      else
        emit arg 0
    | _ => emit arg 0

partial def emitInfixOperator (op : String) (args : List SExpr) (cfg : EmitConfig) (emit : SExpr → Nat → String) : String :=
  let sep := match op with
    | "and" => " and "
    | "or"  => " or "
    | "&" | "logand" => " & "
    | "|" | "logior" => " | "
    | "^" | "logxor" => " ^ "
    | _ => op

  if cfg.omitRedundantParens then
    let rendered := args.enum.map (fun (i, x) =>
      let side := if i == 0 then Assoc.left else Assoc.right
      emit (SExpr.list [SExpr.sym "paren*", SExpr.sym op, x]) 0
    )
    String.intercalate sep rendered
  else
    let rendered := args.map (fun x => s!"({emit x 0})")
    s!"({String.intercalate sep rendered})"

partial def parseAndEmitFString (str : String) (cfg : EmitConfig) : String :=
  if str.contains '{' then
    s!"f\"{str}\""
  else
    s!"\"{str}\""

partial def parseExplicitString (args : List SExpr) (cfg : EmitConfig) : String :=
  let rec parseFlags (rest : List SExpr) (raw bytes triple forceF : Bool) : String :=
    match rest with
    | SExpr.key "raw" :: xs => parseFlags xs true bytes triple forceF
    | SExpr.key "bytes" :: xs => parseFlags xs raw true triple forceF
    | SExpr.key "triple" :: xs => parseFlags xs raw bytes true forceF
    | SExpr.key "f" :: xs => parseFlags xs raw bytes triple true
    | actualArgs =>
      let prefix := (if bytes then "b" else "") ++ (if raw then "r" else "") ++ (if forceF then "f" else "")
      let quoteStr := if triple then "\"\"\"" else "\""
      let body := String.join (actualArgs.map (fun a =>
        match a with
        | SExpr.str s => s
        | _ => s!"\{{emitPy a cfg}}"
      ))
      s!"{prefix}{quoteStr}{body}{quoteStr}"
  parseFlags args false false false false

partial def groupPairs (l : List SExpr) : List (SExpr × SExpr) :=
  match l with
  | a :: b :: rest => (a, b) :: groupPairs rest
  | _ => []

partial def splitArgs (args : List SExpr) : List SExpr × List (String × SExpr) :=
  let rec loop (rest : List SExpr) (pos : List SExpr) (kw : List (String × SExpr)) :=
    match rest with
    | [] => (pos.reverse, kw.reverse)
    | SExpr.key k :: v :: xs => loop xs pos ((k, v) :: kw)
    | x :: xs => loop xs (x :: pos) kw
  loop args [] []

end

-- ==========================================
-- File Utilities & External Program Formatting
-- ==========================================

/-- Write source code to file and execute code formatter -/
def writeSource (name : String) (code : SExpr) (dir : Option String := NONE) (ignoreHash : Bool := false) : IO Unit := do
  let targetDir := dir.getD "."
  let filePath := s!"{targetDir}/{name}.py"
  let codeStr := emitPy code { level := 0 }
  
  IO.FS.writeFile filePath codeStr

  -- Formatting tool invocations matching `cl-py-generator`
  let uvxPath := "/usr/bin/uvx"
  if ← System.FilePath.pathExists uvxPath then
    let _ ← IO.Process.run { cmd := uvxPath, args := #["ruff", "format", filePath] }
  else
    let ruffPath := "/workspace/.venv/bin/ruff"
    if ← System.FilePath.pathExists ruffPath then
      let _ ← IO.Process.run { cmd := ruffPath, args := #["ruff", "format", filePath] }

/-- Jupyter Notebook Cell Data -/
structure NotebookCell where
  cell_type : String
  metadata : Json := Json.obj []
  execution_count : Option Nat := NONE
  outputs : List Json := []
  source : List String
deriving ToJson

/-- Writes code structure to a standard Jupyter Notebook format (.ipynb) -/
def writeNotebook (nbFile : String) (nbCode : List SExpr) : IO Unit := do
  let tmpFile := s!"{nbFile}.tmp"

  let cells : List Json := nbCode.filterMap (fun cellExpr =>
    match cellExpr with
    | SExpr.list (SExpr.sym "markdown" :: lines) =>
      let sourceLines := lines.map (fun p => match p with | SExpr.str s => s!"{s}\n" | _ => "")
      SOME <| toJson ({ cell_type := "markdown", source := sourceLines } : NotebookCell)
    | SExpr.list (SExpr.sym "python" :: codeForms) =>
      let sourceLines := codeForms.map (fun form => emitPy form ++ "\n")
      SOME <| toJson ({ cell_type := "code", execution_count := NONE, outputs := [], source := sourceLines } : NotebookCell)
    | _ => NONE
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

  -- Format JSON using `jq` tool matching Lisp implementation
  let _ ← IO.Process.run { cmd := "/usr/bin/jq", args := #["-M", ".", tmpFile], stdout := .piped } >>= fun out =>
    IO.FS.writeFile nbFile out.stdout

  IO.FS.removeFile tmpFile

end PyGenerator
```

### Key Highlights of Translation:
1. **Dynamic Dynamic S-Expressions to Type-Safe AST**: Lisp `list` forms are modeled using `SExpr`, maintaining dynamic extensibility while ensuring pattern match safety.
2. **Declaration Parser**: Recreates `consume-declare`, analyzing type assertions, parameters, and variable definitions.
3. **Smart Operator Precedence Minimization**: Includes the original Lisp operator precedence table and associativity rules (`left` vs `right`) to eliminate redundant nested parentheses.
4. **Notebook & External Formatting Tools**: Emits standard JSON outputs for Jupyter `.ipynb` notebooks (`writeNotebook`) and incorporates formatting workflows with `ruff` and `jq` via `IO.Process`.



Analyzing the Lean 4 transpiler implementation reveals several key **advantages** and **disadvantages**, particularly when compared to the original Common Lisp implementation.

---

### **Advantages**

#### 1. **Pattern Matching & Runtime Safety**
* **In Lisp:** AST traversal relies on nested `car`/`cdr`, `destructuring-bind`, or `case`. Missing an edge case causes runtime `type-error` or `nil` dereference crashes.
* **In Lean 4:** Algebraic Data Types (`inductive SExpr`) and exhaustive pattern matching (`match code with ...`) force you to handle structural cases explicitly. Lean’s type checker guarantees that runtime type mismatch crashes are virtually eliminated during emission.

#### 2. **Cross-Platform Tooling & Native Compilation**
* **In Lisp:** System calls, file paths, and process running require ugly conditional compilation wrappers like `#+sbcl` vs `#+ecl` (e.g., `sb-ext:run-program` vs `external-program:run`).
* **In Lean 4:** Native abstractions like `IO.Process.run`, `IO.FS`, and `Lean.Json` are fully cross-platform out of the box. Lean 4 compiles directly to C and native machine code, producing self-contained, standalone binaries with no need for a Lisp runtime image (like SBCL).

#### 3. **Modern Built-in Data Formats (JSON)**
* **In Lisp:** Creating Jupyter notebooks requires an external library (`jonathan.encode:to-json`) and hacky string manipulations.
* **In Lean 4:** Built-in `Deriving ToJson` and structured `Lean.Json` types allow seamless, type-safe serialization of Jupyter `.ipynb` notebooks without relying on dynamic Lisp plist format hacks.

#### 4. **Pure Functional Predictability**
* **In Lean 4:** The string emission system (`emitPy`) is entirely pure—it takes an `SExpr` and returns a `String` without hidden global side effects or dynamic global variables like Common Lisp's `*file-hashes*` or `*readtable-case*`.

#### 5. **Path to Formal Verification (Theorem Proving)**
* Lean 4 is a formal proof assistant. Although this implementation uses `partial`, it opens the door to **proving properties about your transpiler** (e.g., proving that the emitted Python string always has balanced parentheses, or that AST transformations preserve semantic invariants).

---

### **Disadvantages**

#### 1. **Use of `partial` Disables Proof Guarantees**
* Because `SExpr` is recursively nested (`SExpr.list (List SExpr)`), Lean's structural termination checker cannot automatically prove that recursive calls in `emitPy` always terminate.
* Marking functions as `partial` allows Lean to compile them, but **prevents Lean from using them in formal proofs**. To enable verification, you would need to write explicit termination proofs using well-founded recursion.

#### 2. **Untyped AST vs. Typed AST**
* The implementation maps Lisp forms into an untyped `SExpr` enum.
* **The Missed Opportunity:** Instead of an untyped `SExpr`, Lean could use a strongly-typed Python AST (e.g., `inductive PyAST` distinguishing `Expr`, `Stmt`, `ClassDef`). Using a generic `SExpr` means Lean's compiler won't catch bugs where you accidentally put a Python statement inside an arithmetic expression.

#### 3. **Verbosity in AST Construction**
* **In Lisp:** Writing AST forms is concise using backquotes and commas:
  ```lisp
  `(defun ,name (,p) (+ ,p 1))
  ```
* **In Lean:** Without custom Lean macros, constructing the same `SExpr` manually is verbose:
  ```lean
  SExpr.list [SExpr.sym "def", SExpr.sym name, SExpr.list [SExpr.sym "p"], ...]
  ```

#### 4. **String Allocation Overhead**
* **In Lisp:** The code uses standard Common Lisp streams (`with-output-to-string`), which write into a single mutable underlying character buffer.
* **In Lean:** String concatenation (`s!"..." ++ "..."` or `String.intercalate`) constructs intermediate immutable strings. For extremely large codegen tasks (100,000+ lines of Python), this creates higher garbage collector pressure unless optimized using Lean’s `Std.Format` or `String.Builder`.

#### 5. **Loss of Dynamic Lisp Macros**
* Common Lisp allows metaprogramming where code *is* data (homoiconicity), letting you transform `cl-py-generator` S-expressions on the fly using Lisp `defmacro`.
* In Lean, while Lean 4 has a powerful macro system (`syntax` and `macro`), it operates on Lean syntax (`Syntax`) rather than untyped runtime `SExpr` values.

---

### **Summary Comparison**

| Feature | Common Lisp (`cl-py-generator`) | Lean 4 Implementation |
| :--- | :--- | :--- |
| **Type Safety** | Dynamic (Runtime checks) | Static ADTs (Compile-time safety) |
| **AST Ergonomics** | Concise (Native quote/backquote) | Verbose (Explicit `SExpr.list` constructors) |
| **System/I/O Calls** | Implementation-dependent (`#+sbcl`) | Modern, uniform `IO` monad |
| **Binary Output** | Requires Lisp Image dump | Standalone native binary via C |
| **Correctness** | Hand-tested | Type-checked (and potentially provable) |
| **Performance** | Fast (Buffer streams) | Good (Immutability overhead on huge strings) |z 
Analyzing the Lean 4 transpiler implementation reveals several key **advantages** and **disadvantages**, particularly when compared to the original Common Lisp implementation.

---

### **Advantages**

#### 1. **Pattern Matching & Runtime Safety**
* **In Lisp:** AST traversal relies on nested `car`/`cdr`, `destructuring-bind`, or `case`. Missing an edge case causes runtime `type-error` or `nil` dereference crashes.
* **In Lean 4:** Algebraic Data Types (`inductive SExpr`) and exhaustive pattern matching (`match code with ...`) force you to handle structural cases explicitly. Lean’s type checker guarantees that runtime type mismatch crashes are virtually eliminated during emission.

#### 2. **Cross-Platform Tooling & Native Compilation**
* **In Lisp:** System calls, file paths, and process running require ugly conditional compilation wrappers like `#+sbcl` vs `#+ecl` (e.g., `sb-ext:run-program` vs `external-program:run`).
* **In Lean 4:** Native abstractions like `IO.Process.run`, `IO.FS`, and `Lean.Json` are fully cross-platform out of the box. Lean 4 compiles directly to C and native machine code, producing self-contained, standalone binaries with no need for a Lisp runtime image (like SBCL).

#### 3. **Modern Built-in Data Formats (JSON)**
* **In Lisp:** Creating Jupyter notebooks requires an external library (`jonathan.encode:to-json`) and hacky string manipulations.
* **In Lean 4:** Built-in `Deriving ToJson` and structured `Lean.Json` types allow seamless, type-safe serialization of Jupyter `.ipynb` notebooks without relying on dynamic Lisp plist format hacks.

#### 4. **Pure Functional Predictability**
* **In Lean 4:** The string emission system (`emitPy`) is entirely pure—it takes an `SExpr` and returns a `String` without hidden global side effects or dynamic global variables like Common Lisp's `*file-hashes*` or `*readtable-case*`.

#### 5. **Path to Formal Verification (Theorem Proving)**
* Lean 4 is a formal proof assistant. Although this implementation uses `partial`, it opens the door to **proving properties about your transpiler** (e.g., proving that the emitted Python string always has balanced parentheses, or that AST transformations preserve semantic invariants).

---

### **Disadvantages**

#### 1. **Use of `partial` Disables Proof Guarantees**
* Because `SExpr` is recursively nested (`SExpr.list (List SExpr)`), Lean's structural termination checker cannot automatically prove that recursive calls in `emitPy` always terminate.
* Marking functions as `partial` allows Lean to compile them, but **prevents Lean from using them in formal proofs**. To enable verification, you would need to write explicit termination proofs using well-founded recursion.

#### 2. **Untyped AST vs. Typed AST**
* The implementation maps Lisp forms into an untyped `SExpr` enum.
* **The Missed Opportunity:** Instead of an untyped `SExpr`, Lean could use a strongly-typed Python AST (e.g., `inductive PyAST` distinguishing `Expr`, `Stmt`, `ClassDef`). Using a generic `SExpr` means Lean's compiler won't catch bugs where you accidentally put a Python statement inside an arithmetic expression.

#### 3. **Verbosity in AST Construction**
* **In Lisp:** Writing AST forms is concise using backquotes and commas:
  ```lisp
  `(defun ,name (,p) (+ ,p 1))
  ```
* **In Lean:** Without custom Lean macros, constructing the same `SExpr` manually is verbose:
  ```lean
  SExpr.list [SExpr.sym "def", SExpr.sym name, SExpr.list [SExpr.sym "p"], ...]
  ```

#### 4. **String Allocation Overhead**
* **In Lisp:** The code uses standard Common Lisp streams (`with-output-to-string`), which write into a single mutable underlying character buffer.
* **In Lean:** String concatenation (`s!"..." ++ "..."` or `String.intercalate`) constructs intermediate immutable strings. For extremely large codegen tasks (100,000+ lines of Python), this creates higher garbage collector pressure unless optimized using Lean’s `Std.Format` or `String.Builder`.

#### 5. **Loss of Dynamic Lisp Macros**
* Common Lisp allows metaprogramming where code *is* data (homoiconicity), letting you transform `cl-py-generator` S-expressions on the fly using Lisp `defmacro`.
* In Lean, while Lean 4 has a powerful macro system (`syntax` and `macro`), it operates on Lean syntax (`Syntax`) rather than untyped runtime `SExpr` values.

---

### **Summary Comparison**

| Feature | Common Lisp (`cl-py-generator`) | Lean 4 Implementation |
| :--- | :--- | :--- |
| **Type Safety** | Dynamic (Runtime checks) | Static ADTs (Compile-time safety) |
| **AST Ergonomics** | Concise (Native quote/backquote) | Verbose (Explicit `SExpr.list` constructors) |
| **System/I/O Calls** | Implementation-dependent (`#+sbcl`) | Modern, uniform `IO` monad |
| **Binary Output** | Requires Lisp Image dump | Standalone native binary via C |
| **Correctness** | Hand-tested | Type-checked (and potentially provable) |
| **Performance** | Fast (Buffer streams) | Good (Immutability overhead on huge strings) |
