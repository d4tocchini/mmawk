
/********************************************
parse.y
copyright 1991-94, 2014 Michael D. Brennan

This is a source file for mawk, an implementation of
the AWK programming language.

Mawk is distributed without warranty under the terms of
the GNU General Public License, version 3, 2007.

If you import elements of this code into another product, you agree to
not name that product mawk.
********************************************/

/* make parser reentrant */
%define api.pure full

%{
#include <stdio.h>
#include "mawk.h"
#include "table.h"
#include "code.h"
#include "types_string.h"
#include "bi_funct.h"
#include "bi_vars.h"
#include "field.h"
#include "files.h"
#include "scan.h"
#include "printf.h"

#define  YYMAXDEPTH	200

extern void     eat_nl(YYSTYPE *yylval) ;
static void     resize_fblock(FBLOCK *) ;
static void     code_array(SYMTAB *) ;
static void     code_call_id(CA_REC *, SYMTAB *) ;
static void     field_A2I(void) ;
static void     check_var(SYMTAB *) ;
static void     check_array(SYMTAB *) ;
static void     RE_as_arg(void) ;
       int      REempty(PTR) ;
static int      scope ;
static FBLOCK * active_funct ;
      /* when scope is SCOPE_FUNCT  */

#define  code_address(x)            if ( is_local(x) ) \
                                        code2op(L_PUSHA, (x)->offset) ;\
                                    else \
                                        code2(_PUSHA, (x)->stval.cp)

#define  CDP(x)                     (code_base+(x))
/* WARNING: These CDP() calculations become invalid after calls
   that might change code_base.  Which are:  code2(), code2op(),
   code_jmp() and code_pop().
*/

/* this nonsense caters to MSDOS large model */
#define  CODE_FE_PUSHA()            code_ptr->ptr = (PTR) 0 ; \
                                    code1(FE_PUSHA)


/* moves the active_code from MAIN to a BEGIN or END */

#define CODE_OPEN_BEGIN             _code_open_BEGIN(&scope)
#define CODE_OPEN_END               _code_open_END(&scope)
#define CODE_CLOSE_ACTIVE           _code_close_active(&scope)
#define CODE_CLOSE_BEGIN            _code_close_BEGIN(&scope)
#define CODE_CLOSE_END              _code_close_END(&scope)
#define CODE_CLOSE_ACTIVE           _code_close_active(&scope)
#define CODE_NOT_SCOPE(SCOPE, MSG)  if ( scope != SCOPE ) \
                                        compile_error("MSG") ;

static void
_code_open_BEGIN( int * scope ) {
    *scope = SCOPE_BEGIN ;
    *main_code_p = active_code;
    if ( !begin_code_p )
        begin_code_p = code_create_block();
    active_code = *begin_code_p;
}

static void
_code_open_END( int * scope ) {
    *scope = SCOPE_END ;
    *main_code_p = active_code;
    if ( !end_code_p )
        end_code_p = code_create_block();
    active_code = *end_code_p;
}

static inline void
__code_close_active( void ) {
    active_code = *main_code_p ;
    active_funct = (FBLOCK*) 0 ;
}

static void
_code_close_BEGIN(
    int * scope
    // CODEBLOCK * active_code_p
) {
    // *begin_code_p = *active_code_p ;
    *begin_code_p = active_code ;
	__code_close_active();
    *scope = SCOPE_MAIN ;
}

static void
_code_close_END(
    int * scope
    // CODEBLOCK * active_code_p
) {
    // *end_code_p = *active_code_p ;
    *end_code_p = active_code ;
	__code_close_active();
    *scope = SCOPE_MAIN ;
}

static void
_code_close_FUNCT(
    int * scope
) {
	__code_close_active();
    *scope = SCOPE_MAIN ;
}

/* reset the active_code back to the MAIN block */
static void
_code_close_active( int * scope ) // switch_code_to_main(void)
{
    switch (*scope) {
        case SCOPE_MAIN :
            __code_close_active();
            break ;
        case SCOPE_BEGIN :
	        _code_close_BEGIN(scope);
	        break ;
        case SCOPE_END :
	        _code_close_END(scope);
	        break ;
        case SCOPE_FUNCT :
            _code_close_FUNCT(scope);
            break ;
    }
//         case SCOPE_FUNCT :
// 	        active_code = *main_code_p ;
// 	        break ;
//         case SCOPE_MAIN :
// 	        break ;
//    }
//    active_funct = (FBLOCK*) 0 ;
//    scope = SCOPE_MAIN ;
}

%}

%union {
    CELL     *      cp          ;
    SYMTAB   *      stp         ;
    int             start       ; /* code starting address as offset from code_base */
    PF_CP           fp          ; /* ptr to a (print/printf) or (sub/gsub) function */
    BI_REC   *      bip         ; /* ptr to info about a builtin */
    FBLOCK   *      fbp         ; /* ptr to a function block */
    ARG2_REC *      arg2p       ;
    CA_REC   *      ca_p        ;
    int             ival        ;
    PTR             ptr         ;
}

/*  two tokens to help with errors */
%token              UNEXPECTED   /* unexpected character */
%token              BAD_DECIMAL
        
%token              NL
%token              SEMI_COLON
%token              LBRACE  RBRACE
%token              LBOX     RBOX
%token              COMMA
%token  <ival>      IO_OUT    /* > or output pipe */
    
%right              ASSIGN  ADD_ASG SUB_ASG MUL_ASG DIV_ASG MOD_ASG POW_ASG
%right              QMARK COLON
%left               OR
%left               AND
%left               IN
%left   <ival>      MATCH   /* ~  or !~ */
%left               EQ  NEQ  LT LTE  GT  GTE
%left               CAT
%left               GETLINE
%left               PLUS      MINUS
%left               MUL      DIV    MOD
%left               NOT   UMINUS
%nonassoc           IO_IN PIPE
%right              POW
%left   <ival>      INC_or_DEC
%left               DOLLAR  FIELD   /* last to remove a SR conflict with getline */
%right              LPAREN  RPAREN  /* removes some SR conflicts */

%token  <ptr>       DOUBLE    STRING_     RE
%token  <stp>       ID        D_ID
%token  <fbp>       FUNCT_ID
%token  <bip>       BUILTIN   LENGTH
%token  <cp>        FIELD
    
%token              PRINT PRINTF SPLIT MATCH_FUNC SUB GSUB SPRINTF
/* keywords */
%token              DO WHILE FOR BREAK CONTINUE IF ELSE  IN
%token              DELETE  BEGIN  END  EXIT NEXT NEXTFILE RETURN  FUNCTION

