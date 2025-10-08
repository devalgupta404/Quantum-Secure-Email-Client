#include "aes.h"
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <stdlib.h>

/* Parse hex string (even length) into bytes */
static int hex2bin(const char *hex, uint8_t *out, size_t out_cap) {
    size_t n = strlen(hex);
    if (n % 2) return -1;
    size_t bytes = n / 2;
    if (bytes > out_cap) return -1;
    for (size_t i = 0; i < bytes; ++i) {
        unsigned int v;
        if (sscanf(hex + 2*i, "%2x", &v) != 1) return -1;
        out[i] = (uint8_t)v;
    }
    return (int)bytes;
}

/* Print buffer as lowercase hex */
static void bin2hex(const uint8_t *buf, size_t len) {
    for (size_t i = 0; i < len; ++i) printf("%02x", buf[i]);
    printf("\n");
}

/* Slurp all of stdin into a malloc'd buffer (binary-safe) */
static int read_all_stdin(uint8_t **out, size_t *out_len) {
    const size_t CHUNK = 4096;
    size_t cap = CHUNK, len = 0;
    uint8_t *buf = (uint8_t*)malloc(cap);
    if (!buf) return -1;

    for (;;) {
        if (len + CHUNK > cap) {
            size_t ncap = cap * 2;
            uint8_t *nbuf = (uint8_t*)realloc(buf, ncap);
            if (!nbuf) { free(buf); return -1; }
            buf = nbuf; cap = ncap;
        }
        size_t got = fread(buf + len, 1, CHUNK, stdin);
        len += got;
        if (got < CHUNK) {
            if (feof(stdin)) break;
            free(buf); return -1;
        }
    }
    *out = buf; *out_len = len;
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <hex-16-byte-key> <hex-16-byte-iv>\n", argv[0]);
        fprintf(stderr, "Example key: 000102030405060708090a0b0c0d0e0f\n");
        fprintf(stderr, "Example  iv: 0f0e0d0c0b0a09080706050403020100\n");
        return 1;
    }

    uint8_t key[16], iv[16];
    int klen = hex2bin(argv[1], key, sizeof(key));
    int ivlen = hex2bin(argv[2], iv, sizeof(iv));
    if (klen != 16 || ivlen != 16) {
        fprintf(stderr, "Key/IV must be exactly 16 bytes (32 hex chars).\n");
        return 1;
    }

    /* Read plaintext (email body) from stdin */
    uint8_t *pt = NULL, *ct = NULL, *dec = NULL;
    size_t pt_len = 0, ct_len = 0, dec_len = 0;

    if (read_all_stdin(&pt, &pt_len) != 0) {
        fprintf(stderr, "Failed to read plaintext from stdin.\n");
        return 1;
    }

    /* Encrypt */
    if (aes128_cbc_encrypt(pt, pt_len, key, iv, &ct, &ct_len) != 0) {
        fprintf(stderr, "Encryption failed.\n");
        free(pt);
        return 1;
    }

    /* Decrypt (for demo/verification) */
    if (aes128_cbc_decrypt(ct, ct_len, key, iv, &dec, &dec_len) != 0) {
        fprintf(stderr, "Decryption failed.\n");
        free(pt); free(ct);
        return 1;
    }

    /* Output */
    printf("CIPHERTEXT_HEX:\n");
    bin2hex(ct, ct_len);

    printf("PLAINTEXT_RECOVERED:\n");
    fwrite(dec, 1, dec_len, stdout);
    printf("\n");

    free(pt); free(ct); free(dec);
    return 0;
}
