#include <string.h>
#include <strings.h>
#include <stdlib.h>

#include "crypto_helper.h"

static size_t calcDecodeLength(char *b64input)
{
    size_t len = strlen(b64input), padding = 0;
    if (b64input[len - 1] == '=' && b64input[len - 2] == '=') //last two chars are =
        padding = 2;
    else if (b64input[len - 1] == '=') //last char is =
        padding = 1;
    return (len * 3) / 4 - padding;
}

static void Base64Decode(char *b64message, unsigned char **buffer, size_t *length)
{
    BIO *bio, *b64;
    int decodeLen = calcDecodeLength(b64message);
    *buffer = (unsigned char* )malloc(decodeLen + 1);
    (*buffer)[decodeLen] = '\0';
    bio = BIO_new_mem_buf(b64message, -1);
    b64 = BIO_new(BIO_f_base64());
    bio = BIO_push(b64, bio);
    *length = BIO_read(bio, *buffer, strlen(b64message));
    BIO_free_all(bio);
}

static unsigned char *decrypt(unsigned char *ciphertext,
                     int ciphertext_len,
                     unsigned char *key,
                     unsigned char *iv)
{
    EVP_CIPHER_CTX *ctx;
    unsigned char *plaintexts;
    int len;
    int plaintext_len;
    unsigned char *plaintext = (unsigned char* )malloc(ciphertext_len);
    bzero(plaintext, ciphertext_len);

    if (!(ctx = EVP_CIPHER_CTX_new()))
        goto err_out;

    if (1 != EVP_DecryptInit_ex(ctx, EVP_aes_128_cbc(), NULL, key, iv))
        goto err_out;

    EVP_CIPHER_CTX_set_key_length(ctx, EVP_MAX_KEY_LENGTH);

    if (1 != EVP_DecryptUpdate(ctx, plaintext, &len, ciphertext, ciphertext_len))
        goto err_out;

    plaintext_len = len;

    if (1 != EVP_DecryptFinal_ex(ctx, plaintext + len, &len))
        goto err_out;

    plaintext_len += len;
    plaintext[plaintext_len] = 0;

    EVP_CIPHER_CTX_free(ctx);
    return plaintext;

err_out:
    if (ctx) EVP_CIPHER_CTX_free(ctx);
    if (plaintext) free (plaintext);

    return NULL;
}

unsigned char *aes128_cbc_decrypt_base64(char *b64_encrypted_message)
{
    unsigned char* encrypted_buffer;
    size_t encrypted_length;

    // f2b66e95e0fc91fec78fee5487be12139f0a4a919b9e31b5acabf5759e249f3b: sha256sum of "threereality"
    unsigned char key[] = {0xf2, 0xb6, 0x6e, 0x95, 0xe0, 0xfc, 0x91, 0xfe, 0xc7, 0x8f, 0xee, 0x54, 0x87, 0xbe, 0x12, 0x13};
    unsigned char iv[] = {0x9f, 0x0a, 0x4a, 0x91, 0x9b, 0x9e, 0x31, 0xb5, 0xac, 0xab, 0xf5, 0x75, 0x9e, 0x24, 0x9f, 0x3b};
    
//    printf("b64_encrypted_message: %s\n", b64_encrypted_message);

    Base64Decode(b64_encrypted_message, &encrypted_buffer, &encrypted_length);

//    printf("encrypted_length: %lu\n", encrypted_length);

    unsigned char* plaintext = decrypt(encrypted_buffer, encrypted_length, key, iv);
//    printf("plaintext: %s\n", plaintext);
    return plaintext;
}
