#ifndef ADBLOCK_RUST_FFI_H
#define ADBLOCK_RUST_FFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AbrEngine AbrEngine;

typedef struct AbrByteBuffer {
  uint8_t* data;
  size_t len;
} AbrByteBuffer;

typedef struct AbrMatchResult {
  bool matched;
  bool important;
  bool has_exception;
  char* redirect;
  char* rewritten_url;
} AbrMatchResult;

typedef struct AbrContentBlockingRulesResult {
  bool ok;
  char* rules_json;
  bool truncated;
  char* error_message;
} AbrContentBlockingRulesResult;

AbrEngine* abr_engine_new(void);
AbrEngine* abr_engine_from_rules(const uint8_t* rules,
                                 size_t rules_len,
                                 char** error_message);
AbrEngine* abr_engine_from_serialized(const uint8_t* data,
                                      size_t data_len,
                                      char** error_message);
void abr_engine_destroy(AbrEngine* engine);

AbrMatchResult abr_engine_matches(const AbrEngine* engine,
                                  const char* url,
                                  const char* hostname,
                                  const char* source_hostname,
                                  const char* request_type,
                                  bool third_party_request,
                                  bool previously_matched_rule,
                                  bool force_check_exceptions);
void abr_match_result_destroy(AbrMatchResult result);

AbrByteBuffer abr_engine_serialize(const AbrEngine* engine);
void abr_free_byte_buffer(AbrByteBuffer buffer);
void abr_free_string(char* value);

AbrContentBlockingRulesResult
abr_content_blocking_rules_from_filter_set(const uint8_t* rules,
                                           size_t rules_len);
void abr_content_blocking_rules_result_destroy(
    AbrContentBlockingRulesResult result);

#ifdef __cplusplus
}
#endif

#endif
