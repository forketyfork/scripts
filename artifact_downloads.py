#!/usr/bin/env python3
"""
Monitor GitHub repositories for new artifact downloads.

Reads repository list from artifact_repos.txt and checks every 60 seconds
for new artifact downloads, outputting messages when detected.
"""

import json
import logging
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def check_dependencies() -> None:
    """Check for required dependencies and provide helpful error messages."""
    missing_modules = []
    
    try:
        import json
    except ImportError:
        missing_modules.append('json (standard library)')
    
    try:
        import urllib.request
        import urllib.error
    except ImportError:
        missing_modules.append('urllib (standard library)')
    
    if missing_modules:
        logging.error("Missing required dependencies: %s", ', '.join(missing_modules))
        sys.exit(1)


def setup_logging() -> None:
    """Setup logging configuration."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )


def validate_repo_name(repo: str) -> bool:
    """Validate GitHub repository name format (owner/repo)."""
    pattern = r'^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$'
    return bool(re.match(pattern, repo))


def read_repos_file(filepath: str) -> List[str]:
    """Read repository list from file."""
    repos_path = Path(filepath)
    if not repos_path.exists():
        logging.error("%s not found", filepath)
        sys.exit(1)
    
    try:
        with repos_path.open('r') as f:
            raw_repos = [line.strip() for line in f if line.strip() and not line.startswith('#')]
        
        valid_repos = []
        for repo in raw_repos:
            if validate_repo_name(repo):
                valid_repos.append(repo)
            else:
                logging.warning("Invalid repository format '%s', skipping", repo)
        
        if not valid_repos:
            logging.error("No valid repositories found in %s", filepath)
            sys.exit(1)
        
        return valid_repos
    except (OSError, IOError, PermissionError) as e:
        logging.error("Error reading %s: %s", filepath, e)
        sys.exit(1)
    except UnicodeDecodeError as e:
        logging.error("%s contains invalid characters: %s", filepath, e)
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
                logging.warning("Only %s GitHub API requests remaining", remaining)
            
            data = json.loads(response.read().decode())
            return data
    except HTTPError as e:
        if e.code == 403:
            reset_time = e.headers.get('x-ratelimit-reset')
            if reset_time:
                wait_time = int(reset_time) - int(time.time())
                if wait_time > 0:
                    logging.warning("Rate limit exceeded. Waiting %d seconds...", wait_time)
                    time.sleep(wait_time + 1)
                    return fetch_repo_releases(repo, github_token)
        logging.error("HTTP error fetching %s: %d %s", repo, e.code, e.reason)
        return None
    except URLError as e:
        logging.error("URL error fetching %s: %s", repo, e.reason)
        return None
    except json.JSONDecodeError as e:
        logging.error("JSON decode error for %s: %s", repo, e)
        return None
    except Exception as e:
        logging.error("Unexpected error fetching %s: %s", repo, e)
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


def load_state(state_file: Path) -> Dict[str, Dict[str, int]]:
    """Load previous download counts from state file."""
    if not state_file.exists():
        return {}
    
    try:
        with state_file.open('r') as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError, IOError) as e:
        logging.warning("Failed to load state from %s: %s", state_file, e)
        return {}


def save_state(state_file: Path, downloads: Dict[str, Dict[str, int]]) -> None:
    """Save current download counts to state file."""
    try:
        with state_file.open('w') as f:
            json.dump(downloads, f, indent=2)
    except (OSError, IOError) as e:
        logging.warning("Failed to save state to %s: %s", state_file, e)


def show_offline_downloads(repos: List[str], current_downloads: Dict[str, Dict[str, int]], 
                          previous_downloads: Dict[str, Dict[str, int]]) -> None:
    """Show downloads that occurred while the script was offline."""
    offline_downloads_found = False
    
    for repo in repos:
        if repo in previous_downloads and repo in current_downloads:
            new_artifacts = detect_new_downloads(
                repo, current_downloads[repo], previous_downloads[repo]
            )
            
            if new_artifacts:
                if not offline_downloads_found:
                    logging.info("Downloads detected while offline:")
                    offline_downloads_found = True
                
                for artifact, additional_count in new_artifacts:
                    logging.info("Artifact downloaded: %s:%s (+%d)", repo, artifact, additional_count)
    
    if offline_downloads_found:
        logging.info("")


def initialize_monitoring() -> Tuple[List[str], Optional[str], Path]:
    """Initialize monitoring configuration and validate setup."""
    repos_file = os.environ.get("ARTIFACT_REPOS_FILE", "artifact_repos.txt")
    github_token = os.environ.get("GITHUB_TOKEN")
    state_file = Path("artifact_downloads_state.json")
    
    if github_token:
        logging.info("Using GitHub token for authentication")
    else:
        logging.warning("No GITHUB_TOKEN found. Rate limits may be restrictive.")
    
    repos = read_repos_file(repos_file)
    logging.info("Monitoring %d repositories for artifact downloads...", len(repos))
    
    return repos, github_token, state_file


def fetch_current_state(repos: List[str], github_token: Optional[str]) -> Dict[str, Dict[str, int]]:
    """Fetch current download state for all repositories."""
    current_downloads: Dict[str, Dict[str, int]] = {}
    
    for repo in repos:
        try:
            current_downloads[repo] = get_artifact_downloads(repo, github_token)
        except (HTTPError, URLError, json.JSONDecodeError) as e:
            logging.warning("Could not fetch current state for %s: %s", repo, e)
            current_downloads[repo] = {}
    
    return current_downloads


def run_monitoring_loop(repos: List[str], github_token: Optional[str], 
                       state_file: Path, initial_state: Dict[str, Dict[str, int]]) -> None:
    """Run the main monitoring loop."""
    previous_downloads = initial_state.copy()
    
    try:
        while True:
            for repo in repos:
                try:
                    repo_downloads = get_artifact_downloads(repo, github_token)
                    
                    if repo in previous_downloads:
                        new_artifacts = detect_new_downloads(
                            repo, repo_downloads, previous_downloads[repo]
                        )
                        
                        for artifact, additional_count in new_artifacts:
                            logging.info("Artifact downloaded: %s:%s (+%d)", repo, artifact, additional_count)
                    
                    previous_downloads[repo] = repo_downloads
                    
                except (HTTPError, URLError, json.JSONDecodeError) as e:
                    logging.error("Error processing %s: %s", repo, e)
            
            # Save state after each monitoring cycle
            save_state(state_file, previous_downloads)
            
            time.sleep(60)
            
    except KeyboardInterrupt:
        logging.info("Stopping artifact download monitor...")
        sys.exit(0)
    except (KeyError, ValueError, OSError) as e:
        logging.error("Unexpected error in main loop: %s", e)
        sys.exit(1)


def main() -> None:
    """Main entry point."""
    check_dependencies()
    setup_logging()
    
    repos, github_token, state_file = initialize_monitoring()
    
    # Load previous state
    previous_downloads = load_state(state_file)
    
    # Get current downloads for all repos to check for offline activity
    current_downloads = fetch_current_state(repos, github_token)
    
    # Show any downloads that happened while offline
    show_offline_downloads(repos, current_downloads, previous_downloads)
    
    logging.info("Press Ctrl+C to stop")
    
    # Run the monitoring loop
    run_monitoring_loop(repos, github_token, state_file, current_downloads)


if __name__ == "__main__":
    main()