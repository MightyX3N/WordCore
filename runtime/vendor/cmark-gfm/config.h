/* Hand-written replacement for the CMake-generated config.h (WordCore build). */
#ifndef CMARK_CONFIG_H
#define CMARK_CONFIG_H
#include <stdbool.h>
#define HAVE_STDBOOL_H
#define HAVE___BUILTIN_EXPECT
#define HAVE___ATTRIBUTE__
#define CMARK_ATTRIBUTE(list) __attribute__ (list)
#ifndef CMARK_INLINE
  #define CMARK_INLINE inline
#endif
#endif
