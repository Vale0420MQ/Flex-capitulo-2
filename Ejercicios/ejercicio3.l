/* Ejercicio 3: Implementación con Chaining sobre base fb2-5 */
%option noyywrap nodefault yylineno
%x COMMENT
%x IFILE

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

struct symbol {
    char *name;
    struct ref *reflist;
    struct symbol *next; /* MODIFICACIÓN: Puntero para Chaining */
};

struct ref {
    struct ref *next;
    char *filename;
    int flags;
    int lineno;
};

/* La tabla ahora es un arreglo de punteros a estructuras symbol */
#define NHASH 9997
struct symbol *symtab[NHASH]; 

struct symbol *lookup(char*);
void addref(int, char*, char*, int);

char *curfilename; 

struct bufstack {
    struct bufstack *prev;
    YY_BUFFER_STATE bs;
    int lineno;
    char *filename;
    FILE *f;
} *curbs;

int newfile(char *fn);
int popfile(void);
int defining;
%}

%%

"/*"             { BEGIN(COMMENT); }
<COMMENT>"*/"    { BEGIN(INITIAL); }
<COMMENT>([^*]|\n)+|.
<COMMENT><<EOF>> { printf("%s:%d: Comentario no terminado\n", curfilename, yylineno); return 0; }

"//".*\n         

_Bool | _Complex | _Imaginary | auto | char | const | double | enum | extern | float | inline | int | long | register | restrict | short | signed | static | struct | typedef | union | unsigned | void | volatile { defining = 1; }

break | case | continue | default | do | else | for | goto | if | return | sizeof | switch | while { defining = 0; }

[0-9]+[fFlL]? | 0[xX][0-9a-fA-F]+ { /* Ignorar literales numéricos */ }

L?\"([^"\\]|\\.)*\" | L?\'([^'\\]|\\.)*\' { /* Ignorar literales de cadena */ }

"{"|"<%"|";"     { defining = 0; }
"["|"]"|"("|")"|"{"|"}"|"."|"->" | "++"|"--"|"&"|"*"|"+"|"-"|"~"|"!" | "/"|"%"|"<<"|">>"|"<"|">"|"<="|">="|"=="|"!="|"^"|"|"|"&&"|"||" | "?"|":"|","|"#"|"##" | "="|"*="|"/="|"%="|"+="|"-="|"<<="|">>="|"&="|"^="|"|=" { /* Ignorar operadores */ }

[_a-zA-Z][_a-zA-Z0-9]* {
    addref(yylineno, curfilename, yytext, defining);
    defining = 0;
}

^#[ \t]*include[ \t]*[\"<] { BEGIN(IFILE); }
<IFILE>[^ \t\n\">]+ {
    {
        int c;
        while((c = input()) != '\n' && c != EOF);
        if(!newfile(yytext)) yyterminate();
        BEGIN(INITIAL);
    }
}
<IFILE>.|\n { BEGIN(INITIAL); }

<<EOF>> { if(!popfile()) yyterminate(); }

[ \t\n\r] 
.       { /* Ignorar otros caracteres */ }

%%

static unsigned symhash(char *sym) {
    unsigned int hash = 0;
    unsigned c;
    while(c = *sym++) hash = hash*9 ^ c;
    return hash;
}

/* MODIFICACIÓN: Lookup rediseñado para Chaining */
struct symbol *lookup(char* s) {
    unsigned h = symhash(s) % NHASH;
    struct symbol *sp = symtab[h];

    /* Buscar en la lista ligada del índice correspondiente */
    while(sp) {
        if(sp->name && !strcmp(sp->name, s)) return sp;
        sp = sp->next;
    }

    /* Si no se encuentra, asignar memoria nueva con malloc() */
    sp = malloc(sizeof(struct symbol));
    if(!sp) { fputs("Sin memoria\n", stderr); abort(); }
    
    sp->name = strdup(s);
    sp->reflist = NULL;
    sp->next = symtab[h]; /* Insertar al inicio de la cadena */
    symtab[h] = sp;
    
    return sp;
}

void addref(int lineno, char *filename, char *word, int flags) {
    struct symbol *sp = lookup(word);
    struct ref *r;
    if(sp->reflist && sp->reflist->lineno == lineno && sp->reflist->filename == filename) return;
    r = malloc(sizeof(struct ref));
    r->next = sp->reflist;
    r->filename = filename;
    r->lineno = lineno;
    r->flags = flags;
    sp->reflist = r;
}

static int symcompare(const void *s1, const void *s2) {
    const struct symbol *sp1 = *(struct symbol **)s1;
    const struct symbol *sp2 = *(struct symbol **)s2;
    return strcmp(sp1->name, sp2->name);
}

/* MODIFICACIÓN: Impresión adaptada a Chaining */
void printrefs() {
    struct symbol **all_syms = NULL;
    int nsyms = 0;
    int i;

    /* Recolectar símbolos dispersos para ordenarlos */
    for(i = 0; i < NHASH; i++) {
        struct symbol *sp = symtab[i];
        while(sp) {
            all_syms = realloc(all_syms, (nsyms + 1) * sizeof(struct symbol *));
            all_syms[nsyms++] = sp;
            sp = sp->next;
        }
    }

    if(nsyms > 0) {
        qsort(all_syms, nsyms, sizeof(struct symbol *), symcompare);
        for(i = 0; i < nsyms; i++) {
            struct symbol *sp = all_syms[i];
            char *prevfn = NULL;
            struct ref *rp = sp->reflist;
            struct ref *rpp = NULL, *rpn;
            while(rp) { rpn = rp->next; rp->next = rpp; rpp = rp; rp = rpn; }
            printf("%10s", sp->name);
            for(rp = rpp; rp; rp = rp->next) {
                if(rp->filename == prevfn) printf(", %d", rp->lineno);
                else { printf(" %s:%d", rp->filename, rp->lineno); prevfn = rp->filename; }
                if(rp->flags & 01) printf("*");
            }
            printf("\n");
        }
        free(all_syms);
    }
}

int main(int argc, char **argv) {
    int i;
    for(i = 0; i < NHASH; i++) symtab[i] = NULL; /* Inicializar tabla vacía */

    if(argc < 2) {
        fprintf(stderr, "Necesita archivos de entrada\n");
        return 1;
    }
    for(i = 1; i < argc; i++) {
        if(newfile(argv[i])) yylex();
    }
    printrefs();
    return 0;
}

int newfile(char *fn) {
    FILE *f = fopen(fn, "r");
    struct bufstack *bs = malloc(sizeof(struct bufstack));
    if(!f) { perror(fn); return 0; }
    if(!bs) { perror("malloc"); exit(1); }
    if(curbs) curbs->lineno = yylineno;
    bs->prev = curbs;
    bs->f = f;
    bs->filename = fn;
    bs->bs = yy_create_buffer(f, YY_BUF_SIZE);
    yy_switch_to_buffer(bs->bs);
    curbs = bs;
    yylineno = 1;
    curfilename = fn;
    return 1;
}

int popfile(void) {
    struct bufstack *bs = curbs;
    struct bufstack *prevbs;
    if(!bs) return 0;
    fclose(bs->f);
    yy_delete_buffer(bs->bs);
    prevbs = bs->prev;
    free(bs);
    if(!prevbs) return 0;
    yy_switch_to_buffer(prevbs->bs);
    curbs = prevbs;
    yylineno = curbs->lineno;
    curfilename = curbs->filename;
    return 1;
}
