use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;

use md_engine::{render_markdown, RenderOptions};
use once_cell::sync::Lazy;

static LAST_ERROR: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("no_error").expect("static cstring")));
static LOCK_POISONED: Lazy<CString> =
    Lazy::new(|| CString::new("ffi lock poisoned").expect("static cstring"));
thread_local! {
    static LAST_ERROR_SNAPSHOT: RefCell<CString> =
        RefCell::new(CString::new("no_error").expect("static cstring"));
}

fn set_last_error(message: impl AsRef<str>) {
    let safe = sanitize_for_c(message.as_ref());
    if let Ok(mut guard) = LAST_ERROR.lock() {
        *guard = safe;
    }
}

fn sanitize_for_c(value: &str) -> CString {
    let clean = value.replace('\0', " ");
    CString::new(clean).unwrap_or_else(|_| CString::new("ffi_error").expect("static cstring"))
}

fn cstr_to_str<'a>(ptr: *const c_char) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err("null pointer passed to ffi".to_string());
    }

    // SAFETY: caller guarantees null-terminated input.
    let c_str = unsafe { CStr::from_ptr(ptr) };
    c_str
        .to_str()
        .map_err(|_| "invalid utf-8 input passed to ffi".to_string())
}

#[no_mangle]
pub extern "C" fn md_render(markdown_utf8: *const c_char, options_json: *const c_char) -> *mut c_char {
    let markdown = match cstr_to_str(markdown_utf8) {
        Ok(value) => value,
        Err(error) => {
            set_last_error(error);
            return std::ptr::null_mut();
        }
    };

    let options_payload = match cstr_to_str(options_json) {
        Ok(value) => value,
        Err(error) => {
            set_last_error(error);
            return std::ptr::null_mut();
        }
    };

    let options: RenderOptions = match serde_json::from_str(options_payload) {
        Ok(value) => value,
        Err(error) => {
            set_last_error(format!("invalid options json: {error}"));
            return std::ptr::null_mut();
        }
    };

    let rendered = match render_markdown(markdown, &options) {
        Ok(value) => value,
        Err(error) => {
            set_last_error(error.to_string());
            return std::ptr::null_mut();
        }
    };

    let payload = match serde_json::to_string(&rendered) {
        Ok(value) => value,
        Err(error) => {
            set_last_error(format!("serialization failed: {error}"));
            return std::ptr::null_mut();
        }
    };

    match CString::new(payload) {
        Ok(value) => value.into_raw(),
        Err(_) => {
            set_last_error("render payload contained interior null byte");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn md_free_result(result_ptr: *mut c_char) {
    if result_ptr.is_null() {
        return;
    }

    // SAFETY: pointer was returned from CString::into_raw in md_render.
    unsafe {
        let _ = CString::from_raw(result_ptr);
    }
}

#[no_mangle]
pub extern "C" fn md_last_error() -> *const c_char {
    let snapshot = match LAST_ERROR.lock() {
        Ok(guard) => guard.clone(),
        Err(_) => LOCK_POISONED.clone(),
    };

    LAST_ERROR_SNAPSHOT.with(|cell| {
        *cell.borrow_mut() = snapshot;
        cell.borrow().as_ptr()
    })
}
