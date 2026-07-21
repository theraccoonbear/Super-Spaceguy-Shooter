#ifndef CURL_QB64_H
#define CURL_QB64_H

/* Minimal libcurl declarations for QB64-PE DECLARE LIBRARY binding.
 * Parameters use intptr_t to match QB64-PE's _OFFSET (%&) internal type.
 * With extern "C" the linker resolves by C name, and ABI is identical at runtime. */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

intptr_t curl_easy_init(void);
int      curl_easy_setopt(intptr_t, int, ...);
void     curl_easy_cleanup(intptr_t);
intptr_t curl_slist_append(intptr_t, const char*);
void     curl_slist_free_all(intptr_t);
intptr_t curl_multi_init(void);
int      curl_multi_add_handle(intptr_t, intptr_t);
int      curl_multi_perform(intptr_t, int*);
int      curl_multi_remove_handle(intptr_t, intptr_t);

#ifdef __cplusplus
}
#endif

#endif
