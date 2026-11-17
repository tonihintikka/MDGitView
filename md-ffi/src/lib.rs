use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

use md_engine::{render_markdown, RenderOptions};

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::new("no_error").unwrap());
}

fn set_last_error(message: impl AsRef<str>) {
    LAST_ERROR.with(|cell| *cell.borrow_mut() = sanitize_for_c(message.as_ref()));
}

fn clear_last_error() {
    LAST_ERROR.with(|cell| *cell.borrow_mut() = CString::new("no_error").unwrap());
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
pub extern "C" fn md_render(
    markdown_utf8: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    md_render_guarded(markdown_utf8, options_json, false)
}

fn md_render_guarded(
    markdown_utf8: *const c_char,
    options_json: *const c_char,
    force_panic: bool,
) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(|| {
        md_render_inner(markdown_utf8, options_json, force_panic)
    })) {
        Ok(result) => result,
        Err(payload) => {
            set_last_error(format!("renderer panicked: {}", panic_message(payload)));
            std::ptr::null_mut()
        }
    }
}

fn md_render_inner(
    markdown_utf8: *const c_char,
    options_json: *const c_char,
    force_panic: bool,
) -> *mut c_char {
    if force_panic {
        panic!("test panic from renderer");
    }

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
        Ok(value) => {
            clear_last_error();
            value.into_raw()
        }
        Err(_) => {
            set_last_error("render payload contained interior null byte");
            std::ptr::null_mut()
        }
    }
}

fn panic_message(payload: Box<dyn std::any::Any + Send>) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "unknown panic payload".to_string()
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
    LAST_ERROR.with(|cell| cell.borrow().as_ptr())
}

#[cfg(test)]
mod tests {
    use super::{md_free_result, md_last_error, md_render_guarded};
    use std::ffi::{CStr, CString};

    #[test]
    fn renderer_panic_returns_null_with_thread_local_error() {
        let markdown = CString::new("# heading").unwrap();
        let options = CString::new("{}").unwrap();
        let result = md_render_guarded(markdown.as_ptr(), options.as_ptr(), true);

        assert!(result.is_null());
        let error = unsafe { CStr::from_ptr(md_last_error()) }.to_str().unwrap();
        assert!(error.contains("renderer panicked: test panic from renderer"));

        let success = md_render_guarded(markdown.as_ptr(), options.as_ptr(), false);
        assert!(!success.is_null());
        let error = unsafe { CStr::from_ptr(md_last_error()) }.to_str().unwrap();
        assert_eq!(error, "no_error");
        md_free_result(success);
    }

    #[test]
    fn last_error_is_isolated_per_thread() {
        let worker = std::thread::spawn(|| {
            let markdown = CString::new("# heading").unwrap();
            let options = CString::new("{}").unwrap();
            let result = md_render_guarded(markdown.as_ptr(), options.as_ptr(), true);
            assert!(result.is_null());
            unsafe { CStr::from_ptr(md_last_error()) }
                .to_str()
                .unwrap()
                .to_string()
        });

        assert!(worker.join().unwrap().contains("renderer panicked"));
        let main_thread_error = unsafe { CStr::from_ptr(md_last_error()) }.to_str().unwrap();
        assert_eq!(main_thread_error, "no_error");
    }
}
