/*
This file acts as the main orchestrator. From here, we will decide if the user wants to use Level 1,2,3 or Level 4

Input - Take the user input, the input file and make the user choose the Level 
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "level1/otp.h"
#include "level2/aes.h"
#include "Key_Manager/km_client.h"

static void usage(const char *prog) {
    fprintf(stderr,
      "Usage:\n"
      "  Level 1 (OTP via KM):\n"
      "    %s 1 enc <plain> <cipher.bin> <key_id.txt>\n"
      "    %s 1 dec <cipher.bin> <key_id.txt> <output>\n"
      "  Level 2 (AES-128-GCM):\n"
      "    %s 2 enc <plain> <cipher.qaes> <seed.key>\n"
      "    %s 2 dec <cipher.qaes> <seed.key> <output>\n",
      prog, prog, prog, prog);
}

// tiny helper to read exactly N bytes (key file)


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

        if (argc < 6) { usage(argv[0]); return 1; }

        if (strcmp(argv[2], "enc") == 0) {
            // ./qumail 1 enc <plain> <cipher.bin> <key_id.txt>
            const char *plain_path  = argv[3];
            const char *cipher_path = argv[4];
            const char *keyid_path  = argv[5];

            FILE *fplain = fopen(plain_path, "rb");
            FILE *fcipher = fopen(cipher_path, "wb");
            if (!fplain || !fcipher) { perror("fopen"); if(fplain)fclose(fplain); if(fcipher)fclose(fcipher); return 1; }

            // get plaintext size
            if (fseek(fplain, 0, SEEK_END) != 0) { perror("fseek"); fclose(fplain); fclose(fcipher); return 1; }
            long sz = ftell(fplain);
            if (sz < 0) { perror("ftell"); fclose(fplain); fclose(fcipher); return 1; }
            rewind(fplain);

            // fetch key of same size from KM -> key.bin + key_id.txt
            if (km_fetch_new_key((size_t)sz, "key.bin", keyid_path) != 0) {
                fprintf(stderr, "KM fetch new key failed\n");
                fclose(fplain); fclose(fcipher); return 1;
            }

            FILE *fkey = fopen("key.bin", "rb");
            if (!fkey) { perror("key.bin"); fclose(fplain); fclose(fcipher); return 1; }

            int rc = one_time_pad(fplain, fkey, fcipher);
            fclose(fplain); fclose(fkey); fclose(fcipher);
            if (rc != 0) { fprintf(stderr, "OTP encrypt failed\n"); return rc; }
            return 0;
        }


        const char *cipher_path = argv[3];
            const char *keyid_path  = argv[4];
            const char *out_path    = argv[5];

            // read key id
            char key_id[256] = {0};
            FILE *fid = fopen(keyid_path, "rb");
            if (!fid) { perror("key_id.txt"); return 1; }
            fgets(key_id, sizeof(key_id), fid);
            fclose(fid);

            // fetch key by id -> key.bin
            if (km_fetch_key_by_id(key_id, "key.bin") != 0) {
                fprintf(stderr, "KM fetch key by id failed\n");
                return 1;
            }

            // check sizes: key.bin must equal cipher.bin
            FILE *fc = fopen(cipher_path, "rb"); fseek(fc, 0, SEEK_END); long clen = ftell(fc); fclose(fc);
            FILE *fk = fopen("key.bin", "rb");  fseek(fk, 0, SEEK_END); long klen = ftell(fk); fclose(fk);
            if (klen != clen) {
                fprintf(stderr, "KM key length (%ld) != ciphertext length (%ld)\n", klen, clen);
                return 1;
        }

            FILE *fcipher = fopen(cipher_path, "rb");
            FILE *fkey    = fopen("key.bin", "rb");
            FILE *fout    = fopen(out_path, "wb");
            if (!fcipher || !fkey || !fout) { perror("fopen"); if(fcipher)fclose(fcipher); if(fkey)fclose(fkey); if(fout)fclose(fout); return 1; }

            int rc = one_time_pad_decoder(fkey, fcipher, fout);
            fclose(fcipher); fclose(fkey); fclose(fout);
            if (rc != 0) { fprintf(stderr, "OTP decrypt failed (key mismatch/short?)\n"); return rc; }
            return 0;
        }
/*
    else if (level == 2) {
        if (argc < 6) { usage(argv[0]); return 1; }

        if (strcmp(argv[2], "enc") == 0) {
            const char *plain  = argv[3];
            const char *cipher = argv[4];
            const char *keyf   = argv[5];
            unsigned char key16[16];
            if (read_exact_key(keyf, key16, 16)) return 1;
            int rc = qaes_encrypt_file(plain, cipher, key16);
            if (rc != 0) { fprintf(stderr, "AES-GCM encrypt failed\n"); return rc; }
            return 0;
        } else if (strcmp(argv[2], "dec") == 0) {
            const char *cipher = argv[3];
            const char *keyf   = argv[4];
            const char *out    = argv[5];
            unsigned char key16[16];
            if (read_exact_key(keyf, key16, 16)) return 1;
            int rc = qaes_decrypt_file(cipher, out, key16);
            if (rc != 0) { fprintf(stderr, "AES-GCM decrypt failed (auth?)\n"); return rc; }
            return 0;
        } else { usage(argv[0]); return 1; }
    }
        */

    else {
        fprintf(stderr, "Level %d not implemented yet.\n", level);
        usage(argv[0]);
        return 1;
    }
}