%type   <start>     block            block_or_separator
%type   <start>     stmt_list   statement           mark    pmark
%type   <ival>      pr_args          printf_args
%type   <arg2p>     arg2
%type   <start>     builtin
%type   <start>     getline_file
%type   <start>     lvalue           field               fvalue
%type   <start>     expr             cat_expr            p_expr
%type   <start>     while_front      if_front
%type   <start>     for1 for2
%type   <start>     array_loop_front
%type   <start>     return_stmt
%type   <start>     split_front      re_arg sub_back
%type   <ival>      arglist args
%type   <fp>        sub_or_gsub
%type   <fbp>       funct_start      funct_head
%type   <ca_p>      call_args        ca_front            ca_back
%type   <ival>      f_arglist        f_args
%type   <ptr>       string_comma

%%
/*  productions  */
start               :   program

                    |   {                                           CODE_OPEN_BEGIN;
                        } // TODO: refactor midrule issues? https://www.gnu.org/software/bison/manual/bison.html#Midrule-Actions
                        stmt_list                               {   CODE_CLOSE_BEGIN;
                                                                }
                    ;
program             :   program_block
                    |   program  program_block
                    ;
program_block       :   PA_block   /* pattern-action */
                    |   function_def
                    |   outside_error  block
                    ;
PA_block            :   block                                   {   /* this do nothing removes a vacuous warning from Bison */
                                                                }
                    |   BEGIN       {                               CODE_OPEN_BEGIN;
                                    }
                                    block                       {   CODE_CLOSE_BEGIN;
                                                                }
                    |   END         {                               CODE_OPEN_END;
                                    }
                                    block                       {   CODE_CLOSE_END;
                                                                }
                    /*  this works just like an if statement */
                    |   expr        {                               code_jmp(_JZ, (INST*)0);
                                    }
                                    block_or_separator          {   patch_jmp( code_ptr ) ;
                                                                }
                    /*  range pattern, see comment in execute.c near _RANGE */
                    |   expr COMMA {                                INST *p1 = CDP($1) ;
                                                                    int len ;

                                                                    code_push(p1, code_ptr - p1, scope, active_funct) ;
                                                                    code_ptr = p1 ;

                                                                    code2op(_RANGE, 1) ;
                                                                    code_ptr += 3 ;
                                                                    len = code_pop(code_ptr) ;
                                                                    code_ptr += len ;
                                                                    code1(_STOP) ;
                                                                    p1 = CDP($1) ;
                                                                    p1[2].op = code_ptr - (p1+1) ;
                                    }
                                    expr    {                       code1(_STOP);
                                            }
                                            block_or_separator  {   INST *p1 = CDP($1) ;
                                                                    p1[3].op = CDP($6) - (p1+1) ;
                                                                    p1[4].op = code_ptr - (p1+1) ;
                                                                }
                    ;

block               :   LBRACE   stmt_list  RBRACE              {   $$ = $2;
                                                                }
                    |   LBRACE   error  RBRACE                  {   $$ = code_offset ; /* does nothing won't be executed */
                                                                    print_flag = getline_flag = paren_cnt = 0 ;
                                                                    yyerrok ;
                                                                }
                    ;
block_or_separator  :   block
                    |   separator                               {   /* default print action */
                                                                    $$ = code_offset ;
                                                                    code1(_PUSHINT) ; code1(0) ;
                                                                    code2(_PRINT, bi_print) ;
                                                                }

stmt_list           :   statement           
                    |   stmt_list   statement           
                    ;           
statement           :   block           
                    |   expr        separator                   {   code1(_POP) ;
                                                                }
                    |   /*empty*/   separator                   {   $$ = code_offset ;
                                                                }
                    |   error       separator                   {   $$ = code_offset ;
                                                                    print_flag = getline_flag = 0 ;
                                                                    paren_cnt = 0 ;
                                                                    yyerrok ;
                                                                }
                    |   BREAK       separator                   {   $$ = code_offset ;
                                                                    BC_insert('B', code_ptr+1) ;
                                                                    code2(_JMP, 0) ; /* don't use code_jmp ! */
                                                                }
                    |   CONTINUE    separator                   {   $$ = code_offset ;
                                                                    BC_insert('C', code_ptr+1) ;
                                                                    code2(_JMP, 0) ;
                                                                }
                    |   return_stmt                             {   CODE_NOT_SCOPE( SCOPE_FUNCT, "return outside function body") ;
                                                                }
                    |   NEXT        separator                   {   CODE_NOT_SCOPE( SCOPE_MAIN, "improper use of next") ;
                                                                    $$ = code_offset ;
                                                                    code1(_NEXT) ;
                                                                }
                    |   NEXTFILE    separator                   {   CODE_NOT_SCOPE( SCOPE_MAIN, "improper use of nextfile" ) ;
                                                                    $$ = code_offset ;
                                                                    code1(_NEXTFILE) ;
                                                                }
                    ;
            
separator           :   NL          
                    |   SEMI_COLON          
                    ;
            
expr                :   cat_expr            
                    |   lvalue      ASSIGN   expr               {   code1(_ASSIGN)  ;
                                                                }
                    |   lvalue      ADD_ASG  expr               {   code1(_ADD_ASG) ; 
                                                                }
                    |   lvalue      SUB_ASG  expr               {   code1(_SUB_ASG) ; 
                                                                }
                    |   lvalue      MUL_ASG  expr               {   code1(_MUL_ASG) ; 
                                                                }
                    |   lvalue      DIV_ASG  expr               {   code1(_DIV_ASG) ; 
                                                                }
                    |   lvalue      MOD_ASG  expr               {   code1(_MOD_ASG) ; 
                                                                }
                    |   lvalue      POW_ASG  expr               {   code1(_POW_ASG) ; 
                                                                }
                    |   expr        EQ       expr               {   code1(_EQ)  ;
                                                                }
                    |   expr        NEQ      expr               {   code1(_NEQ) ; 
                                                                }
                    |   expr        LT       expr               {   code1(_LT)  ; 
                                                                }
                    |   expr        LTE      expr               {   code1(_LTE) ; 
                                                                }
                    |   expr        GT       expr               {   code1(_GT)  ; 
                                                                }
                    |   expr        GTE      expr               {   code1(_GTE) ; 
                                                                }
                    |   expr        MATCH    expr               {   INST *p3 = CDP($3) ;
                                                                    if ( p3 == code_ptr - 2 ) {
                                                                        if ( p3->op == _MATCH0 )
                                                                            p3->op = _MATCH1 ;
                                                                        else /* check for string */
                                                                            if ( p3->op == _PUSHS ) {
                                                                                CELL *cp = ZMALLOC(CELL) ;
                                                                                cp->type = C_STRING ;
                                                                                cp->ptr = p3[1].ptr ;
                                                                                cast_to_RE(cp) ;
                                                                                code_ptr -= 2 ;
                                                                                code2(_MATCH1, cp->ptr) ;
                                                                                ZFREE(cp) ;
                                                                            }
                                                                            else
                                                                                code1(_MATCH2) ;
                                                                    }
                                                                    else
                                                                        code1(_MATCH2) ;
            
                                                                    if ( !$2 )
                                                                        code1(_NOT) ;
                                                                }
    
                    /* short circuit boolean evaluation */  
                    |   expr  OR    {                               code1(_TEST) ;
                                                                    code_jmp(_LJNZ, (INST*)0) ;
                                    }
                                    expr                        {   code1(_TEST) ;
                                                                    patch_jmp(code_ptr) ;
                                                                }

                    |   expr AND                                {   code1(_TEST) ;
		                                                            code_jmp(_LJZ, (INST*)0) ;
	                                                            }
                        expr                                    {   code1(_TEST) ;
                                                                    patch_jmp(code_ptr) ;
                                                                }
                    |   expr QMARK                              {   code_jmp(_JZ, (INST*)0) ;
                                                                }
                        expr COLON                              {   code_jmp(_JMP, (INST*)0) ;
                                                                }
                        expr                                    {   patch_jmp(code_ptr) ;
                                                                    patch_jmp(CDP($7)) ;
                                                                }
                    ;
