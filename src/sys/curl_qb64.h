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
intptr_t    curl_multi_init(void);
int         curl_multi_add_handle(intptr_t, intptr_t);
int         curl_multi_perform(intptr_t, int*);
int         curl_multi_remove_handle(intptr_t, intptr_t);
void*       curl_multi_info_read(intptr_t, int*);
int         curl_easy_getinfo(intptr_t, int, ...);
const char* curl_easy_strerror(int);

#ifdef __cplusplus
}
#endif

/* ---- response capture helpers (outside extern "C" -- compiled as C++) ---- */

#define QBC_RESPONSE_CODE   2097154  /* CURLINFO_LONG (0x200000) + 2 */
#define QBC_WRITEFUNCTION   20011    /* CURLOPTTYPE_FUNCTIONPOINT + 11 */
#define QBC_HEADERFUNCTION  20079    /* CURLOPTTYPE_FUNCTIONPOINT + 79 */
#define QBC_BODY_MAX        32768
#define QBC_HDR_MAX         8192
#define QBC_POST_MAX        131072   /* max POST body: 128 KB */

static char qbc_body[QBC_BODY_MAX];
static int  qbc_body_len;
static char qbc_hdrs[QBC_HDR_MAX];
static int  qbc_hdrs_len;
static char qbc_post[QBC_POST_MAX];  /* stable POST body buffer -- curl reads this during async transfer */
static int  qbc_post_len;

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

/*
 * CURLMsg layout on 64-bit (x86-64 / aarch64):
 *   offset  0: CURLMSG msg      (enum → int, 4 bytes)
 *   offset  4: padding          (4 bytes)
 *   offset  8: CURL *easy_handle (pointer, 8 bytes)
 *   offset 16: union { void*; CURLcode result; } (8-byte slot; result is int at offset 16)
 * CURLMSG_DONE = 1
 */
static inline int qb64_curl_last_curlcode(intptr_t multi_handle) {
    int msgs = 0;
    unsigned char *msg = (unsigned char *)curl_multi_info_read(multi_handle, &msgs);
    if (!msg) return -1;
    int curlmsg; memcpy(&curlmsg, msg,      sizeof(curlmsg));  /* CURLMSG enum */
    if (curlmsg != 1) return -2;                                /* not CURLMSG_DONE */
    int result;  memcpy(&result,  msg + 16, sizeof(result));   /* CURLcode */
    return result;
}

static inline void qb64_curl_error_str(int code, char *out, int maxlen) {
    const char *s = curl_easy_strerror(code);
    if (!s) s = "(null)";
    int n = 0;
    while (s[n] && n < maxlen - 1) { out[n] = s[n]; n++; }
    out[n] = '\0';
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

/*
 * Copy POST body into stable C static buffer, then set CURLOPT_POSTFIELDS + SIZE.
 * CURLOPT_POSTFIELDS stores the raw pointer -- QB64-PE's string temp is freed after
 * setopt returns, leaving curl with a dangling pointer for async transfers.
 * Copying here keeps qbc_post[] valid until the next call to this function.
 * Returns 0 on success, -1 if body exceeds QBC_POST_MAX.
 */
static inline int qb64_set_post_body(intptr_t handle, const char *body, int len) {
    if (len < 0 || len >= QBC_POST_MAX) return -1;
    memcpy(qbc_post, body, len);
    qbc_post_len = len;
    curl_easy_setopt(handle, 10015, qbc_post);    /* CURLOPT_POSTFIELDS */
    curl_easy_setopt(handle, 60,    (long)len);   /* CURLOPT_POSTFIELDSIZE */
    return 0;
}

#endif
