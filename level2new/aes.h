#ifndef AES_H
#define AES_H

#include <stdint.h>
#include <stddef.h>

#define AES_BLOCK_SIZE 16
#define AES128_ROUND_KEYS_SIZE 176  /* 11 * 16 */

#ifdef __cplusplus
extern "C" {
#endif

/* --- Core types --- */
typedef uint8_t state_t[4][4];

/* --- Low-level helpers (bytes/words) --- */
uint32_t sub_word(uint32_t w);
uint32_t rot_word(uint32_t w);
void xor_bytes(uint8_t *dst, const uint8_t *a, const uint8_t *b, size_t len);

/* --- State transforms (forward) --- */
void add_round_key(state_t s, const uint8_t *roundKey);
void sub_bytes(state_t s);
void shift_rows(state_t s);
void mix_columns(state_t s);

/* --- State transforms (inverse) --- */
void inv_sub_bytes(state_t s);
void inv_shift_rows(state_t s);
void inv_mix_columns(state_t s);

/* --- Conversions --- */
void state_from_bytes(state_t s, const uint8_t in[16]);  /* AES column-major */
void bytes_from_state(uint8_t out[16], const state_t s);

/* --- Key expansion --- */
void key_expansion_128(const uint8_t key[16], uint8_t roundKeys[AES128_ROUND_KEYS_SIZE]);

/* --- One-block cipher --- */
void aes_encrypt_block_128(uint8_t out[16], const uint8_t in[16], const uint8_t roundKeys[AES128_ROUND_KEYS_SIZE]);
void aes_decrypt_block_128(uint8_t out[16], const uint8_t in[16], const uint8_t roundKeys[AES128_ROUND_KEYS_SIZE]);

/* --- Modes & padding (CBC, PKCS#7) --- */
int  pkcs7_pad(const uint8_t *in, size_t in_len, uint8_t **out, size_t *out_len);
int  pkcs7_unpad(uint8_t *buf, size_t *len); /* in-place */

int  aes128_cbc_encrypt(const uint8_t *pt, size_t pt_len,
                        const uint8_t key[16], const uint8_t iv[16],
                        uint8_t **ct, size_t *ct_len);

int  aes128_cbc_decrypt(const uint8_t *ct, size_t ct_len,
                        const uint8_t key[16], const uint8_t iv[16],
                        uint8_t **pt, size_t *pt_len);

/* --- Aliases for your earlier names (so code compiles if you used them) --- */
#define byes_from_state bytes_from_state
#define aes_encrytion aes_encrypt_block_128
#define inv_shoftrows inv_shift_rows
#define inv_sub_btes  inv_sub_bytes
#define x_time        xtime

#ifdef __cplusplus
}
#endif

#endif /* AES_H */
