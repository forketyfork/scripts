#!/usr/bin/env python3
"""
Monitor GitHub repositories for new artifact downloads.

Reads repository list from artifact_repos.txt and checks every 60 seconds
for new artifact downloads, outputting messages when detected.
"""

import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def validate_repo_name(repo: str) -> bool:
    """Validate GitHub repository name format (owner/repo)."""
    pattern = r'^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$'
    return bool(re.match(pattern, repo))


def read_repos_file(filepath: str) -> List[str]:
    """Read repository list from file."""
    repos_path = Path(filepath)
    if not repos_path.exists():
        print(f"Error: {filepath} not found", file=sys.stderr)
        sys.exit(1)
    
    try:
        with repos_path.open('r') as f:
            raw_repos = [line.strip() for line in f if line.strip() and not line.startswith('#')]
        
        valid_repos = []
        for repo in raw_repos:
            if validate_repo_name(repo):
                valid_repos.append(repo)
            else:
                print(f"Warning: Invalid repository format '{repo}', skipping", file=sys.stderr)
        
        if not valid_repos:
            print(f"Error: No valid repositories found in {filepath}", file=sys.stderr)
            sys.exit(1)
        
        return valid_repos
    except (OSError, IOError, PermissionError) as e:
        print(f"Error reading {filepath}: {e}", file=sys.stderr)
        sys.exit(1)
    except UnicodeDecodeError as e:
        print(f"Error: {filepath} contains invalid characters: {e}", file=sys.stderr)
        sys.exit(1)


def fetch_repo_releases(repo: str, github_token: Optional[str] = None) -> Optional[List[Dict]]:
    """Fetch releases data from GitHub API for a repository."""
    url = f"https://api.github.com/repos/{repo}/releases"
    
    try:
        request = Request(url)
        request.add_header("Accept", "application/vnd.github+json")
        if github_token:
            request.add_header("Authorization", f"Bearer {github_token}")
        
        with urlopen(request, timeout=30) as response:
            remaining = response.headers.get('x-ratelimit-remaining')
            if remaining and int(remaining) < 10:
                print(f"Warning: Only {remaining} GitHub API requests remaining", file=sys.stderr)
            
            data = json.loads(response.read().decode())
            return data
    except HTTPError as e:
        if e.code == 403:
            reset_time = e.headers.get('x-ratelimit-reset')
            if reset_time:
                wait_time = int(reset_time) - int(time.time())
                if wait_time > 0:
                    print(f"Rate limit exceeded. Waiting {wait_time} seconds...", file=sys.stderr)
                    time.sleep(wait_time + 1)
                    return fetch_repo_releases(repo, github_token)
        print(f"HTTP error fetching {repo}: {e.code} {e.reason}", file=sys.stderr)
        return None
    except URLError as e:
        print(f"URL error fetching {repo}: {e.reason}", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        print(f"JSON decode error for {repo}: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Unexpected error fetching {repo}: {e}", file=sys.stderr)
        return None


def get_artifact_downloads(repo: str, github_token: Optional[str] = None) -> Dict[str, int]:
    """Get current download counts for all artifacts in a repository."""
    releases = fetch_repo_releases(repo, github_token)
    if not releases:
        return {}
    
    downloads = {}
    for release in releases:
        if 'assets' in release:
            for asset in release['assets']:
                artifact_name = asset.get('name', '')
                download_count = asset.get('download_count', 0)
                if artifact_name:
                    downloads[artifact_name] = download_count
    
    return downloads


def detect_new_downloads(repo: str, current: Dict[str, int], previous: Dict[str, int]) -> List[Tuple[str, int]]:
    """Detect artifacts with new downloads since last check."""
    new_downloads = []
    
    for artifact, count in current.items():
        prev_count = previous.get(artifact, 0)
        if count > prev_count:
            additional_downloads = count - prev_count
            new_downloads.append((artifact, additional_downloads))
    
    return new_downloads


def main() -> None:
    """Main monitoring loop."""
    repos_file = os.environ.get("ARTIFACT_REPOS_FILE", "artifact_repos.txt")
    github_token = os.environ.get("GITHUB_TOKEN")
    
    if github_token:
        print("Using GitHub token for authentication")
    else:
        print("Warning: No GITHUB_TOKEN found. Rate limits may be restrictive.", file=sys.stderr)
    
    repos = read_repos_file(repos_file)
    
    print(f"Monitoring {len(repos)} repositories for artifact downloads...")
    print("Press Ctrl+C to stop")
    
    previous_downloads: Dict[str, Dict[str, int]] = {}
    
    try:
        while True:
            for repo in repos:
                try:
                    current_downloads = get_artifact_downloads(repo, github_token)
                    
                    if repo in previous_downloads:
                        new_artifacts = detect_new_downloads(
                            repo, current_downloads, previous_downloads[repo]
                        )
                        
                        for artifact, additional_count in new_artifacts:
                            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                            print(f"{timestamp} Artifact downloaded: {repo}:{artifact} (+{additional_count})")
                    
                    previous_downloads[repo] = current_downloads
                    
                except (HTTPError, URLError, json.JSONDecodeError) as e:
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    print(f"{timestamp} Error processing {repo}: {e}", file=sys.stderr)
            
            time.sleep(60)
            
    except KeyboardInterrupt:
        print("\nStopping artifact download monitor...")
        sys.exit(0)
    except (KeyError, ValueError, OSError) as e:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{timestamp} Unexpected error in main loop: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()