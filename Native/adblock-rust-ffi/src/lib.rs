use adblock::lists::{FilterSet, ParseOptions, RuleTypes};
use adblock::request::Request;
use adblock::Engine;
use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::slice;

const MAX_IOS_CONTENT_BLOCKER_RULES: usize = 150_000;

#[repr(C)]
pub struct AbrByteBuffer {
    data: *mut u8,
    len: usize,
}

#[repr(C)]
pub struct AbrMatchResult {
    matched: bool,
    important: bool,
    has_exception: bool,
    redirect: *mut c_char,
    rewritten_url: *mut c_char,
}

#[repr(C)]
pub struct AbrContentBlockingRulesResult {
    ok: bool,
    rules_json: *mut c_char,
    truncated: bool,
    error_message: *mut c_char,
}

pub struct AbrEngine {
    engine: Engine,
}

fn empty_c_string() -> *mut c_char {
    CString::new("").unwrap().into_raw()
}

fn string_to_c(value: String) -> *mut c_char {
    CString::new(value)
        .unwrap_or_else(|_| CString::new("").unwrap())
        .into_raw()
}

unsafe fn c_str<'a>(value: *const c_char) -> Option<&'a str> {
    if value.is_null() {
        return None;
    }
    CStr::from_ptr(value).to_str().ok()
}

unsafe fn bytes<'a>(data: *const u8, len: usize) -> Option<&'a [u8]> {
    if data.is_null() && len != 0 {
        return None;
    }
    Some(slice::from_raw_parts(data, len))
}

fn engine_from_rules(rules: &str) -> Engine {
    let mut filter_set = FilterSet::new(false);
    filter_set.add_filter_list(rules, ParseOptions::default());
    Engine::from_filter_set(filter_set, true)
}

