
/********************************************
code.c
copyright 1991-93,2014-2016  Michael D. Brennan

This is a source file for mawk, an implementation of
the AWK programming language.

Mawk is distributed without warranty under the terms of
the GNU General Public License, version 3, 2007.

If you import elements of this code into another product,
you agree to not name that product mawk.
********************************************/

#include "mawk.h"
#include "code.h"
#include "init.h"
#include "jmp.h"
#include "field.h"

// static CODEBLOCK * code_create_block( void );

CODEBLOCK   active_code;
CODEBLOCK * main_code_p;
CODEBLOCK * begin_code_p;
CODEBLOCK * end_code_p;

INST * begin_start;
INST * main_start;
INST * end_start;

unsigned begin_size;
unsigned main_size;

// INST *execution_start = 0 ;

/* grow the active code */
void
code_grow( void )
{
    unsigned oldsize = code_limit - code_base;
    unsigned newsize = PAGESZ + oldsize;
    unsigned delta   = code_ptr - code_base;

    if ( code_ptr > code_limit )
        bozo( "CODEWARN is too small" );

    code_base = (INST *)
        zrealloc( code_base, INST_BYTES( oldsize ),
                  INST_BYTES( newsize ) );
    code_limit = code_base + newsize;
    code_warn  = code_limit - CODEWARN;
    code_ptr   = code_base + delta;
}

/* shrinks executable code that's done to its final size */
INST *
code_shrink( CODEBLOCK * p, unsigned * sizep )
{

    unsigned oldsize = INST_BYTES( p->limit - p->base );
    unsigned newsize = INST_BYTES( p->ptr - p->base );
    INST *   retval;

    *sizep = newsize;

    retval = (INST *)zrealloc( p->base, oldsize, newsize );
    ZFREE( p );
    return retval;
}

/* code an op and a pointer in the active_code */
void
xcode2( int op, void * ptr )
{
    register INST * p = code_ptr + 2;
    if ( p >= code_warn ) {
        code_grow();
        p = code_ptr + 2;
    }
    p[-2].op  = op;
    p[-1].ptr = ptr;
    code_ptr  = p;
}

/* code two ops in the active_code */
void
code2op( int x, int y )
{
    register INST * p = code_ptr + 2;

    if ( p >= code_warn ) {
        code_grow();
        p = code_ptr + 2;
    }

    p[-2].op = x;
    p[-1].op = y;
    code_ptr = p;
}

void
code_init( void )
{
    main_code_p = code_create_block();
    active_code = *main_code_p;
    code1( _OMAIN );
}

/* final code relocation
   set_code() as in set concrete */
void
set_code( void )
{
    /* set the main code which is active_code */
    if ( end_code_p || code_offset > 1 ) {
        int        gl_offset = code_offset;
        extern int NR_flag;

        if ( NR_flag )
            code2op( OL_GL_NR, _HALT );
        else
            code2op( OL_GL, _HALT );

        *main_code_p    = active_code;
        main_start      = code_shrink( main_code_p, &main_size );
        next_label      = main_start + gl_offset;
        execution_start = main_start;
    }
    else /* only BEGIN */
    {
        zfree( code_base, INST_BYTES( PAGESZ ) );
        ZFREE( main_code_p );
    }

    /* set the END code */
    if ( end_code_p ) {
        unsigned dummy;

        active_code = *end_code_p;
        code2op( _EXIT0, _HALT );
        *end_code_p = active_code;
        end_start   = code_shrink( end_code_p, &dummy );
    }

    /* set the BEGIN code */
    if ( begin_code_p ) {
        active_code     = *begin_code_p;
        if ( main_start )
            code2op( _JMAIN, _HALT );
        else
            code2op( _EXIT0, _HALT );
        *begin_code_p   = active_code;
        begin_start     = code_shrink( begin_code_p, &begin_size );
        execution_start = begin_start;
    }

    if ( !execution_start ) {
        /* program had functions but no pattern-action bodies */
        execution_start = begin_start = (INST *)zmalloc( 2 * sizeof( INST ) );
        execution_start[0].op         = _EXIT0;
        execution_start[1].op         = _HALT;
    }
}

void
dump_code( void )
{
    fdump(); /* dumps all user functions */
    if ( begin_start ) {
        fprintf( stdout, "BEGIN\n" );
        da( begin_start, stdout );
    }
    if ( end_start ) {
        fprintf( stdout, "END\n" );
        da( end_start, stdout );
    }
    if ( main_start ) {
        fprintf( stdout, "MAIN\n" );
        da( main_start, stdout );
    }
}

CODEBLOCK *
code_create_block( void )
{
    CODEBLOCK * p = ZMALLOC( CODEBLOCK );

    p->base  = (INST *)zmalloc( INST_BYTES( PAGESZ ) );
    p->limit = p->base + PAGESZ;
    p->warn  = p->limit - CODEWARN;
    p->ptr   = p->base;

    return p;
}
