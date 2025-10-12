#include "km_client.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int run_cmd(const char *cmd) {
    return system(cmd);
}

// Extract "X-Key-Id: VALUE" from a headers file
static int extract_key_id(const char *headers_path, char *out, size_t outsz) {
    FILE *f = fopen(headers_path, "rb");
    if (!f) return 1;
    char line[1024];
    int found = 0;
    while (fgets(line, sizeof(line), f)) {
        if (_strnicmp(line, "X-Key-Id:", 9) == 0 || strncmp(line, "X-Key-Id:", 9) == 0) {
            char *p = line + 9;
            while (*p==' ' || *p=='\t') p++;
            char *end = p + strlen(p);
            while (end>p && (end[-1]=='\r' || end[-1]=='\n')) end--;
            size_t len = (size_t)(end - p);
            if (len >= outsz) len = outsz - 1;
            memcpy(out, p, len);
            out[len] = '\0';
            found = 1; break;
        }
    }
    fclose(f);
    return found ? 0 : 1;
}

int km_fetch_new_key(size_t size, const char *key_out, const char *keyid_out) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd),
        "curl -sSf -D headers.tmp -o \"%s\" \"http://127.0.0.1:2020/otp/keys?size=%lu\"",
        key_out, (unsigned long)size);
    if (run_cmd(cmd) != 0) return 1;

    char keyid[256];
    if (extract_key_id("headers.tmp", keyid, sizeof(keyid)) != 0) {
        fprintf(stderr, "KM: failed to read Key-ID from headers.tmp\n");
        return 1;
    }
    FILE *f = fopen(keyid_out, "wb");
    if (!f) { perror("key_id.txt fopen"); return 1; }
    fprintf(f, "%s", keyid);
    fclose(f);
    remove("headers.tmp");
    return 0;
}

int km_fetch_key_by_id(const char *key_id, const char *key_out) {
    // strip trailing newlines/spaces if read from file
    char idclean[256]; size_t n = 0;
    while (*key_id && n < sizeof(idclean)-1) {
        if (*key_id=='\r' || *key_id=='\n') { key_id++; continue; }
        idclean[n++] = *key_id++;
    }
    idclean[n] = '\0';

    char cmd[1024];
    snprintf(cmd, sizeof(cmd),
        "curl -sSf -o \"%s\" \"http://127.0.0.1:2020/otp/keys/%s\"",
        key_out, idclean);
    if(run_cmd(cmd) != 0){
        fprintf(stderr, "KM: HTTP fetch failed (bad key_id or KM Down)\n");
    }
    return 0; // Adding for now
}
