"""Shadow Studio: a single-user, loopback-only English and French shadowing workspace."""
import os
from pathlib import Path
ROOT = Path(__file__).resolve().parent
os.environ.setdefault('HF_HOME', str(ROOT / 'data' / 'models'))
os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')
import urllib.request, json, re, secrets, shutil, subprocess, threading, time, uuid, math, ipaddress, socket, hashlib, base64, random, unicodedata
from types import SimpleNamespace
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse, parse_qs
import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly
from scipy.ndimage import minimum_filter1d, maximum_filter1d
from fastapi import FastAPI, HTTPException, Request, UploadFile, File, Form
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

DATA = ROOT / 'data'
DATA.mkdir(exist_ok=True)
TOKEN = secrets.token_urlsafe(32)
ENGINE_SIGNATURE = hashlib.sha256(str(ROOT).encode()+b'\0'+Path(__file__).read_bytes()).hexdigest()
PORT = int(os.environ.get('SHADOW_PORT', '8765'))
LAN = os.environ.get('SHADOW_LAN') == '1'
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
executor = ThreadPoolExecutor(max_workers=1)
jobs = {}
models = {}
LANGUAGES = {'en': 'English', 'fr': 'French'}
model_lock = threading.Lock()
file_lock = threading.RLock()

def lan_host(host):
    name, _, port = host.rpartition(':')
    try: return port == str(PORT) and ipaddress.ip_address(name).is_private
    except ValueError: return False

@app.middleware('http')
async def local_only(request, call_next):
    host = request.headers.get('host') or ''
    if host not in {f'127.0.0.1:{PORT}', f'localhost:{PORT}'} and not (LAN and lan_host(host)):
        return JSONResponse({'detail':'Use the local app address.'}, status_code=403)
    if request.method not in ('GET','HEAD') and request.headers.get('x-shadow-token') != TOKEN:
        return JSONResponse({'detail':'Refresh the app and try again.'}, status_code=403)
    response = await call_next(request)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"
    return response

@app.get('/')
def home():
    return HTMLResponse((ROOT/'static/index.html').read_text().replace('__TOKEN__', TOKEN))
app.mount('/static', StaticFiles(directory=ROOT/'static'), name='static')

def ident(value):
    if not re.fullmatch(r'[0-9a-f]{32}', value): raise HTTPException(404, 'Not found')
    return value

def folder(lid):
    return DATA / ident(lid)

def read_lesson(lid):
    try: return json.loads((folder(lid)/'lesson.json').read_text())
    except FileNotFoundError: raise HTTPException(404, 'Lesson not found')

def save_lesson(lesson):
    target = folder(lesson['id'])/'lesson.json'
    with file_lock:
        temp = target.with_suffix('.tmp')
        try:
            temp.write_text(json.dumps(lesson, ensure_ascii=False, indent=2))
            temp.replace(target)
        except Exception:
            temp.unlink(missing_ok=True)
            raise

def phrase_revision(lesson, index):
    p=lesson['phrases'][index]
    revision={k:p[k] for k in ('start','end','text')}
    # Existing clients can fetch an identity for a legacy phrase without rewriting the lesson.
    key=p.get('revision') or hashlib.sha256(json.dumps([lesson['id'],index,revision],sort_keys=True).encode()).hexdigest()[:32]
    return revision | {'id':key}

def legacy_take(lesson, index):
    result=lesson['phrases'][index].get('latest')
    if result and not result.get('phraseRevision'):
        return result | {'phraseRevision':phrase_revision(lesson,index),'legacy':True}

def archive_phrase(lesson, index):
    revision=phrase_revision(lesson,index)
    lesson.setdefault('archivedRevisions',{})[revision['id']]=revision
    if old:=legacy_take(lesson,index):
        lesson.setdefault('takeHistory',[]).append(old)

def public_lesson(lesson):
    history=lesson.get('takeHistory',[])+[old for i in range(len(lesson['phrases'])) if (old:=legacy_take(lesson,i))]
    return {k:v for k,v in lesson.items() if k!='archivedRevisions'} | {
        'phrases':[p | {'revision':phrase_revision(lesson,i)['id']} for i,p in enumerate(lesson['phrases'])],
        'takeHistory':sorted(history,key=lambda r:r.get('created') or 0,reverse=True),
    }

def run(cmd, timeout=180):
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if result.returncode: raise ValueError('Audio processing failed. Try another audio or video file.')
    return result.stdout