cat_expr            :   p_expr            %prec  CAT
                    |   cat_expr  p_expr  %prec  CAT            {   code1(_CAT) ;
                                                                }
                    ;
p_expr              :   DOUBLE                                  {   $$ = code_offset ;
                                                                    code2(_PUSHD, $1) ;
                                                                }
                    |   STRING_                                 {   $$ = code_offset ;
                                                                    code2(_PUSHS, $1) ;
                                                                }
                    |   ID      %prec   AND                     {   /* anything less than IN */
                                                                    check_var($1) ;
                                                                    $$ = code_offset ;
                                                                    if ( is_local($1) ) {
                                                                        code2op(L_PUSHI, $1->offset) ;
                                                                    }
                                                                    else
                                                                        code2(_PUSHI, $1->stval.cp) ;
                                                                }
                    |   LPAREN  expr    RPAREN                  {   $$ = $2 ;
                                                                }
                    ;
p_expr              :   RE                                      {   $$ = code_offset ;
                                                                    code2(_MATCH0, $1) ;
                                                                }
                    ;
p_expr              :   p_expr  PLUS    p_expr                  {   code1(_ADD) ;
                                            }
                    |   p_expr  MINUS   p_expr                  {   code1(_SUB) ; 
                                                                }
                    |   p_expr  MUL     p_expr                  {   code1(_MUL) ; 
                                                                }
                    |   p_expr  DIV     p_expr                  {   code1(_DIV) ; 
                                                                }
                    |   p_expr  MOD     p_expr                  {   code1(_MOD) ; 
                                                                }
                    |   p_expr  POW     p_expr                  {   code1(_POW) ; 
                                                                }
                    |   NOT     p_expr                          {   $$ = $2 ;
                                                                    code1(_NOT) ;
                                                                }
                    |   PLUS  p_expr  %prec  UMINUS             {   $$ = $2 ;
                                                                    code1(_UPLUS) ;
                                                                }
                    |   MINUS  p_expr  %prec  UMINUS            {   $$ = $2 ;
                                                                    code1(_UMINUS) ;
                                                                }
                    |   builtin
                    ;
p_expr              :   ID  INC_or_DEC                          {   check_var($1) ;
                                                                    $$ = code_offset ;
                                                                    code_address($1) ;
                                                                    if ( $2 == '+' )
                                                                        code1(_POST_INC) ;
                                                                    else
                                                                        code1(_POST_DEC) ;
                                                                }
                    |   INC_or_DEC  lvalue                      {   $$ = $2 ;
                                                                    if ( $1 == '+' )
                                                                        code1(_PRE_INC) ;
                                                                    else
                                                                        code1(_PRE_DEC) ;
                                                                }
                    ;
p_expr              :   field  INC_or_DEC                       {   if ($2 == '+' )
                                                                        code1(F_POST_INC ) ;
                                                                    else
                                                                        code1(F_POST_DEC) ;
                                                                }
                    |   INC_or_DEC  field                       {   $$ = $2 ;
                                                                    if ( $1 == '+' )
                                                                        code1(F_PRE_INC) ;
                                                                    else
                                                                        code1( F_PRE_DEC) ;
                                                                }
                    ;
lvalue              :   ID                                      {   $$ = code_offset ;
                                                                    check_var($1) ;
                                                                    code_address($1) ;
                                                                }
                    ;
arglist             :   /* empty */                             {   $$ = 0 ;
                                                                }
                    |   args
                    ;
args                :   expr    %prec  LPAREN                   {   $$ = 1 ;
                                                                }
                    |   args    COMMA  expr                     {   $$ = $1 + 1 ;
                                                                }
                    ;
builtin             :   BUILTIN  mark  LPAREN  arglist  RPAREN  {   BI_REC *p = $1 ;
                                                                    $$ = $2 ;
                                                                    if ( (int)p->min_args > $4 || (int)p->max_args < $4 )
                                                                        compile_error(
                                                                            "wrong number of arguments in call to %s" ,
                                                                            p->name
                                                                        ) ;
                                                                    /* variable args */
                                                                    if ( p->min_args != p->max_args ) {
                                                                        code1(_PUSHINT) ;
                                                                        code1($4) ;
                                                                    }
                                                                    code2(_BUILTIN , p->fp) ;
                                                                }
                    ;
/*
one shift/reduce conflict
    SPRINTF mark LPAREN STRING_  .  COMMA
    reduce STRING_ --> expr   or   shift COMMA
    shift wins and is what we want
*/
builtin             :   SPRINTF  mark  LPAREN  RPAREN           {   $$ = $2 ;
                                                                    compile_error("no argments in call to sprintf()") ;
                                                                }
	                |   SPRINTF  mark  LPAREN  string_comma  args  RPAREN
	                                                            {   /* the usual case */
                                                                    const Form* form = (Form*) $4 ;
                                                                    $$ = $2 ;
                                                                    if (form && form->num_args != $5) {
                                                                        compile_error("wrong number of arguments to sprintf, needs %d, has %d",
                                                                            form->num_args+1, $5+1) ;
                                                                        }
                                                                        code2op(_PUSHINT, $5 + 1) ;
                                                                        code2(_BUILTIN, bi_sprintf) ;
                                                                }
	                |   SPRINTF  mark  LPAREN  args  RPAREN     {   $$ = $2 ;
                                                                    code2op(_PUSHINT, $4) ;
                                                                    code2(_BUILTIN, bi_sprintf1) ;
                                                                }
                    ;
