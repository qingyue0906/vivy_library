"""
从 project.json (wallpaper engine) 提取标题/标签/描述，
生成 info.json 并同步文件时间戳。
"""
import sys
import os
import json
import re


def main():
    if len(sys.argv) < 2:
        print('Usage: generate_info.py <directory_path>')
        sys.exit(1)

    folder_path = sys.argv[1].strip('"').strip()

    if not os.path.isdir(folder_path):
        print(f'Error: not a directory: {folder_path}')
        sys.exit(1)

    project_json_path = os.path.join(folder_path, 'project.json')
    if not os.path.exists(project_json_path):
        print(f'No project.json found in {folder_path}, skipped.')
        return

    try:
        project_stat = os.stat(project_json_path)
        original_atime = project_stat.st_atime
        original_mtime = project_stat.st_mtime

        with open(project_json_path, 'r', encoding='utf-8') as f:
            p_data = json.load(f)

        p_title = p_data.get('title', '')

        tags_list = []
        tag_match = re.search(r'\[(.*?)\]', p_title)
        if tag_match:
            tags_list = [t.strip() for t in tag_match.group(1).split() if t.strip()]

        info_data = {
            'title': os.path.basename(folder_path),
            'description': p_data.get('description', ''),
            'creator': None,
            'type': p_data.get('type', ''),
            'contentrating': 'G',
            'rating': 5,
            'class': [],
            'tags': tags_list,
        }

        info_json_path = os.path.join(folder_path, 'info.json')
        with open(info_json_path, 'w', encoding='utf-8') as f:
            json.dump(info_data, f, ensure_ascii=False, indent=4)

        os.utime(info_json_path, (original_atime, original_mtime))

        print(f'Generated: {info_json_path}')

    except Exception as e:
        print(f'Error processing {folder_path}: {e}')
        sys.exit(1)


if __name__ == '__main__':
    main()