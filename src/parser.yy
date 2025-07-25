%skeleton "lalr1.cc"
%require "3.0.4"
%defines
%define api.namespace { bpftrace }
// Pretend like the following %define is uncommented. We set the actual
// definition from cmake to handle older versions of bison.
// %define api.parser.class { Parser }
%define api.token.constructor
%define api.value.type variant
%define define_location_comparison
%define parse.assert
%define parse.trace
%expect 0

%define parse.error verbose

%param { bpftrace::Driver &driver }
%param { void *yyscanner }
%locations

// Forward declarations of classes referenced in the parser
%code requires
{
#include <cstdint>
#include <limits>
#include <regex>

namespace bpftrace {
class Driver;
namespace ast {
class Node;
} // namespace ast
} // namespace bpftrace
#include "ast/ast.h"
#include "ast/context.h"
}

%{
#include <iostream>

#include "driver.h"
#include "parser.tab.hh"

YY_DECL;

void yyerror(bpftrace::Driver &driver, const char *s);
%}

%token
  END 0      "end of file"
  COLON      ":"
  SEMI       ";"
  LBRACE     "{"
  RBRACE     "}"
  LBRACKET   "["
  RBRACKET   "]"
  LPAREN     "("
  RPAREN     ")"
  QUES       "?"
  ENDPRED    "end predicate"
  COMMA      ","
  PARAMCOUNT "$#"
  ASSIGN     "="
  EQ         "=="
  NE         "!="
  LE         "<="
  GE         ">="
  LEFT       "<<"
  RIGHT      ">>"
  LT         "<"
  GT         ">"
  LAND       "&&"
  LOR        "||"
  PLUS       "+"
  INCREMENT  "++"

  LEFTASSIGN   "<<="
  RIGHTASSIGN  ">>="
  PLUSASSIGN  "+="
  MINUSASSIGN "-="
  MULASSIGN   "*="
  DIVASSIGN   "/="
  MODASSIGN   "%="
  BANDASSIGN  "&="
  BORASSIGN   "|="
  BXORASSIGN  "^="

  MINUS      "-"
  DECREMENT  "--"
  MUL        "*"
  DIV        "/"
  MOD        "%"
  BAND       "&"
  BOR        "|"
  BXOR       "^"
  LNOT       "!"
  BNOT       "~"
  DOT        "."
  PTR        "->"
  STRUCT     "struct"
  UNION      "union"

  // Pseudo token; see below.
  LOW "low-precedence"
;

%token <std::string> BUILTIN "builtin"
%token <std::string> INT_TYPE "integer type"
%token <std::string> BUILTIN_TYPE "builtin type"
%token <std::string> SUBPROG "subprog"
%token <std::string> MACRO "macro"
%token <std::string> SIZED_TYPE "sized type"
%token <std::string> IDENT "identifier"
%token <std::string> PATH "path"
%token <std::string> CPREPROC "preprocessor directive"
%token <std::string> STRUCT_DEFN "struct definition"
%token <std::string> ENUM "enum"
%token <std::string> STRING "string"
%token <std::string> MAP "map"
%token <std::string> VAR "variable"
%token <std::string> PARAM "positional parameter"
%token <uint64_t> UNSIGNED_INT "integer"
%token <std::string> CONFIG "config"
%token <std::string> UNROLL "unroll"
%token <std::string> WHILE "while"
%token <std::string> FOR "for"
%token <std::string> RETURN "return"
%token <std::string> IF "if"
%token <std::string> ELSE "else"
%token <std::string> CONTINUE "continue"
%token <std::string> BREAK "break"
%token <std::string> SIZEOF "sizeof"
%token <std::string> OFFSETOF "offsetof"
%token <std::string> LET "let"
%token <std::string> IMPORT "import"

%type <ast::Operator> unary_op compound_op
%type <std::string> attach_point_def c_definitions ident keyword external_name
%type <std::vector<std::string>> struct_field