string_comma        :   STRING_  COMMA                          {   STRING* str = (STRING*) $1 ;
                                                                    const Form* form = parse_form(str) ;
                                                                    free_STRING(str) ;
                                                                    $$ = (PTR) form ;
                                                                    code2(PUSHFM, form) ;
                                                                }
	                ;
             ;
                    //  empty production to store the code_ptr
mark                :   /* empty */                             {   $$ = code_offset ;
                                                                }
//  print_statement
statement           :   PRINT pmark pr_args pr_direction separator
                                                                {   code2(_PRINT, bi_print) ;
                                                                    print_flag = 0 ;
                                                                    $$ = $2 ;
                                                                }
                    ;
/* printf statment
   - first case is same as print statment
   - second case is first arg is const string no braces, at least one more arg
   - third  case is first arg is const string inside braces, at least one more arg
   last two cases are the usual
*/
statement           :   PRINTF pmark pr_args pr_direction separator
                                                                {   code2(_PRINT, bi_printf1) ;
                                                                    print_flag = 0 ;
                                                                    $$ = $2 ;
                                                                    if ($3 == 0) {
                                                                        compile_error("no arguments in call to printf") ;
                                                                    }
                                                                }
	                |   PRINTF pmark string_comma printf_args pr_direction separator
                                                                {   const Form* form = (Form*) $3 ;
                                                                    if (form && form->num_args != $4) {
                                                                        compile_error(
                                                                            "wrong number of arguments to printf, needs %d, has %d",
                                                                            form->num_args+1, $4+1
                                                                        ) ;
                                                                    }
                                                                    code2(_PRINT, bi_printf) ;
                                                                    print_flag = 0 ;
                                                                    $$ = $2 ;
                                                                }
	                |   PRINTF pmark LPAREN string_comma printf_args RPAREN pr_direction separator
                                                                {   const Form* form = (Form*) $4 ;
                                                                    if (form && form->num_args != $5) {
                                                                        compile_error(
                                                                            "wrong number of arguments to printf, needs %d, has %d",
                                                                            form->num_args+1, $5+1
                                                                        ) ;
                                                                    }
                                                                    code2(_PRINT, bi_printf) ;
                                                                    print_flag = 0 ;
                                                                    $$ = $2 ;
                                                                }
	                ;
pmark               :   /* empty */                             {   $$ = code_offset ;
	                                                                print_flag = 1 ;
	                                                            }
	                ;
printf_args         :   args                                    {   code2op(_PUSHINT, $1 + 1) ;
	                                                            }
	                ;
pr_args             :   arglist                                 {   code2op(_PUSHINT, $1) ;
                                                                }
                    |   LPAREN  arg2 RPAREN                     {   $$ = $2->cnt ;
                                                                    zfree($2,sizeof(ARG2_REC)) ;
                                                                    code2op(_PUSHINT, $$) ;
                                                                }
	                |   LPAREN  RPAREN                          {   $$=0 ;
                                                                    code2op(_PUSHINT, 0) ;
                                                                }
                    ;
arg2                :   expr  COMMA  expr                       {   $$ = (ARG2_REC*) zmalloc(sizeof(ARG2_REC)) ;
                                                                    $$->start = $1 ;
                                                                    $$->cnt = 2 ;
                                                                }
                    |   arg2 COMMA  expr                        {   $$ = $1 ;
                                                                    $$->cnt++ ;
                                                                }
                    ;
pr_direction        :   /* empty */
                    |   IO_OUT  expr                            {   code2op(_PUSHINT, $1) ;
                                                                }
                    ;
/*  IF and IF-ELSE */
if_front            :   IF LPAREN expr RPAREN                   {   $$ = $3 ;
                                                                    EAT_NL_ ;
                                                                    code_jmp(_JZ, (INST*)0) ;
                                                                }
                    ;
/* if_statement */
statement           :   if_front statement                      {   patch_jmp( code_ptr ) ;
                                                                }
                    ;
else                :   ELSE                                    {   EAT_NL_ ;
                                                                    code_jmp(_JMP, (INST*)0) ;
                                                                }
                    ;
/* if_else_statement */
statement           :   if_front statement else statement       {   patch_jmp(code_ptr) ;
		                                                            patch_jmp(CDP($4)) ;
		                                                        }
/*  LOOPS   */
do                  :   DO                                      {   EAT_NL_ ;
                                                                    BC_new() ;
                                                                }
                    ;
/* do_statement */
statement           :   do statement WHILE LPAREN expr RPAREN separator
                                                                {   $$ = $2 ;
                                                                    code_jmp(_JNZ, CDP($2)) ;
                                                                    BC_clear(code_ptr, CDP($5)) ;
                                                                }
                    ;
while_front         :   WHILE LPAREN expr RPAREN                {   EAT_NL_ ;
                                                                    BC_new() ;
                                                                    $$ = $3 ;
                                                                    /* check if const expression */
                                                                    if ( code_ptr - 2 == CDP($3) &&
                                                                    code_ptr[-2].op == _PUSHD &&
                                                                    *(double*)code_ptr[-1].ptr != 0.0
                                                                    )
                                                                        code_ptr -= 2 ;
                                                                    else {
                                                                        INST *p3 = CDP($3) ;
                                                                        code_push(p3, code_ptr-p3, scope, active_funct) ;
                                                                        code_ptr = p3 ;
                                                                        code2(_JMP, (INST*)0) ; /* code2() not code_jmp() */
                                                                    }
                                                                }
                    ;
/* while_statement */
statement           :   while_front  statement                  {   int   saved_offset ;
                                                                    int   len ;
                                                                    INST *p1 = CDP($1) ;
                                                                    INST *p2 = CDP($2) ;
                                                                    if ( p1 != p2 ) {  /* real test in loop */
                                                                        p1[1].op = code_ptr-(p1+1) ;
                                                                        saved_offset = code_offset ;
                                                                        len = code_pop(code_ptr) ;
                                                                        code_ptr += len ;
                                                                        code_jmp(_JNZ, CDP($2)) ;
                                                                        BC_clear(code_ptr, CDP(saved_offset)) ;
                                                                    }
                                                                    else { /* while(1) */
                                                                        code_jmp(_JMP, p1) ;
                                                                        BC_clear(code_ptr, CDP($2)) ;
                                                                    }
                                                                }
                    ;
/* for_statement */
statement           :   for1 for2 for3 statement                {   int cont_offset = code_offset ;
                                                                    unsigned len = code_pop(code_ptr) ;
                                                                    INST *   p2  = CDP($2) ;
                                                                    INST *   p4  = CDP($4) ;
                                                                    code_ptr += len ;
                                                                    if ( p2 != p4 ) {  /* real test in for2 */
                                                                        p4[-1].op = code_ptr - p4 + 1 ;
                                                                        len = code_pop(code_ptr) ;
                                                                        code_ptr += len ;
                                                                        code_jmp(_JNZ, CDP($4)) ;
                                                                    }
                                                                    else /*  for(;;) */
                                                                        code_jmp(_JMP, p4) ;
                                                                    BC_clear(code_ptr, CDP(cont_offset)) ;
                                                                }
                    ;
