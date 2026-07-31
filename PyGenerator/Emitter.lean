import PyGenerator.AST
import PyGenerator.Precedence
import PyGenerator.Declarations

open Lean

namespace PyGenerator

structure EmitConfig where
  level : Nat := 0
  omitRedundantParens : Bool := true
deriving Inhabited

def printSufficientDigitsF64 (f : Float) : String :=
  let s := toString f
  if s.contains 'e' || s.contains 'E' then
    s
  else if !s.contains '.' then
    s ++ ".0"
  else
    s

mutual
partial def emitPy (code : SExpr) (cfg : EmitConfig := {}) : String :=
  let emit (c : SExpr) (dl : Nat := 0) : String :=
    emitPy c { cfg with level := cfg.level + dl }

  let emitWithDl (c : SExpr) (dl : Nat) : String := emit c dl

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
    | "tuple" =>
      if args.isEmpty then "()"
      else if args.length == 1 then s!"({emit args.head!},)"
      else s!"({String.intercalate ", " (args.map (emit ·))})"
    | "dict" =>
      let kvs := groupPairs args
      let rendered := kvs.map (fun (k, v) => s!"({emit k}): ({emit v})")
      s!"\{{String.intercalate ", " rendered}}"
    | "dict*" =>
      let kvs := groupPairs args
      let rendered := kvs.map (fun (k, v) =>
        let keyName := match k with
          | SExpr.key s => s
          | SExpr.sym s => if s.startsWith ":" then (s.drop 1).toString else s
          | _ => emit k
        s!"{keyName}={emit v}"
      )
      s!"dict({String.intercalate ", " rendered})"
    | "indent" =>
      let pad := String.ofList (List.replicate (cfg.level * 4) ' ')
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
    | "def" => emitDefun (SExpr.list (head :: args)) emitWithDl
    | "=" =>
      match args with
      | [a, b] => s!"{emit a} = {emit b}"
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
      | name :: indices => s!"{emit name}[{String.intercalate ", " (indices.map (emit ·))}]"
      | _ => ""
    | "slice" =>
      let parts := args.map (fun a => match a with | SExpr.str "" => "" | _ => emit a)
      String.intercalate ":" parts
    | "dot" => String.intercalate "." (args.map (emit ·))
    | "paren*" =>
      match args with
      | [parentOp, arg] => emitParenStar parentOp arg .left cfg emitWithDl
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
    | "fstring" =>
      match args with
      | [SExpr.str s] => s!"f\"{s}\""
      | _ => ""
    | "fstring3" =>
      match args with
      | [SExpr.str s] => s!"f\"\"\"{s}\"\"\""
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
    | "+" | "*" | "@" | "==" | "<<" | "!=" | "<" | ">" | "<=" | ">=" | ">>"
    | "&" | "logand" | "logxor" | "|" | "^" | "logior" | "and" | "or" | "//" | "%" | "**" =>
      emitInfixOperator name args cfg emitWithDl
    | "-" =>
      if args.length == 1 then
        s!"-{emit (SExpr.list [SExpr.sym "paren*", SExpr.sym "-", args.head!])}"
      else
        emitInfixOperator "-" args cfg emitWithDl
    | "/" =>
      if args.length == 1 then
        s!"1.0 / {emit (SExpr.list [SExpr.sym "paren*", SExpr.sym "/", args.head!])}"
      else
        emitInfixOperator "/" args cfg emitWithDl
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
      let clauses := args.zipIdx.map (fun (clause, i) =>
        match clause with
        | SExpr.list (c :: stmts) =>
          let prefixStr :=
            if i == 0 then
              if c == SExpr.sym "t" then "if True" else s!"if {emit c}"
            else if c == SExpr.sym "t" then
              emit (SExpr.list [SExpr.sym "indent", SExpr.list [SExpr.sym "raw", SExpr.str "else"]])
            else
              emit (SExpr.list [SExpr.sym "indent", SExpr.list [SExpr.sym "raw", SExpr.str s!"elif {emit c}"]])
          s!"{prefixStr}:\n{emit (SExpr.list (SExpr.sym "body" :: stmts))}"
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
      match env.lookupType p with
      | some t => s!"{p}: {emit t 0}"
      | none => p
    )
    let keys := parsed.keyParam.map (fun (k, init) =>
      let typeHint := match env.lookupType k with
        | some t => s!": {emit t 0}"
        | none => ""
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
    | _ => s!" {op} "

  if cfg.omitRedundantParens then
    let rendered := args.zipIdx.map (fun (x, i) =>
      let side := if i == 0 then Assoc.left else Assoc.right
      emit (SExpr.list [SExpr.sym "paren*", SExpr.sym op, x]) 0
    )
    String.intercalate sep rendered
  else
    let rendered := args.map (fun x => s!"({emit x 0})")
    s!"({String.intercalate sep rendered})"

partial def parseAndEmitFString (str : String) (_cfg : EmitConfig) : String :=
  if str.contains '{' then
    s!"f\"{str}\""
  else
    s!"\"{str}\""

partial def parseExplicitString (args : List SExpr) (cfg : EmitConfig) : String :=
  let rec loop (rest : List SExpr) (raw bytes triple forceF : Bool) : String :=
    match rest with
    | e :: xs =>
      let matchesKey (target : String) : Bool :=
        match e with
        | SExpr.key k => k == target
        | SExpr.sym s => s == target || s == s!":{target}"
        | _ => false
      if matchesKey "raw" then loop xs true bytes triple forceF
      else if matchesKey "bytes" then loop xs raw true triple forceF
      else if matchesKey "triple" then loop xs raw bytes true forceF
      else if matchesKey "f" then loop xs raw bytes triple true
      else
        let prefixStr := (if bytes then "b" else "") ++ (if raw then "r" else "") ++ (if forceF then "f" else "")
        let quoteStr := if triple then "\"\"\"" else "\""
        let body := String.join ((e :: xs).map (fun a =>
          match a with
          | SExpr.str s => s
          | _ => s!"\{{emitPy a cfg}}"
        ))
        s!"{prefixStr}{quoteStr}{body}{quoteStr}"
    | [] =>
      let prefixStr := (if bytes then "b" else "") ++ (if raw then "r" else "") ++ (if forceF then "f" else "")
      let quoteStr := if triple then "\"\"\"" else "\""
      s!"{prefixStr}{quoteStr}{quoteStr}"
  loop args false false false false
end

end PyGenerator