%type <ast::AttachPoint *> attach_point
%type <ast::AttachPointList> attach_points
%type <ast::Block *> bare_block
%type <ast::BlockExpr *> block_expr
%type <ast::Call *> call
%type <ast::Sizeof *> sizeof_expr
%type <ast::Offsetof *> offsetof_expr
%type <ast::Expression> and_expr addi_expr primary_expr cast_expr conditional_expr equality_expr expr logical_and_expr muli_expr
%type <ast::Expression> logical_or_expr or_expr postfix_expr relational_expr shift_expr tuple_access_expr unary_expr xor_expr
%type <ast::ExpressionList> vargs
%type <ast::SubprogArg *> subprog_arg
%type <ast::SubprogArgList> subprog_args
%type <ast::ExpressionList> macro_args
%type <ast::Map *> map
%type <ast::MapAccess *> map_expr
%type <ast::PositionalParameter *> param
%type <ast::PositionalParameterCount *> param_count
%type <ast::Predicate *> pred
%type <ast::Config *> config
%type <ast::Import *> import_stmt
%type <ast::ImportList> imports
%type <ast::Statement> assign_stmt block_stmt expr_stmt if_stmt jump_stmt loop_stmt for_stmt
%type <ast::RootStatement> root_stmt macro map_decl_stmt subprog probe
%type <ast::RootStatements> root_stmts
%type <ast::Range *> range
%type <ast::VarDeclStatement *> var_decl_stmt
%type <ast::StatementList> block block_or_if stmt_list
%type <ast::AssignConfigVarStatement *> config_assign_stmt
%type <ast::ConfigStatementList> config_assign_stmt_list config_block
%type <SizedType> type int_type pointer_type struct_type
%type <ast::Variable *> var
%type <ast::Program *> program


// A pseudo token, which is the lowest precedence among all tokens.
//
// This helps us explicitly lower the precedence of a given rule to force shift
// vs. reduce, and make the grammar explicit (still ambiguous, but explicitly
// ambiguous). For example, consider the inherently ambiguous `@foo[..]`, which
// could be interpreted as accessing the `@foo` non-scalar map, or indexing
// into the value of the `@foo` scalar map, e.g. `(@foo)[...]`. We lower the
// precedence of the associated rules to ensure that this is shifted, and the
// longer `map_expr` rule will match over the `map` rule in this case.
%left LOW

%left COMMA
%right ASSIGN LEFTASSIGN RIGHTASSIGN PLUSASSIGN MINUSASSIGN MULASSIGN DIVASSIGN MODASSIGN BANDASSIGN BORASSIGN BXORASSIGN
%left QUES COLON
%left LOR
%left LAND
%left BOR
%left BXOR
%left BAND
%left EQ NE
%left LE GE LT GT
%left LEFT RIGHT
%left PLUS MINUS
%left MUL DIV MOD
%right LNOT BNOT
%left DOT PTR
%right PAREN RPAREN
%right LBRACKET RBRACKET

// In order to support the parsing of full programs and the parsing of just
// expressions (used while expanding C macros, for example), use the trick
// described in Bison's FAQ [1].
// [1] https://www.gnu.org/software/bison/manual/html_node/Multiple-start_002dsymbols.html
%token START_PROGRAM "program"
%token START_EXPR "expression"
%start start

%%

start:          START_PROGRAM program END { driver.result = $2; }
        |       START_EXPR expr END       { driver.result = $2; }
                ;

program:
                c_definitions config imports root_stmts {
                    $$ = driver.ctx.make_node<ast::Program>($1, $2, std::move($3), std::move($4), @$);
                }
                ;

c_definitions:
                CPREPROC c_definitions           { $$ = $1 + "\n" + $2; }
        |       STRUCT STRUCT_DEFN c_definitions { $$ = $2 + ";\n" + $3; }
        |       STRUCT ENUM c_definitions        { $$ = $2 + ";\n" + $3; }
        |       %empty                           { $$ = std::string(); }
                ;

imports:
                imports import_stmt { $$ = std::move($1); $$.push_back($2); }
        |       %empty              { $$ = ast::ImportList{}; }
                ;

import_stmt:
                IMPORT STRING ";" { $$ = driver.ctx.make_node<ast::Import>($2, @$); }
                ;

