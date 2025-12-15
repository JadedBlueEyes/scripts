#!/usr/bin/env python3
"""
Migrate .lrc and .txt files from old music folder structure to new structure.

Old structure: Artist/Album/01. Track.mp3
New structure: Artist/Album [identifier]/01. Track.mp3

This script:
1. Finds old folders (without identifiers) containing .lrc or .txt files
2. Looks for corresponding new folders (with identifiers)
3. Moves lyrics files if there's exactly one matching folder
4. Asks for intervention if there are multiple matches
5. Deletes empty old folders after moving files
"""

import os
import sys
import re
import shutil
from pathlib import Path
from typing import List, Dict, Tuple


def find_lyrics_files(directory: Path) -> List[Path]:
    """Find all .lrc and .txt files in a directory."""
    lrc_files = list(directory.glob("*.lrc"))
    txt_files = list(directory.glob("*.txt"))
    return lrc_files + txt_files


def find_new_folders(old_folder: Path) -> List[Path]:
    """
    Find new folders that match the old folder pattern.

    Old: Artist/Album
    New: Artist/Album [identifier]
    """
    parent = old_folder.parent
    old_name = old_folder.name

    # Look for folders that match "old_name [identifier]" where identifier is exactly 8 chars (case-insensitive)
    pattern = re.escape(old_name) + r" \[.{8}\]"
    matching_folders = []

    if parent.exists():
        for item in parent.iterdir():
            if item.is_dir() and re.match(pattern, item.name, re.IGNORECASE):
                matching_folders.append(item)

    return matching_folders


def is_old_folder(folder: Path) -> bool:
    """
    Check if a folder follows the old naming pattern (no identifier).
    Returns False if folder name contains [identifier] (exactly 8 chars).
    """
    return not re.search(r'\[.{8}\]', folder.name)


def is_folder_empty(folder: Path) -> bool:
    """Check if a folder is empty (no files or subdirectories)."""
    try:
        return not any(folder.iterdir())
    except (OSError, PermissionError):
        return False


def move_lyrics_files(source: Path, destination: Path) -> int:
    """Move all .lrc and .txt files from source to destination. Returns count of moved files."""
    lyrics_files = find_lyrics_files(source)
    moved_count = 0

    for lyrics_file in lyrics_files:
        dest_file = destination / lyrics_file.name
        if dest_file.exists():
            print(f"  Warning: {dest_file.name} already exists in destination, skipping")
            continue

        try:
            shutil.move(str(lyrics_file), str(dest_file))
            print(f"  Moved: {lyrics_file.name}")
            moved_count += 1
        except (OSError, PermissionError) as e:
            print(f"  Error moving {lyrics_file.name}: {e}")

    return moved_count


