#include <stdio.h>
#include <stdlib.h>
#include "otp.h"


int one_time_pad(FILE* input, FILE* key_file, FILE* cipher_file){

    int c;

    while((c = fgetc(input)) != EOF){
        unsigned char k = rand() % 256;
        // When using KM, please keep a check for when the keys are shorter in length than the plaintext

        unsigned char ans = ((unsigned char)k) ^ ((unsigned char)c);

        fputc(k, key_file);
        fputc(ans, cipher_file);


    }

    return 0;


}