type:
                int_type { $$ = $1; }
        |       BUILTIN_TYPE {
                    static std::unordered_map<std::string, SizedType> type_map = {
                        {"void", CreateVoid()},
                        {"min_t", CreateMin(true)},
                        {"max_t", CreateMax(true)},
                        {"sum_t", CreateSum(true)},
                        {"count_t", CreateCount()},
                        {"avg_t", CreateAvg(true)},
                        {"stats_t", CreateStats(true)},
                        {"umin_t", CreateMin(false)},
                        {"umax_t", CreateMax(false)},
                        {"usum_t", CreateSum(false)},
                        {"uavg_t", CreateAvg(false)},
                        {"ustats_t", CreateStats(false)},
                        {"timestamp", CreateTimestamp()},
                        {"macaddr_t", CreateMacAddress()},
                        {"cgroup_path_t", CreateCgroupPath()},
                        {"strerror_t", CreateStrerror()},
                        {"string", CreateString(0)},
                    };
                    $$ = type_map[$1];
                }
        |       SIZED_TYPE {
                    if ($1 == "inet") {
                        $$ = CreateInet(0);
                    } else if ($1 == "buffer") {
                        $$ = CreateBuffer(0);
                    }
                }
        |       SIZED_TYPE "[" UNSIGNED_INT "]" {
                    if ($1 == "inet") {
                        $$ = CreateInet($3);
                    } else if ($1 == "buffer") {
                        $$ = CreateBuffer($3);
                    }
                }
        |       int_type "[" UNSIGNED_INT "]" {
                  $$ = CreateArray($3, $1);
                }
        |       struct_type "[" UNSIGNED_INT "]" {
                  $$ = CreateArray($3, $1);
                }
        |       int_type "[" "]" {
                  $$ = CreateArray(0, $1);
                }
        |       pointer_type { $$ = $1; }
        |       struct_type { $$ = $1; }
                ;

int_type:
                INT_TYPE {
                    static std::unordered_map<std::string, SizedType> type_map = {
                        {"bool", CreateBool()},
                        {"uint8", CreateUInt(8)},
                        {"uint16", CreateUInt(16)},
                        {"uint32", CreateUInt(32)},
                        {"uint64", CreateUInt(64)},
                        {"int8", CreateInt(8)},
                        {"int16", CreateInt(16)},
                        {"int32", CreateInt(32)},
                        {"int64", CreateInt(64)},
                    };
                    $$ = type_map[$1];
                }
                ;

pointer_type:
                type "*" { $$ = CreatePointer($1); }
                ;
struct_type:
                STRUCT IDENT { $$ = ast::ident_to_sized_type($2); }
                ;

config:
                CONFIG ASSIGN config_block     { $$ = driver.ctx.make_node<ast::Config>(std::move($3), @$); }
        |        %empty                        { $$ = nullptr; }
                ;

/*
 * The last statement in a config_block does not require a trailing semicolon.
 */
config_block:   "{" config_assign_stmt_list "}"                    { $$ = std::move($2); }
            |   "{" config_assign_stmt_list config_assign_stmt "}" { $$ = std::move($2); $$.push_back($3); }
                ;

config_assign_stmt_list:
                config_assign_stmt_list config_assign_stmt ";" { $$ = std::move($1); $$.push_back($2); }
        |       %empty                                         { $$ = ast::ConfigStatementList{}; }
                ;

config_assign_stmt:
                IDENT ASSIGN UNSIGNED_INT { $$ = driver.ctx.make_node<ast::AssignConfigVarStatement>($1, $3, @$); }
        |       IDENT ASSIGN IDENT        { $$ = driver.ctx.make_node<ast::AssignConfigVarStatement>($1, $3, @$); }
        |       IDENT ASSIGN STRING       { $$ = driver.ctx.make_node<ast::AssignConfigVarStatement>($1, $3, @$); }
                ;

subprog:
                SUBPROG IDENT "(" subprog_args ")" ":" type block {
                    $$ = driver.ctx.make_node<ast::Subprog>($2, $7, std::move($4), std::move($8), @$);
                }
        |       SUBPROG IDENT "(" ")" ":" type block {
                    $$ = driver.ctx.make_node<ast::Subprog>($2, $6, ast::SubprogArgList(), std::move($7), @$);
                }
                ;

subprog_args:
                subprog_args "," subprog_arg { $$ = std::move($1); $$.push_back($3); }
        |       subprog_arg                  { $$ = ast::SubprogArgList{$1}; }
                ;

subprog_arg:
                VAR ":" type { $$ = driver.ctx.make_node<ast::SubprogArg>($1, $3, @$); }
                ;