def process_music_directory(root_dir: Path, dry_run: bool = False) -> Tuple[Dict[str, int], List[Path]]:
    """
    Process the music directory to migrate .lrc and .txt files.

    Returns statistics about the operation and list of folders with no match.
    """
    stats = {
        "folders_processed": 0,
        "files_moved": 0,
        "folders_deleted": 0,
        "manual_intervention": 0,
        "no_match_found": 0,
    }

    no_match_folders = []

    # Find all potential old folders (recursively)
    old_folders_to_process = []

    print("Scanning for old folders...")
    for dirpath, dirnames, filenames in os.walk(root_dir):
        current_path = Path(dirpath)

        # Check if this folder follows old naming pattern (no identifier)
        # Include folders with .lrc/.txt files OR empty folders (already moved manually)
        if is_old_folder(current_path):
            has_lyrics = any(f.endswith('.lrc') or f.endswith('.txt') for f in filenames)
            is_empty = len(filenames) == 0 and len(dirnames) == 0

            if has_lyrics or is_empty:
                old_folders_to_process.append(current_path)

    print(f"Found {len(old_folders_to_process)} old folders to process\n")

    for old_folder in old_folders_to_process:
        stats["folders_processed"] += 1
        lyrics_files = find_lyrics_files(old_folder)

        print(f"Processing: {old_folder}")
        print(f"  Found {len(lyrics_files)} lyrics file(s)")

        # Check if folder is already empty (lyrics files moved manually)
        if is_folder_empty(old_folder):
            # Find matching new folders to verify they exist
            new_folders = find_new_folders(old_folder)
            if len(new_folders) > 0:
                print(f"  ℹ️  Folder is empty (files already moved)")
                if dry_run:
                    print(f"  [DRY RUN] Would delete empty folder")
                else:
                    try:
                        old_folder.rmdir()
                        print(f"  ✓ Deleted empty folder")
                        stats["folders_deleted"] += 1
                    except (OSError, PermissionError) as e:
                        print(f"  Error deleting folder: {e}")
                print()
                continue
            else:
                # Empty folder but no new folder found - treat as no match
                print(f"  ⚠️  Folder is empty but no matching folder with identifier found")
                stats["no_match_found"] += 1
                no_match_folders.append(old_folder)
                print()
                continue
        
        # Find matching new folders
        new_folders = find_new_folders(old_folder)
        
        if len(new_folders) == 0:
            print(f"  ⚠️  No matching folder with identifier found")
            stats["no_match_found"] += 1
            no_match_folders.append(old_folder)
            print()

        elif len(new_folders) == 1:
            print(f"  ✓ Found one match: {new_folders[0].name}")

            if dry_run:
                print(f"  [DRY RUN] Would move {len(lyrics_files)} file(s) to {new_folders[0]}")
            else:
                moved = move_lyrics_files(old_folder, new_folders[0])
                stats["files_moved"] += moved

                # Check if old folder is now empty and delete it
                if is_folder_empty(old_folder):
                    try:
                        old_folder.rmdir()
                        print(f"  ✓ Deleted empty folder: {old_folder.name}")
                        stats["folders_deleted"] += 1
                    except (OSError, PermissionError) as e:
                        print(f"  Error deleting folder: {e}")
            print()

        else:
            print(f"  ⚠️  Multiple matches found ({len(new_folders)}):")
            for i, folder in enumerate(new_folders, 1):
                print(f"    {i}. {folder.name}")

            stats["manual_intervention"] += 1

            if not dry_run:
                print("  Please choose:")
                print("    Enter number (1-{}): Select destination folder".format(len(new_folders)))
                print("    's': Skip this folder")
                print("    'q': Quit")

                choice = input("  Your choice: ").strip().lower()

                if choice == 'q':
                    print("\nQuitting...")
                    return stats
                elif choice == 's':
                    print("  Skipped")
                elif choice.isdigit() and 1 <= int(choice) <= len(new_folders):
                    selected_folder = new_folders[int(choice) - 1]
                    print(f"  Selected: {selected_folder.name}")
                    moved = move_lyrics_files(old_folder, selected_folder)
                    stats["files_moved"] += moved

                    # Check if old folder is now empty and delete it
                    if is_folder_empty(old_folder):
                        try:
                            old_folder.rmdir()
                            print(f"  ✓ Deleted empty folder: {old_folder.name}")
                            stats["folders_deleted"] += 1
                        except (OSError, PermissionError) as e:
                            print(f"  Error deleting folder: {e}")
                else:
                    print("  Invalid choice, skipping")
            print()

    return stats, no_match_folders


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Migrate .lrc and .txt files from old to new music folder structure"
    )
    parser.add_argument(
        "music_dir",
        type=str,
        help="Root directory of your music library"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes"
    )

    args = parser.parse_args()

    music_dir = Path(args.music_dir)

    if not music_dir.exists():
        print(f"Error: Directory '{music_dir}' does not exist")
        sys.exit(1)

    if not music_dir.is_dir():
        print(f"Error: '{music_dir}' is not a directory")
        sys.exit(1)

    print("=" * 70)
    print("Lyrics File Migration Tool")
    print("=" * 70)
    if args.dry_run:
        print("DRY RUN MODE - No changes will be made")
        print("=" * 70)
    print()

    stats, no_match_folders = process_music_directory(music_dir, dry_run=args.dry_run)

    print("=" * 70)
    print("Summary:")
    print(f"  Folders processed: {stats['folders_processed']}")
    print(f"  Files moved: {stats['files_moved']}")
    print(f"  Folders deleted: {stats['folders_deleted']}")
    print(f"  Manual intervention needed: {stats['manual_intervention']}")
    print(f"  No match found: {stats['no_match_found']}")
    print("=" * 70)

    if no_match_folders:
        print()
        print("Folders with no matching identifier found:")
        print("-" * 70)
        for folder in no_match_folders:
            print(f"  {folder}")
        print("=" * 70)


if __name__ == "__main__":
    main()
