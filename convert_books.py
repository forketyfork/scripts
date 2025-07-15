#!/usr/bin/env python3
"""
Converts Book Track exported CSV file to individual markdown files for Obsidian Bookshelf plugin.

This script reads a CSV file containing book data and converts each book
into a separate markdown file with YAML frontmatter. The output files
are saved in a specified directory.
"""

import argparse
import csv
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Optional

def sanitize_filename(title: str) -> str:
    """Sanitize title for use as filename.
    
    Args:
        title: The book title to sanitize
        
    Returns:
        A sanitized filename safe for filesystem use
    """
    # Replace invalid characters with underscores
    sanitized = re.sub(r'[<>:"/\\|?*]', '_', title)
    # Remove multiple consecutive underscores
    sanitized = re.sub(r'_+', '_', sanitized)
    # Remove leading/trailing underscores and whitespace
    sanitized = sanitized.strip('_').strip()
    return sanitized

def format_date(date_str: str) -> str:
    """Format date from CSV to YYYY-MM-DD format.
    
    Args:
        date_str: Date string in ISO format
        
    Returns:
        Formatted date string in YYYY-MM-DD format, or original string if parsing fails
    """
    if not date_str:
        return ""
    try:
        # Parse ISO format date
        dt = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
        return dt.strftime('%Y-%m-%d')
    except (ValueError, TypeError):
        return date_str

def parse_list_field(field_str: str) -> List[str]:
    """Parse comma-separated field into list.
    
    Args:
        field_str: Comma-separated string
        
    Returns:
        List of stripped, non-empty items
    """
    if not field_str:
        return []
    return [item.strip() for item in field_str.split(',') if item.strip()]

def parse_authors(authors_str: str) -> List[str]:
    """Parse authors from 'Last,First' format to 'First Last' format.
    
    Args:
        authors_str: String containing author names in various formats
        
    Returns:
        List of author names in 'First Last' format
    """
    if not authors_str:
        return []
    
    parts = authors_str.split(',')
    result = []
    i = 0
    
    while i < len(parts):
        part = parts[i].strip()
        if not part:
            i += 1
            continue
            
        # Check if this part has no spaces (likely a last name)
        if ' ' not in part and i + 1 < len(parts):
            # This is a last name, next should be first name
            last_name = part
            first_name = parts[i + 1].strip()
            result.append(f"{first_name} {last_name}")
            i += 2
        else:
            # This might be a single name or already formatted
            result.append(part)
            i += 1
    
    return result

def parse_source_from_tags(tags_str: str) -> str:
    """Extract source from tags field (everything before first '|').
    
    Args:
        tags_str: String containing tags with potential source information
        
    Returns:
        Source string extracted from tags, or empty string if not found
    """
    if not tags_str:
        return ""
    
    pipe_index = tags_str.find('|')
    if pipe_index == -1:
        return tags_str.strip()
    
    return tags_str[:pipe_index].strip()

def convert_csv_to_markdown(csv_path: str, output_dir: str, delimiter: str = ';') -> None:
    """Convert CSV file to individual markdown files.
    
    Args:
        csv_path: Path to the CSV file to convert
        output_dir: Directory where markdown files will be created
        delimiter: CSV delimiter character (default: ';')
        
    Raises:
        FileNotFoundError: If CSV file doesn't exist
        PermissionError: If unable to create output directory or files
        ValueError: If CSV format is invalid
    """
    csv_file = Path(csv_path)
    if not csv_file.exists():
        raise FileNotFoundError(f"CSV file not found: {csv_path}")
    
    output_path = Path(output_dir)
    try:
        output_path.mkdir(parents=True, exist_ok=True)
    except PermissionError as e:
        raise PermissionError(f"Unable to create output directory: {e}")
    
    try:
        with open(csv_file, 'r', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile, delimiter=delimiter)
            
            for row_num, row in enumerate(reader, start=2):
                title = row.get('title', '').strip()
                if not title:
                    print(f"Warning: Skipping row {row_num} - no title", file=sys.stderr)
                    continue
                    
                # Sanitize filename
                filename = sanitize_filename(title) + '.md'
                filepath = output_path / filename
                
                # Extract data from CSV
                cover = row.get('remoteImageUrl', '')
                authors = parse_authors(row.get('authors', ''))
                published = format_date(row.get('releaseDate', ''))
                publisher = row.get('publishers', '')
                rating = row.get('userRating', '')
                pages = row.get('pages', '')
                language = row.get('languages', '')
                subtitle = row.get('subtitle', '')
                types = parse_list_field(row.get('types', ''))
                isbn10 = row.get('isbn10', '')
                isbn13 = row.get('isbn13', '')
                source = parse_source_from_tags(row.get('tags', ''))
                
                # Create markdown content
                content = "---\n"
                if cover:
                    content += f"cover: \"{cover}\"\n"
                if authors:
                    content += "author:\n"
                    for author in authors:
                        content += f"  - \"{author}\"\n"
                if published:
                    content += f"published: \"{published}\"\n"
                if publisher:
                    content += f"publisher: \"{publisher}\"\n"
                content += "rating: \n"
                if pages:
                    content += f"pages: {pages}\n"
                content += "lists: \n"
                content += "comment: \n"
                if language:
                    content += f"language: \"{language}\"\n"
                if subtitle:
                    content += f"subtitle: \"{subtitle}\"\n"
                if types:
                    content += "types:\n"
                    for type_item in types:
                        content += f"  - \"{type_item.lower()}\"\n"
                if isbn10:
                    content += f"isbn10: \"{isbn10}\"\n"
                if isbn13:
                    content += f"isbn13: \"{isbn13}\"\n"
                if source:
                    content += f"source: \"{source}\"\n"
                
                content += "---\n"
                content += f"# {title}\n\n"
                content += "## Reading Journey\n\n"
                
                # Add start reading date if available
                start_date = format_date(row.get('startReading', ''))
                if start_date:
                    content += f"- {start_date}: Started\n"
                
                # Add end reading date if available, convert to "Finished"
                end_date = format_date(row.get('endReading', ''))
                if end_date:
                    content += f"- {end_date}: Finished\n"
                
                # Write the markdown file
                try:
                    with open(filepath, 'w', encoding='utf-8') as mdfile:
                        mdfile.write(content)
                    print(f"Created: {filename}")
                except PermissionError as e:
                    print(f"Error: Unable to write file {filename}: {e}", file=sys.stderr)
                    continue
                    
    except UnicodeDecodeError as e:
        raise ValueError(f"Invalid CSV encoding: {e}")
    except csv.Error as e:
        raise ValueError(f"CSV parsing error: {e}")

def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments.
    
    Returns:
        Parsed command line arguments
    """
    parser = argparse.ArgumentParser(
        description='Convert Book Tracker CSV to individual markdown files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  %(prog)s input.csv output_dir
  %(prog)s "Book Tracker.csv" Books --delimiter=";"
        """
    )
    
    parser.add_argument(
        'csv_file',
        help='Path to the CSV file to convert'
    )
    
    parser.add_argument(
        'output_dir',
        help='Directory where markdown files will be created'
    )
    
    parser.add_argument(
        '--delimiter', '-d',
        default=';',
        help='CSV delimiter character (default: ";")',
        metavar='CHAR'
    )
    
    return parser.parse_args()


def main() -> None:
    """Main entry point for the script."""
    try:
        args = parse_arguments()
        convert_csv_to_markdown(args.csv_file, args.output_dir, args.delimiter)
        print(f"Successfully converted CSV to markdown files in {args.output_dir}")
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except PermissionError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nOperation cancelled by user", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