macro:
                MACRO IDENT "(" macro_args ")" block_expr { $$ = driver.ctx.make_node<ast::Macro>($2, std::move($4), $6, @$); }
        |       MACRO IDENT "(" macro_args ")" bare_block { $$ = driver.ctx.make_node<ast::Macro>($2, std::move($4), $6, @$); }

macro_args:
                macro_args "," map { $$ = std::move($1); $$.push_back($3); }
        |       macro_args "," var { $$ = std::move($1); $$.push_back($3); }
        |       map                { $$ = ast::ExpressionList{$1}; }
        |       var                { $$ = ast::ExpressionList{$1}; }
        |       %empty             { $$ = ast::ExpressionList{}; }
                ;

root_stmts:
                root_stmts root_stmt { $$ = std::move($1); $$.push_back($2); }
        |       %empty               { $$ = ast::RootStatements{}; }

root_stmt:
                macro         { $$ = $1; }
        |       map_decl_stmt { $$ = $1; }
        |       subprog       { $$ = $1; }
        |       probe         { $$ = $1; }
                ;

probe:
                attach_points pred block
                {
                  $$ = driver.ctx.make_node<ast::Probe>(std::move($1), $2, driver.ctx.make_node<ast::Block>(std::move($3), @3), @$);
                }
                ;

attach_points:
                attach_points "," attach_point { $$ = std::move($1); $$.push_back($3); }
        |       attach_point                   { $$ = ast::AttachPointList{$1}; }
                ;

attach_point:
                attach_point_def                { $$ = driver.ctx.make_node<ast::AttachPoint>($1, false, @$); }
                ;

attach_point_def:
                attach_point_def ident    { $$ = $1 + $2; }
                // Since we're double quoting the STRING for the benefit of the
                // AttachPointParser, we have to make sure we re-escape any double
                // quotes. Note that this is a general escape hatch for many cases,
                // since we can't handle the general parsing and unparsing of e.g.
                // integer types that use `_` separators, or exponential notation,
                // or hex vs. non-hex representation etc.
        |       attach_point_def STRING       { $$ = $1 + "\"" + std::regex_replace($2, std::regex("\""), "\\\"") + "\""; }
        |       attach_point_def UNSIGNED_INT { $$ = $1 + std::to_string($2); }
        |       attach_point_def PATH         { $$ = $1 + $2; }
        |       attach_point_def COLON        { $$ = $1 + ":"; }
        |       attach_point_def DOT          { $$ = $1 + "."; }
        |       attach_point_def PLUS         { $$ = $1 + "+"; }
        |       attach_point_def MUL          { $$ = $1 + "*"; }
        |       attach_point_def LBRACKET     { $$ = $1 + "["; }
        |       attach_point_def RBRACKET     { $$ = $1 + "]"; }
        |       attach_point_def param
                {
                  // "Un-parse" the positional parameter back into text so
                  // we can give it to the AttachPointParser. This is kind of
                  // a hack but there doesn't look to be any other way.
                  $$ = $1 + "$" + std::to_string($2->n);
                }
        |       %empty                    { $$ = ""; }
                ;

pred:
                DIV expr ENDPRED { $$ = driver.ctx.make_node<ast::Predicate>($2, @$); }
        |        %empty           { $$ = nullptr; }
                ;


param:
                PARAM {
                        try {
                          long n = std::stol($1.substr(1, $1.size()-1));
                          if (n == 0) throw std::exception();
                          $$ = driver.ctx.make_node<ast::PositionalParameter>(n, @$);
                        } catch (std::exception const& e) {
                          error(@1, "param " + $1 + " is out of integer range [1, " +
                                std::to_string(std::numeric_limits<long>::max()) + "]");
                          YYERROR;
                        }
                      }
                ;

param_count:
                PARAMCOUNT { $$ = driver.ctx.make_node<ast::PositionalParameterCount>(@$); }
                ;

/*
 * The last statement in a block does not require a trailing semicolon.
 */
block:
                "{" stmt_list "}"                   { $$ = std::move($2); }
        |       "{" stmt_list expr_stmt "}"         { $$ = std::move($2); $$.push_back($3); }
                ;

stmt_list:
                stmt_list expr_stmt ";"     { $$ = std::move($1); $$.push_back($2); }
        |       stmt_list block_stmt        { $$ = std::move($1); $$.push_back($2); }
        |       stmt_list var_decl_stmt ";" { $$ = std::move($1); $$.push_back($2); }
        |       %empty                      { $$ = ast::StatementList{}; }
                ;

