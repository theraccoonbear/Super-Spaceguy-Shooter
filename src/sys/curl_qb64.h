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
static char qbc_post[QBC_POST_MAX];
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

/*
 * CURLMsg layout on 64-bit:
 *   offset  0: CURLMSG msg      (int, 4 bytes)
 *   offset  4: padding          (4 bytes)
 *   offset  8: CURL *easy_handle (pointer, 8 bytes)
 *   offset 16: union { void*; CURLcode result; } (CURLcode is int at offset 16)
 * CURLMSG_DONE = 1
 */
static inline int qb64_curl_last_curlcode(intptr_t multi_handle) {
    int msgs = 0;
    unsigned char *msg = (unsigned char *)curl_multi_info_read(multi_handle, &msgs);
    if (!msg) return -1;
    int curlmsg; memcpy(&curlmsg, msg,      sizeof(curlmsg));
    if (curlmsg != 1) return -2;
    int result;  memcpy(&result,  msg + 16, sizeof(result));
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

#define QBC_URL_MAX  2048
#define QBC_KEY_MAX  1024

static char     qbc_url[QBC_URL_MAX];
static char     qbc_key[QBC_KEY_MAX];
static char     qbc_hdr_key[QBC_KEY_MAX  + 10];
static char     qbc_hdr_auth[QBC_KEY_MAX + 24];
static intptr_t qbc_slist;

static inline void qb64_http_cleanup_slist(void) {
    if (qbc_slist) { curl_slist_free_all(qbc_slist); qbc_slist = 0; }
}

/*
 * qb64_http_post -- copy ALL strings to stable C buffers, then configure curl for a POST.
 * QB64-PE DECLARE LIBRARY passes string temporaries that are freed after the call returns;
 * curl holds raw pointers and reads them asynchronously, so everything must be copied first.
 * Returns 0 on success, negative on validation error, CURLMcode on multi failure.
 */
static inline int qb64_http_post(
    intptr_t easy,   intptr_t multi,
    const char *url, int url_len,
    const char *key, int key_len,
    const char *body, int body_len
) {
    if (url_len  <= 0 || url_len  >= QBC_URL_MAX)  return -1;
    if (key_len  <= 0 || key_len  >= QBC_KEY_MAX)  return -2;
    if (body_len <= 0 || body_len >= QBC_POST_MAX) return -3;

    memcpy(qbc_url,  url,  url_len);  qbc_url[url_len]  = '\0';
    memcpy(qbc_key,  key,  key_len);  qbc_key[key_len]  = '\0';
    memcpy(qbc_post, body, body_len); qbc_post_len = body_len;

    memcpy(qbc_hdr_key,  "apikey: ",              8);
    memcpy(qbc_hdr_key  + 8,  qbc_key, key_len); qbc_hdr_key[8  + key_len] = '\0';
    memcpy(qbc_hdr_auth, "Authorization: Bearer ", 22);
    memcpy(qbc_hdr_auth + 22, qbc_key, key_len); qbc_hdr_auth[22 + key_len] = '\0';

    qb64_http_cleanup_slist();
    intptr_t sl = curl_slist_append(0, "Content-Type: application/json");
    sl = curl_slist_append(sl, qbc_hdr_key);
    sl = curl_slist_append(sl, qbc_hdr_auth);
    sl = curl_slist_append(sl, "Prefer: return=minimal");
    qbc_slist = sl;

    qbc_body_len = 0; qbc_body[0] = '\0';
    qbc_hdrs_len = 0; qbc_hdrs[0] = '\0';

    curl_easy_setopt(easy, QBC_WRITEFUNCTION,  (qbc_write_fn)qbc_write_body);
    curl_easy_setopt(easy, QBC_HEADERFUNCTION, (qbc_write_fn)qbc_write_hdrs);
    curl_easy_setopt(easy, 10002, qbc_url);            /* CURLOPT_URL            */
    curl_easy_setopt(easy, 10015, qbc_post);           /* CURLOPT_POSTFIELDS     */
    curl_easy_setopt(easy, 60,    (long)body_len);     /* CURLOPT_POSTFIELDSIZE  */
    curl_easy_setopt(easy, 10023, (intptr_t)sl);       /* CURLOPT_HTTPHEADER     */
    curl_easy_setopt(easy, 13,    (long)5);            /* CURLOPT_TIMEOUT        */
    curl_easy_setopt(easy, 45,    (long)1);            /* CURLOPT_FAILONERROR    */

    return (int)curl_multi_add_handle(multi, easy);
}

/*
 * qb64_http_get -- configure curl for a GET request with apikey/Bearer auth headers.
 * Same stable-buffer pattern as qb64_http_post; no request body.
 */
static inline int qb64_http_get(
    intptr_t easy,   intptr_t multi,
    const char *url, int url_len,
    const char *key, int key_len
) {
    if (url_len <= 0 || url_len >= QBC_URL_MAX) return -1;
    if (key_len <= 0 || key_len >= QBC_KEY_MAX) return -2;

    memcpy(qbc_url, url, url_len); qbc_url[url_len] = '\0';
    memcpy(qbc_key, key, key_len); qbc_key[key_len] = '\0';

    memcpy(qbc_hdr_key,  "apikey: ",              8);
    memcpy(qbc_hdr_key  + 8,  qbc_key, key_len); qbc_hdr_key[8  + key_len] = '\0';
    memcpy(qbc_hdr_auth, "Authorization: Bearer ", 22);
    memcpy(qbc_hdr_auth + 22, qbc_key, key_len); qbc_hdr_auth[22 + key_len] = '\0';

    qb64_http_cleanup_slist();
    intptr_t sl = curl_slist_append(0, "Accept: application/json");
    sl = curl_slist_append(sl, qbc_hdr_key);
    sl = curl_slist_append(sl, qbc_hdr_auth);
    qbc_slist = sl;

    qbc_body_len = 0; qbc_body[0] = '\0';
    qbc_hdrs_len = 0; qbc_hdrs[0] = '\0';

    curl_easy_setopt(easy, QBC_WRITEFUNCTION,  (qbc_write_fn)qbc_write_body);
    curl_easy_setopt(easy, QBC_HEADERFUNCTION, (qbc_write_fn)qbc_write_hdrs);
    curl_easy_setopt(easy, 10002, qbc_url);            /* CURLOPT_URL            */
    curl_easy_setopt(easy, 10023, (intptr_t)sl);       /* CURLOPT_HTTPHEADER     */
    curl_easy_setopt(easy, 80,    (long)1);            /* CURLOPT_FOLLOWLOCATION */
    curl_easy_setopt(easy, 13,    (long)10);           /* CURLOPT_TIMEOUT        */

    return (int)curl_multi_add_handle(multi, easy);
}

#endif