for1                :   FOR LPAREN  SEMI_COLON                  {   $$ = code_offset ;
                                                                }
                    |   FOR LPAREN  expr  SEMI_COLON            {   $$ = $3 ;
                                                                    code1(_POP) ;
                                                                }
                    ;
for2                :   SEMI_COLON                              {   $$ = code_offset ;
                                                                }
                    |   expr  SEMI_COLON                        {   if ( code_ptr - 2 == CDP($1) &&
                                                                        code_ptr[-2].op == _PUSHD &&
                                                                        * (double*) code_ptr[-1].ptr != 0.0
                                                                    ) {
                                                                        code_ptr -= 2 ;
                                                                    }
                                                                    else {
                                                                        INST *p1 = CDP($1) ;
                                                                        code_push(p1, code_ptr-p1, scope, active_funct) ;
                                                                        code_ptr = p1 ;
                                                                        code2(_JMP, (INST*)0) ;
                                                                    }
                                                                }
                    ;
for3                :   RPAREN                                  {   EAT_NL_ ;
                                                                    BC_new() ;
	                                                                code_push((INST*)0,0, scope, active_funct) ;
	                                                            }
                    |   expr RPAREN                             {   INST *p1 = CDP($1) ;
                                                                    EAT_NL_ ; BC_new() ;
                                                                    code1(_POP) ;
                                                                    code_push(p1, code_ptr - p1, scope, active_funct) ;
                                                                    code_ptr -= code_ptr - p1 ;
                                                                }
                    ;
/* arrays  */
expr                :   expr  IN  ID                            {   check_array($3) ;
                                                                    code_array($3) ;
                                                                    code1(A_TEST) ;
                                                                }
                    |   LPAREN  arg2  RPAREN  IN  ID            {   $$ = $2->start ;
                                                                    code2op(A_CAT, $2->cnt) ;
                                                                    zfree($2, sizeof(ARG2_REC)) ;
                                                                    check_array($5) ;
                                                                    code_array($5) ;
                                                                    code1(A_TEST) ;
                                                                }
                    ;
lvalue              :   ID  mark  LBOX  args  RBOX              {   if ( $4 > 1 ) {
                                                                        code2op(A_CAT, $4) ;
                                                                    }
                                                                    check_array($1) ;
                                                                    if ( is_local($1) ) {
                                                                        code2op(LAE_PUSHA, $1->offset) ;
                                                                    }
                                                                    else
                                                                        code2(AE_PUSHA, $1->stval.array) ;
                                                                    $$ = $2 ;
                                                                }
                    ;

p_expr              :   ID  mark  LBOX  args  RBOX  %prec  AND  {   if ( $4 > 1 ) {
                                                                        code2op(A_CAT, $4) ;
                                                                    }
                                                                    check_array($1) ;
                                                                    if( is_local($1) ) {
                                                                        code2op(LAE_PUSHI, $1->offset) ;
                                                                    }
                                                                    else
                                                                        code2(AE_PUSHI, $1->stval.array) ;
                                                                    $$ = $2 ;
                                                                }
                    |   ID  mark  LBOX  args  RBOX  INC_or_DEC  {   if ( $4 > 1 ) {
                                                                        code2op(A_CAT,$4) ;
                                                                    }
                                                                    check_array($1) ;
                                                                    if ( is_local($1) ) {
                                                                        code2op(LAE_PUSHA, $1->offset) ;
                                                                    }
                                                                    else
                                                                        code2(AE_PUSHA, $1->stval.array) ;
                                                                    if ( $6 == '+' )
                                                                        code1(_POST_INC) ;
                                                                    else
                                                                        code1(_POST_DEC) ;
                                                                    $$ = $2 ;
                                                                }
                    ;
/* delete A[i] or delete A */
statement           :   DELETE  ID  mark  LBOX  args  RBOX  separator
                                                                {   $$ = $3 ;
                                                                    if ( $5 > 1 ) { code2op(A_CAT, $5) ; }
                                                                    check_array($2) ;
                                                                    code_array($2) ;
                                                                    code1(A_DEL) ;
                                                                }
	                |   DELETE  ID  separator                   {   $$ = code_offset ;
                                                                    check_array($2) ;
                                                                    code_array($2) ;
                                                                    code1(DEL_A) ;
                                                                }
                    ;
/*  for ( i in A )  statement */
array_loop_front    :   FOR  LPAREN  ID  IN  ID  RPAREN         {   EAT_NL_ ;
                                                                    BC_new() ;
                                                                    $$ = code_offset ;
                                                                    check_var($3) ;
                                                                    code_address($3) ;
                                                                    check_array($5) ;
                                                                    code_array($5) ;
                                                                    code2(SET_ALOOP, (INST*)0) ;
                                                                }
                    ;
/* array_loop */
statement           :   array_loop_front  statement             {   INST *p2 = CDP($2) ;
                                                                    p2[-1].op = code_ptr - p2 + 1 ;
                                                                    BC_clear( code_ptr+2 , code_ptr) ;
                                                                    code_jmp(ALOOP, p2) ;
                                                                    code1(POP_AL) ;
                                                                }
                    ;
/*  fields
    D_ID is a special token , same as an ID, but yylex()
    only returns it after a '$'.  In essense,
    DOLLAR D_ID is really one token.
*/
field               :   FIELD                                   {   $$ = code_offset ;
                                                                    code2(F_PUSHA, $1) ;
                                                                }
                    |   DOLLAR  D_ID                            {   check_var($2) ;
                                                                    $$ = code_offset ;
                                                                    if ( is_local($2) )
                                                                        code2op(L_PUSHI, $2->offset) ;
                                                                    else
                                                                        code2(_PUSHI, $2->stval.cp) ;
                                                                    CODE_FE_PUSHA() ;
                                                                }
                    |   DOLLAR  D_ID mark  LBOX  args  RBOX     {   if ( $5 > 1 )
                                                                        code2op(A_CAT, $5) ;
                                                                    check_array($2) ;
                                                                    if ( is_local($2) )
                                                                        code2op(LAE_PUSHI, $2->offset) ;
                                                                    else
                                                                        code2(AE_PUSHI, $2->stval.array) ;
                                                                    CODE_FE_PUSHA() ;
                                                                    $$ = $3 ;
                                                                }
                    |   DOLLAR  p_expr                          {   $$ = $2 ;
                                                                    CODE_FE_PUSHA() ;
                                                                }
                    |   LPAREN  field  RPAREN                   {   $$ = $2 ;
                                                                }
                    ;
                    /*  removes field (++|--) sr conflict */
