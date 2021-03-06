
/********************************************
mawk.h
copyright 1991-94,2014-2016 Michael D. Brennan

This is a source file for mawk, an implementation of
the AWK programming language.

Mawk is distributed without warranty under the terms of
the GNU General Public License, version 3, 2007.

If you import elements of this code into another product,
you agree to not name that product mawk.
********************************************/

/*  mawk.h  */

#ifndef MAWK_H
#define MAWK_H



#define EVAL_STACK_SIZE  256	/* initial size , can grow */

/*
 * FBANK_SZ, the number of fields at startup, must be a power of 2.
 *
 */
#define  FBANK_SZ	      1024
#define  FB_SHIFT	      10	/* lg(FBANK_SZ) */

/*
 * initial size of sprintf buffer
 */
#define  SPRINTF_LIMIT	8192

#define  BUFFSZ         4096
#define  FINBUFFSZ      8192
  /* starting buffer size for input files, grows if
     necessary */

#define  MAX_COMPILE_ERRORS  5	/* quit if more than 4 errors */



// typedef void * PTR;
typedef int    Bool;

#include "scan.h"
#include "types.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef DEBUG
#define YYDEBUG 1
extern int yydebug; /* print parse if on */
extern int dump_RE;
#endif

/*----------------
 *  GLOBAL VARIABLES
 *----------------*/

// #define COMP

// DOD_SOA                                 mawk_d {
//     DOD_CONS STRING const * const           the_empty_str;
//     DOD_COMP STRING                         null_str ; // a well known string
// /*  `string_buff` a useful scratch area
//     Once execute() starts the sprintf code is (belatedly) the only code allowed to use string_buff */
//     DOD_COMP char *                         string_buff;
//     DOD_COMP char *                         string_buff_end;
//                                         }


// typedef struct                      mawk_soa_page {
//           STRING const * const          the_empty_str;
//     COMP( STRING,                       null_str ); // a well known string

// /*  `string_buff` a useful scratch area
//     Once execute() starts the sprintf code is (belatedly) the only code allowed to use string_buff */
//    COMP( char *,                       string_buff );
//    COMP( char *,                       string_buff_end );

// }                                   mawk_state_t;

/* a well known string */
extern STRING         null_str;
extern STRING * const the_empty_str;

/* `string_buff` a useful scratch area
    Once execute() starts the sprintf code is (belatedly) the only code allowed to use string_buff
*/
extern char * string_buff;
extern char * string_buff_end;

char * enlarge_string_buff( char * );



/* these are used by the parser, scanner and error messages
    from the compile  */

extern const char * pfile_name; /* program input file */
extern int          current_token;
extern unsigned     token_lineno; /* lineno of current token */
extern unsigned     compile_error_count;
extern int          paren_cnt, brace_cnt;
extern int          print_flag, getline_flag;

extern const char * progname;      /* for error messages */
extern unsigned     rt_nr, rt_fnr; /* ditto */

extern int posix_space_flag;
extern int interactive_flag;
extern int posix_repl_scan_flag;

int mawk_state;     /* 0 is compiling */
#define EXECUTION 1 /* other state is 0 compiling */

// typedef struct mawk_opts {

// } mawk_opts;

// typedef struct mawk_ctx {
//     state
// } mawk_ctx;

/* macro to get at the string part of a CELL */
#define string( cp ) ( (STRING *)( cp )->ptr )

#ifdef DEBUG
#define cell_destroy( cp ) DB_cell_destroy( cp )
#else

#define cell_destroy( cp )                                            \
    do {                                                              \
        if ( ( cp )->type >= C_STRING && ( cp )->type <= C_MBSTRN ) { \
            free_STRING( string( cp ) );                              \
        }                                                             \
    } while ( 0 )
#endif

/*  prototypes  */

void cast1_to_s( CELL * );
void cast1_to_d( CELL * );
void cast_to_RE( CELL * );
void cast_for_split( CELL * );
void check_strnum( CELL * );
void cast_to_REPL( CELL * );
int  d_to_I( double );

#define cast2_to_s( p )      \
    do {                     \
        cast1_to_s( p );     \
        cast1_to_s( p + 1 ); \
    } while ( 0 )
#define cast2_to_d( p )      \
    do {                     \
        cast1_to_d( p );     \
        cast1_to_d( p + 1 ); \
    } while ( 0 )

int    test( CELL * ); /* test for null non-null */
CELL * cellcpy( CELL *, CELL * );
CELL * repl_cpy( CELL *, CELL * );
void   DB_cell_destroy( CELL * );
void   overflow( const char *, unsigned );
void   rt_overflow( const char *, unsigned );
void   rt_error( const char *, ... );
void   mawk_exit( int );
void   da( INST *, FILE * );
char * str_str( const char *, size_t, const char *, size_t );
size_t rm_escape( char * );
char * re_pos_match( const char *, size_t, void *, size_t *, Bool );
int    binmode( void );

void bozo( const char * );
void errmsg( int, const char *, ... );
void compile_error( const char *, ... );
void call_error( unsigned, const char *, ... );
void compile_or_rt_error( const char *, ... );

int _mawk_execute(
    INST *          cdp, // code ptr, start execution here
    register CELL * sp,  // eval_stack pointer
    CELL *          fp   // frame ptr into eval_stack for user defined funcs */
);
#define mawk_execute( cdp, sp, fp ) \
    ( mawk_state= EXECUTION ) && _mawk_execute( cdp, sp, fp )
// TODO: || mawk_state = ....

const char * find_kw_str( int );

#endif /* MAWK_H */
