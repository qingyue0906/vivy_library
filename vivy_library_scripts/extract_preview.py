"""
提取第一个视频的第一帧作为 preview.jpg。
目录中已有图片则跳过。
"""

import sys
import os
import subprocess

IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'}
VIDEO_EXTS = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.wmv'}

def main():
    if len(sys.argv) < 2:
        print('Usage: extract_preview.py <directory_path>')
        sys.exit(1)

    dir_path = sys.argv[1]
    if not os.path.isdir(dir_path):
        print(f'Error: not a directory: {dir_path}')
        sys.exit(1)

    has_image = any(
        f.lower().endswith(tuple(IMAGE_EXTS))
        for f in os.listdir(dir_path)
        if os.path.isfile(os.path.join(dir_path, f))
    )

    if has_image:
        print(f'Image files already exist in {dir_path}, skipping.')
        return

    videos = [
        f for f in os.listdir(dir_path)
        if os.path.isfile(os.path.join(dir_path, f))
        and f.lower().endswith(tuple(VIDEO_EXTS))
    ]

    if not videos:
        print(f'No video files found in {dir_path}')
        return

    first_video = os.path.join(dir_path, videos[0])
    output = os.path.join(dir_path, 'preview.jpg')

    result = subprocess.run(
        ['ffmpeg', '-y', '-i', first_video, '-vframes', '1', output],
        capture_output=True, text=True,
    )

    if result.returncode == 0:
        print(f'Extracted preview from {videos[0]} -> {output}')
    else:
        print(f'ffmpeg failed:\n{result.stderr}')
        sys.exit(1)

if __name__ == '__main__':
    main()