block_stmt:
                loop_stmt    { $$ = $1; }
        |       if_stmt      { $$ = $1; }
        |       for_stmt     { $$ = $1; }
        |       bare_block   { $$ = $1; }
                ;

bare_block:
                "{" stmt_list "}"  { $$ = driver.ctx.make_node<ast::Block>(std::move($2), @2); }

expr_stmt:
                expr               { $$ = driver.ctx.make_node<ast::ExprStatement>($1, @1); }
        |       jump_stmt          { $$ = $1; }
/*
 * quirk. Assignment is not an expression but the AssignMapStatement makes it difficult
 * this avoids a r/r conflict
 */
        |       assign_stmt        { $$ = $1; }
                ;

jump_stmt:
                BREAK       { $$ = driver.ctx.make_node<ast::Jump>(ast::JumpType::BREAK, @$); }
        |       CONTINUE    { $$ = driver.ctx.make_node<ast::Jump>(ast::JumpType::CONTINUE, @$); }
        |       RETURN      { $$ = driver.ctx.make_node<ast::Jump>(ast::JumpType::RETURN, @$); }
        |       RETURN expr { $$ = driver.ctx.make_node<ast::Jump>(ast::JumpType::RETURN, $2, @$); }
                ;

loop_stmt:
                UNROLL "(" expr ")" block { $$ = driver.ctx.make_node<ast::Unroll>($3, driver.ctx.make_node<ast::Block>(std::move($5), @5), @1 + @4); }
        |       WHILE  "(" expr ")" block { $$ = driver.ctx.make_node<ast::While>($3, driver.ctx.make_node<ast::Block>(std::move($5), @5), @1); }
                ;

for_stmt:
                FOR "(" var ":" map ")" block        { $$ = driver.ctx.make_node<ast::For>($3, $5, std::move($7), @1); }
        |       FOR "(" var ":" range ")" block      { $$ = driver.ctx.make_node<ast::For>($3, $5, std::move($7), @1); }
                ;

range:
                postfix_expr DOT DOT postfix_expr { $$ = driver.ctx.make_node<ast::Range>($1, $4, @$); }
                ;

if_stmt:
                IF "(" expr ")" block                  { $$ = driver.ctx.make_node<ast::If>($3, driver.ctx.make_node<ast::Block>(std::move($5), @5), driver.ctx.make_node<ast::Block>(ast::StatementList(), @1), @$); }
        |       IF "(" expr ")" block ELSE block_or_if { $$ = driver.ctx.make_node<ast::If>($3, driver.ctx.make_node<ast::Block>(std::move($5), @5), driver.ctx.make_node<ast::Block>(std::move($7), @7), @$); }
                ;

block_or_if:
                block        { $$ = std::move($1); }
        |       if_stmt      { $$ = ast::StatementList{$1}; }
                ;

assign_stmt:
                tuple_access_expr ASSIGN expr
                {
                  error(@1 + @3, "Tuples are immutable once created. Consider creating a new tuple and assigning it instead.");
                  YYERROR;
                }
        |       map ASSIGN expr           { $$ = driver.ctx.make_node<ast::AssignScalarMapStatement>($1, $3, @$); }
        |       map_expr ASSIGN expr      { $$ = driver.ctx.make_node<ast::AssignMapStatement>($1->map, $1->key, $3, @$); }
        |       var_decl_stmt ASSIGN expr { $$ = driver.ctx.make_node<ast::AssignVarStatement>($1, $3, @$); }
        |       var ASSIGN expr           { $$ = driver.ctx.make_node<ast::AssignVarStatement>($1, $3, @$); }
        |       map compound_op expr
                {
                  auto b = driver.ctx.make_node<ast::Binop>($1, $2, $3, @2);
                  $$ = driver.ctx.make_node<ast::AssignScalarMapStatement>($1, b, @$);
                }
        |       map_expr compound_op expr
                {
                  auto b = driver.ctx.make_node<ast::Binop>($1, $2, $3, @2);
                  $$ = driver.ctx.make_node<ast::AssignMapStatement>($1->map, $1->key, b, @$);
                }
        |       var compound_op expr
                {
                  auto b = driver.ctx.make_node<ast::Binop>($1, $2, $3, @2);
                  $$ = driver.ctx.make_node<ast::AssignVarStatement>($1, b, @$);
                }
        ;

