use wasm_bindgen::prelude::*;
use std::path::Path;

#[wasm_bindgen]
pub fn compile_mll(source: &str) -> String {
    match mllc::compile(source, Path::new("."), &[]) {
        Ok(result) => result.lua_code,
        Err(e) => format!("-- Error:\n-- {}", format!("{}", e).replace('\n', "\n-- ")),
    }
}
