#ifndef MD_FFI_H
#define MD_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

char *md_render(const char *markdown_utf8, const char *options_json);
void md_free_result(char *result_ptr);
const char *md_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
