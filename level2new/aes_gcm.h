#ifndef AES_GCM_H
#define AES_GCM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* AES-128-GCM with 128-bit tag */
int aes128_gcm_encrypt(const uint8_t *pt, size_t pt_len,
                       const uint8_t *aad, size_t aad_len,
                       const uint8_t key[16],
                       const uint8_t *iv, size_t iv_len,
                       uint8_t **ct, size_t *ct_len,
                       uint8_t tag[16]);

int aes128_gcm_decrypt(const uint8_t *ct, size_t ct_len,
                       const uint8_t *aad, size_t aad_len,
                       const uint8_t key[16],
                       const uint8_t *iv, size_t iv_len,
                       const uint8_t tag[16],
                       uint8_t **pt, size_t *pt_len);

#ifdef __cplusplus
}
#endif
#endif /* AES_GCM_H */
