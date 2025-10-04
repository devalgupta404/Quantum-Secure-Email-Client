#include <stdio.h>
#include <stdlib.h>
#include "otp.h"

//otp.h

int one_time_pad_decoder(FILE* key_file, FILE* cipher_file, FILE* output){

    // We need to take the key_file adn the cipher_file and take their XOR again to get the output

    int k;
    int c;

    while((c = fgetc(cipher_file)) != EOF){
        k = fgetc(key_file);

        if(k == EOF){
            fprintf(stderr, "Key File shorter than the ciphertext\n");
            return 1;
        }

        


        unsigned char out = ((unsigned char)c) ^ ((unsigned char)k);

        if(fputc(out, output) == EOF){
            perror("putc(output)");
            return 1;
        }
    }

    return 0;
}