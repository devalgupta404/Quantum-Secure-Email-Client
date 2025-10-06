#include "aes.h"
#include "aes_gcm.h"
#include <string.h>
#include <stdlib.h>

/* ---------- Helpers: big-endian put, consttime cmp, inc32(Y) ---------- */
static void be_store64(uint8_t out[8], uint64_t v) {
    for (int i = 7; i >= 0; --i) { out[i] = (uint8_t)(v & 0xFF); v >>= 8; }
}
static int consttime_eq16(const uint8_t *a, const uint8_t *b) {
    uint8_t x = 0; for (int i = 0; i < 16; ++i) x |= (uint8_t)(a[i] ^ b[i]); return x == 0;
}
static void inc32(uint8_t y[16]) {
    uint32_t n = ((uint32_t)y[12]<<24) | ((uint32_t)y[13]<<16) | ((uint32_t)y[14]<<8) | (uint32_t)y[15];
    n = n + 1;
    y[12] = (uint8_t)(n>>24); y[13]=(uint8_t)(n>>16); y[14]=(uint8_t)(n>>8); y[15]=(uint8_t)n;
}

/* ---------- GHASH multiply in GF(2^128): bit-by-bit per SP800-38D ---------- */
/* R = 0xe1 || 0^120 */
static void gcm_mult(uint8_t X[16], const uint8_t Y[16]) {
    uint8_t Z[16] = {0};
    uint8_t V[16]; memcpy(V, Y, 16);

    for (int i = 0; i < 16; ++i) {
        uint8_t x = X[i];
        for (int b = 7; b >= 0; --b) {
            /* if bit is 1, Z = Z XOR V */
            if ((x >> b) & 1) for (int j = 0; j < 16; ++j) Z[j] ^= V[j];
            /* if LSB(V) == 1, then (V >> 1) ^ Rshift */
            int lsb = V[15] & 1;
            /* shift V right by 1 */
            for (int j = 15; j > 0; --j) V[j] = (uint8_t)((V[j] >> 1) | ((V[j-1] & 1) << 7));
            V[0] >>= 1;
            if (lsb) V[0] ^= 0xe1;
        }
    }
    memcpy(X, Z, 16);
}

/* GHASH over A (AAD) and C (ciphertext) with H */
static void ghash(const uint8_t H[16],
                  const uint8_t *A, size_t Alen,
                  const uint8_t *C, size_t Clen,
                  uint8_t S[16])
{
    uint8_t Y[16] = {0};
    uint8_t Hcopy[16]; memcpy(Hcopy, H, 16);

    /* process AAD in 16-byte blocks */
    for (size_t off = 0; off < Alen; off += 16) {
        uint8_t blk[16] = {0};
        size_t n = (Alen - off >= 16) ? 16 : (Alen - off);
        memcpy(blk, A + off, n);
        for (int i = 0; i < 16; ++i) Y[i] ^= blk[i];
        uint8_t Ht[16]; memcpy(Ht, Hcopy, 16);
        gcm_mult(Y, Ht);
    }

    /* process C in 16-byte blocks */
    for (size_t off = 0; off < Clen; off += 16) {
        uint8_t blk[16] = {0};
        size_t n = (Clen - off >= 16) ? 16 : (Clen - off);
        memcpy(blk, C + off, n);
        for (int i = 0; i < 16; ++i) Y[i] ^= blk[i];
        uint8_t Ht[16]; memcpy(Ht, Hcopy, 16);
        gcm_mult(Y, Ht);
    }

    /* lengths block: |A|_64 || |C|_64 in bits */
    uint8_t lenblk[16] = {0};
    be_store64(lenblk, (uint64_t)Alen * 8);
    be_store64(lenblk + 8, (uint64_t)Clen * 8);
    for (int i = 0; i < 16; ++i) Y[i] ^= lenblk[i];
    uint8_t Ht[16]; memcpy(Ht, Hcopy, 16);
    gcm_mult(Y, Ht);

    memcpy(S, Y, 16);
}

