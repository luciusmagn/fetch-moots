use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use clap::Parser;
use futures::future::join_all;
use serde_json::{json, Value};

#[derive(Debug, Parser)]
#[clap(
    name = "mutual_downloader",
    about = "Download Twitter mutual followers' profile pictures"
)]
struct Opt {
    #[clap(
        name = "FILES",
        help = "Followers JSON file(s) to process"
    )]
    files: Vec<String>,

    #[clap(
        long,
        default_value = "mutuals",
        help = "Folder to save profile pictures"
    )]
    folder: String,
}

#[derive(Debug)]
struct UserInfo {
    username: String,
    profile_image_url: String,
}

async fn download_profile_picture(
    user: &UserInfo,
    folder: &str,
) -> Result<()> {
    let client = reqwest::Client::new();
    let response =
        client.get(&user.profile_image_url).send().await?;

    if response.status().is_success() {
        let content = response.bytes().await?;
        let file_extension = user
            .profile_image_url
            .split('.')
            .last()
            .unwrap_or("jpg");
        let filename =
            format!("{}.{}", user.username, file_extension);
        let filepath = Path::new(folder).join(filename);

        fs::create_dir_all(folder)?;
        fs::write(&filepath, content)?;
        println!(
            "Downloaded profile picture for @{}",
            user.username
        );
    } else {
        println!(
            "Failed to download profile picture for @{}",
            user.username
        );
    }

    Ok(())
}

fn extract_user_info(entry: &Value) -> Option<UserInfo> {
    entry["content"]["itemContent"]["user_results"]["result"]
        ["legacy"]
        .as_object()
        .map(|user| {
            let username = user["screen_name"]
                .as_str()
                .unwrap_or("")
                .to_string();
            let mut profile_image_url = user
                ["profile_image_url_https"]
                .as_str()
                .unwrap_or("")
                .to_string();
            profile_image_url =
                profile_image_url.replace("_normal", "");
            let is_mutual = user["followed_by"]
                .as_bool()
                .unwrap_or(false)
                && user["following"].as_bool().unwrap_or(false);

            if is_mutual {
                Some(UserInfo {
                    username,
                    profile_image_url,
                })
            } else {
                None
            }
        })
        .flatten()
}

fn find_all_entries(instructions: &[Value]) -> Vec<Value> {
    instructions
        .iter()
        .flat_map(|instruction| {
            instruction
                .as_object()
                .into_iter()
                .flat_map(|obj| obj.values())
                .filter_map(|value| {
                    if let Some(entries) = value.as_array() {
                        Some(
                            entries
                                .iter()
                                .filter(|item| {
                                    item.is_object()
                                        && item
                                            .get("entryId")
                                            .is_some()
                                })
                                .cloned()
                                .collect::<Vec<Value>>(),
                        )
                    } else {
                        None
                    }
                })
                .flatten()
        })
        .collect()
}

fn process_followers_file(
    file_path: &str,
) -> Result<Vec<UserInfo>> {
    let content =
        fs::read_to_string(file_path).with_context(|| {
            format!("Failed to read file: {}", file_path)
        })?;
    let data: Value = serde_json::from_str(&content)?;

    let instructions = &data["data"]["user"]["result"]
        ["timeline"]["timeline"]["instructions"];
    let entries = find_all_entries(
        instructions.as_array().unwrap_or(&Vec::new()),
    );

    let mutuals: Vec<UserInfo> = entries
        .iter()
        .filter(|entry| {
            entry["content"]["entryType"]
                == json!("TimelineTimelineItem")
        })
        .filter_map(|entry| extract_user_info(entry))
        .collect();

    println!("Found {} mutuals in {}", mutuals.len(), file_path);
    Ok(mutuals)
}

#[tokio::main]
async fn main() -> Result<()> {
    let opt = Opt::parse();

    let all_mutuals: Vec<UserInfo> = opt
        .files
        .iter()
        .map(|file| process_followers_file(file))
        .collect::<Result<Vec<Vec<UserInfo>>>>()?
        .into_iter()
        .flatten()
        .collect();

    let download_tasks = all_mutuals.iter().map(|mutual| {
        download_profile_picture(mutual, &opt.folder)
    });

    join_all(download_tasks).await;

    println!(
        "Finished downloading {} profile pictures to {}",
        all_mutuals.len(),
        opt.folder
    );
    Ok(())
}
