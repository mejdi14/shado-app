"""Shadow Studio: a single-user, loopback-only English shadowing workspace."""
import os
from pathlib import Path
ROOT = Path(__file__).resolve().parent
os.environ.setdefault('HF_HOME', str(ROOT / 'data' / 'models'))
os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')
import json, re, secrets, shutil, subprocess, threading, time, uuid, math
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse, parse_qs
import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly
from fastapi import FastAPI, HTTPException, Request, UploadFile, File, Form
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

DATA = ROOT / 'data'
DATA.mkdir(exist_ok=True)
TOKEN = secrets.token_urlsafe(32)
PORT = int(os.environ.get('SHADOW_PORT', '8765'))
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
executor = ThreadPoolExecutor(max_workers=1)
jobs = {}
model = None
model_lock = threading.Lock()
file_lock = threading.Lock()

@app.middleware('http')
async def local_only(request, call_next):
    allowed = {f'127.0.0.1:{PORT}', f'localhost:{PORT}'}
    if request.headers.get('host') not in allowed:
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
        temp.write_text(json.dumps(lesson, ensure_ascii=False, indent=2))
        temp.replace(target)

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

def transcribe(path):
    global model
    with model_lock:
        if model is None:
            from faster_whisper import WhisperModel
            model = WhisperModel('base.en', device='cpu', compute_type='int8', download_root=str(DATA/'models'))
        segments, info = model.transcribe(str(path), language='en', word_timestamps=True, vad_filter=True, condition_on_previous_text=False, beam_size=5)
        return list(segments)

def make_phrases(segments):
    phrases=[]; words=[]
    def flush():
        if not words: return
        phrases.append({'start':round(max(0,words[0]['start']-.08),3),'end':round(words[-1]['end']+.12,3),'text':''.join(w['word'] for w in words).strip(),'words':words.copy(),'practised':False})
        words.clear()
    for seg in segments:
        if seg.no_speech_prob > .8: continue
        for w in (seg.words or []):
            if words and (w.start-words[-1]['end']>.65 or w.end-words[0]['start']>11): flush()
            words.append({'start':w.start,'end':w.end,'word':w.word})
            if re.search(r'[.!?][\"\u201d\u2019]?$', w.word.strip()) and w.end-words[0]['start']>.65: flush()
    flush()
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

def finish_import(lid, title, source, jid):
    path=folder(lid)
    audio=load_audio(path/'audio.wav')
    if len(audio)>16000*1800: raise ValueError('Choose a video or file under 30 minutes for focused practice.')
    jobs[jid]['message']='Finding phrases… The first import downloads a speech model (about 150 MB).'
    phrases=make_phrases(transcribe(path/'audio.wav'))
    if not phrases: raise ValueError('No clear English speech found. Try a clip with a single speaker and little music.')
    lesson={'id':lid,'title':title[:160],'source':source,'created':time.time(),'duration':round(len(audio)/16000,2),'phrases':phrases,'sample':False}
    save_lesson(lesson)
    return lid

@app.get('/api/library')
def library():
    lessons=[]
    for p in DATA.glob('*/lesson.json'):
        try:
            l=json.loads(p.read_text()); lessons.append({k:l[k] for k in ['id','title','source','created','duration','sample']} | {'count':len(l['phrases']),'practised':sum(bool(x.get('practised')) for x in l['phrases'])})
        except (ValueError,KeyError): pass
    return sorted(lessons,key=lambda x:x['created'],reverse=True)

@app.get('/api/lesson/{lid}')
def lesson(lid:str): return read_lesson(lid)

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
        return finish_import(lid,info.get('title','YouTube practice'),canonical,jid)
    return job_start(action)

@app.post('/api/upload')
async def upload(file:UploadFile=File(...), title:str=Form('')):
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
            return finish_import(lid,title or Path(file.filename or 'My practice').stem,'Uploaded file',jid)
        finally: source.unlink(missing_ok=True)
    return job_start(action)

@app.patch('/api/phrase/{lid}/{index}')
async def edit(lid:str,index:int,request:Request):
    lesson=read_lesson(lid)
    if not 0<=index<len(lesson['phrases']): raise HTTPException(404,'Phrase not found')
    body=await request.json()
    try: start=float(body['start']); end=float(body['end']); text=str(body['text']).strip()
    except (KeyError,ValueError,TypeError): raise HTTPException(400,'Enter text and valid start/end times.')
    if not text or len(text)>1000 or not (math.isfinite(start) and math.isfinite(end) and 0<=start<end<=lesson['duration']+.2 and end-start<=30): raise HTTPException(400,'Choose a phrase between 0 and 30 seconds within the audio.')
    lesson['phrases'][index].update(start=start,end=end,text=text,words=[],practised=False)
    lesson['phrases'][index].pop('latest',None)
    save_lesson(lesson)
    return lesson

