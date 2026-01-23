#!/usr/bin/env python3
"""
Extract CVA6 RTL files from Flist.cva6 for Makefile inclusion
Works on Windows and Linux
"""

import re
import sys
import os

def process_flist_file(flist_path, cva6_repo_dir, target_cfg, processed_flists=None):
    """Process a Flist file and return files and include directories"""
    if processed_flists is None:
        processed_flists = set()
    
    # Normalize path to avoid processing same file twice
    flist_path = os.path.normpath(os.path.abspath(flist_path))
    if flist_path in processed_flists:
        return [], []
    processed_flists.add(flist_path)
    
    if not os.path.exists(flist_path):
        print(f"Warning: Flist not found at {flist_path}", file=sys.stderr)
        return [], []
    
    with open(flist_path, 'r') as f:
        content = f.read()
    
    # Calculate HPDCACHE_DIR before replacement
    # HPDCACHE_DIR should point to hpdcache directory (without /rtl) since Flist uses ${HPDCACHE_DIR}/rtl/...
    hpdcache_dir = os.path.join(cva6_repo_dir, 'core', 'cache_subsystem', 'hpdcache')
    
    # Replace variables (order matters - do HPDCACHE_DIR first since it contains CVA6_REPO_DIR pattern)
    content = content.replace('${HPDCACHE_DIR}', hpdcache_dir.replace('\\', '/'))
    content = content.replace('${CVA6_REPO_DIR}', cva6_repo_dir.replace('\\', '/'))
    content = content.replace('${TARGET_CFG}', target_cfg)
    
    files = []
    include_dirs = []
    
    for line in content.split('\n'):
        line = line.strip()
        # Skip comments and empty lines
        if not line or line.startswith('//'):
            continue
        
        # Extract include directories
        if line.startswith('+incdir'):
            incdir = line.replace('+incdir+', '').strip()
            if incdir:
                include_dirs.append(incdir)
            continue
        
        # Handle -F references (file lists) - recursively process them
        if line.startswith('-F'):
            # Extract the Flist path (after variable replacement, paths are relative to cva6_repo_dir)
            flist_ref = line[2:].strip()
            # After variable replacement, paths are relative to cva6_repo_dir
            # Check if it's already an absolute path (after variable replacement)
            if os.path.isabs(flist_ref):
                # Already absolute, use as-is
                pass
            else:
                # Relative to cva6_repo_dir
                flist_ref = os.path.join(cva6_repo_dir, flist_ref)
            # Normalize the path
            flist_ref = os.path.normpath(flist_ref)
            # Recursively process the referenced Flist
            sub_files, sub_incdirs = process_flist_file(flist_ref, cva6_repo_dir, target_cfg, processed_flists)
            files.extend(sub_files)
            include_dirs.extend(sub_incdirs)
            continue
        
        # Extract file paths (.sv, .svh, .v)
        if re.match(r'.*\.(sv|svh|v)$', line):
            # Normalize path separators - all paths should use forward slashes
            file_path = line.replace('\\', '/')
            
            # Convert to relative path from integration/ directory
            # All paths in Flist.cva6 are relative to CVA6_REPO_DIR
            if not file_path.startswith('../'):
                # Make it relative from integration/
                file_path = '../' + file_path
            
            files.append(file_path)
    
    return files, include_dirs

def extract_cva6_files(cva6_repo_dir, target_cfg='cv32a60x', output_file=None):
    """Extract all CVA6 RTL files from Flist.cva6"""
    flist_path = os.path.join(cva6_repo_dir, 'core', 'Flist.cva6')
    
    if not os.path.exists(flist_path):
        print(f"Error: Flist.cva6 not found at {flist_path}", file=sys.stderr)
        return [], []
    
    files, include_dirs = process_flist_file(flist_path, cva6_repo_dir, target_cfg)
    
    if output_file:
        with open(output_file, 'w') as f:
            f.write('\n'.join(files))
        print(f"Extracted {len(files)} CVA6 files to {output_file}", file=sys.stderr)
    
    return files, include_dirs

if __name__ == '__main__':
    cva6_repo_dir = sys.argv[1] if len(sys.argv) > 1 else '../cva6'
    target_cfg = sys.argv[2] if len(sys.argv) > 2 else 'cv32a60x'
    output_file = sys.argv[3] if len(sys.argv) > 3 else 'cva6_files.list'
    
    files, incdirs = extract_cva6_files(cva6_repo_dir, target_cfg, output_file)
    
    # Output files (space-separated for Makefile)
    print(' '.join(files))
