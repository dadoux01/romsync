/*
 * http_curl.c - HTTP transport with libcurl (see http.h).
 *
 * The same file runs on Linux (system libcurl) and on the 3DS (devkitPro's
 * 3ds-curl portlib). On the 3DS, the app must start the network (socInit)
 * and call curl_global_init once before the first request.
 */
#include <curl/curl.h>
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>

#include "http.h"

/* libcurl hands the body over in pieces: append them to the buffer. */
static size_t on_body(char *data, size_t size, size_t count, void *userdata)
{
    rs_buf *body = userdata;
    return rs_buf_append(body, data, size * count) ? size * count : 0;
}

/* Copies the value of a "Name: value\r\n" header line when the name
 * matches (case-insensitive). */
static void header_value(const char *line, size_t len, const char *name, char *out, size_t size)
{
    size_t n = strlen(name);
    if (len <= n || strncasecmp(line, name, n) != 0 || line[n] != ':')
        return;
    const char *v = line + n + 1;
    const char *end = line + len;
    while (v < end && isspace((unsigned char)*v))
        v++;
    while (end > v && isspace((unsigned char)end[-1]))
        end--;
    size_t k = (size_t)(end - v);
    if (k >= size)
        k = size - 1;
    memcpy(out, v, k);
    out[k] = 0;
}

static size_t on_header(char *line, size_t size, size_t count, void *userdata)
{
    rs_http_response *res = userdata;
    size_t len = size * count;
    header_value(line, len, "Date", res->date, sizeof res->date);
    header_value(line, len, "X-Content-SHA256", res->content_sha256, sizeof res->content_sha256);
    return len;
}

rs_status rs_http_curl_send(void *ctx, const rs_http_request *req, rs_http_response *res, rs_error *err)
{
    (void)ctx;
    CURL *curl = curl_easy_init();
    if (!curl)
        return rs_fail(err, RS_ERR_NOMEM, "Initialisation réseau impossible");

    struct curl_slist *headers = NULL;
    char line[512];
    for (int i = 0; i < req->header_count; i++) {
        /* "Name;" sends a header with an empty value ("Name:" would remove
         * it), e.g. X-Base-Version for a first save. */
        if (req->headers[i].value[0])
            snprintf(line, sizeof line, "%s: %s", req->headers[i].name, req->headers[i].value);
        else
            snprintf(line, sizeof line, "%s;", req->headers[i].name);
        headers = curl_slist_append(headers, line);
    }
    /* No "Expect: 100-continue" round trip before uploads. */
    headers = curl_slist_append(headers, "Expect:");

    curl_easy_setopt(curl, CURLOPT_URL, req->url);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, req->method);
    if (strcmp(req->method, "POST") == 0) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, req->body ? (const char *)req->body : "");
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)req->body_len);
    }
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, on_body);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &res->body);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, on_header);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, res);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "RomSync-3DS");
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    /* The 3DS Wi-Fi is slow: generous total time, short connection time so
     * that an absent server is detected quickly. */
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 8L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 120L);

    CURLcode rc = curl_easy_perform(curl);
    rs_status st = RS_OK;
    if (rc == CURLE_OK) {
        long status = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
        res->status = (int)status;
    } else {
        st = rs_fail(err, RS_ERR_OFFLINE, "Serveur injoignable (%s)", curl_easy_strerror(rc));
    }
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return st;
}