def words(text): return re.findall(r"[a-z]+(?:'[a-z]+)?",text.lower().replace('’',"'"))

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
    frame=640; hop=320
    energies=[]; pitches=[]
    for off in range(0,max(1,len(y)-frame),hop):
        x=y[off:off+frame]
        if len(x)<frame: continue
        x=x-x.mean(); rms=float(np.sqrt(np.mean(x*x))); energies.append(rms)
        pitch=np.nan
        if rms>.008:
            x=x*np.hanning(frame); corr=np.correlate(x,x,mode='full')[frame-1:]
            low,high=40,267; lag=int(np.argmax(corr[low:high]))+low
            if corr[0]>0 and corr[lag]/corr[0]>.45: pitch=16000/lag
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
async def record(lid:str,index:int,request:Request,speed:float=1.0):
    if not math.isfinite(speed) or not .5<=speed<=1.5: raise HTTPException(400,'Invalid playback speed')
    lesson=read_lesson(lid)
    if not 0<=index<len(lesson['phrases']): raise HTTPException(404,'Phrase not found')
    if int(request.headers.get('content-length','0'))>12*1024*1024: raise HTTPException(413,'Recording is too large.')
    raw=bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw)>12*1024*1024: raise HTTPException(413,'Recording is too large.')
    tid=uuid.uuid4().hex; path=folder(lid); temp=path/(tid+'.media'); temp.write_bytes(raw)
    def action(jid):
        try:
            jobs[jid]['message']='Listening to your take…'
            wav=path/(tid+'.wav'); convert(temp,wav,duration=40)
            take=load_audio(wav); phrase=lesson['phrases'][index]
            source=load_audio(path/'audio.wav'); ref=source[int(phrase['start']*16000):int(phrase['end']*16000)]
            if len(take)>16000*35: raise ValueError('Keep each take under 35 seconds.')
            heard=' '.join(s.text.strip() for s in transcribe(wav))
            result=compare(ref,take,phrase['text'],heard,speed)
            result.update(id=tid,audio=f'/api/take/{lid}/{tid}')
            current=read_lesson(lid); p=current['phrases'][index]
            p['practised']=True; p['latest']=result; p['takes']=p.get('takes',0)+1
            save_lesson(current)
            return lid
        except Exception:
            (path/(tid+'.wav')).unlink(missing_ok=True)
            raise
        finally: temp.unlink(missing_ok=True)
    return job_start(action)

@app.get('/api/wave/{lid}/{index}')
def waveform(lid:str,index:int):
    lesson=read_lesson(lid)
    if not 0<=index<len(lesson['phrases']): raise HTTPException(404,'Phrase not found')
    phrase=lesson['phrases'][index]
    sr,y=wavfile.read(folder(lid)/'audio.wav',mmap=True)
    y=y[int(phrase['start']*sr):int(phrase['end']*sr)].astype(np.float32)
    values=np.array([float(np.sqrt(np.mean(c*c))) if len(c) else 0 for c in np.array_split(y,110)])
    return np.round(values/max(float(values.max()),1e-8),3).tolist()

@app.get('/api/take/{lid}/{tid}')
def take_audio(lid:str,tid:str):
    path=folder(lid)/(ident(tid)+'.wav')
    if not path.exists(): raise HTTPException(404,'Take not found')
    return FileResponse(path,media_type='audio/wav')

@app.delete('/api/lesson/{lid}')
def delete(lid:str):
    read_lesson(lid); shutil.rmtree(folder(lid)); return {'ok':True}

@app.get('/api/status')
def status(): return {'local':True,'modelReady':model is not None,'ffmpeg':bool(shutil.which('ffmpeg') or Path('/opt/homebrew/bin/ffmpeg').exists())}

if __name__=='__main__':
    os.environ['PATH']='/opt/homebrew/bin:'+os.environ.get('PATH','')
    import uvicorn
    uvicorn.run(app,host='127.0.0.1',port=PORT,log_level='warning')
