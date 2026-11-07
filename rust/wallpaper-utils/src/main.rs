//! On-demand wallpaper image helpers for the active Nyvorel shell.
//! No service or background worker remains after a command exits.

mod image_io;
mod placement;
mod regions;
mod thumbnails;

use clap::{Args, Parser, Subcommand};
use std::{path::PathBuf, process};

#[derive(Parser)]
#[command(
    name = "nyvorel-wallpaper-utils",
    version,
    about = "Nyvorel image utilities"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    FindRegions(RegionArgs),
    LeastBusyRegion(PlacementArgs),
    Thumbnails(ThumbnailArgs),
}

#[derive(Args)]
struct RegionArgs {
    #[arg(
        short = 'i',
        long,
        default_value = "/tmp/quickshell/media/screenshot/image"
    )]
    image: PathBuf,
    #[arg(long)]
    debug_output: Option<PathBuf>,
    #[arg(long, default_value_t = 90)]
    min_width: u32,
    #[arg(long, default_value_t = 42)]
    min_height: u32,
    #[arg(long)]
    max_width: Option<u32>,
    #[arg(long)]
    max_height: Option<u32>,
    #[arg(long)]
    single: bool,
    #[arg(long)]
    hyprctl: bool,
    // Historical no-op flags remain accepted for existing scripts.
    #[arg(long)]
    quality: bool,
    #[arg(long, default_value_t = 3000)]
    k: u32,
    #[arg(long, default_value_t = 50)]
    min_size: u32,
    #[arg(long, default_value_t = 0.6)]
    sigma: f32,
    #[arg(long, default_value_t = 1.0)]
    resize_factor: f32,
}

#[derive(Args)]
struct PlacementArgs {
    image_path: PathBuf,
    #[arg(long, default_value_t = 300)]
    width: u32,
    #[arg(long, default_value_t = 200)]
    height: u32,
    #[arg(short = 'v', long)]
    visual_output: bool,
    #[arg(long, default_value_t = 1920)]
    screen_width: u32,
    #[arg(long, default_value_t = 1080)]
    screen_height: u32,
    #[arg(long, default_value_t = 10)]
    stride: u32,
    #[arg(long, default_value = "fill", value_parser = ["fill", "fit"])]
    screen_mode: String,
    #[arg(long)]
    verbose: bool,
    #[arg(short = 'l', long)]
    largest_region: bool,
    #[arg(short = 't', long, default_value_t = 1000.0)]
    variance_threshold: f64,
    #[arg(long, default_value_t = 1.78)]
    aspect_ratio: f64,
    #[arg(long, default_value_t = 50)]
    horizontal_padding: u32,
    #[arg(long, default_value_t = 50)]
    vertical_padding: u32,
    #[arg(long)]
    busiest: bool,
}

#[derive(Args)]
struct ThumbnailArgs {
    #[arg(short = 'd', long = "img_dirs", alias = "img-dirs")]
    img_dirs: String,
    #[arg(short = 's', long, default_value = "normal", value_parser = ["normal", "large", "x-large", "xx-large"])]
    size: String,
    #[arg(short = 'w', long, default_value_t = 1)]
    workers: usize,
    #[arg(short = 'i', long = "only_images", alias = "only-images")]
    only_images: bool,
    #[arg(short = 'r', long)]
    recursive: bool,
    #[arg(long = "machine_progress", alias = "machine-progress")]
    machine_progress: bool,
}

fn main() {
    let normalized: Vec<String> = std::env::args()
        .map(|arg| match arg.as_str() {
            "-do" => "--debug-output".into(),
            "-hp" => "--horizontal-padding".into(),
            "-vp" => "--vertical-padding".into(),
            _ => arg,
        })
        .collect();
    let cli = Cli::parse_from(normalized);
    let result = match cli.command {
        Command::FindRegions(args) => regions::run(&args),
        Command::LeastBusyRegion(args) => placement::run(&args),
        Command::Thumbnails(args) => thumbnails::run(&args),
    };
    if let Err(error) = result {
        eprintln!("{error}");
        process::exit(1);
    }
}
