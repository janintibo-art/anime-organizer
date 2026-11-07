"""V19 - conservative local visual matching for repeated opening/ending sequences.
Command: AnimeOrganizerCreditsDetector.exe <json input file>.
Output: one JSON object on stdout; never edits videos or application state.
Requires ffmpeg and ffprobe in PATH or next to executable.
"""
import json, math, os, shutil, subprocess, sys
from pathlib import Path

HEAD = 450
TAIL = 330
FRAME_BYTES = 12 * 8
MIN_LENGTH = 40
MAX_FILES = 4

def locate(name):
    local = Path(sys.executable).resolve().parent / (name + ('.exe' if os.name == 'nt' else ''))
    return str(local) if local.is_file() else shutil.which(name)

def duration(probe, path):
    r = subprocess.run([probe, '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1', path], capture_output=True,
        text=True, timeout=20)
    if r.returncode: raise RuntimeError('ffprobe a échoué')
    return float(r.stdout.strip())

def frames(ffmpeg, path, start, seconds):
    cmd = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin',
        '-ss', str(max(0, start)), '-i', path, '-t', str(seconds), '-an',
        '-vf', 'fps=1,scale=12:8:flags=area,format=gray', '-f', 'rawvideo', 'pipe:1']
    r = subprocess.run(cmd, capture_output=True, timeout=105)
    if r.returncode: raise RuntimeError('ffmpeg ne peut pas analyser une vidéo')
    result = []
    for i in range(0, len(r.stdout) - FRAME_BYTES + 1, FRAME_BYTES):
        a = r.stdout[i:i+FRAME_BYTES]
        mean = sum(a) / FRAME_BYTES
        variance = sum((v-mean)**2 for v in a) / FRAME_BYTES
        bits = sum(1 << j for j, v in enumerate(a) if v >= mean)
        result.append((bits, variance))
    return result

def similar(a, b):
    if min(a[1], b[1]) < 110: return False  # blank frames / credits fades
    return (a[0] ^ b[0]).bit_count() <= 15

def best_region(a, b, kind):
    # Scan displacement between episodes (recaps can shift the OP).
    best = None
    for shift in range(-150, 151, 3):
        lo = max(0, -shift)
        hi = min(len(a), len(b)-shift)
        if hi-lo < MIN_LENGTH: continue
        # Running 50 second matching window: robust to transitions and edits.
        matches = [int(similar(a[i], b[i+shift])) for i in range(lo, hi)]
        width = 50
        if len(matches) < width: continue
        score = sum(matches[:width])
        for j in range(0, len(matches)-width+1):
            if j:
                score += matches[j+width-1]-matches[j-1]
            if score < 37: continue
            start = lo+j
            end = start+width
            # Grow over consecutive nearby matching windows.
            while end+5 <= hi and sum(matches[end-lo:end-lo+5]) >= 4:
                end += 5
            length = end-start
            rank = length * (score / width)
            # Ignore recurring splash logos (shorter than 40s, guard already).
            if best is None or rank > best[0]: best = (rank,start,end,shift)
    return best

def detect(paths):
    ffmpeg, ffprobe = locate('ffmpeg'), locate('ffprobe')
    if not ffmpeg or not ffprobe:
        return {'ok':False,'error':'FFmpeg et ffprobe sont nécessaires sur le PC.'}
    source=[]
    for path in paths[:MAX_FILES]:
        p=Path(path)
        if not p.is_file(): continue
        d=duration(ffprobe, str(p))
        if d < 600: continue
        source.append({'path':str(p),'duration':d,
            'head':frames(ffmpeg,str(p),0,min(HEAD,d/2)),
            'tailStart':max(0,d-TAIL),
            'tail':frames(ffmpeg,str(p),max(0,d-TAIL),min(TAIL,d))})
    if len(source)<3:
        return {'ok':False,'error':'Au moins 3 épisodes lisibles de la même saison sont nécessaires.'}
    proposals={}
    for kind in ('intro','outro'):
        field='head' if kind=='intro' else 'tail'
        ref=source[0][field]
        first=best_region(ref,source[1][field],kind)
        if not first: continue
        _, astart, aend, shift = first
        # Validate shared sequence in episode 3 at nearly the same timeline.
        third=best_region(ref,source[2][field],kind)
        if not third: continue
        _, tstart,tend,tshift=third
        overlap=min(aend,tend)-max(astart,tstart)
        if overlap<35: continue
        # For whole-season reuse require absolute coordinates to agree.
        start=max(astart,tstart)
        end=min(aend,tend)
        times=[]
        for i,offset in [(0,0),(1,shift),(2,tshift)]:
            s=start+offset + (source[i]['tailStart'] if kind=='outro' else 0)
            e=end+offset + (source[i]['tailStart'] if kind=='outro' else 0)
            times.append((s,e))
        if kind=='intro':
            value=max(x[1] for x in times)+1
            if value > 600: continue
            key='introEnd'
        else:
            value=min(x[0] for x in times)
            if value < 120: continue
            key='outroStart'
        spread=max((x[1] if kind=='intro' else x[0]) for x in times)-min((x[1] if kind=='intro' else x[0]) for x in times)
        if spread>12: continue
        proposals[key]={'milliseconds':int(value*1000),'confidence':'élevée' if spread<=5 else 'moyenne',
           'sources':3,'spreadSeconds':round(spread,1)}
    return {'ok':True,'analyzed':len(source),'proposals':proposals,
        'warning':'Suggestions visuelles : valider avant de modifier les repères. Un générique variable peut ne pas être détecté.'}

def main():
    try:
        if len(sys.argv)!=2: raise ValueError('Fichier JSON attendu.')
        with open(sys.argv[1],encoding='utf-8') as f: data=json.load(f)
        paths=data.get('paths',[])
        if not isinstance(paths,list) or len(paths)<3 or any(not isinstance(x,str) for x in paths):
            raise ValueError('Sélectionne au moins trois vidéos.')
        print(json.dumps(detect(paths),ensure_ascii=False))
    except Exception as e:
        print(json.dumps({'ok':False,'error':str(e)},ensure_ascii=False))
        sys.exit(1)
if __name__=='__main__': main()