#[no_mangle]
pub extern "C" fn abr_engine_new() -> *mut AbrEngine {
    Box::into_raw(Box::new(AbrEngine {
        engine: Engine::default(),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn abr_engine_from_rules(
    rules: *const u8,
    rules_len: usize,
    error_message: *mut *mut c_char,
) -> *mut AbrEngine {
    let Some(rules) = bytes(rules, rules_len) else {
        if !error_message.is_null() {
            *error_message = string_to_c("rules pointer was null".to_string());
        }
        return ptr::null_mut();
    };

    let Ok(rules) = std::str::from_utf8(rules) else {
        if !error_message.is_null() {
            *error_message = string_to_c("rules were not valid UTF-8".to_string());
        }
        return ptr::null_mut();
    };

    Box::into_raw(Box::new(AbrEngine {
        engine: engine_from_rules(rules),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn abr_engine_from_serialized(
    data: *const u8,
    data_len: usize,
    error_message: *mut *mut c_char,
) -> *mut AbrEngine {
    let Some(data) = bytes(data, data_len) else {
        if !error_message.is_null() {
            *error_message = string_to_c("serialized data pointer was null".to_string());
        }
        return ptr::null_mut();
    };

    let mut engine = Engine::default();
    match engine.deserialize(data) {
        Ok(()) => Box::into_raw(Box::new(AbrEngine { engine })),
        Err(error) => {
            if !error_message.is_null() {
                *error_message = string_to_c(format!("{error:?}"));
            }
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn abr_engine_destroy(engine: *mut AbrEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[no_mangle]
pub unsafe extern "C" fn abr_engine_matches(
    engine: *const AbrEngine,
    url: *const c_char,
    hostname: *const c_char,
    source_hostname: *const c_char,
    request_type: *const c_char,
    third_party_request: bool,
    previously_matched_rule: bool,
    force_check_exceptions: bool,
) -> AbrMatchResult {
    if engine.is_null() {
        return AbrMatchResult {
            matched: false,
            important: false,
            has_exception: false,
            redirect: empty_c_string(),
            rewritten_url: empty_c_string(),
        };
    }

    let Some(url) = c_str(url) else {
        return AbrMatchResult {
            matched: false,
            important: false,
            has_exception: false,
            redirect: empty_c_string(),
            rewritten_url: empty_c_string(),
        };
    };
    let Some(hostname) = c_str(hostname) else {
        return AbrMatchResult {
            matched: false,
            important: false,
            has_exception: false,
            redirect: empty_c_string(),
            rewritten_url: empty_c_string(),
        };
    };
    let Some(source_hostname) = c_str(source_hostname) else {
        return AbrMatchResult {
            matched: false,
            important: false,
            has_exception: false,
            redirect: empty_c_string(),
            rewritten_url: empty_c_string(),
        };
    };
    let Some(request_type) = c_str(request_type) else {
        return AbrMatchResult {
            matched: false,
            important: false,
            has_exception: false,
            redirect: empty_c_string(),
            rewritten_url: empty_c_string(),
        };
    };

    let result = (*engine).engine.check_network_request_subset(
        &Request::preparsed(
            url,
            hostname,
            source_hostname,
            request_type,
            third_party_request,
        ),
        previously_matched_rule,
        force_check_exceptions,
    );

    AbrMatchResult {
        matched: result.matched,
        important: result.important,
        has_exception: result.exception.is_some(),
        redirect: result
            .redirect
            .map(string_to_c)
            .unwrap_or_else(empty_c_string),
        rewritten_url: result.rewritten_url.map(string_to_c).unwrap_or_else(empty_c_string),
    }
}

#[no_mangle]
pub unsafe extern "C" fn abr_engine_serialize(engine: *const AbrEngine) -> AbrByteBuffer {
    if engine.is_null() {
        return AbrByteBuffer {
            data: ptr::null_mut(),
            len: 0,
        };
    }

    let mut data = (*engine).engine.serialize();
    let buffer = AbrByteBuffer {
        data: data.as_mut_ptr(),
        len: data.len(),
    };
    std::mem::forget(data);
    buffer
}

#[no_mangle]
pub unsafe extern "C" fn abr_free_byte_buffer(buffer: AbrByteBuffer) {
    if !buffer.data.is_null() {
        drop(Vec::from_raw_parts(buffer.data, buffer.len, buffer.len));
    }
}

#[no_mangle]
pub unsafe extern "C" fn abr_free_string(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

#[no_mangle]
pub unsafe extern "C" fn abr_match_result_destroy(result: AbrMatchResult) {
    abr_free_string(result.redirect);
    abr_free_string(result.rewritten_url);
}

#[no_mangle]
pub unsafe extern "C" fn abr_content_blocking_rules_from_filter_set(
    rules: *const u8,
    rules_len: usize,
) -> AbrContentBlockingRulesResult {
    let Some(rules) = bytes(rules, rules_len) else {
        return AbrContentBlockingRulesResult {
            ok: false,
            rules_json: empty_c_string(),
            truncated: false,
            error_message: string_to_c("rules pointer was null".to_string()),
        };
    };

    let Ok(rules) = std::str::from_utf8(rules) else {
        return AbrContentBlockingRulesResult {
            ok: false,
            rules_json: empty_c_string(),
            truncated: false,
            error_message: string_to_c("rules were not valid UTF-8".to_string()),
        };
    };

    let mut filter_set = FilterSet::new(true);
    filter_set.add_filter_list(
        rules,
        ParseOptions {
            rule_types: RuleTypes::NetworkOnly,
            ..Default::default()
        },
    );

    let Ok((mut content_blocking_rules, _)) = filter_set.into_content_blocking() else {
        return AbrContentBlockingRulesResult {
            ok: false,
            rules_json: empty_c_string(),
            truncated: false,
            error_message: string_to_c("failed to convert rules to content blockers".to_string()),
        };
    };

    let rules_len = content_blocking_rules.len();
    let truncated = if rules_len > MAX_IOS_CONTENT_BLOCKER_RULES {
        content_blocking_rules.swap(rules_len - 1, MAX_IOS_CONTENT_BLOCKER_RULES - 1);
        content_blocking_rules.truncate(MAX_IOS_CONTENT_BLOCKER_RULES);
        true
    } else {
        false
    };

    match serde_json::to_string(&content_blocking_rules) {
        Ok(rules_json) => AbrContentBlockingRulesResult {
            ok: true,
            rules_json: string_to_c(rules_json),
            truncated,
            error_message: empty_c_string(),
        },
        Err(error) => AbrContentBlockingRulesResult {
            ok: false,
            rules_json: empty_c_string(),
            truncated,
            error_message: string_to_c(error.to_string()),
        },
    }
}

#[no_mangle]
pub unsafe extern "C" fn abr_content_blocking_rules_result_destroy(
    result: AbrContentBlockingRulesResult,
) {
    abr_free_string(result.rules_json);
    abr_free_string(result.error_message);
}