/* GCTR: out = AES-CTR starting from ICB, processing input Len bytes */
static void gctr(const uint8_t key[16], const uint8_t ICB[16],
                 const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len == 0) return;
    uint8_t counter[16]; memcpy(counter, ICB, 16);

    uint8_t rk[AES128_ROUND_KEYS_SIZE];
    key_expansion_128(key, rk);

    size_t off = 0;
    while (off < in_len) {
        uint8_t Ek[16]; aes_encrypt_block_128(Ek, counter, rk);
        size_t n = (in_len - off >= 16) ? 16 : (in_len - off);
        for (size_t i = 0; i < n; ++i) out[off + i] = in[off + i] ^ Ek[i];
        off += n;
        inc32(counter);
    }
}

/* J0 derivation:
   - if iv_len == 12: J0 = IV || 0x00000001
   - else: J0 = GHASH_H(A={}, C=IV) */
static void derive_J0(const uint8_t H[16],
                      const uint8_t *iv, size_t iv_len,
                      uint8_t J0[16])
{
    if (iv_len == 12) {
        memcpy(J0, iv, 12);
        J0[12]=0; J0[13]=0; J0[14]=0; J0[15]=1;
    } else {
        ghash(H, NULL, 0, iv, iv_len, J0);
    }
}

int aes128_gcm_encrypt(const uint8_t *pt, size_t pt_len,
                       const uint8_t *aad, size_t aad_len,
                       const uint8_t key[16],
                       const uint8_t *iv, size_t iv_len,
                       uint8_t **ct, size_t *ct_len,
                       uint8_t tag[16])
{
    if (!pt && pt_len) return -1;
    if (!iv || iv_len == 0) return -1;

    *ct = (uint8_t*)malloc(pt_len);
    if (!*ct && pt_len) return -1;
    *ct_len = pt_len;

    /* H = E_k(0^128) */
    uint8_t rk[AES128_ROUND_KEYS_SIZE];
    key_expansion_128(key, rk);

    uint8_t H[16] = {0}, zero[16] = {0};
    aes_encrypt_block_128(H, zero, rk);

    /* J0 */
    uint8_t J0[16]; derive_J0(H, iv, iv_len, J0);

    /* C = GCTR_k(inc32(J0), P) */
    uint8_t ICB[16]; memcpy(ICB, J0, 16); inc32(ICB);
    if (pt_len) gctr(key, ICB, pt, pt_len, *ct);

    /* S = GHASH_H(A, C) */
    uint8_t S[16]; ghash(H, aad, aad_len, *ct, pt_len, S);

    /* T = MSB_128( GCTR_k(J0, S) ) == E_k(J0) XOR S */
    uint8_t EkJ0[16]; aes_encrypt_block_128(EkJ0, J0, rk);
    for (int i = 0; i < 16; ++i) tag[i] = (uint8_t)(EkJ0[i] ^ S[i]);

    return 0;
}

int aes128_gcm_decrypt(const uint8_t *ct, size_t ct_len,
                       const uint8_t *aad, size_t aad_len,
                       const uint8_t key[16],
                       const uint8_t *iv, size_t iv_len,
                       const uint8_t tag[16],
                       uint8_t **pt, size_t *pt_len)
{
    if (!iv || iv_len == 0) return -1;

    *pt = (uint8_t*)malloc(ct_len);
    if (!*pt && ct_len) return -1;
    *pt_len = ct_len;

    /* H = E_k(0^128) */
    uint8_t rk[AES128_ROUND_KEYS_SIZE];
    key_expansion_128(key, rk);

    uint8_t H[16] = {0}, zero[16] = {0};
    aes_encrypt_block_128(H, zero, rk);

    /* J0 */
    uint8_t J0[16]; derive_J0(H, iv, iv_len, J0);

    /* Compute expected tag using C (per spec) */
    uint8_t S[16]; ghash(H, aad, aad_len, ct, ct_len, S);
    uint8_t EkJ0[16]; aes_encrypt_block_128(EkJ0, J0, rk);
    uint8_t tag_exp[16];
    for (int i = 0; i < 16; ++i) tag_exp[i] = (uint8_t)(EkJ0[i] ^ S[i]);

    /* Constant-time compare */
    if (!consttime_eq16(tag, tag_exp)) {
        free(*pt); *pt = NULL; *pt_len = 0;
        return -1; /* auth fail */
    }

    /* P = GCTR_k(inc32(J0), C) */
    uint8_t ICB[16]; memcpy(ICB, J0, 16); inc32(ICB);
    if (ct_len) gctr(key, ICB, ct, ct_len, *pt);

    return 0;
}
