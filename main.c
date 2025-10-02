/*
This file acts as the main orchestrator. From here, we will decide if the user wants to use Level 1,2,3 or Level 4

Input - Take the user input, the input file and make the user choose the Level 
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "otp.h"



int main(int argc, char *argv[]){
    // We are going to have 3 levels in this solution. Level 1 - OTP with QKD. We need an integer, one input file, so 2 arguments

    // argc should be 2 and argv[0] = main.c, argv[1] = integer, argc[2] = input text file

    if(argc <  2){
        printf("Usage %s <Level> <input file> ", argv[0]);

        return 1;
    }

    // Check which level does the user want.

    int level = atoi(argv[1]);

    if(level == 1){
        if(strcmp(argv[2], "enc") == 0){
            FILE *fplain = fopen(argv[3], "rb");
            FILE *fcipher = fopen(argv[4], "wb");
            FILE* fkey = fopen("key.out", "wb");

            if(fplain == NULL || (fcipher == NULL)){
                perror("Some trouble in opening the file\n");

                return 1;
            }

            one_time_pad(fplain, fkey, fcipher);

            fclose(fplain);
            fclose(fcipher);
            fclose(fkey);
        }
        else if(strcmp(argv[2], "dec") == 0){
            FILE* fcipher = fopen(argv[3], "rb");
            FILE* fkey = fopen(argv[4], "rb");
            FILE* fout = fopen(argv[5], "wb");

            one_time_pad_decoder(fkey, fcipher, fout);

            fclose(fkey);
            fclose(fcipher);
            fclose(fout);
        }
    }
}