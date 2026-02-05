import os
import sys
import glob
import xml.etree.ElementTree as ET
from datetime import timedelta

def parse_time(time_str):
    """Converts TTML time format (00:00:00.000) to seconds."""
    try:
        if not time_str:
            return 0
        
        # Handle '00:00:00.000' format
        h, m, s = time_str.split(':')
        s, ms = s.split('.') if '.' in s else (s, 0)
        
        seconds = int(h) * 3600 + int(m) * 60 + int(s) + float(f"0.{ms}")
        return seconds
    except ValueError:
        return 0

def to_lrc_time(seconds):
    """Converts seconds to LRC format [mm:ss.xx]."""
    m = int(seconds // 60)
    s = int(seconds % 60)
    cs = int((seconds - int(seconds)) * 100) # centiseconds
    return f"[{m:02d}:{s:02d}.{cs:02d}]"

def convert_ttml_to_lrc(ttml_file):
    tree = ET.parse(ttml_file)
    root = tree.getroot()
    
    # TTML namespace handling (often required)
    ns = {'tt': 'http://www.w3.org/ns/ttml'}
    
    lrc_lines = []
    
    # Find all 'p' tags in the body
    for p in root.findall('.//tt:p', ns) or root.findall('.//{http://www.w3.org/ns/ttml}p'):
        begin = p.get('begin')
        text = "".join(p.itertext()).strip()
        
        if begin and text:
            # Clean 't' suffix if present (e.g., '0.5s', '100t') - simplified for standard HH:MM:SS
            begin = begin.replace('t', '') 
            
            seconds = parse_time(begin)
            lrc_timestamp = to_lrc_time(seconds)
            lrc_lines.append(f"{lrc_timestamp} {text}")

    output_file = os.path.splitext(ttml_file)[0] + ".lrc"
    
    # Add timestamped empty line at end
    if lrc_lines:
        last_seconds = parse_time(root.findall('.//tt:p', ns)[-1].get('begin', '0'))
        final_timestamp = to_lrc_time(last_seconds + 1)  # 1 second after last line
        lrc_lines.append(f"{final_timestamp}")
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("\n".join(lrc_lines))
        f.write("\n")
    print(f"Converted: {ttml_file} -> {output_file}")

if __name__ == "__main__":
    files = glob.glob("*.ttml")
    if not files:
        print("No .ttml files found in current directory.")
    for f in files:
        convert_ttml_to_lrc(f)