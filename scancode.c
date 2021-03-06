

/* scancode.c */
/* generated from scancode.src.c */
/* Fri Apr  5 06:20:29 PDT 2019 */


#include "scan.h" 
const int scan_code[256] = {
 0,34,34,34,34,34,34,34,34, 1, 2, 1, 1, 1,34,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,
 1,27,23,25,33,15,10,34,17,18,13,11,30,12,31,14,
22,22,22,22,22,22,22,22,22,22, 8, 3,28,26,29, 7,
34,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,
21,21,21,21,21,21,21,21,21,21,21,19,24,20,16,21,
34,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,
21,21,21,21,21,21,21,21,21,21,21, 5, 9, 6,32,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,
34,34,34,34,34,34,34,34,34,34,34,34,34,34,34,34
};
    int        scan_code_NL_value = SC_NL;  
    int scan_code_get(const unsigned char c) {               
       const  int code = scan_code[c];                       
       const  int i = code ^ SC_NL;                          
       switch (i) {                  
           case 0 :                                         
               return scan_code_NL_value;            
       }                                                    
       return code;                                         
   }                                                        
