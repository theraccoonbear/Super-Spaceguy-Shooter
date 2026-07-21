#ifndef CURL_QB64_H
#define CURL_QB64_H

#include <stdint.h>
#include <string.h>

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
int      curl_easy_getinfo(intptr_t, int, ...);

#ifdef __cplusplus
}
#endif

/* ---- response capture helpers (outside extern "C" -- compiled as C++) ---- */

#define QBC_RESPONSE_CODE   2097154  /* CURLINFO_LONG (0x200000) + 2 */
#define QBC_WRITEFUNCTION   20011    /* CURLOPTTYPE_FUNCTIONPOINT + 11 */
#define QBC_HEADERFUNCTION  20079    /* CURLOPTTYPE_FUNCTIONPOINT + 79 */
#define QBC_BODY_MAX        32768
#define QBC_HDR_MAX         8192

static char qbc_body[QBC_BODY_MAX];
static int  qbc_body_len;
static char qbc_hdrs[QBC_HDR_MAX];
static int  qbc_hdrs_len;

static size_t qbc_write_body(char *ptr, size_t size, size_t nmemb, void *) {
    size_t n = size * nmemb;
    if (qbc_body_len + (int)n < QBC_BODY_MAX - 1) {
        memcpy(qbc_body + qbc_body_len, ptr, n);
        qbc_body_len += (int)n;
        qbc_body[qbc_body_len] = '\0';
    }
    return n;
}

static size_t qbc_write_hdrs(char *ptr, size_t size, size_t nmemb, void *) {
    size_t n = size * nmemb;
    if (qbc_hdrs_len + (int)n < QBC_HDR_MAX - 1) {
        memcpy(qbc_hdrs + qbc_hdrs_len, ptr, n);
        qbc_hdrs_len += (int)n;
        qbc_hdrs[qbc_hdrs_len] = '\0';
    }
    return n;
}

typedef size_t (*qbc_write_fn)(char *, size_t, size_t, void *);

static inline void qb64_curl_enable_capture(intptr_t handle) {
    qbc_body_len = 0; qbc_body[0] = '\0';
    qbc_hdrs_len = 0; qbc_hdrs[0] = '\0';
    curl_easy_setopt(handle, QBC_WRITEFUNCTION,  (qbc_write_fn)qbc_write_body);
    curl_easy_setopt(handle, QBC_HEADERFUNCTION, (qbc_write_fn)qbc_write_hdrs);
}

static inline long qb64_curl_response_code(intptr_t handle) {
    long code = 0;
    curl_easy_getinfo(handle, QBC_RESPONSE_CODE, &code);
    return code;
}

static inline int  qb64_resp_body_length(void) { return qbc_body_len; }
static inline int  qb64_resp_hdrs_length(void) { return qbc_hdrs_len; }

static inline void qb64_get_body(char *out, int maxlen) {
    int n = qbc_body_len < maxlen ? qbc_body_len : maxlen;
    memcpy(out, qbc_body, n);
}

static inline void qb64_get_hdrs(char *out, int maxlen) {
    int n = qbc_hdrs_len < maxlen ? qbc_hdrs_len : maxlen;
    memcpy(out, qbc_hdrs, n);
}

#endif
