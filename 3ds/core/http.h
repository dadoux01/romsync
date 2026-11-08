/*
 * http.h - the HTTP transport used by the API client.
 *
 * The API client (api.c) builds requests and reads responses; a transport
 * function sends them. Two transports exist:
 *   - http_curl.c, with libcurl, on Linux and on the 3DS (portlib 3ds-curl);
 *   - a fake in-memory server in the unit tests (tests/fake_server.c).
 */
#ifndef RS_HTTP_H
#define RS_HTTP_H

#include <stddef.h>
#include <stdint.h>

#include "rs.h"

typedef struct {
    const char *name;
    const char *value;
} rs_http_header;

#define RS_HTTP_MAX_HEADERS 12

typedef struct {
    const char *method; /* "GET", "POST" */
    const char *url;
    rs_http_header headers[RS_HTTP_MAX_HEADERS];
    int header_count;
    const uint8_t *body;
    size_t body_len;
} rs_http_request;

typedef struct {
    int status;
    rs_buf body;
    /* The only response headers RomSync reads. */
    char date[64];            /* "Date": server clock */
    char content_sha256[65];  /* "X-Content-SHA256" of a downloaded save */
} rs_http_response;

/* Sends req and fills res. Returns RS_OK when the server answered, whatever
 * the HTTP status, and RS_ERR_OFFLINE when it could not be reached. */
typedef rs_status (*rs_http_send_fn)(void *ctx, const rs_http_request *req, rs_http_response *res,
                                     rs_error *err);

/* Adds a header to a request (ignored beyond RS_HTTP_MAX_HEADERS). */
void rs_http_add_header(rs_http_request *req, const char *name, const char *value);
void rs_http_response_free(rs_http_response *res);

/* libcurl transport (http_curl.c). ctx is unused (NULL). */
rs_status rs_http_curl_send(void *ctx, const rs_http_request *req, rs_http_response *res, rs_error *err);

#endif
