#ifndef __CRYPTO_HELPER__
#define __CRYPTO_HELPER__

#include <openssl/evp.h>

unsigned char *aes128_cbc_decrypt_base64(char *b64_encrypted_message);

#endif //__CRYPTO_HELPER__
