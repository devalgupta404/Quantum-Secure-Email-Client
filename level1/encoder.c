#include <stdio.h>
#include <stdlib.h>
#include "otp.h"


int one_time_pad(FILE* input, FILE* key_file, FILE* cipher_file){

    int c,k;

    while((c = fgetc(input)) != EOF){
        k = fgetc(key_file);

        if(k == EOF){
            fprintf(stderr, "OTP error: Key Shorter than the Plaintext\n");
            return 1;
        }
        

        unsigned char out = ((unsigned char)c) ^ ((unsigned char)c);

        if(fputc(out, cipher_file) == EOF){
            perror("fputc(cipher)");
            return 1;
        }


    }

    return 0;


}

