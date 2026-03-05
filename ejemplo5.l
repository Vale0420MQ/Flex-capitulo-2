/* fb2-5 C cross-ref */
%option noyywrap nodefault yylineno
%x COMMENT
%x IFILE

/* Universal Character Name */
UCN (\\u[0-9a-fA-F]{4}|\\U[0-9a-fA-F]{8})
/* float exponent */
EXP ([Ee][-+]?[0-9]+)
/* integer lenght */
ILEN (([uU](ll|LL|[lL])?)|((ll|LL|[lL])[uU]?))

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


struct symbol {
    struct ref *reflist;
    char *name;
};

struct ref {
    struct ref *next;
    char *filename;
    int flags; /* 01 - es una definición */
    int lineno;
};

#define NHASH 9997
struct symbol symtab[NHASH];

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

_Bool |
_Complex |
_Imaginary |
auto |
char |
const |
double |
enum |
extern |
float |
inline |
int |
long |
register |
restrict |
short |
signed |
static |
struct |
typedef |
union |
unsigned |
void |
volatile         { defining = 1; }

break |
case |
continue |
default |
do |
else |
for |
goto |
if |
return |
sizeof |
switch |
while            { defining = 0; }

0[0-7]*{ILEN}?
[1-9][0-9]*{ILEN}?
0[Xx][0-9a-fA-F]+{ILEN}?
([0-9]*\.[0-9]+|[0-9]+\.){EXP}?[flFL]?
[0-9]+{EXP}[flFL]?
0[Xx]([0-9a-fA-F]*\.[0-9a-fA-F]+|[0-9a-fA-F]+\.?)[Pp][-+]?[0-9]+[flFL]?

/* Literales de cadena y caracteres */
L?\"([^"\\]|\\.)*\"
L?\'([^'\\]|\\.)*\'

"{"|"<%"|";"     { defining = 0; }
"["|"]"|"("|")"|"{"|"}"|"."|"->"
"++"|"--"|"&"|"*"|"+"|"-"|"~"|"!"
"/"|"%"|"<<"|">>"|"<"|">"|"<="|">="|"=="|"!="|"^"|"|"|"&&"|"||"
"?"|":"|","|"#"|"##"
"="|"*="|"/="|"%="|"+="|"-="|"<<="|">>="|"&="|"^="|"|="

([_a-zA-Z]|{UCN})([_a-zA-Z0-9]|{UCN})* {
    addref(yylineno, curfilename, yytext, defining);
    defining = 0;
}

^#[ \t]*include[ \t]*[\"<] { BEGIN(IFILE); }
<IFILE>[^ \t\n\">]+ {
    {
        int c;
        while((c = input()) != '\n' && c != EOF);
        if(!newfile(yytext))
            yyterminate(); /* no pudo abrir el archivo */
        BEGIN(INITIAL);
    }
}
<IFILE>.|\n { printf("%s:%d mal formado el include\n", curfilename, yylineno); BEGIN(INITIAL); }

<<EOF>> { if(!popfile()) yyterminate(); }

[ \t\n\r] 
.           { printf("%s:%d: Carácter misterioso %s\n", curfilename, yylineno, yytext); }
%%

static unsigned symhash(char *sym) {
    unsigned int hash = 0;
    unsigned c;
    while(c = *sym++) hash = hash*9 ^ c;
    return hash;
}

struct symbol *lookup(char* s) {
    struct symbol *sp = &symtab[symhash(s)%NHASH];
    int scount = NHASH;
    while(--scount >= 0) {
        if(sp->name && !strcmp(sp->name, s)) return sp;
        if(!sp->name) {
            sp->name = strdup(s);
            sp->reflist = 0;
            return sp;
        }
        if(++sp >= symtab+NHASH) sp = symtab;
    }
    abort();
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

static int symcompare(const void *s1, const void *s2) {
    const struct symbol *sp1 = s1;
    const struct symbol *sp2 = s2;
    if(!sp1->name) { if(!sp2->name) return 0; return 1; }
    if(!sp2->name) return -1;
    return strcmp(sp1->name, sp2->name);
}

void printrefs() {
    struct symbol *sp;
    qsort(symtab, NHASH, sizeof(struct symbol), symcompare);
    for(sp = symtab; sp->name && sp < symtab+NHASH; sp++) {
        char *prevfn = NULL;
        struct ref *rp = sp->reflist;
        struct ref *rpp = 0, *rpn;
        while(rp) { rpn = rp->next; rp->next = rpp; rpp = rp; rp = rpn; }
        printf("%10s", sp->name);
        for(rp = rpp; rp; rp = rp->next) {
            if(rp->filename == prevfn) printf(", %d", rp->lineno);
            else { printf(" %s:%d", rp->filename, rp->lineno); prevfn = rp->filename; }
            if(rp->flags & 01) printf("*"); 
        }
        printf("\n");
    }
}

int main(int argc, char **argv) {
    int i;
    if(argc < 2) {
        fprintf(stderr, "necesita archivos de entrada\n");
        return 1;
    }
    for(i = 1; i < argc; i++) {
        if(newfile(argv[i])) yylex();
    }
    printrefs();
    return 0;
}
