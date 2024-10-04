#!/usr/bin/env python3

import json
import os
import requests
import argparse
from typing import List, Dict, Optional
from itertools import chain

def extract_user_info(entry: Dict) -> Dict:
    user = entry['content']['itemContent']['user_results']['result']
    return {
        'username': user['legacy']['screen_name'],
        'name': user['legacy']['name'],
        'profile_image_url': user['legacy']['profile_image_url_https'].replace('_normal', ''),
        'is_mutual': user['legacy']['followed_by'] and user['legacy']['following']
    }

def download_profile_picture(username: str, url: str, folder: str):
    if not os.path.exists(folder):
        os.makedirs(folder)

    response = requests.get(url)
    if response.status_code == 200:
        file_extension = url.split('.')[-1]
        filename = f"{username}.{file_extension}"
        filepath = os.path.join(folder, filename)
        with open(filepath, 'wb') as f:
            f.write(response.content)
        print(f"Downloaded profile picture for @{username}")
    else:
        print(f"Failed to download profile picture for @{username}")

def find_all_entries(instructions: List[Dict]) -> List[Dict]:
    all_entries = []
    for instruction in instructions:
        if isinstance(instruction, dict):
            for value in instruction.values():
                if isinstance(value, list):
                    all_entries.extend([item for item in value if isinstance(item, dict) and 'entryId' in item])
    return all_entries

def process_followers_file(file_path: str) -> List[Dict]:
    with open(file_path, 'r') as file:
        data = json.load(file)

    instructions = data['data']['user']['result']['timeline']['timeline']['instructions']
    entries = find_all_entries(instructions)

    if not entries:
        print(f"No entries found in {file_path}")
        return []

    mutuals = [
        extract_user_info(entry)
        for entry in entries
        if entry['content']['entryType'] == 'TimelineTimelineItem'
        and extract_user_info(entry)['is_mutual']
    ]

    print(f"Found {len(mutuals)} mutuals in {file_path}")
    return mutuals

def main():
    parser = argparse.ArgumentParser(description="Process Twitter followers JSON files and download mutual profile pictures.")
    parser.add_argument("files", nargs='+', help="Followers JSON file(s) to process")
    parser.add_argument("--folder", default="mutuals", help="Folder to save profile pictures (default: mutuals)")
    args = parser.parse_args()

    all_mutuals = list(chain.from_iterable(process_followers_file(file_path) for file_path in args.files))

    for mutual in all_mutuals:
        download_profile_picture(mutual['username'], mutual['profile_image_url'], args.folder)

    print(f"Finished downloading {len(all_mutuals)} profile pictures to {args.folder}")

if __name__ == "__main__":
    main()
