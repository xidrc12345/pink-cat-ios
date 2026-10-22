#ifndef PC_MINI_APPLE_H
#define PC_MINI_APPLE_H
/* Public ABI declarations only. No Apple SDK implementation is bundled. */
typedef unsigned int u32;
typedef int i32;
typedef unsigned long long u64;
typedef long long i64;
typedef unsigned long usize;
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef struct objc_method *Method;
typedef id (*IMP)(id,SEL,...);
typedef struct {double x,y;} PCPoint;
typedef struct {double width,height;} PCSize;
typedef struct {PCPoint origin;PCSize size;} PCRect;
typedef struct {double top,left,bottom,right;} PCInsets;
extern Class objc_getClass(const char *);
extern Class objc_allocateClassPair(Class,const char *,usize);
extern void objc_registerClassPair(Class);
extern _Bool class_addMethod(Class,SEL,IMP,const char *);
extern Method class_getInstanceMethod(Class,SEL);
extern const char *method_getTypeEncoding(Method);
extern IMP method_setImplementation(Method,IMP);
extern SEL sel_registerName(const char *);
extern id objc_msgSend(id,SEL,...);
extern u32 _dyld_image_count(void);
extern const char *_dyld_get_image_name(u32);
extern const void *_dyld_get_image_header(u32);
extern char _dispatch_main_q;
extern void dispatch_async_f(void *,void *,void (*)(void *));
extern int strcmp(const char *,const char *);
extern char *strstr(const char *,const char *);
extern usize strlen(const char *);
extern int snprintf(char *,usize,const char *,...);
extern void *memcpy(void *,const void *,usize);
extern void *memset(void *,int,usize);
extern id NSHomeDirectory(void);
extern int pthread_key_create(unsigned long *,void (*)(void *));
extern void *pthread_getspecific(unsigned long);
extern int pthread_setspecific(unsigned long,const void *);

static inline SEL S(const char *s){return sel_registerName(s);}
static inline id C(const char *s){return (id)objc_getClass(s);}
static inline id O(id o,const char *s){return ((id(*)(id,SEL))objc_msgSend)(o,S(s));}
static inline id O1(id o,const char *s,id a){return ((id(*)(id,SEL,id))objc_msgSend)(o,S(s),a);}
static inline void V(id o,const char *s){((void(*)(id,SEL))objc_msgSend)(o,S(s));}
static inline void V1(id o,const char *s,id a){((void(*)(id,SEL,id))objc_msgSend)(o,S(s),a);}
static inline void VI(id o,const char *s,long v){((void(*)(id,SEL,long))objc_msgSend)(o,S(s),v);}
static inline void VD(id o,const char *s,double v){((void(*)(id,SEL,double))objc_msgSend)(o,S(s),v);}
static inline void VB(id o,const char *s,_Bool v){((void(*)(id,SEL,_Bool))objc_msgSend)(o,S(s),v);}
static inline long I(id o,const char *s){return ((long(*)(id,SEL))objc_msgSend)(o,S(s));}
static inline i32 I32(id o,const char *s){return ((i32(*)(id,SEL))objc_msgSend)(o,S(s));}
static inline double D(id o,const char *s){return ((double(*)(id,SEL))objc_msgSend)(o,S(s));}
static inline _Bool B(id o,const char *s){return ((_Bool(*)(id,SEL))objc_msgSend)(o,S(s));}
static inline _Bool Responds(id o,const char *s){return ((_Bool(*)(id,SEL,SEL))objc_msgSend)(o,S("respondsToSelector:"),S(s));}
static inline _Bool Kind(id o,const char *cls){return ((_Bool(*)(id,SEL,Class))objc_msgSend)(o,S("isKindOfClass:"),objc_getClass(cls));}
static inline id Str(const char *s){return ((id(*)(id,SEL,const char*))objc_msgSend)(C("NSString"),S("stringWithUTF8String:"),s?s:"");}
static inline const char *UTF8(id s){return ((const char*(*)(id,SEL))objc_msgSend)(s,S("UTF8String"));}
static inline id Retain(id o){return O(o,"retain");}
static inline void Release(id o){if(o)V(o,"release");}
static inline PCRect Rect(double x,double y,double w,double h){PCRect r={{x,y},{w,h}};return r;}
static inline PCRect Bounds(id o){return ((PCRect(*)(id,SEL))objc_msgSend)(o,S("bounds"));}
static inline PCRect Frame(id o){return ((PCRect(*)(id,SEL))objc_msgSend)(o,S("frame"));}
static inline void SetFrame(id o,PCRect r){((void(*)(id,SEL,PCRect))objc_msgSend)(o,S("setFrame:"),r);}
static inline id Color(double r,double g,double b,double a){return ((id(*)(id,SEL,double,double,double,double))objc_msgSend)(C("UIColor"),S("colorWithRed:green:blue:alpha:"),r,g,b,a);}
static inline id Font(double size,double weight){return ((id(*)(id,SEL,double,double))objc_msgSend)(C("UIFont"),S("systemFontOfSize:weight:"),size,weight);}
static inline id At(id array,usize index){return ((id(*)(id,SEL,usize))objc_msgSend)(array,S("objectAtIndex:"),index);}
static inline id Number(i64 n){return ((id(*)(id,SEL,i64))objc_msgSend)(C("NSNumber"),S("numberWithLongLong:"),n);}
static inline void Dict(id d,const char *k,id v){((void(*)(id,SEL,id,id))objc_msgSend)(d,S("setObject:forKey:"),v,Str(k));}
static inline void OnMain(void(*f)(void*),void *p){dispatch_async_f(&_dispatch_main_q,p,f);}
#endif
