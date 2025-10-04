//otp.h

#ifndef OTP_H
#define OTP_H

#include <stdio.h>

// XOR plaintext with key -> write ciphertext
// Returns 0 on success, non-zero on error.
int one_time_pad(FILE *input, FILE *key_file, FILE *cipher_file);

// XOR ciphertext with key -> write plaintext (same operation)
int one_time_pad_decoder(FILE *key_file, FILE *cipher_file, FILE *output);

#endif