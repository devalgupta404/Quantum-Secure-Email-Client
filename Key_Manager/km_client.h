#ifndef KM_CLIENT_H
#define KM_CLIENT_H
#include <stddef.h>

// Ask KM for `size` random bytes. Writes bytes to key_out_path,
// and write the key id into keyid_out_path (text file).
int km_fetch_new_key(size_t size, const char *key_out_path, const char *keyid_out_path);

// Get the key bytes by key id (string from key_id.txt). Writes bytes to key_out_path.
int km_fetch_key_by_id(const char *key_id, const char *key_out_path);

#endif