p_expr              :   field  %prec  CAT                       {   field_A2I() ;
                                                                }
                    ;
expr                :   field  ASSIGN   expr                    {   code1(F_ASSIGN)  ; }
                    |   field  ADD_ASG  expr                    {   code1(F_ADD_ASG) ; }
                    |   field  SUB_ASG  expr                    {   code1(F_SUB_ASG) ; }
                    |   field  MUL_ASG  expr                    {   code1(F_MUL_ASG) ; }
                    |   field  DIV_ASG  expr                    {   code1(F_DIV_ASG) ; }
                    |   field  MOD_ASG  expr                    {   code1(F_MOD_ASG) ; }
                    |   field  POW_ASG  expr                    {   code1(F_POW_ASG) ; }
                    ;
/*
split is handled different than a builtin because
it takes an array and optionally a regular expression as args
*/
p_expr              :   split_front  split_back                 {   code2(_BUILTIN, bi_split) ;
                                                                }
                    ;
split_front         :   SPLIT  LPAREN  expr  COMMA  ID          {   $$ = $3 ;
                                                                    check_array($5) ;
                                                                    code_array($5)  ;
                                                                }
                    ;
split_back          :   RPAREN                                  {   code2(_PUSHI, &fs_shadow) ;
                                                                }
                    |   COMMA  expr  RPAREN                     {   if ( CDP($2) == code_ptr - 2 ) {
                                                                        if (code_ptr[-2].op == _MATCH0) {
                                                                            RE_as_arg() ;
			                                                                {
                                                                                /* see if // needs conversion */
                                                                                CELL* cp = (CELL*) code_ptr[-1].ptr ;
                                                                                if (REempty(cp->ptr)) {
                                                                                    cp->type = C_SNULL ;
                                                                                    cp->ptr = 0 ;
                                                                                }
                                                                            }
                                                                        }
                                                                        else {
                                                                            if ( code_ptr[-2].op == _PUSHS ) {
                                                                                CELL *cp = ZMALLOC(CELL) ;
                                                                                cp->type = C_STRING ;
                                                                                cp->ptr = code_ptr[-1].ptr ;
                                                                                cast_for_split(cp) ;
                                                                                code_ptr[-2].op = _PUSHC ;
                                                                                code_ptr[-1].ptr = (PTR) cp ;
                                                                            }
                                                                        }
                                                                    }
                                                                }
                    ;
/*
sprintf -- try to parse form at compile time
                    -   length is now overloaded to return size of an array
                    -   note: first two rules give SR conflict, but S is correct so it's ok
*/
p_expr              :   LENGTH                                  {   $$ = code_offset ;
                                                                    code2(_PUSHI,field) ;
                                                                    code2(_BUILTIN,bi_length) ;
                                                                }
                    |   LENGTH  LPAREN  RPAREN                  {   $$ = code_offset ;
                                                                    code2(_PUSHI,field) ;
                                                                    code2(_BUILTIN,bi_length) ;
                                                                }
                    |   LENGTH  LPAREN  expr  RPAREN            {   $$ = $3 ;
                                                                    code2(_BUILTIN,bi_length) ;
	                                                            }
                    |   LENGTH  LPAREN  ID  RPAREN              {   SYMTAB* stp = $3 ;
                                                                    $$ = code_offset ;
                                                                    switch(stp->type) {
                                                                        case ST_VAR:
                                                                            code2(_PUSHI, stp->stval.cp) ;
                                                                            code2(_BUILTIN, bi_length) ;
                                                                            break ;
                                                                        case ST_ARRAY:
                                                                            code2(A_PUSHA, stp->stval.array) ;
                                                                            code2(_BUILTIN, bi_alength) ;
                                                                            break ;
                                                                        case ST_LOCAL_VAR:
                                                                            code2op(L_PUSHI, stp->offset) ;
                                                                            code2(_BUILTIN, bi_length) ;
                                                                            break ;
                                                                        case ST_LOCAL_ARRAY:
                                                                            code2op(LA_PUSHA, stp->offset) ;
                                                                            code2(_BUILTIN, bi_alength) ;
                                                                            break ;
                                                                        case ST_NONE:
                                                                            /* could go on modified resolve list, but too much work to
                                                                                figure that out.  Will be patched at run time */
                                                                            code2(PI_LOAD, stp) ;
                                                                            code2(_BUILTIN, bi_length) ;
                                                                            break ;
                                                                        case ST_LOCAL_NONE:
                                                                            {   /* ditto, patched at run-time */
                                                                                Local_PI* pi = (Local_PI *)zmalloc(sizeof(Local_PI)) ;
                                                                            pi->fbp = active_funct ;
                                                                            pi->offset = stp->offset ;
                                                                            code2(LPI_LOAD, pi) ;
                                                                            code2(_BUILTIN, bi_length) ;
                                                                            }
                                                                            break ;
                                                                        default:
                                                                            type_error(stp) ;
                                                                            break ;
                                                                    }
                                                                }
                    ;
/*  match(expr, RE) */
p_expr              :   MATCH_FUNC  LPAREN  expr  COMMA  re_arg  RPAREN
                                                                {   $$ = $3 ;
                                                                    code2(_BUILTIN, bi_match) ;
                                                                }
                    ;
re_arg              :   expr                                    {   INST *p1 = CDP($1) ;
                                                                    if ( p1 == code_ptr - 2 ) {
                                                                        if ( p1->op == _MATCH0 )
                                                                            RE_as_arg() ;
                                                                        else
                                                                            if ( p1->op == _PUSHS ) {
                                                                                CELL *cp = ZMALLOC(CELL) ;
                                                                                cp->type = C_STRING ;
                                                                                cp->ptr = p1[1].ptr ;
                                                                                cast_to_RE(cp) ;
                                                                                p1->op = _PUSHC ;
                                                                                p1[1].ptr = (PTR) cp ;
                                                                            }
                                                                    }
                                                                }
/* exit_statement */    
statement           :   EXIT  separator                         {   $$ = code_offset ;
                                                                    code1(_EXIT0) ;
                                                                }
                    |   EXIT  expr  separator                   {   $$ = $2 ;
                                                                    code1(_EXIT) ;
                                                                }
return_stmt         :   RETURN  separator                       {   $$ = code_offset ;
                                                                    code1(_RET0) ;
                                                                }
                    |   RETURN  expr  separator                 {   $$ = $2 ;
                                                                    code1(_RET) ;
                                                                }
