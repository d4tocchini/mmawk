/********************************************
field.h
copyright 1991-1995,2014-2016 Michael D. Brennan

This is a source file for mawk, an implementation of
the AWK programming language.

Mawk is distributed without warranty under the terms of
the GNU General Public License, version 3, 2007.

If you import elements of this code into another product,
you agree to not name that product mawk.
********************************************/


/* field.h */

#ifndef  MAWK_FIELD_H
#define  MAWK_FIELD_H   1

#include "types.h"

extern void set_field0(const char *, size_t);
extern void split_field0(void);
extern void field_assign(CELL *, CELL *);
extern char *is_string_split(PTR, size_t *);
extern void slow_cell_assign(CELL *, CELL *);
extern CELL *slow_field_ptr(int);
extern int field_addr_to_index(CELL *);
extern void set_binmode(int);

#define  NUM_PFIELDS		5
extern CELL field[FBANK_SZ + NUM_PFIELDS];
	/* $0, $1 ... $(FBANK_SZ-1), NF, RS, RS, CONVFMT, OFMT */

/* more fields if needed go here */
extern CELL **fbankv;		/* fbankv[0] == field */

/* index to CELL *  for a field */
#define field_ptr(i) ((i) < FBANK_SZ ? field + (i) : slow_field_ptr(i))

/* some, such as RS may be defined in system-headers */
#undef NF
#undef RS
#undef FS
#undef CONVFMT
#undef OFMT

/* some compilers choke on (NF-field) in a case statement
   even though it's constant so ...
*/
#define  NF_field      FBANK_SZ
#define  RS_field      (FBANK_SZ + 1)
#define  FS_field      (FBANK_SZ + 2)
#define  CONVFMT_field (FBANK_SZ + 3)
#define  OFMT_field    (FBANK_SZ + 4)

/* the pseudo fields, assignment has side effects */
#define  NF            (field + NF_field)	/* must be first */
#define  RS            (field + RS_field)
#define  FS            (field + FS_field)
#define  CONVFMT       (field + CONVFMT_field)
#define  OFMT          (field + OFMT_field)	/* must be last */

#define  LAST_PFIELD	OFMT

extern int nf;			/* shadows NF */

/* a shadow type for RS and FS */
#define  SEP_SPACE      0
#define  SEP_CHAR       1
#define  SEP_STR        2
#define  SEP_RE         3
#define  SEP_MLR	4

typedef struct {
    char type;
    char c;
    PTR ptr;			/* STRING* or RE machine* */
} SEPARATOR;

extern SEPARATOR rs_shadow;
extern CELL fs_shadow;

/*  types for splitting overflow */

typedef struct spov {
    struct spov *link;
    STRING *sval;
} SPLIT_OV;

extern SPLIT_OV *split_ov_list;

#endif /* MAWK_FIELD_H  */
