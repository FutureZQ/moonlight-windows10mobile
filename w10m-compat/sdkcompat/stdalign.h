#pragma once
/* Minimal C11 <stdalign.h> for the v143 ARM UWP toolchain used to build the
 * C dependencies. MSVC v143 supports the _Alignas/_Alignof keywords but does
 * not ship this header in all UWP configurations. */
#ifndef __cplusplus
#ifndef alignas
#define alignas _Alignas
#endif
#ifndef alignof
#define alignof _Alignof
#endif
#endif