map_decl_stmt:
                LET MAP ASSIGN IDENT LPAREN UNSIGNED_INT RPAREN ";" { $$ = driver.ctx.make_node<ast::MapDeclStatement>($2, $4, $6, @$); }
        ;

var_decl_stmt:
                 LET var {  $$ = driver.ctx.make_node<ast::VarDeclStatement>($2, @$); }
        |        LET var COLON type {  $$ = driver.ctx.make_node<ast::VarDeclStatement>($2, $4, @$); }
        ;

primary_expr:
                UNSIGNED_INT       { $$ = driver.ctx.make_node<ast::Integer>($1, @$); }
        |       STRING             { $$ = driver.ctx.make_node<ast::String>($1, @$); }
        |       BUILTIN            { $$ = driver.ctx.make_node<ast::Builtin>($1, @$); }
        |       LPAREN expr RPAREN { $$ = $2; }
        |       param              { $$ = $1; }
        |       param_count        { $$ = $1; }
        |       var                { $$ = $1; }
        |       map_expr           { $$ = $1; }
        |       "(" vargs "," expr ")"
                {
                  auto &args = $2;
                  args.push_back($4);
                  $$ = driver.ctx.make_node<ast::Tuple>(std::move(args), @$);
                }
        |       map %prec LOW      { $$ = $1; }
        |       IDENT %prec LOW    { $$ = driver.ctx.make_node<ast::Identifier>($1, @$); }
                ;

postfix_expr:
                primary_expr                   { $$ = $1; }
/* pointer  */
        |       postfix_expr DOT external_name { $$ = driver.ctx.make_node<ast::FieldAccess>($1, $3, @2); }
        |       postfix_expr PTR external_name { $$ = driver.ctx.make_node<ast::FieldAccess>(driver.ctx.make_node<ast::Unop>($1, ast::Operator::MUL, false, @2), $3, @$); }
/* tuple  */
        |       tuple_access_expr              { $$ = $1; }
/* array  */
        |       postfix_expr "[" expr "]"      { $$ = driver.ctx.make_node<ast::ArrayAccess>($1, $3, @2 + @4); }
        |       call                           { $$ = $1; }
        |       sizeof_expr                    { $$ = $1; }
        |       offsetof_expr                  { $$ = $1; }
        |       var INCREMENT                  { $$ = driver.ctx.make_node<ast::Unop>($1, ast::Operator::INCREMENT, true, @2); }
        |       var DECREMENT                  { $$ = driver.ctx.make_node<ast::Unop>($1, ast::Operator::DECREMENT, true, @2); }
        |       map      INCREMENT             { $$ = driver.ctx.make_node<ast::Unop>($1, ast::Operator::INCREMENT, true, @2); }
        |       map      DECREMENT             { $$ = driver.ctx.make_node<ast::Unop>($1, ast::Operator::DECREMENT, true, @2); }
        |       map_expr INCREMENT             { $$ = driver.ctx.make_node<ast::Unop>($1, ast::Operator::INCREMENT, true, @2); }
        |       map_expr DECREMENT             { $$ = driver.ctx.make_node<ast::Unop>($1, ast::Operator::DECREMENT, true, @2); }
/* errors */
        |       INCREMENT ident                { error(@1, "The ++ operator must be applied to a map or variable"); YYERROR; }
        |       DECREMENT ident                { error(@1, "The -- operator must be applied to a map or variable"); YYERROR; }
                ;

/* Tuple factored out so we can use it in the tuple field assignment error */
tuple_access_expr:
                postfix_expr DOT UNSIGNED_INT { $$ = driver.ctx.make_node<ast::TupleAccess>($1, $3, @3); }
                ;

block_expr:
                "{" stmt_list expr "}" { $$ = driver.ctx.make_node<ast::BlockExpr>(std::move($2), $3, @$); }
                ;

