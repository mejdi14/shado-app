"""Generate a clearly labelled workflow sample using the Mac's built-in voice."""
import json, subprocess, uuid, time
from pathlib import Path
import numpy as np
from scipy.io import wavfile
ROOT=Path(__file__).resolve().parent
DATA=ROOT/'data'; DATA.mkdir(exist_ok=True)
existing=next((p for p in DATA.glob('*/lesson.json') if json.loads(p.read_text()).get('sample')),None)
if existing is None or json.loads(existing.read_text()).get('duration',0)<5:
    path=existing.parent if existing else DATA/uuid.uuid4().hex; path.mkdir(exist_ok=True)
    texts=["You don't have to rush to make yourself heard.","Take a breath, and give the words a little space.","The way you say something can change how it feels.","Listen for the rhythm, not just the words.","A little practice every day goes a long way."]
    audio=[]; phrases=[]; cursor=0
    for i,text in enumerate(texts):
        aiff=path/f'sample-{i}.aiff'; wav=path/f'sample-{i}.wav'
        subprocess.run(['/usr/bin/say','-v','Samantha','-r','155','-o',str(aiff),text],check=True)
        subprocess.run(['/opt/homebrew/bin/ffmpeg','-nostdin','-v','error','-y','-i',str(aiff),'-ar','16000','-ac','1',str(wav)],check=True)
        sr,y=wavfile.read(wav); seconds=len(y)/sr
        if seconds<1 or not np.any(y): raise RuntimeError('Mac speech synthesis produced no audio. Run the launcher in Terminal to create the guided sample.')
        phrases.append({'start':round(cursor,3),'end':round(cursor+seconds,3),'text':text,'words':[],'practised':False})
        audio.extend([y,np.zeros(6400,dtype=np.int16)]); cursor+=seconds+.4
        aiff.unlink();wav.unlink()
    wavfile.write(path/'audio.wav',16000,np.concatenate(audio))
    lesson={'id':path.name,'title':'A little space for your voice','source':'Built-in Mac voice · guided workflow sample','created':time.time(),'duration':round(cursor,3),'sample':True,'phrases':phrases}
    (path/'lesson.json').write_text(json.dumps(lesson,indent=2))
    print('Guided sample created.')
else: print('Guided sample already exists.')
