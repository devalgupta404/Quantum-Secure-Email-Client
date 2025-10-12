#include "aes.h"
#include "aes_gcm.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static int hex2bin_dyn(const char *hex, uint8_t **out, size_t *out_len) {
    size_t n = strlen(hex);
    if (n % 2) return -1;
    *out_len = n / 2;
    *out = (uint8_t*)malloc(*out_len);
    if (!*out) return -1;
    for (size_t i = 0; i < *out_len; ++i) {
        unsigned int v;
        if (sscanf(hex + 2*i, "%2x", &v) != 1) { free(*out); return -1; }
        (*out)[i] = (uint8_t)v;
    }
    return 0;
}
static int hex2bin_fixed(const char *hex, uint8_t *out, size_t need) {
    size_t n = strlen(hex);
    if (n != need*2) return -1;
    for (size_t i = 0; i < need; ++i) {
        unsigned int v; if (sscanf(hex + 2*i, "%2x", &v) != 1) return -1;
        out[i] = (uint8_t)v;
    }
    return 0;
}
static void bin2hex_line(const uint8_t *buf, size_t len) {
    for (size_t i = 0; i < len; ++i) printf("%02x", buf[i]);
    printf("\n");
}
static int read_all_stdin(uint8_t **out, size_t *out_len) {
    const size_t CH = 4096;
    size_t cap = CH, len = 0;
    uint8_t *buf = (uint8_t*)malloc(cap);
    if (!buf) return -1;
    for (;;) {
        if (len + CH > cap) { cap *= 2; uint8_t *nb = (uint8_t*)realloc(buf, cap); if (!nb){free(buf);return -1;} buf=nb; }
        size_t got = fread(buf+len,1,CH,stdin);
        len += got;
        if (got < CH) { if (feof(stdin)) break; free(buf); return -1; }
    }
    *out = buf; *out_len = len; return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr,
            "Usage:\n"
            "  Encrypt: %s <hex-16B-key> <hex-iv> [--aad HEX] < plaintext\n"
            "  Decrypt: %s <hex-16B-key> <hex-iv> --dec <HEXCT> <HEXTAG> [--aad HEX]\n"
            "  Decrypt (stdin): %s <hex-16B-key> <hex-iv> --dec-stdin <HEXTAG> [--aad HEX] < ciphertext_hex\n",
            argv[0], argv[0], argv[0]);
        return 1;
    }

    uint8_t key[16];
    if (hex2bin_fixed(argv[1], key, 16) != 0) { fprintf(stderr,"Bad key\n"); return 1; }

    uint8_t *iv=NULL; size_t iv_len=0;
    if (hex2bin_dyn(argv[2], &iv, &iv_len) != 0) { fprintf(stderr,"Bad IV\n"); return 1; }

    /* parse optional flags */
    const char *aad_hex = NULL;
    int decrypt_mode = 0;
    int decrypt_stdin_mode = 0;
    const char *ct_hex = NULL, *tag_hex = NULL;

    for (int i = 3; i < argc; ++i) {
        if (strcmp(argv[i], "--aad") == 0 && i+1 < argc) { aad_hex = argv[++i]; }
        else if (strcmp(argv[i], "--dec") == 0 && i+2 < argc) { decrypt_mode = 1; ct_hex = argv[++i]; tag_hex = argv[++i]; }
        else if (strcmp(argv[i], "--dec-stdin") == 0 && i+1 < argc) { decrypt_stdin_mode = 1; tag_hex = argv[++i]; }
    }

    uint8_t *aad = NULL; size_t aad_len = 0;
    if (aad_hex) {
        if (hex2bin_dyn(aad_hex, &aad, &aad_len) != 0) { fprintf(stderr,"Bad AAD\n"); return 1; }
    }

    int rc = 0;
    if (!decrypt_mode && !decrypt_stdin_mode) {
        uint8_t *pt=NULL; size_t pt_len=0;
        if (read_all_stdin(&pt, &pt_len) != 0) { fprintf(stderr,"Failed to read PT\n"); return 1; }

        uint8_t *ct=NULL; size_t ct_len=0; uint8_t tag[16];
        rc = aes128_gcm_encrypt(pt, pt_len, aad, aad_len, key, iv, iv_len, &ct, &ct_len, tag);
        if (rc != 0) { fprintf(stderr,"Encrypt failed\n"); free(pt); return 1; }

        printf("CIPHERTEXT_HEX:\n"); bin2hex_line(ct, ct_len);
        printf("TAG_HEX:\n");        bin2hex_line(tag, 16);

        free(pt); free(ct);
    } else if (decrypt_stdin_mode) {
        // Read ciphertext hex from stdin
        uint8_t *ct_hex_buf=NULL; size_t ct_hex_len=0;
        if (read_all_stdin(&ct_hex_buf, &ct_hex_len) != 0) { fprintf(stderr,"Failed to read CT from stdin\n"); return 1; }
        // Trim whitespace/newlines
        while (ct_hex_len > 0 && isspace(ct_hex_buf[ct_hex_len-1])) ct_hex_len--;
        ct_hex_buf[ct_hex_len] = '\0';

        uint8_t *ct=NULL; size_t ct_len=0;
        if (hex2bin_dyn((char*)ct_hex_buf, &ct, &ct_len) != 0) { fprintf(stderr,"Bad CT from stdin\n"); free(ct_hex_buf); return 1; }
        free(ct_hex_buf);

        uint8_t tag[16];
        if (hex2bin_fixed(tag_hex, tag, 16) != 0) { fprintf(stderr,"Bad TAG\n"); free(ct); return 1; }

        uint8_t *pt=NULL; size_t pt_len=0;
        rc = aes128_gcm_decrypt(ct, ct_len, aad, aad_len, key, iv, iv_len, tag, &pt, &pt_len);
        if (rc != 0) { fprintf(stderr,"Auth failed (bad tag)\n"); free(ct); return 2; }

        fwrite(pt, 1, pt_len, stdout);
        free(pt); free(ct);
    } else {
        uint8_t *ct=NULL; size_t ct_len=0;
        if (hex2bin_dyn(ct_hex, &ct, &ct_len) != 0) { fprintf(stderr,"Bad CT\n"); return 1; }
        uint8_t tag[16];
        if (hex2bin_fixed(tag_hex, tag, 16) != 0) { fprintf(stderr,"Bad TAG\n"); free(ct); return 1; }

        uint8_t *pt=NULL; size_t pt_len=0;
        rc = aes128_gcm_decrypt(ct, ct_len, aad, aad_len, key, iv, iv_len, tag, &pt, &pt_len);
        if (rc != 0) { fprintf(stderr,"Auth failed (bad tag)\n"); free(ct); return 2; }

        fwrite(pt, 1, pt_len, stdout); printf("\n");
        free(pt); free(ct);
    }

    free(aad); free(iv);
    return 0;
}
