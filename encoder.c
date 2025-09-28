#include <stdio.h>
#include <stdlib.h>



void one_time_pad(FILE* input, FILE* key_file, FILE* cipher_file){

    int c;

    while((c = fgetc(input)) != EOF){
        int key = rand();

        int cipher = c ^ key;

        fputc(key, key_file);
        fputc(cipher, cipher_file);
    }


}

int main(int argc, char* argv[]){

    if(argc != 2){
        printf("Usage %s <input_file>\n", argv[0]);

        return 1;
    }   

    char* input_text_file = argv[1];

    FILE* text_file = fopen(input_text_file, "r");

    if(text_file == NULL){
        perror("Could not open the file");
        
        return 1;
    }

    FILE* key_file = fopen("key.out", "w");

    if(key_file == NULL){
        perror("Could not open the key file");

        return 1;
    }

    FILE* cipher_text = fopen("cipher.out", "w");

    if(cipher_text == NULL){
        perror("Could not open the cipher text file");

        return 1;
    }

    one_time_pad(text_file, key_file, cipher_text);

    fclose(text_file);

    fclose(key_file);

    fclose(cipher_text);



    
}