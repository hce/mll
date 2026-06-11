use clap::Parser;
use std::path::Path;

#[derive(Parser)]
#[command(name = "mll", about = "mll compiler and runner")]
struct Cli {
    /// The .mll source file to compile
    file: String,

    /// Run the compiled code immediately (don't write .lua file)
    #[arg(short, long)]
    run: bool,

    /// Write the compiled .lua file (default when not using --run)
    #[arg(short, long)]
    emit_lua: bool,

    /// Additional library search paths
    #[arg(short = 'L', long = "lib")]
    lib_paths: Vec<String>,
}

fn main() {
    let cli = Cli::parse();

    // Run compilation on a thread with a large stack to handle deeply
    // nested ASTs (e.g. 256-element list literals desugar into 256
    // nested cons applications, each requiring a stack frame during
    // type inference).
    let builder = std::thread::Builder::new()
        .stack_size(64 * 1024 * 1024); // 64 MB stack
    let handler = builder.spawn(move || {
        run_compiler(cli);
    }).expect("Failed to spawn compiler thread");

    if let Err(e) = handler.join() {
        eprintln!("Compiler panicked: {:?}", e);
        std::process::exit(1);
    }
}

fn run_compiler(cli: Cli) {
    let filename = &cli.file;

    let source = match std::fs::read_to_string(filename) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Error reading {}: {}", filename, e);
            std::process::exit(1);
        }
    };

    let source_dir = Path::new(filename).parent().unwrap_or(Path::new("."));

    // Auto-add lib/ directory relative to the compiler executable
    let exe_dir = std::env::current_exe().ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()));
    let auto_lib = exe_dir.as_ref()
        .map(|d| d.join("../../lib"))
        .and_then(|p| p.canonicalize().ok());

    let mut lib_paths: Vec<&Path> = cli.lib_paths.iter()
        .map(|p| Path::new(p.as_str()))
        .collect();
    if let Some(ref auto) = auto_lib {
        lib_paths.push(auto.as_path());
    }

    let result = match mllc::compile(&source, source_dir, &lib_paths) {
        Ok(r) => r,
        Err(e) => {
            eprint!("{}", e);
            std::process::exit(1);
        }
    };

    // Write .lua file if requested or if not running
    if cli.emit_lua || !cli.run {
        let out_filename = filename.replace(".mll", ".lua");
        if let Err(e) = std::fs::write(&out_filename, &result.lua_code) {
            eprintln!("Error writing {}: {}", out_filename, e);
            std::process::exit(1);
        }
        if !cli.run {
            println!("Compiled {} -> {}", filename, out_filename);
        }
    }

    // Run with mlua if requested
    if cli.run {
        run_lua(&result.lua_code, filename);
    }
}

fn run_lua(code: &str, filename: &str) {
    let lua = mlua::Lua::new();

    // Set up the script name for error messages
    lua.scope(|_scope| {
        Ok(())
    }).unwrap();

    match lua.load(code).set_name(filename).exec() {
        Ok(()) => {}
        Err(e) => {
            eprintln!("Runtime error: {}", e);
            std::process::exit(1);
        }
    }
}