unary_expr:
                unary_op cast_expr   { $$ = driver.ctx.make_node<ast::Unop>($2, $1, false, @1); }
        |       postfix_expr         { $$ = $1; }
        |       INCREMENT var        { $$ = driver.ctx.make_node<ast::Unop>($2, ast::Operator::INCREMENT, false, @1); }
        |       DECREMENT var        { $$ = driver.ctx.make_node<ast::Unop>($2, ast::Operator::DECREMENT, false, @1); }
        |       INCREMENT map        { $$ = driver.ctx.make_node<ast::Unop>($2, ast::Operator::INCREMENT, false, @1); }
        |       DECREMENT map        { $$ = driver.ctx.make_node<ast::Unop>($2, ast::Operator::DECREMENT, false, @1); }
        |       INCREMENT map_expr   { $$ = driver.ctx.make_node<ast::Unop>($2, ast::Operator::INCREMENT, false, @1); }
        |       DECREMENT map_expr   { $$ = driver.ctx.make_node<ast::Unop>($2, ast::Operator::DECREMENT, false, @1); }
        |       block_expr           { $$ = $1; }
/* errors */
        |       ident DECREMENT      { error(@1, "The -- operator must be applied to a map or variable"); YYERROR; }
        |       ident INCREMENT      { error(@1, "The ++ operator must be applied to a map or variable"); YYERROR; }
                ;

unary_op:
                MUL    { $$ = ast::Operator::MUL; }
        |       BNOT   { $$ = ast::Operator::BNOT; }
        |       LNOT   { $$ = ast::Operator::LNOT; }
        |       MINUS  { $$ = ast::Operator::MINUS; }
                ;

expr:
                conditional_expr    { $$ = $1; }
                ;

conditional_expr:
                logical_or_expr                                  { $$ = $1; }
        |       logical_or_expr QUES expr COLON conditional_expr { $$ = driver.ctx.make_node<ast::Ternary>($1, $3, $5, @$); }
                ;

logical_or_expr:
                logical_and_expr                     { $$ = $1; }
        |       logical_or_expr LOR logical_and_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::LOR, $3, @2); }
                ;

logical_and_expr:
                or_expr                       { $$ = $1; }
        |       logical_and_expr LAND or_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::LAND, $3, @2); }
                ;

or_expr:
                xor_expr             { $$ = $1; }
        |       or_expr BOR xor_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::BOR, $3, @2); }
                ;

xor_expr:
                and_expr               { $$ = $1; }
        |       xor_expr BXOR and_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::BXOR, $3, @2); }
                ;


and_expr:
                equality_expr               { $$ = $1; }
        |       and_expr BAND equality_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::BAND, $3, @2); }
                ;

equality_expr:
                relational_expr                  { $$ = $1; }
        |       equality_expr EQ relational_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::EQ, $3, @2); }
        |       equality_expr NE relational_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::NE, $3, @2); }
                ;

relational_expr:
                shift_expr                    { $$ = $1; }
        |       relational_expr LE shift_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::LE, $3, @2); }
        |       relational_expr GE shift_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::GE, $3, @2); }
        |       relational_expr LT shift_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::LT, $3, @2); }
        |       relational_expr GT shift_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::GT, $3, @2); }
                ;

shift_expr:
                addi_expr                  { $$ = $1; }
        |       shift_expr LEFT addi_expr  { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::LEFT, $3, @2); }
        |       shift_expr RIGHT addi_expr { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::RIGHT, $3, @2); }
                ;

muli_expr:
                cast_expr                  { $$ = $1; }
        |       muli_expr MUL cast_expr    { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::MUL, $3, @2); }
        |       muli_expr DIV cast_expr    { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::DIV, $3, @2); }
        |       muli_expr MOD cast_expr    { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::MOD, $3, @2); }
                ;

addi_expr:
                muli_expr                  { $$ = $1; }
        |       addi_expr PLUS muli_expr   { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::PLUS, $3, @2); }
        |       addi_expr MINUS muli_expr  { $$ = driver.ctx.make_node<ast::Binop>($1, ast::Operator::MINUS, $3, @2); }
                ;

cast_expr:
                unary_expr                                  { $$ = $1; }
        |       LPAREN type RPAREN cast_expr                { $$ = driver.ctx.make_node<ast::Cast>($2, $4, @1 + @3); }
/* workaround for typedef types, see https://github.com/bpftrace/bpftrace/pull/2560#issuecomment-1521783935 */
        |       LPAREN IDENT RPAREN cast_expr               { $$ = driver.ctx.make_node<ast::Cast>(ast::ident_to_record($2, 0), $4, @1 + @3); }
        |       LPAREN IDENT "*" RPAREN cast_expr           { $$ = driver.ctx.make_node<ast::Cast>(ast::ident_to_record($2, 1), $5, @1 + @4); }
        |       LPAREN IDENT "*" "*" RPAREN cast_expr       { $$ = driver.ctx.make_node<ast::Cast>(ast::ident_to_record($2, 2), $6, @1 + @5); }
                ;