/* getline */
p_expr              :   getline  %prec  GETLINE                 {   $$ = code_offset ;
                                                                    code2(F_PUSHA, &field[0]) ;
                                                                    code1(_PUSHINT) ; code1(0) ;
                                                                    code2(_BUILTIN, bi_getline) ;
                                                                    getline_flag = 0 ;
                                                                }
                    |   getline  fvalue  %prec  GETLINE         {   $$ = $2 ;
                                                                    code1(_PUSHINT) ; code1(0) ;
                                                                    code2(_BUILTIN, bi_getline) ;
                                                                    getline_flag = 0 ;
                                                                }
                    |   getline_file  p_expr  %prec  IO_IN      {   code1(_PUSHINT) ;
                                                                    code1(F_IN) ;
                                                                    code2(_BUILTIN, bi_getline) ;
                                                                    /* getline_flag already off in yylex() */
                                                                }
                    |   p_expr  PIPE  GETLINE                   {   code2(F_PUSHA, &field[0]) ;
                                                                    code1(_PUSHINT) ; code1(PIPE_IN) ;
                                                                    code2(_BUILTIN, bi_getline) ;
                                                                }
                    |   p_expr  PIPE  GETLINE  fvalue           {   code1(_PUSHINT) ;
                                                                    code1(PIPE_IN) ;
                                                                    code2(_BUILTIN, bi_getline) ;
                                                                }
                    ;

getline             :   GETLINE                                 {   getline_flag = 1 ;
                                                                }
fvalue              :   lvalue
                    |   field
                    ;
getline_file        :   getline  IO_IN                          {   $$ = code_offset ;
                                                                    code2(F_PUSHA, field+0) ;
                                                                }
                    |   getline  fvalue  IO_IN                  {   $$ = $2 ;
                                                                }
                    ;
/*==========================================
    sub and gsub
  ==========================================*/
p_expr              :   sub_or_gsub  LPAREN  re_arg  COMMA  expr  sub_back
                                                                {   INST *p5 = CDP($5) ;
                                                                    INST *p6 = CDP($6) ;
                                                                    if ( p6 - p5 == 2 && p5->op == _PUSHS ) {
                                                                        /* cast from STRING to REPL at compile time */
                                                                        CELL *cp = ZMALLOC(CELL) ;
                                                                        cp->type = C_STRING ;
                                                                        cp->ptr = p5[1].ptr ;
                                                                        cast_to_REPL(cp) ;
                                                                        p5->op = _PUSHC ;
                                                                        p5[1].ptr = (PTR) cp ;
                                                                    }
                                                                    code2(_BUILTIN, $1) ;
                                                                    $$ = $3 ;
                                                                }
                    ;
sub_or_gsub         :   SUB                                     {   $$ = bi_sub ;
                                                                }
                    |   GSUB                                    {   $$ = bi_gsub ;
                                                                }
                    ;
                    /*  substitute into $0  */
sub_back            :   RPAREN                                  {   $$ = code_offset ;
                                                                    code2(F_PUSHA, &field[0]) ;
                                                                }
                    |   COMMA  fvalue  RPAREN                   {   $$ = $2 ;
                                                                }
                    ;
/*================================================
    user defined functions
*=================================*/
function_def        :   funct_start  block                      {   resize_fblock($1) ;
                                                                    restore_ids() ;
                                                                    CODE_CLOSE_ACTIVE;
                                                                }
                    ;
funct_start         :   funct_head  LPAREN  f_arglist  RPAREN   {   EAT_NL_ ;
                                                                    scope        = SCOPE_FUNCT ;
                                                                    active_funct = $1 ;
                                                                    *main_code_p = active_code ;
                                                                    $1->nargs    = $3 ;
                                                                    if ( $3 )
                                                                        $1->typev = (char *) memset(
                                                                            zmalloc($3),
                                                                            ST_LOCAL_NONE,
                                                                            $3
                                                                        ) ;
                                                                    else
                                                                        $1->typev = (char *) 0 ;
                                                                    code_ptr      =
                                                                    code_base     =
                                                                                    (INST *) zmalloc(INST_BYTES(PAGESZ))
                                                                    ;
                                                                    code_limit    = code_base + PAGESZ ;
                                                                    code_warn     = code_limit - CODEWARN ;
                                                                }
                    ;
funct_head          :   FUNCTION  ID                            {   FBLOCK  *fbp ;
                                                                    if ( $2->type == ST_NONE ) {
                                                                        $2->type = ST_FUNCT ;
                                                                        fbp               =
                                                                        $2->stval.fbp     =
                                                                                            (FBLOCK *) zmalloc(sizeof(FBLOCK)) ;
                                                                        fbp->name         = $2->name ;
                                                                        fbp->code         = (INST*) 0 ;
                                                                    }
                                                                    else {
                                                                        type_error( $2 ) ;
                                                                        /* this FBLOCK will not be put in the symbol table */
                                                                        fbp       = (FBLOCK*) zmalloc(sizeof(FBLOCK)) ;
                                                                        fbp->name = "" ;
                                                                    }
                                                                    $$ = fbp ;
                                                                }
                    |   FUNCTION  FUNCT_ID                      {   $$ = $2 ;
                                                                    if ( $2->code )
                                                                        compile_error("redefinition of %s" , $2->name) ;
                                                                }
                    ;
f_arglist           :   /* empty */                             {   $$ = 0 ;
                                                                }
                    |   f_args
                    ;

f_args              :   ID                                      {   $1 = save_id($1->name) ;
                                                                    $1->type = ST_LOCAL_NONE ;
                                                                    $1->offset = 0 ;
                                                                    $$ = 1 ;
                                                                }
                    |   f_args  COMMA  ID                       {   if ( is_local($3) )
                                                                        compile_error
                                                                            ("%s is duplicated in argument list",
                                                                            $3->name
                                                                        ) ;
                                                                    else {
                                                                        $3 = save_id($3->name) ;
                                                                        $3->type = ST_LOCAL_NONE ;
                                                                        $3->offset = $1 ;
                                                                        $$ = $1 + 1 ;
                                                                    }
                                                                }
                    ;
outside_error       :   error                                   {   // we may have to recover from a bungled function definition
                                                                    // can have local ids, before code scope changes
                                                                    restore_ids() ;
                                                                    CODE_CLOSE_ACTIVE;
                                                                }
	                ;
/* a call to a user defined function */
p_expr              :   FUNCT_ID  mark  call_args               {   $$ = $2 ;
                                                                    code2(_CALL, $1) ;
                                                                    if ( $3 )
                                                                        code1($3->arg_num+1) ;
                                                                    else
                                                                        code1(0) ;
                                                                    check_fcall(
                                                                        $1,
                                                                        scope,
                                                                        code_move_level,
                                                                        active_funct,
                                                                        $3,
                                                                        token_lineno
                                                                    ) ;
                                                                }
                    ;
call_args           :   LPAREN  RPAREN                          {   $$ = (CA_REC *) 0 ;
                                                                }
                    |   ca_front  ca_back                       {   $$ = $2 ;
                                                                    $$->link = $1 ;
                                                                    $$->arg_num = $1 ? $1->arg_num+1 : 0 ;
                                                                }
                    ;
