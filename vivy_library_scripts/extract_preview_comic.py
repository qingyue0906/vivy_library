#!/usr/bin/env python3
"""
轻量版：提取第一个 zip/cbz 或第一个含图片的子文件夹中的第一张图，
复制为 preview.xxx（原图后缀）。无排序，找到即停。
若已存在 preview.* 则跳过。
"""

import sys
import os
import zipfile
import shutil

IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'}
ARCHIVE_EXTS = {'.zip', '.cbz'}

def is_image_file(filename):
    return os.path.splitext(filename)[1].lower() in IMAGE_EXTS

def preview_exists(dir_path):
    for f in os.listdir(dir_path):
        full = os.path.join(dir_path, f)
        if os.path.isfile(full):
            name, ext = os.path.splitext(f)
            if name.lower() == 'preview' and ext.lower() in IMAGE_EXTS:
                return True
    return False

def extract_first_image_from_zip(zip_path, output_dir):
    with zipfile.ZipFile(zip_path, 'r') as zf:
        # 遍历所有文件信息，找到第一个图片立即提取
        for info in zf.infolist():
            fname = info.filename
            if is_image_file(fname) and not fname.endswith('/'):
                ext = os.path.splitext(fname)[1]
                out_path = os.path.join(output_dir, f'preview{ext}')
                data = zf.read(fname)
                with open(out_path, 'wb') as f:
                    f.write(data)
                return out_path, fname
    return None, None

def extract_first_image_from_folder(folder_path, output_dir):
    for f in os.listdir(folder_path):
        full = os.path.join(folder_path, f)
        if os.path.isfile(full) and is_image_file(f):
            ext = os.path.splitext(f)[1]
            out_path = os.path.join(output_dir, f'preview{ext}')
            shutil.copy2(full, out_path)
            return out_path, f
    return None, None

def main():
    if len(sys.argv) < 2:
        print('Usage: extract_preview.py <directory_path>')
        sys.exit(1)

    dir_path = sys.argv[1]
    if not os.path.isdir(dir_path):
        print(f'Error: not a directory: {dir_path}')
        sys.exit(1)

    if preview_exists(dir_path):
        print(f'Preview image already exists in {dir_path}, skipping.')
        return

    entries = os.listdir(dir_path)
    entries.sort()  # 排序仅影响查找顺序，不影响性能（数量少时忽略）
    for entry in entries:
        full_path = os.path.join(dir_path, entry)

        if os.path.isfile(full_path):
            ext = os.path.splitext(entry)[1].lower()
            if ext in ARCHIVE_EXTS:
                out_path, inner = extract_first_image_from_zip(full_path, dir_path)
                if out_path:
                    print(f'Extracted from archive {entry} (inner: {inner}) -> {out_path}')
                    return
                else:
                    print(f'Archive {entry} has no images, skip.')
                    continue

        elif os.path.isdir(full_path):
            out_path, fname = extract_first_image_from_folder(full_path, dir_path)
            if out_path:
                print(f'Extracted from folder {entry} (file: {fname}) -> {out_path}')
                return
            else:
                print(f'Folder {entry} has no images, skip.')
                continue

    print('No zip/cbz archives or folders with images found.')
    sys.exit(1)

if __name__ == '__main__':
    main()