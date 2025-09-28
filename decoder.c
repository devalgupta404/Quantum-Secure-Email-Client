#include <stdio.h>
#include <stdlib.h>

void one_time_pad_decoder(FILE* key_file, FILE* cipher_file, FILE* output_file){

    // We need to take the key_file adn the cipher_file and take their XOR again to get the output

    int k;
    int c;

    while((k = fgetc(key_file)) != EOF  && ((c = fgetc(cipher_file)) != EOF)){
        int result = k ^ c;

        fputc(result, output_file);
    }
}

int main(int argc, char* argv[]){
    // We need to take two input files, so argc = 3.

    /*
    We need to take key.out and cipher.out file as the input. 

    We will create a new file decoded.txt file as the output file

    We will create a decoder function which XOR the characters of key.out and cipher.out

    This result will then be stored inside output.txt file using fputc function just like we did in encoder.c
    */

    if(argc != 3){
        printf("Use %s <key.out> <cipher.out> format as the input\n", argv[0]);

        return 1;
    }

    char* key = argv[1];

    char* cipher = argv[2];

    FILE* key_file = fopen(key, "rb");

    FILE* cipher_file = fopen(cipher, "rb");

    if(key_file == NULL){
        perror("Could not open the key_file");

        return 1;
    }

    else if(cipher_file == NULL){
        perror("Could not open the cipher_file");

        return 1;
    }

    FILE* output = fopen("decoded.txt", "wb");

    if(output == NULL){
        perror("Could not open the output file");

        return 1;
    }

    one_time_pad_decoder(key_file, cipher_file, output);

    fclose(key_file);
    fclose(cipher_file);

    fclose(output);




}