/*
The funny definition of ca_front with the COMMA bound to
the ID is to force a shift to avoid a reduce/reduce conflict
    ID->id or ID->array

Or to avoid a decision, if the type of the ID has not yet been determined
*/
ca_front            :   LPAREN                                  {   $$ = (CA_REC *) 0 ;
                                                                }
                    |   ca_front  expr  COMMA                   {   $$ = ZMALLOC(CA_REC) ;
                                                                    $$->link = $1 ;
                                                                    $$->type = CA_EXPR  ;
                                                                    $$->arg_num = $1 ? $1->arg_num+1 : 0 ;
                                                                    $$->call_offset = code_offset ;
                                                                }
                    |   ca_front  ID  COMMA                     {   $$ = ZMALLOC(CA_REC) ;
                                                                    $$->link = $1 ;
                                                                    $$->arg_num = $1 ? $1->arg_num+1 : 0 ;
                                                                    code_call_id($$, $2) ;
                                                                }
                    ;

ca_back             :   expr  RPAREN                            {   $$ = ZMALLOC(CA_REC) ;
                                                                    $$->type = CA_EXPR ;
                                                                    $$->call_offset = code_offset ;
                                                                }
                    |   ID  RPAREN                              {   $$ = ZMALLOC(CA_REC) ;
                                                                    code_call_id($$, $1) ;
                                                                }
                    ;
%%

/* resize the code for a user function */

static void
resize_fblock( FBLOCK * fbp ) {
    CODEBLOCK *p = ZMALLOC(CODEBLOCK) ;
    unsigned dummy ;

    code2op(_RET0, _HALT) ;
        /* make sure there is always a return */

    *p = active_code ;
    fbp->code = code_shrink(p, &dummy) ;
        /* code_shrink() zfrees p */

    if ( dump_code_flag )
        add_to_fdump_list(fbp) ;
}


/* convert FE_PUSHA  to  FE_PUSHI
   or F_PUSH to F_PUSHI
*/

static void
field_A2I(void) {
    CELL *cp ;
    if ( code_ptr[-1].op == FE_PUSHA &&
        code_ptr[-1].ptr == (PTR) 0) {
        /*  On most architectures, the two tests are the same; a good
            compiler might eliminate one.  On LM_DOS, and possibly other
            segmented architectures, they are not */
        code_ptr[-1].op = FE_PUSHI ;
    }
    else {
        cp = (CELL *) code_ptr[-1].ptr ;
        if ( cp == field  || (cp > NF && cp <= LAST_PFIELD) ) {
            code_ptr[-2].op = _PUSHI  ;
        }
        else if ( cp == NF ) {
            code_ptr[-2].op = NF_PUSHI ; code_ptr-- ;
        }
        else {
            code_ptr[-2].op = F_PUSHI ;
            code_ptr -> op = field_addr_to_index( (CELL *)code_ptr[-1].ptr ) ;
            code_ptr++ ;
        }
    }
}

/* we've seen an ID in a context where it should be a VAR,
   check that's consistent with previous usage */

static void
check_var(SYMTAB * p ) {
    switch (p->type) {
        case ST_NONE : /* new id */
            p->type = ST_VAR ;
            p->stval.cp = ZMALLOC(CELL) ;
            p->stval.cp->type = C_NOINIT ;
            break ;
        case ST_LOCAL_NONE :
            p->type = ST_LOCAL_VAR ;
            active_funct->typev[p->offset] = ST_LOCAL_VAR ;
            break ;
        case ST_VAR :
        case ST_LOCAL_VAR :
            break ;
        default :
            type_error(p) ;
            break ;
    }
}

/* we've seen an ID in a context where it should be an ARRAY,
   check that's consistent with previous usage */
static void
check_array(SYMTAB *p) {
    switch (p->type) {
        case ST_NONE :  /* a new array */
            p->type = ST_ARRAY ;
            p->stval.array = new_ARRAY() ;
            break ;
        case  ST_ARRAY :
        case  ST_LOCAL_ARRAY :
            break ;
        case  ST_LOCAL_NONE  :
            p->type = ST_LOCAL_ARRAY ;
            active_funct->typev[p->offset] = ST_LOCAL_ARRAY ;
            break ;
        default :
            type_error(p) ;
            break ;
    }
}

static void
code_array(SYMTAB* p) {
    if ( is_local(p) )
        code2op(LA_PUSHA, p->offset) ;
    else
        code2(A_PUSHA, p->stval.array) ;
}

/* we've seen an ID as an argument to a user defined function */

static void
code_call_id(CA_REC * p, SYMTAB * ip ) {
    static CELL dummy ;

    p->call_offset = code_offset ;
    /* This always get set now.  So that fcall:relocate_arglist
	works. */
    switch( ip->type ) {
        case  ST_VAR  :
            p->type = CA_EXPR ;
            code2(_PUSHI, ip->stval.cp) ;
            break ;
        case  ST_LOCAL_VAR  :
            p->type = CA_EXPR ;
            code2op(L_PUSHI, ip->offset) ;
            break ;
        case  ST_ARRAY  :
            p->type = CA_ARRAY ;
            code2(A_PUSHA, ip->stval.array) ;
            break ;
        case  ST_LOCAL_ARRAY :
            p->type = CA_ARRAY ;
            code2op(LA_PUSHA, ip->offset) ;
            break ;
        /*
        not enough info to code it now; it will have to
        be patched later */
        case  ST_NONE :
            p->type = ST_NONE ;
            p->sym_p = ip ;
            code2(_PUSHI, &dummy) ;
            break ;
        case  ST_LOCAL_NONE :
            p->type = ST_LOCAL_NONE ;
            p->type_p = & active_funct->typev[ip->offset] ;
            code2op(L_PUSHI, ip->offset) ;
            break ;

#ifdef  DEBUG
        default :
            bozo("code_call_id") ;
#endif
    }
}

/*
an RE by itself was coded as _MATCH0 , change to
push as an expression */
static void
RE_as_arg(void) {
    CELL *cp = ZMALLOC(CELL) ;
    code_ptr -= 2 ;
    cp->type = C_RE ;
    cp->ptr = code_ptr[1].ptr ;
    code2(_PUSHC, cp) ;
}

void
parse(void) {
    if ( yyparse() || compile_error_count != 0 )
        mawk_exit(2) ;
    scan_cleanup() ;
    set_code() ;
    /* code must be set before call to resolve_fcalls() */
    if ( resolve_list )
        resolve_fcalls() ;
    if ( compile_error_count != 0 )
        mawk_exit(2) ;
    if ( dump_code_flag ) {
        dump_code() ;
        mawk_exit(0) ;
    }
}