sizeof_expr:
                SIZEOF "(" type ")"                         { $$ = driver.ctx.make_node<ast::Sizeof>($3, @$); }
        |       SIZEOF "(" expr ")"                         { $$ = driver.ctx.make_node<ast::Sizeof>($3, @$); }
                ;

offsetof_expr:
                OFFSETOF "(" struct_type "," struct_field ")"      { $$ = driver.ctx.make_node<ast::Offsetof>($3, $5, @$); }
                /* For example: offsetof(*curtask, comm) */
        |       OFFSETOF "(" expr "," struct_field ")"             { $$ = driver.ctx.make_node<ast::Offsetof>($3, $5, @$); }
                ;

keyword:
                BREAK         { $$ = $1; }
        |       CONFIG        { $$ = $1; }
        |       CONTINUE      { $$ = $1; }
        |       ELSE          { $$ = $1; }
        |       FOR           { $$ = $1; }
        |       IF            { $$ = $1; }
        |       LET           { $$ = $1; }
        |       OFFSETOF      { $$ = $1; }
        |       RETURN        { $$ = $1; }
        |       SIZEOF        { $$ = $1; }
        |       UNROLL        { $$ = $1; }
        |       WHILE         { $$ = $1; }
        |       SUBPROG       { $$ = $1; }
        ;

ident:
                IDENT         { $$ = $1; }
        |       BUILTIN       { $$ = $1; }
        |       BUILTIN_TYPE  { $$ = $1; }
        |       SIZED_TYPE    { $$ = $1; }
                ;

struct_field:
                external_name                       { $$.push_back($1); }
        |       struct_field DOT external_name      { $$ = std::move($1); $$.push_back($3); }
        ;

external_name:
                keyword       { $$ = $1; }
        |       ident         { $$ = $1; }
        ;

call:
                IDENT "(" ")"                 { $$ = driver.ctx.make_node<ast::Call>($1, @$); }
        |       BUILTIN "(" ")"               { $$ = driver.ctx.make_node<ast::Call>($1, @$); }
        |       IDENT "(" vargs ")"           { $$ = driver.ctx.make_node<ast::Call>($1, std::move($3), @$); }
        |       BUILTIN "(" vargs ")"         { $$ = driver.ctx.make_node<ast::Call>($1, std::move($3), @$); }
                ;

map:
                MAP { $$ = driver.ctx.make_node<ast::Map>($1, @$); }

map_expr:
                map "[" vargs "]" {
                        if ($3.size() > 1) {
                          auto t = driver.ctx.make_node<ast::Tuple>(std::move($3), @$);
                          $$ = driver.ctx.make_node<ast::MapAccess>($1, t, @$);
                        } else {
                          $$ = driver.ctx.make_node<ast::MapAccess>($1, $3.back(), @$);
                        }
                }
                ;

var:
                VAR { $$ = driver.ctx.make_node<ast::Variable>($1, @$); }
                ;

vargs:
                vargs "," expr { $$ = std::move($1); $$.push_back($3); }
        |       expr           { $$ = ast::ExpressionList{$1}; }
                ;

compound_op:
                LEFTASSIGN   { $$ = ast::Operator::LEFT; }
        |       BANDASSIGN   { $$ = ast::Operator::BAND; }
        |       BORASSIGN    { $$ = ast::Operator::BOR; }
        |       BXORASSIGN   { $$ = ast::Operator::BXOR; }
        |       DIVASSIGN    { $$ = ast::Operator::DIV; }
        |       MINUSASSIGN  { $$ = ast::Operator::MINUS; }
        |       MODASSIGN    { $$ = ast::Operator::MOD; }
        |       MULASSIGN    { $$ = ast::Operator::MUL; }
        |       PLUSASSIGN   { $$ = ast::Operator::PLUS; }
        |       RIGHTASSIGN  { $$ = ast::Operator::RIGHT; }
                ;

%%

void bpftrace::Parser::error(const location &l, const std::string &m)
{
  driver.error(l, m);
}