def convert(source, destination, start=None, duration=None):
    cmd = [shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg','-nostdin','-v','error','-y']
    if start is not None: cmd += ['-ss',str(start)]
    cmd += ['-i',str(source)]
    if duration is not None: cmd += ['-t',str(duration)]
    cmd += ['-vn','-ac','1','-ar','16000',str(destination)]
    run(cmd)

def load_audio(path):
    sr, y = wavfile.read(path)
    if y.ndim > 1: y = y.mean(axis=1)
    if np.issubdtype(y.dtype, np.integer): y = y.astype(np.float64)/max(abs(np.iinfo(y.dtype).min),np.iinfo(y.dtype).max)
    if sr != 16000: y = resample_poly(y,16000,sr)
    return y.astype(np.float32)

def import_language(language):
    if language not in ('en','fr'): raise HTTPException(400,'Choose English or French for this session.')
    return language

def transcribe(path, language):
    with model_lock:
        if language not in models:
            from faster_whisper import WhisperModel
            models[language] = WhisperModel('base.en' if language=='en' else 'base', device='cpu', compute_type='int8', download_root=str(DATA/'models'))
        segments, info = models[language].transcribe(str(path), language=language, word_timestamps=True, vad_filter=True, condition_on_previous_text=False, beam_size=5)
        return list(segments)

CLAUSE_START={'and','but','or','so','because','although','though','while','whereas','when','whenever','where','wherever','if','unless','until','since','after','before','which','who','whom','whose','then','however','yet','nor','also','actually','anyway','instead','otherwise','therefore','meanwhile','plus'}
NO_END={'a','an','the','my','your','his','its','our','their','this','these','those','of','to','in','on','at','for','with','from','by','about','into','onto','than','and','or','but','so','because','if','that','which','who','whose','i','we','they','he','she','is','are','was','were','am','be','been','do','does','did','have','has','had','will','would','can','could','should','shall','may','might','must','very','such',"i'm","you're","we're","they're","it's","that's","there's","he's","she's","i've","you've","we've","they've","i'll","you'll","we'll","they'll","i'd","you'd","we'd","they'd","don't","doesn't","didn't","can't","won't","isn't","aren't","wasn't","weren't","let's",'gonna','wanna','gotta'}
ABBREV={'mr','mrs','ms','dr','prof','st','vs','jr','sr'}
TAIL,LEAD=.3,.15
AUTO_PHRASE_MAX=8.

def speech_map(y):
    # 10 ms loudness frames and a quiet mask judged against the local noise floor, so tails count as sound in clean and noisy audio alike.
    if len(y)<160: y=np.pad(y,(0,160-len(y)))
    n=len(y)//160; frames=y[:n*160].reshape(n,160)
    db=10*np.log10(np.convolve(np.einsum('ij,ij->i',frames,frames,dtype=np.float64)/160,np.ones(3)/3,mode='same')+1e-10)
    m=-(-n//100); blocks=np.pad(db,(0,m*100-n),mode='edge').reshape(m,100)
    floor=minimum_filter1d(np.percentile(blocks,10,axis=1),21); level=np.maximum(maximum_filter1d(np.percentile(blocks,95,axis=1),5),np.percentile(db,95)-20)
    thr=np.interp(np.arange(n),np.arange(m)*100+50,np.clip(floor+np.clip(.35*(level-floor),6,14),level-50,level-10))
    quiet=db<thr
    try:
        from faster_whisper.vad import get_vad_model
        padded=np.pad(y,(0,512-len(y)%512))
        vad=np.asarray(get_vad_model()(padded),dtype=np.float32).reshape(len(padded)//512,-1)[:,0]
        quiet&=(vad[np.minimum(len(vad)-1,(np.arange(n)*160+80)//512)]<.35)|(db<thr-10)
    except Exception: pass
    return db,quiet

def quiet_runs(mask):
    edges=np.flatnonzero(np.diff(np.concatenate(([False],mask,[False])).astype(np.int8)))
    return [[int(s),int(e)] for s,e in zip(edges[::2],edges[1::2])]

def pause_between(a, b, quiet):
    # Only one continuous pause can define a cut. Joining separate quiet runs can swallow a consonant between them.
    n=len(quiet); g0,g1=a['end'],b['start']
    lo=max(0,math.ceil(max((a['start']+g0)/2,g0-.12)*100)); hi=min(n,math.floor(min((g1+b['end'])/2,g1+.12)*100))
    candidates=[]
    for s,e in quiet_runs(quiet[lo:max(lo,hi)]):
        s=(s+lo)/100; e=(e+lo)/100
        if e-s<.12: continue
        dist=max(0,g0-e,s-g1)
        if dist>.06: continue
        # Sound after this pause but before the next word may be the previous word's final consonant.
        tail=quiet[round(e*100):max(round(e*100),math.floor((g1-.03)*100))]
        if np.count_nonzero(~tail)>2: continue
        candidates.append((dist,-min(e-s,.4),s,e))
    if candidates:
        _,_,s,e=min(candidates)
        return s,e
    # This is only a word-timing fallback for speech with no safe pause, not an acoustic boundary.
    c=max((a['start']+g0)/2,min((g0+g1)/2,(g1+b['end'])/2))
    return c,c

def sound_start(w, quiet):
    n=len(quiet); i0=min(n-1,max(0,int((w['start']-.3)*100))); i1=min(n,max(i0,int(w['start']*100)))
    rs=[[s+i0,e+i0] for s,e in quiet_runs(quiet[i0:i1]) if e-s>=15 or s+i0==0]
    if not rs: return w['start']
    e=rs[-1][1]
    return e/100

def sound_end(w, quiet):
    n=len(quiet); i0=min(n-1,max(0,math.ceil(w['end']*100))); i1=min(n,max(i0+1,int((w['end']+.6)*100)))
    rs=[[s+i0,e+i0] for s,e in quiet_runs(quiet[i0:i1]) if e-s>=15 or e+i0==n]
    if not rs: return min(n/100,w['end']+.2)
    s=rs[0][0]
    return s/100

def break_punctuation(word, nxt):
    tail=word.strip().rstrip('"\'\u201d\u2019»)]}'); core=re.sub(r"[^a-z']","",tail.lower().replace('\u2019',"'"))
    if core in ABBREV or re.fullmatch(r"(?:[A-Za-z]\.)+",tail): punct=0
    elif tail.endswith(('...','\u2026',';',':')): punct=.7
    elif tail.endswith(('.','!','?')): punct=1
    elif tail.endswith(('\u2014','\u2013','-')) or nxt.strip().startswith(('\u2014','\u2013','-')): punct=.6
    elif tail.endswith(','): punct=.35
    else: punct=0
    return punct

def break_score(word, nxt, pause, seg_end):
    tail=word.strip().rstrip('"\'\u201d\u2019»)]}'); punct=break_punctuation(word,nxt); core=re.sub(r"[^a-z']","",tail.lower().replace('\u2019',"'")); head=re.sub(r"[^a-z']","",nxt.lower().replace('\u2019',"'"))
    score=2*punct+.5*(1-math.exp(-pause/.25))+(.1 if seg_end else 0)-(.15 if pause<.05 else 0)+(.2 if head in CLAUSE_START else .1 if head=='that' else 0)
    return score-(.6 if not punct and core in NO_END else 0)

def phrase_cost(seconds, count):
    eff=max(seconds,.3*count)
    return (2.5*math.log(eff/5.5)**2 if eff>5.5 else .9*math.log(eff/2)**2 if eff<2 else 0)+(.4 if count==1 else .15 if count==2 else 0)

def make_phrases(segments, audio):
    words=[]; seg_end=set()
    for seg in segments:
        if seg.no_speech_prob > .8: continue
        for w in (seg.words or []):
            if not any(ch.isalnum() for ch in w.word):
                if words: words[-1]['word']+=w.word
                continue
            start=max(float(w.start),words[-1]['start'] if words else 0.)
            words.append({'start':start,'end':max(float(w.end),start+.02),'word':w.word})
        if words: seg_end.add(len(words)-1)
    if not words: return []
    _,quiet=speech_map(audio); total=len(audio)/16000; n=len(words)
    gaps=[pause_between(words[k],words[k+1],quiet) for k in range(n-1)]
    on=[sound_start(words[0],quiet)]+[g[1] for g in gaps]; off=[g[0] for g in gaps]+[sound_end(words[-1],quiet)]
    pause=[b-a for a,b in gaps]
    score=[break_score(words[k]['word'],words[k+1]['word'],pause[k],k in seg_end) for k in range(n-1)]
    sentence=[break_punctuation(words[k]['word'],words[k+1]['word'])==1 for k in range(n-1)]
    # Sentence endings and short practice chunks take priority; prefer an acoustic pause when choosing other cuts.
    best=[0.]+[math.inf]*n; back=[0]*(n+1)
    for j in range(n):
        inner=0.; longest=0.
        for i in range(j,-1,-1):
            if i<j:
                if sentence[i] or off[j]-on[i]+TAIL+LEAD>AUTO_PHRASE_MAX: break
                longest=max(longest,pause[i]); inner+=max(0,pause[i]-.7)*1.5
                if longest>1.6: break
            cost=best[i]+phrase_cost(off[j]-on[i],j-i+1)+inner
            if j<n-1: cost+=(1.5 if not pause[j] else 0)-score[j]+.7
            if cost<best[j+1]: best[j+1]=cost; back[j+1]=i
    spans=[]; j=n
    while j: spans.append((back[j],j-1)); j=back[j]
    def cut(k):
        a,b=gaps[k]; room=b-a
        if room>=TAIL+LEAD: return a+TAIL,b-LEAD
        c=(a+b)/2; return c,c
    phrases=[]
    for i,j in reversed(spans):
        start=max(0,on[0]-LEAD) if i==0 else cut(i-1)[1]
        end=min(total,off[-1]+TAIL) if j==n-1 else cut(j)[0]
        ws=[dict(w) for w in words[i:j+1]]
        ws[0]['start']=max(start,min(ws[0]['start'],on[i])); ws[-1]['end']=min(end,max(ws[-1]['end'],off[j]))
        for w in ws: w['start']=round(w['start'],3); w['end']=round(w['end'],3)
        phrases.append({'start':round(start,3),'end':round(max(end,start+.1),3),'text':''.join(w['word'] for w in ws).strip(),'words':ws,'practised':False})
    return phrases

def job_start(action):
    jid=uuid.uuid4().hex
    jobs[jid]={'state':'working','message':'Preparing audio…'}
    def work():
        try:
            lid=action(jid)
            jobs[jid]={'state':'done','lessonId':lid}
        except Exception as exc:
            msg=str(exc)
            cleanup=jobs[jid].get('cleanup')
            if cleanup:
                target=Path(cleanup)
                if target.parent==DATA and not (target/'lesson.json').exists(): shutil.rmtree(target,ignore_errors=True)
            jobs[jid]={'state':'error','message':msg if isinstance(exc,ValueError) else 'Processing failed. Check your connection for the first model download, then try again.'}
    executor.submit(work)
    return {'jobId':jid}

def finish_import(lid, title, source, jid, language, segments=None):
    path=folder(lid)
    audio=load_audio(path/'audio.wav')
    if len(audio)>16000*1800: raise ValueError('Choose a video or file under 30 minutes for focused practice.')
    jobs[jid]['message']='Finding phrases…'+('' if segments else ' The first import downloads a speech model (about 150 MB).')
    phrases=make_phrases(segments or transcribe(path/'audio.wav', language), audio)
    if not phrases: raise ValueError(f'No clear {LANGUAGES[language]} speech found. Try a clip with a single speaker and little music.')
    lesson={'id':lid,'title':title[:160],'source':source,'created':time.time(),'duration':round(len(audio)/16000,2),'phrases':phrases,'sample':False,'language':language}
    save_lesson(lesson)
    return lid

@app.get('/api/library')
def library():
    lessons=[]
    for p in DATA.glob('*/lesson.json'):
        try:
            l=json.loads(p.read_text()); lessons.append({k:l[k] for k in ['id','title','source','created','duration','sample']} | {'language':l.get('language','en'),'count':len(l['phrases']),'practised':sum(bool(x.get('practised')) for x in l['phrases'])})
        except (ValueError,KeyError): pass
    return sorted(lessons,key=lambda x:x['created'],reverse=True)

def training_progress():
    path=DATA/'voice-training.json'
    if not path.exists(): return {'completed':[]}
    try:
        body=json.loads(path.read_text())
        if not isinstance(body,dict) or not isinstance(body.get('completed'),list): raise ValueError()
        return {'completed':[x for x in body['completed'] if isinstance(x,str) and re.fullmatch(r'[a-z-]+\.[a-z0-9-]+',x)]}
    except (ValueError,OSError): raise HTTPException(500,'Voice Training progress could not be read. Your saved file has been kept.')

@app.get('/api/voice-training/progress')
def get_training_progress(): return training_progress()

@app.post('/api/voice-training/progress')
async def complete_training_exercise(request:Request):
    if len(raw:=await request.body())>1024: raise HTTPException(413,'Progress update is too large.')
    try: exercise=json.loads(raw).get('exercise')
    except (ValueError,AttributeError): raise HTTPException(400,'Choose a Voice Training exercise.')
    if not isinstance(exercise,str) or len(exercise)>80 or not re.fullmatch(r'[a-z-]+\.[a-z0-9-]+',exercise): raise HTTPException(400,'Choose a Voice Training exercise.')
    with file_lock:
        progress=training_progress()
        if exercise not in progress['completed']:
            if len(progress['completed'])>=1000: raise HTTPException(400,'The saved practice list is full.')
            progress['completed'].append(exercise)
            path=DATA/'voice-training.json'; temp=path.with_suffix('.tmp')
            try: temp.write_text(json.dumps(progress,indent=2)); temp.replace(path)
            except OSError: raise HTTPException(500,'Progress could not be saved. Please try again.')
        return progress

@app.get('/api/lesson/{lid}')
def lesson(lid:str): return public_lesson(read_lesson(lid))

@app.get('/api/audio/{lid}')
def audio(lid:str):
    read_lesson(lid)
    return FileResponse(folder(lid)/'audio.wav', media_type='audio/wav')

@app.get('/api/jobs/{jid}')
def job(jid:str):
    if jid not in jobs: raise HTTPException(404,'Job not found')
    return {k:v for k,v in jobs[jid].items() if k!='cleanup'}

@app.post('/api/import')
async def youtube(request:Request):
    body=await request.json()
    language=import_language(body.get('language','en'))
    url=str(body.get('url','')).strip()
    parsed=urlparse(url)
    host=(parsed.hostname or '').lower()
    vid=None
    if host in ('youtube.com','www.youtube.com','m.youtube.com'):
        vid=parse_qs(parsed.query).get('v',[None])[0] if parsed.path=='/watch' else (parsed.path.split('/')[2] if parsed.path.startswith(('/shorts/','/embed/','/live/')) and len(parsed.path.split('/'))>2 else None)
    elif host=='youtu.be': vid=parsed.path.strip('/')
    if parsed.scheme not in ('https','http') or not vid or not re.fullmatch(r'[\w-]{11}',vid): raise HTTPException(400,'Paste a YouTube video link, rather than a channel or playlist.')
    canonical='https://www.youtube.com/watch?v='+vid
    def action(jid):
        import yt_dlp
        lid=uuid.uuid4().hex; path=folder(lid); path.mkdir()
        jobs[jid]['cleanup']=str(path)
        jobs[jid]['message']='Importing YouTube audio…'
        def limit(info, *, incomplete=False):
            if info.get('is_live'): return 'Live streams are not supported.'
            if (info.get('duration') or 0)>1800: return 'Choose a video under 30 minutes.'
        node='/Users/mejdihafiene/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node'
        opts={'format':'bestaudio/best','outtmpl':str(path/'source.%(ext)s'),'noplaylist':True,'quiet':True,'no_warnings':True,'socket_timeout':25,'retries':1,'max_filesize':150*1024*1024,'match_filter':limit}
        if Path(node).exists(): opts['js_runtimes']={'node':{'path':node}}
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info=ydl.extract_info(canonical,download=True)
                if not info: raise ValueError('This video could not be imported. Choose one under 30 minutes.')
                src=Path(ydl.prepare_filename(info))
            convert(src,path/'audio.wav')
            src.unlink(missing_ok=True)
        except Exception as exc:
            if isinstance(exc,ValueError): raise
            raise ValueError('YouTube blocked this import or the video is unavailable. Try another link, or upload an audio/video file you can use.')
        return finish_import(lid,info.get('title','YouTube practice'),canonical,jid,language)
    return job_start(action)

@app.post('/api/upload')
async def upload(file:UploadFile=File(...), title:str=Form(''), language:str=Form('en')):
    language=import_language(language)
    lid=uuid.uuid4().hex; path=folder(lid); path.mkdir()
    source=path/'upload.media'; size=0
    with source.open('wb') as out:
        while chunk:=await file.read(1024*1024):
            size+=len(chunk)
            if size>150*1024*1024:
                source.unlink(missing_ok=True); raise HTTPException(413,'Choose a file smaller than 150 MB.')
            out.write(chunk)
    def action(jid):
        jobs[jid]['cleanup']=str(path)
        try:
            convert(source,path/'audio.wav',duration=1801)
            return finish_import(lid,title or Path(file.filename or 'My practice').stem,'Uploaded file',jid,language)
        finally: source.unlink(missing_ok=True)
    return job_start(action)

PDF_CHARS=20000
ELEVEN_FAILED='ElevenLabs could not create the voice. Check your connection, that you are signed in (run “elevenlabs auth login” in Terminal) and that you have credits left, then try again.'

def text_cut(text, n):
    if len(text)<=n: return len(text)
    ends=[m.end() for m in re.finditer(r'[.!?]["\')”’»]*\s',text[:n])]
    return ends[-1] if ends and ends[-1]>n//2 else (text.rfind(' ',0,n)+1 or n)

def pdf_text(source):
    try: from pypdf import PdfReader
    except ImportError: raise ValueError('PDF import needs one more package. Quit Shadow Studio, open “Start Shadow Studio.command” once to install it, then try again.')
    try:
        pages=[]; size=0
        for page in PdfReader(str(source)).pages:
            pages.append(unicodedata.normalize('NFC',page.extract_text() or '')); size+=len(pages[-1])
            if size>PDF_CHARS*2: break
    except Exception: raise ValueError('This PDF could not be read. If it is password-protected, save an unlocked copy and try again.')
    raw=re.sub(r'(?m)^[ \t]*\d+[ \t]*$\n?','',re.sub(r'[\x00-\x08\x0b-\x1f­]','','\n'.join(pages)))
    blocks=[re.sub(r'\s+',' ',re.sub(r'(?<=[^\W\d_])-\n(?=[a-zàâæçéèêëîïôœùûüÿ])','',b)).strip() for b in re.split(r'\n\s*\n',raw)]
    # A short block with no closing punctuation is most likely a heading; end it so it is not read into the next sentence.
    text=' '.join(b+'.' if len(b)<80 and b[-1].isalnum() else b for b in blocks if b)
    if len(re.findall(r'[^\W\d_]{2,}',text))<5: raise ValueError('No readable text was found in this PDF. Scanned pages are pictures of text; choose a PDF whose text you can select and copy.')
    return text[:text_cut(text,PDF_CHARS)].strip()

def eleven_cli(): return shutil.which('elevenlabs') or '/opt/homebrew/bin/elevenlabs'

def eleven(args, body=None):
    cli=eleven_cli()
    if not Path(cli).exists(): raise ValueError('PDF import needs the ElevenLabs command-line tool. Install it, run “elevenlabs auth login” in Terminal, then try again.')
    try:
        result=subprocess.run([cli,*args,'--format','json','--no-extract'],input=body,capture_output=True,text=True,timeout=300)
        if result.returncode: raise ValueError()
        out=json.loads(result.stdout)
        if not isinstance(out,dict): raise ValueError()
        return out
    except (ValueError,OSError,subprocess.SubprocessError): raise ValueError(ELEVEN_FAILED)

def timed_words(alignment, offset):
    found=[]; cur=None
    for ch,s,e in zip(alignment['characters'],alignment['character_start_times_seconds'],alignment['character_end_times_seconds']):
        if not ch.strip(): cur=None
        elif cur: cur.word+=ch; cur.end=offset+e
        else: cur=SimpleNamespace(word=' '+ch,start=offset+s,end=offset+e); found.append(cur)
    return found

PDF_VOICES={}
PDF_PREVIEWS={}

def no_pdf_voices(language):
    return f'No {LANGUAGES[language]} voices with samples were found in your ElevenLabs account. Add a voice from the ElevenLabs Voice Library to My Voices, then try again.'

def pdf_voices(language, refresh=False):
    if not refresh and language in PDF_VOICES: return PDF_VOICES[language]
    if language=='fr':
        available=eleven(['voices','search','--language','fr','--page-size','100']).get('voices') or []
        picked=sorted((v for v in available if v.get('voice_id') and v.get('preview_url')),key=lambda v:str(v.get('name')))[:8]
    else:
        by={}
        for gender in ('male','female'):
            got=[v for v in eleven(['voices','search','--gender',gender,'--page-size','100']).get('voices') or [] if v.get('voice_id') and (v.get('labels') or {}).get('language','en')=='en' and v.get('preview_url')]
            by[gender]=sorted(got,key=lambda v:(v.get('category')!='premade',(v.get('labels') or {}).get('accent') not in ('american','british'),str(v.get('name'))))
        picked=by['male'][:4]+by['female'][:4]
        picked+=[v for v in by['male'][4:]+by['female'][4:] if v not in picked][:8-len(picked)]
    voices={}
    for v in picked:
        name,_,about=str(v.get('name') or '').partition(' - '); labels=v.get('labels') or {}
        voices[v['voice_id']]={'id':v['voice_id'],'name':name.strip() or 'Voice','about':about.strip(),'gender':labels.get('gender') or '','accent':labels.get('accent') or '','preview':v['preview_url']}
    PDF_VOICES[language]=voices
    return voices

@app.get('/api/pdf/voices')
def pdf_voice_list(language:str='en'):
    language=import_language(language)
    try: voices=pdf_voices(language, refresh=True)
    except ValueError as e: raise HTTPException(502,str(e))
    if not voices: raise HTTPException(404,no_pdf_voices(language))
    return [{k:v[k] for k in ('id','name','about','gender','accent')} for v in voices.values()]

@app.get('/api/pdf/voices/{vid}/preview')
def pdf_voice_preview(vid:str, language:str='en'):
    language=import_language(language)
    try: voice=pdf_voices(language).get(vid)
    except ValueError as e: raise HTTPException(502,str(e))
    if not voice: raise HTTPException(404,'Choose one of the listed voices.')
    if vid not in PDF_PREVIEWS:
        url=urlparse(voice['preview'])
        if url.scheme!='https' or not (url.hostname or '').endswith(('.googleapis.com','.elevenlabs.io')): raise HTTPException(502,'This voice has no sample available.')
        try:
            with urllib.request.urlopen(voice['preview'],timeout=20) as r: PDF_PREVIEWS[vid]=r.read(3*1024*1024)
        except (OSError,ValueError): raise HTTPException(502,'The voice sample could not be loaded. Check your connection and try again.')
    return Response(PDF_PREVIEWS[vid],media_type='audio/mpeg')

@app.post('/api/pdf')
async def pdf(file:UploadFile=File(...), title:str=Form(''), voice_id:str=Form(''), language:str=Form('en')):
    language=import_language(language)
    lid=uuid.uuid4().hex; path=folder(lid); path.mkdir()
    source=path/'upload.pdf'; size=0
    with source.open('wb') as out:
        while chunk:=await file.read(1024*1024):
            size+=len(chunk)
            if size>150*1024*1024:
                out.close(); shutil.rmtree(path,ignore_errors=True); raise HTTPException(413,'Choose a file smaller than 150 MB.')
            out.write(chunk)
    def action(jid):
        jobs[jid]['cleanup']=str(path)
        try:
            jobs[jid]['message']='Reading the PDF…'
            text=pdf_text(source); chunks=[]
            while text: k=text_cut(text,2500); chunks.append(text[:k].strip()); text=text[k:].lstrip()
            jobs[jid]['message']='Choosing a voice…'
            voices=pdf_voices(language)
            if not voices: raise ValueError(no_pdf_voices(language))
            voice=voices.get(voice_id) if voice_id else random.choice([v for v in voices.values() if v['gender']=='male'] or list(voices.values()))
            if not voice: raise ValueError('That voice is no longer in your ElevenLabs list. Choose another one and try again.')
            name=voice['name']
            audio=[]; segments=[]; timed=True; offset=0.
            for n,chunk in enumerate(chunks):
                jobs[jid]['message']=f'{name} is reading your PDF… part {n+1} of {len(chunks)}'
                body={'text':chunk,'model_id':'eleven_multilingual_v2'}
                if n: body['previous_text']=chunks[n-1][-300:]
                if n+1<len(chunks): body['next_text']=chunks[n+1][:300]
                out=eleven(['text-to-speech','convert_with_timestamps','--voice-id',voice['id'],'--json','-'],json.dumps(body))
                if not out.get('audio_base64'): raise ValueError(ELEVEN_FAILED)
                part=path/f'part{n}.mp3'; wav=path/f'part{n}.wav'
                part.write_bytes(base64.b64decode(out['audio_base64'])); convert(part,wav)
                y=load_audio(wav); part.unlink(); wav.unlink()
                # ElevenLabs returns when each character is spoken, so phrases keep the PDF's exact wording. Without it, fall back to local transcription.
                try: segments.append(SimpleNamespace(no_speech_prob=0.,words=timed_words(out['alignment'],offset)))
                except (KeyError,TypeError): timed=False
                audio.append(y); offset+=len(y)/16000
            wavfile.write(path/'audio.wav',16000,(np.clip(np.concatenate(audio),-1,1)*32767).astype(np.int16))
            return finish_import(lid,title or Path(file.filename or 'My practice').stem,f'PDF, read by {name} (ElevenLabs)',jid,language,segments if timed else None)
        finally: source.unlink(missing_ok=True)
    return job_start(action)

@app.post('/api/resplit/{lid}')
def resplit(lid:str):
    if read_lesson(lid).get('sample'): raise HTTPException(400,'The guided sample keeps its own phrases.')
    def action(jid):
        path=folder(lid)
        jobs[jid]['message']='Finding new phrases… Long sessions can take a few minutes.'
        before=read_lesson(lid); language=before.get('language','en')
        phrases=make_phrases(transcribe(path/'audio.wav', language), load_audio(path/'audio.wav'))
        if not phrases: raise ValueError(f'No clear {LANGUAGES[language]} speech found, so the current phrases were kept.')
        with file_lock:
            lesson=read_lesson(lid)
            active=[phrase_revision(lesson,i)['id'] for i in range(len(lesson['phrases']))]
            if active!=[phrase_revision(before,i)['id'] for i in range(len(before['phrases']))]:
                raise ValueError('The phrases changed during re-splitting. Start re-splitting again to replace them.')
            for i in range(len(lesson['phrases'])): archive_phrase(lesson,i)
            lesson['phrases']=[p | {'revision':uuid.uuid4().hex} for p in phrases]
            save_lesson(lesson)
        return lid
    return job_start(action)

@app.patch('/api/phrase/{lid}/{index}')
async def edit(lid:str,index:int,request:Request):
    body=await request.json()
    try: start=float(body['start']); end=float(body['end']); text=str(body['text']).strip()
    except (KeyError,ValueError,TypeError): raise HTTPException(400,'Enter text and valid start/end times.')
    with file_lock:
        lesson=read_lesson(lid)
        if not 0<=index<len(lesson['phrases']): raise HTTPException(404,'Phrase not found')
        previous=phrase_revision(lesson,index)
        if body.get('revision') is not None and body['revision']!=previous['id']:
            raise HTTPException(409,'This phrase has changed. Reopen the session before editing it.')
        if not text or len(text)>1000 or not (math.isfinite(start) and math.isfinite(end) and 0<=start<end<=lesson['duration']+.2 and end-start<=30): raise HTTPException(400,'Choose a phrase between 0 and 30 seconds within the audio.')
        if (start,end,text)!=(previous['start'],previous['end'],previous['text']):
            archive_phrase(lesson,index)
            phrase=lesson['phrases'][index]
            phrase.update(start=start,end=end,text=text,words=[],practised=False,revision=uuid.uuid4().hex)
            phrase.pop('latest',None)
            save_lesson(lesson)
    return public_lesson(lesson)

def words(text): return re.findall(r"[^\W\d_]+(?:'[^\W\d_]+)*", unicodedata.normalize('NFC',text).lower().replace('’',"'"))

def align(ref,hyp):
    n,m=len(ref),len(hyp); dp=np.zeros((n+1,m+1),dtype=int)
    dp[:,0]=np.arange(n+1); dp[0,:]=np.arange(m+1)
    for i in range(1,n+1):
        for j in range(1,m+1): dp[i,j]=min(dp[i-1,j]+1,dp[i,j-1]+1,dp[i-1,j-1]+(ref[i-1]!=hyp[j-1]))
    i,j=n,m; marks=[]
    while i or j:
        if i and j and dp[i,j]==dp[i-1,j-1]+(ref[i-1]!=hyp[j-1]): marks.append({'word':ref[i-1],'match':ref[i-1]==hyp[j-1]}); i-=1; j-=1
        elif i and dp[i,j]==dp[i-1,j]+1: marks.append({'word':ref[i-1],'match':False}); i-=1
        else: j-=1
    return max(0,round(100*(1-int(dp[n,m])/max(n,1)))),list(reversed(marks))

def features(y):
    frame=640; hop=320; low,high=40,267
    win=np.hanning(frame); norm=np.correlate(win,win,mode='full')[frame-1:]; norm=norm/norm[0]
    energies=[]; pitches=[]
    for off in range(0,max(1,len(y)-frame),hop):
        x=y[off:off+frame]
        if len(x)<frame: continue
        x=x-x.mean(); rms=float(np.sqrt(np.mean(x*x))); energies.append(rms)
        pitch=np.nan
        if rms>.006:
            x=x*win; corr=np.correlate(x,x,mode='full')[frame-1:]
            if corr[0]>0:
                r=corr[low:high]/(corr[0]*norm[low:high]); best=float(r.max())
                if best>.45: pitch=16000/(low+next((k for k in range(1,len(r)-1) if r[k]>=.9*best and r[k]>=r[k-1] and r[k]>=r[k+1]),int(np.argmax(r))))
        pitches.append(pitch)
    return np.asarray(energies),np.asarray(pitches)

def stretch(x,n=80): return np.interp(np.linspace(0,1,n),np.linspace(0,1,len(x)),x)

def trim(y):
    e,_=features(y)
    if not len(e): return y
    active=np.where(e>max(.008,float(e.max())*.07))[0]
    return y[max(0,active[0]*320-800):min(len(y),active[-1]*320+1440)] if len(active) else y

def compare(ref,take,text,heard,speed=1.0):
    ref=trim(ref); take=trim(take)
    er,pr=features(ref); et,pt=features(take)
    if len(et)<8 or float(np.sqrt(np.mean(take*take)))<.006: raise ValueError('The recording is too quiet or short. Move closer to the microphone and try again.')
    accuracy,marks=align(words(text),words(heard))
    ratio=len(take)*speed/max(len(ref),1)
    # A transparent practice estimate, not a phoneme-level pronunciation assessment.
    timing=round(100*math.exp(-abs(math.log(max(.01,ratio)))))
    energy=float(np.mean(np.abs(stretch(er/(np.max(er)+1e-8))-stretch(et/(np.max(et)+1e-8)))))
    rhythm=max(0,round(timing*(1-min(.6,energy))))
    pitch=None; curves={'original':[],'you':[]}
    for key,p in [('original',pr),('you',pt)]:
        valid=np.isfinite(p)
        if valid.sum()>=10 and valid.mean()>.15:
            contour=12*np.log2(p[valid]/np.median(p[valid]))
            curves[key]=np.round(stretch(contour,60),2).tolist()
    if curves['original'] and curves['you']:
        error=float(np.mean(np.abs(np.array(curves['original'])-np.array(curves['you']))))
        pitch=max(0,round(100*math.exp(-error/4)))
    tips=[]
    if accuracy<85: tips.append('Listen for the highlighted words. Speech recognition heard a different word or missed it; replay to check before changing your pronunciation.')
    if ratio>1.15: tips.append(f'Your take was {round((ratio-1)*100)}% longer. Try linking words and shortening pauses.')
    elif ratio<.85: tips.append(f'Your take was {round((1-ratio)*100)}% shorter. Leave more space for stressed words and pauses.')
    else: tips.append('Your overall pace is close. Focus next on the placement of pauses and stressed words.')
    if pitch is not None and pitch<70: tips.append('Follow the rises and falls in the speaker’s pitch. The chart is relative to each voice, so you do not need to copy their natural pitch.')
    return {'accuracy':accuracy,'rhythm':rhythm,'intonation':pitch,'durationRatio':round(ratio,2),'heard':heard,'words':marks,'curves':curves,'tips':tips,'created':time.time(),'playbackSpeed':speed}

@app.post('/api/record/{lid}/{index}')
async def record(lid:str,index:int,request:Request,speed:float=1.0,revision:str|None=None):
    if not math.isfinite(speed) or not .5<=speed<=1.5: raise HTTPException(400,'Invalid playback speed')
    lesson=read_lesson(lid)
    phrase=phrase_revision(lesson,index) if 0<=index<len(lesson['phrases']) else None
    if revision is not None and (not phrase or revision!=phrase['id']):
        phrase=lesson.get('archivedRevisions',{}).get(ident(revision))
        if not phrase: raise HTTPException(409,'This phrase version is unavailable. Reopen the session before recording again.')
    if not phrase: raise HTTPException(404,'Phrase not found')
    created=time.time()
    if int(request.headers.get('content-length','0'))>12*1024*1024: raise HTTPException(413,'Recording is too large.')
    raw=bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw)>12*1024*1024: raise HTTPException(413,'Recording is too large.')
    tid=uuid.uuid4().hex; path=folder(lid)
    temp=path/(tid+'.media'); pending=path/(tid+'.pending.wav'); wav=path/(tid+'.wav')
    def action(jid):
        try:
            jobs[jid]['message']='Listening to your take…'
            convert(temp,pending,duration=40)
            take=load_audio(pending)
            source=load_audio(path/'audio.wav'); ref=source[int(phrase['start']*16000):int(phrase['end']*16000)]
            if len(take)>16000*35: raise ValueError('Keep each take under 35 seconds.')
            heard=' '.join(s.text.strip() for s in transcribe(pending, lesson.get('language','en')))
            result=compare(ref,take,phrase['text'],heard,speed)
            result.update(id=tid,audio=f'/api/take/{lid}/{tid}',created=created,phraseRevision=phrase)
            with file_lock:
                current=read_lesson(lid)
                history=current.setdefault('takeHistory',[])
                if 0<=index<len(current['phrases']) and phrase_revision(current,index)['id']==phrase['id']:
                    p=current['phrases'][index]
                    if old:=legacy_take(current,index): history.append(old)
                    p['practised']=True; p['latest']=result; p['takes']=(p.get('takes') or 0)+1
                history.append(result)
                pending.replace(wav)
                try: save_lesson(current)
                except Exception:
                    wav.unlink(missing_ok=True)
                    raise ValueError('The take could not be saved. Free some disk space and try again.')
            return lid
        except HTTPException as exc:
            raise ValueError('This session is no longer available.') from exc
        finally:
            for file in (temp,pending):
                try: file.unlink(missing_ok=True)
                except OSError: pass
    with file_lock:
        read_lesson(lid)
        try:
            temp.write_bytes(raw)
            return job_start(action) | {'takeId':tid}
        except Exception:
            temp.unlink(missing_ok=True)
            raise HTTPException(500,'The recording could not be queued. Please try again.')

@app.get('/api/wave/{lid}/{index}')
def waveform(lid:str,index:int):
    lesson=read_lesson(lid)
    if not 0<=index<len(lesson['phrases']): raise HTTPException(404,'Phrase not found')
    phrase=lesson['phrases'][index]
    sr,y=wavfile.read(folder(lid)/'audio.wav',mmap=True)
    y=y[int(phrase['start']*sr):int(phrase['end']*sr)].astype(np.float32)
    values=np.array([float(np.sqrt(np.mean(c*c))) if len(c) else 0 for c in np.array_split(y,110)])
    return np.round(values/max(float(values.max()),1e-8),3).tolist()

def track(y):
    e,p=features(y)
    return {'energy':np.round(e/max(float(e.max()) if len(e) else 0,1e-8),3).tolist(),'pitch':[round(float(v),1) if np.isfinite(v) else None for v in p]}

@app.get('/api/voice/{lid}/{index}')
def voice(lid:str,index:int,revision:str|None=None):
    lesson=read_lesson(lid)
    if not 0<=index<len(lesson['phrases']): raise HTTPException(404,'Phrase not found')
    if revision is not None and revision!=phrase_revision(lesson,index)['id']:
        raise HTTPException(409,'This phrase has changed. Reopen the session to see its voice map.')
    phrase=lesson['phrases'][index]; path=folder(lid)
    sr,y=wavfile.read(path/'audio.wav',mmap=True)
    ref=y[int(phrase['start']*sr):int(phrase['end']*sr)]
    ref=ref.astype(np.float32)/32768 if ref.dtype==np.int16 else ref.astype(np.float32)
    result={'hop':.02,'source':track(ref),'take':None}
    latest=phrase.get('latest')
    if latest and (path/(ident(latest['id'])+'.wav')).exists():
        result['take']=track(load_audio(path/(latest['id']+'.wav')))|{'speed':latest.get('playbackSpeed',1)}
    return result

@app.get('/api/take/{lid}/{tid}')
def take_audio(lid:str,tid:str):
    path=folder(lid)/(ident(tid)+'.wav')
    lesson=read_lesson(lid)
    saved=any(r['id']==tid for r in lesson.get('takeHistory',[])) or any((p.get('latest') or {}).get('id')==tid for p in lesson['phrases'])
    if not saved or not path.is_file(): raise HTTPException(404,'Audio for this take is unavailable.')
    return FileResponse(path,media_type='audio/wav')

@app.delete('/api/lesson/{lid}')
def delete(lid:str):
    with file_lock:
        read_lesson(lid); shutil.rmtree(folder(lid)); return {'ok':True}

@app.get('/api/status')
def status(): return JSONResponse({'local':True,'modelReady':bool(models),'ffmpeg':bool(shutil.which('ffmpeg') or Path('/opt/homebrew/bin/ffmpeg').exists()),'elevenLabsCLI':os.access(eleven_cli(),os.X_OK)},headers={'X-Shadow-Engine':ENGINE_SIGNATURE})

if __name__=='__main__':
    os.environ['PATH']='/opt/homebrew/bin:'+os.environ.get('PATH','')
    import uvicorn
    if LAN:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            try: probe.connect(('10.255.255.255', 1)); print(f'LAN mode: anyone on this Wi-Fi can reach Shadow Studio. Phone address: http://{probe.getsockname()[0]}:{PORT}')
            except OSError: print('LAN mode: anyone on this network can reach Shadow Studio.')
    uvicorn.run(app,host='0.0.0.0' if LAN else '127.0.0.1',port=PORT,log_level='warning')
