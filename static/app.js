'use strict';
const $ = s => document.querySelector(s), $$ = s => [...document.querySelectorAll(s)];
let token = $('meta[name="shadow-token"]').content;
let lesson=null, index=0, mode='listen', looping=false, concealed=false, busy=false, recorder=null, micStream=null, recording=false, starting=false, stopping=false, chunks=[], recordStart=0, recordTimer=null, autoStop=null, playbackTimer=null, abMode=false, playbackDone=null, sampleId=null;
let takeDraft=null, captureInterrupted=false;
const original=$('#originalAudio'), take=$('#takeAudio'), historyAudio=$('#historyAudio'), historyDialog=$('#takeHistoryDialog');
const fmt=n=>`${Math.floor(n/60).toString().padStart(2,'0')}:${Math.floor(n%60).toString().padStart(2,'0')}`;
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function toast(msg){$('#toast').textContent=msg;$('#toast').hidden=false;clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('#toast').hidden=true,6500)}
async function apiResponse(path,options={}){options.headers={...(options.headers||{}),'X-Shadow-Token':token};const r=await fetch(path,options);if(!r.ok){let x;try{x=await r.json()}catch{}throw Object.assign(new Error(typeof x?.detail==='string'?x.detail:'Something went wrong. Please try again.'),{status:r.status})}return r}
async function api(path,options){return (await apiResponse(path,options)).json()}
function json(method,data){return{method,headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}}
function guarded(fn){return async(...args)=>{try{await fn(...args)}catch(e){toast(e.message)}}}
function setBusy(value,title='Preparing your practice',message='Preparing audio…'){busy=value;$('#jobOverlay').hidden=!value;$('#jobTitle').textContent=title;$('#jobMessage').textContent=message;$('main').inert=value;$('.sidebar').inert=value}
async function waitJob(id,title,importing=false){
  setBusy(true,title,importing?'Checking import status…':'Preparing audio…');
  try{
    while(true){
      let j;
      try{j=await api('/api/jobs/'+id)}
      catch(error){if(importing&&error.status===404){saveImportJob(null);throw new Error(missingImport)}throw error}
      $('#jobMessage').textContent=j.message||'Finishing up…';
      if(j.state==='error'){
        if(importing)saveImportJob(null);
        throw new Error(j.message||'Processing failed. Please try again.');
      }
      if(j.state==='done')return j.lessonId;
      await new Promise(r=>setTimeout(r,900));
    }
  }finally{if(!importing)setBusy(false)}
}
const lastLessonKey='shadow-lesson', phraseKey=id=>'shadow-phrase:'+id;
function readPreference(key){try{return localStorage.getItem(key)}catch{return null}}
function writePreference(key,value){try{if(value===null)localStorage.removeItem(key);else localStorage.setItem(key,value)}catch{}}
function forgetLesson(id){writePreference(phraseKey(id),null);if(readPreference(lastLessonKey)===id)writePreference(lastLessonKey,null)}
function phraseIdentity(p){return p&&JSON.stringify([p.start,p.end,p.text])}
function savedPhraseIndex(phrases,saved){
  let position;
  try{position=JSON.parse(saved)}catch{return -1}
  if(!Number.isSafeInteger(position?.index)||position.index<0||typeof position.identity!=='string')return -1;
  const {index,identity}=position;
  if(phraseIdentity(phrases[index])===identity)return index;
  const matches=phrases.flatMap((p,i)=>phraseIdentity(p)===identity?[i]:[]);
  return matches.length===1?matches[0]:-1;
}
function rememberPhrase(){
  const identity=phraseIdentity(lesson.phrases[index]);
  writePreference(phraseKey(lesson.id),identity?JSON.stringify({index,identity}):null);
  const button=$('#continueLesson');
  button.hidden=!identity;
  button.textContent=identity?`Continue · ${lesson.title} · ${lesson.language==='fr'?'French':'English'} · Phrase ${index+1} of ${lesson.phrases.length}`:'';
}
function clearMissingLesson(id){
  forgetLesson(id);
  if(lesson?.id===id){
    stopPlayback();lesson=null;index=0;original.removeAttribute('src');take.removeAttribute('src');
    for(const selector of ['#practiceArea','#phraseSection','#lessonMenu','#resplitLesson','#noPhrases','#continueLesson'])$(selector).hidden=true;
    $('#emptyState').hidden=$('#howItWorks').hidden=false;
    $('#lessonLanguage').innerHTML='<span>EN</span> English practice';
    $('#lessonTitle').textContent='Your next voice starts here';
    $('#lessonMeta').textContent='Listen to a phrase, record a take, then compare.';
    $('#sourceBadge').textContent='GETTING STARTED';
    renderFeedback(null);
  }
  toast('That session is no longer in your library. Choose another session or add a voice.');
}
let libraryItems=[];
const moreRecentFirst=(a,b)=>(b.lastPractised??0)-(a.lastPractised??0);
function renderPracticeProgress(){
  const sum=key=>libraryItems.reduce((total,item)=>total+(item[key]??0),0);
  const timed=sum('timedTakes'),saved=sum('savedTakes'),seconds=sum('recordedSeconds');
  $('#completedPhrases').textContent=`${sum('practised')} of ${sum('count')} current phrases`;
  $('#recordedPracticeTime').textContent=timed===0?'Unavailable':seconds<1?'Under 1 second':`${fmt(seconds)} (min:sec)`;
  $('#practiceTimeCoverage').textContent=(saved?`${timed} of ${saved} linked takes have a recorded duration. `:'')+'Time counts takes saved with this version. Some older takes may be missing from history.';
  const recent=libraryItems.filter(l=>l.lastPractised!=null).sort(moreRecentFirst).slice(0,5);
  const dateFormat=new Intl.DateTimeFormat(undefined,{dateStyle:'medium'});
  $('#noRecentLessons').hidden=!!recent.length;
  $('#recentLessons').innerHTML=recent.map(l=>`<li><button class="button quiet" data-lesson="${esc(l.id)}"><span>${esc(l.title)}</span><small>${esc(dateFormat.format(l.lastPractised*1000))}</small></button></li>`).join('');
  $$('#recentLessons [data-lesson]').forEach(b=>b.onclick=openLibrarySession);
  $('#practiceProgress').hidden=false;
}
const openLibrarySession=guarded(async e=>{if(await loadLesson(e.currentTarget.dataset.lesson))showView('studio')});
function renderLibrary(){
  const query=$('#librarySearch').value.trim().toLocaleLowerCase(),language=$('#libraryLanguage').value,progress=$('#libraryProgress').value,sort=$('#librarySort').value;
  const ratio=l=>l.practised/Math.max(1,l.count);
  const items=libraryItems.filter(l=>{
    const status=l.practised===0?'new':l.count>0&&l.practised>=l.count?'complete':'started';
    return l.title.toLocaleLowerCase().includes(query)&&(language==='all'||language===(l.language==='fr'?'fr':'en'))&&(progress==='all'||progress===status);
  });
  if(sort==='recent')items.sort(moreRecentFirst);
  if(sort==='title')items.sort((a,b)=>a.title.localeCompare(b.title,undefined,{sensitivity:'base'}));
  if(sort==='progress')items.sort((a,b)=>ratio(b)-ratio(a));
  $('#libraryControls').hidden=!libraryItems.length;
  $('#resetLibrary').disabled=!($('#librarySearch').value||language!=='all'||progress!=='all'||sort!=='newest');
  const message=$('#libraryMessage');
  message.textContent=items.length?'':libraryItems.length?'No sessions match. Change your search or filters, or choose Reset.':'Your library is ready for its first voice. Add a clip to get started.';
  message.hidden=!!items.length;
  $('#libraryGrid').innerHTML=items.map(l=>`<button class="library-card card" data-lesson="${esc(l.id)}"><span>${l.sample?'GUIDED SAMPLE':(l.language==='fr'?'FRENCH':'ENGLISH')+' / '+(l.source.startsWith('http')?'YOUTUBE':l.source.startsWith('PDF,')?'PDF':'UPLOADED AUDIO')}</span><h3>${esc(l.title)}</h3><p>${l.count} phrases · ${fmt(l.duration)}<br>${l.practised}/${l.count} practised <span>↗</span></p></button>`).join('');
  $$('#libraryGrid [data-lesson]').forEach(b=>b.onclick=openLibrarySession);
}
async function refreshLibrary(){const current=lesson,list=await api('/api/library');$('#libraryCount').textContent=list.length;sampleId=list.find(x=>x.sample)?.id;$('#sampleButton').disabled=$('#sampleButton').hidden=$('#sampleIntro').hidden=!sampleId;$('#sampleMissing').hidden=!!sampleId;$('#emptyImport').classList.toggle('primary',!sampleId);$('#emptyImport').classList.toggle('quiet',!!sampleId);$('#librarySample').hidden=!sampleId;libraryItems=list;renderLibrary();renderPracticeProgress();if(!recording&&!starting&&!stopping&&!takeDraft&&current&&lesson===current&&!list.some(item=>item.id===current.id))clearMissingLesson(current.id);return list}
if(['127.0.0.1','localhost'].includes(location.hostname)){
  const exportButton=$('#exportBackup'),restoreButton=$('#restoreBackup'),input=$('#backupFile'),status=$('#backupStatus');
  exportButton.hidden=restoreButton.hidden=false;
  const runBackup=async(title,action)=>{if(busy||recording||starting||stopping)return;status.hidden=true;setBusy(true,title,'Keep this page open…');try{status.textContent=await action()}catch(e){status.textContent=e.message}finally{setBusy(false);status.hidden=false}};
  exportButton.onclick=()=>runBackup('Preparing your backup',async()=>{
    const response=await apiResponse('/api/backup/export',{method:'POST'});
    const url=URL.createObjectURL(await response.blob());
    const link=document.createElement('a');link.href=url;link.download='Shadow Studio Backup.zip';document.body.append(link);link.click();link.remove();
    setTimeout(()=>URL.revokeObjectURL(url),60000);
    return 'Backup sent to your browser’s downloads.';
  });
  restoreButton.onclick=()=>input.click();
  input.onchange=()=>{
    const file=input.files[0];input.value='';
    if(!file||!confirm('Restore this backup? Existing session IDs and the current guided sample will be kept. Missing Voice Training completions will be added.'))return;
    runBackup('Restoring your backup',async()=>{
      if(file.size>1024**3)throw new Error('Choose a backup ZIP of 1 GiB or less.');
      const result=await api('/api/backup/restore',{method:'POST',headers:{'Content-Type':'application/zip'},body:file});
      const summary=[`Sessions restored: ${result.restoredLessons}.`];
      if(result.skippedLessons)summary.push(`Existing session IDs skipped: ${result.skippedLessons}.`);
      if(result.skippedSample)summary.push('Your existing guided sample was kept.');
      if(result.trainingAdded)summary.push(`Voice Training completions added: ${result.trainingAdded}.`);
      try{await refreshLibrary()}catch{summary.push('Reload the page to refresh your library.')}
      return summary.join(' ');
    });
  };
}
$('#libraryControls').onsubmit=e=>e.preventDefault();
$('#librarySearch').oninput=renderLibrary;
for(const selector of ['#libraryLanguage','#libraryProgress','#librarySort'])$(selector).onchange=renderLibrary;
$('#resetLibrary').onclick=()=>{$('#libraryControls').reset();renderLibrary();$('#librarySearch').focus()};
$('#librarySample').onclick=guarded(async()=>{if(sampleId&&await loadLesson(sampleId))showView('studio')});
function showView(view){if(recording||starting||stopping||busy||takeDraft)return;stopPlayback();$('#libraryView').hidden=view!=='library';$('#studioView').hidden=view==='library';$('#libraryNav').classList.toggle('active',view==='library');$('#practiceNav').classList.toggle('active',view!=='library');$('#pageLabel').textContent=view==='library'?'Your library':'Practice studio'}
async function loadLesson(id,restart=false){
  stopPlayback();
  let next;
  try{next=await api('/api/lesson/'+id)}
  catch(error){
    if(error.status!==404)throw error;
    clearMissingLesson(id);
    await refreshLibrary();
    return false;
  }
  const currentIdentity=lesson?.id===id?phraseIdentity(lesson.phrases[index]):null;
  const saved=restart?null:currentIdentity?JSON.stringify({index,identity:currentIdentity}):readPreference(phraseKey(id));
  const restored=savedPhraseIndex(next.phrases,saved);
  lesson=next;
  index=Math.max(restored,0);
  const hasPhrases=lesson.phrases.length>0;
  writePreference(lastLessonKey,id);
  if(hasPhrases)original.src='/api/audio/'+id;else original.removeAttribute('src');
  $('#lessonLanguage').innerHTML=lesson.language==='fr'?'<span>FR</span> French practice':'<span>EN</span> English practice';
  $('#emptyState').hidden=$('#howItWorks').hidden=true;
  $('#noPhrases').hidden=hasPhrases;
  $('#practiceArea').hidden=$('#phraseSection').hidden=!hasPhrases;
  $('#lessonMenu').hidden=false;
  $('#resplitLesson').hidden=!!lesson.sample;
  $('#lessonTitle').textContent=lesson.title;$('#lessonMeta').textContent=`${lesson.phrases.length} phrases · ${fmt(lesson.duration)} · ${lesson.sample?'Built-in Mac voice / workflow sample':lesson.source.startsWith('http')?'Imported from YouTube':'Imported from your file'}`;$('#sourceBadge').textContent=lesson.sample?'GUIDED SAMPLE':lesson.source.startsWith('http')?'YOUTUBE':'YOUR AUDIO';
  rememberPhrase();
  if(hasPhrases)renderPhrase();else renderFeedback(null);
  await refreshLibrary();
  if(lesson!==next)return false;
  if(hasPhrases&&saved!==null&&restored<0)toast('The saved phrase could not be found. This session starts at phrase one.');
  return true;
}
function stopPlayback(){clearInterval(playbackTimer);playbackTimer=null;playbackDone=null;original.pause();take.pause();abMode=false;$('#playOriginal span').textContent='▶'}
function renderPhrase(){stopPlayback();const p=lesson.phrases[index];$('#phraseText').textContent=p.text;$('#phraseCounter').textContent=`PHRASE ${String(index+1).padStart(2,'0')} / ${String(lesson.phrases.length).padStart(2,'0')}`;$('#phraseTime').textContent=`${fmt(p.start)} — ${fmt(p.end)}`;$('#prevPhrase').disabled=index===0;$('#nextPhrase').disabled=index===lesson.phrases.length-1;$('#phraseTotal').textContent=lesson.phrases.length;$('#completion').textContent=`${lesson.phrases.filter(p=>p.practised).length} / ${lesson.phrases.length} practised`;$('#phraseList').innerHTML=lesson.phrases.map((p,i)=>`<button class="phrase-item ${i===index?'active':''}" data-index="${i}" aria-current="${i===index?'true':'false'}"><span class="phrase-number">${String(i+1).padStart(2,'0')}</span><span class="phrase-item-text">${esc(p.text)}</span><span class="phrase-duration">${(p.end-p.start).toFixed(1)}s</span><span class="phrase-check">${p.practised?'✓':'○'}</span></button>`).join('');$$('[data-index]').forEach(b=>b.onclick=()=>selectPhrase(+b.dataset.index));$('#listenCue').hidden=$('#micCue').hidden=!!p.latest;$('#replayCue').hidden=$('#takeRow').hidden=!p.latest;if(p.latest){take.src=p.latest.audio;$('#takeCount').textContent=`${p.takes||1} take${p.takes>1?'s':''}`}setMode(mode);renderFeedback(p.latest);drawWave();}
function selectPhrase(next){if(!lesson||recording||starting||stopping||busy||takeDraft)return;if(next<0||next>=lesson.phrases.length)return;index=next;rememberPhrase();renderPhrase()}
function setMode(value){if(recording||starting||stopping)return;mode=value;$$('.mode').forEach(b=>b.classList.toggle('active',b.dataset.mode===mode));concealed=mode==='recall';applyConceal();$('#recordTitle').textContent={listen:'Ready when you are.',recall:'Hold the phrase. Make it yours.',shadow:'Follow the speaker’s flow.'}[mode];$('#recordHint').textContent={listen:'Say the phrase the way you heard it.',recall:'The words are hidden. Record from memory.',shadow:'Use headphones. The original plays while you record.'}[mode]}
function applyConceal(){$('#phraseText').classList.toggle('concealed',concealed);$('#phraseText').setAttribute('aria-hidden',concealed?'true':'false');$('#hideText').setAttribute('aria-pressed',concealed);$('#reveal').hidden=!concealed}
async function playOriginal({once=false,onDone=null,rate=null}={}){const p=lesson?.phrases[index];if(!p)return;stopPlayback();original.playbackRate=rate??+$('#speed').value;original.currentTime=p.start;playbackDone=onDone;await original.play();$('#playOriginal span').textContent='Ⅱ';playbackTimer=setInterval(()=>{if(original.currentTime>=p.end||original.ended){if(looping&&!once&&!recording){original.currentTime=p.start;original.play().catch(e=>toast(e.message))}else{const done=playbackDone;stopPlayback();done?.()}}},15)}
async function togglePlay(){if(!lesson?.phrases[index]||starting||stopping)return;if(!original.paused){if(recording&&mode==='shadow'){stopRecording();return}stopPlayback()}else await playOriginal()}
function renderFeedback(result){$('#accuracyScore').textContent=result?result.accuracy+'%':'—';$('#rhythmScore').textContent=result?result.rhythm+'%':'—';$('#pitchScore').textContent=result?(result.intonation===null?'N/A':result.intonation+'%'):'—';$('#feedbackIntro').textContent=result?`Latest take · practice estimates at ${result.playbackSpeed||1}× speed. Listen back to judge the details.`:'Record a take to see where you match the speaker, and what to try next.';if(result){$('#tips').innerHTML='<span>↗</span><div><b>One thing at a time.</b><ul>'+result.tips.map(x=>'<li>'+esc(x)+'</li>').join('')+'</ul></div>';if(!concealed){let wi=0,end=0,html='';const text=lesson.phrases[index].text;for(const match of text.matchAll(/\p{L}[\p{L}\p{M}]*(?:['’]\p{L}[\p{L}\p{M}]*)*/gu)){const mark=result.words[wi++];html+=esc(text.slice(end,match.index))+`<span class="${mark?.match?'matched':'missed'}">${esc(match[0])}</span>`;end=match.index+match[0].length}$('#phraseText').innerHTML=html+esc(text.slice(end))};}else{$('#tips').innerHTML='<span>↗</span><div><b>Make room for your own voice.</b><p>You’re practising delivery, not becoming someone else. Use headphones for a cleaner comparison.</p></div>'}}
function canvasCtx(el){const dpr=window.devicePixelRatio||1,r=el.getBoundingClientRect(),W=Math.max(1,Math.round(r.width*dpr)),H=Math.max(1,Math.round(r.height*dpr));if(el.width!==W)el.width=W;if(el.height!==H)el.height=H;const ctx=el.getContext('2d');ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,r.width,r.height);return{ctx,w:r.width,h:r.height}}
const ACT=.1;let voiceErr=false,voice=null,live=null,liveCtx=null,visRaf=0;
function smoothPitch(v){const out=v.slice();for(let i=0;i<v.length;){if(v[i]==null){i++;continue}let j=i;while(j<v.length&&v[j]!=null)j++;const m=[];for(let k=i;k<j;k++){const w=v.slice(Math.max(i,k-2),Math.min(j,k+3)).sort((a,b)=>a-b);m.push(w[w.length>>1])}for(let k=i;k<j;k++)out[k]=j-i<4?null:(m[Math.max(0,k-i-1)]+m[k-i]+m[Math.min(j-i-1,k-i+1)])/3;i=j}return out}
function mkTrack(e,hz,xOf){const v=hz.filter(h=>h).sort((a,b)=>a-b),med=v[v.length>>1];const st=smoothPitch(e.map((_,i)=>{if(!hz[i]||!med)return null;let s=12*Math.log2(hz[i]/med);if(s>8)s-=12;else if(s<-8)s+=12;return Math.abs(s)>12?null:s}));return e.map((en,i)=>({x:xOf(i),e:en,st:st[i]}))}
const onIdx=e=>Math.max(0,e.findIndex(v=>v>ACT)),onX=t=>t?.length?t[onIdx(t.map(q=>q.e))].x:0;
function pauses(t){const out=[];if(!t?.length)return out;const a=t.findIndex(q=>q.e>ACT),b=t.findLastIndex(q=>q.e>ACT);let s=null;if(a<0)return out;for(let i=a;i<=b;i++){const on=t[i].e>ACT;if(!on&&s===null)s=i;if(on&&s!==null){if(t[i].x-t[s].x>=.149)out.push([t[s].x,t[i].x]);s=null}}return out}
function ending(t){const v=t.filter(q=>q.st!==null).map(q=>q.st);if(v.length<12)return'';const m=a=>a.reduce((s,x)=>s+x,0)/a.length,d=m(v.slice(-5))-m(v.slice(-15,-5));return d>1.2?'goes up ↗':d<-1.2?'goes down ↘':'stays flat →'}
function speechSpan(t){const a=t.findIndex(q=>q.e>ACT),b=t.findLastIndex(q=>q.e>ACT);return a<0?null:[t[a].x,t[b].x]}
function stressed(t,words,start){if(!t||!words?.length)return new Set;const peaks=words.map(w=>Math.max(0,...t.filter(q=>q.x>=w.start-start&&q.x<=w.end-start).map(q=>q.e))),cut=Math.max(.5,[...peaks].sort((a,b)=>b-a)[Math.max(0,Math.round(words.length/4)-1)]);return new Set(peaks.flatMap((m,i)=>m>=cut?[i]:[]))}
async function drawWave(){if(!lesson)return;const current=lesson,lid=current.id,ix=index;voice=null;voiceErr=false;if(live?.key!==lid+':'+ix)live=null;paintWave();try{const revision=current.phrases[ix].revision;const v=await api(`/api/voice/${lid}/${ix}${revision?`?revision=${encodeURIComponent(revision)}`:''}`);if(lesson!==current||index!==ix)return;const p=lesson.phrases[ix];v.src=mkTrack(v.source.energy,v.source.pitch,i=>(i+1)*v.hop);v.pauses=pauses(v.src);v.stress=stressed(v.src,p.words,p.start);if(v.take){const sp=v.take.speed||1,raw=mkTrack(v.take.energy,v.take.pitch,i=>(i+1)*v.hop*sp),A=speechSpan(v.src),B=speechSpan(raw),len=p.end-p.start;v.scale=sp;v.shift=onX(v.src)-onX(raw);if(A&&B&&B[1]>B[0]){v.scale=(A[1]-A[0])*sp/(B[1]-B[0]);v.shift=A[0]-B[0]/sp*v.scale}v.you=raw.map(q=>({...q,x:q.x/sp*v.scale+v.shift})).filter(q=>q.x>=0&&q.x<=len);if(!recording)live=null}voice=v;paintWave()}catch{if(lesson===current&&index===ix){voiceErr=true;paintWave()}}}
function liveTrack(){const L=live;return mkTrack(L.frames.map(f=>f.rms/L.max),L.frames.map(f=>f.hz),i=>L.frames[i].x)}
function pitchLine(ctx,t,X,Y,color,width){if(!t?.length)return;ctx.strokeStyle=color;ctx.lineWidth=width;ctx.lineJoin=ctx.lineCap='round';ctx.beginPath();let run=[],prev=null;const flush=()=>{if(run.length>1){ctx.moveTo(...run[0]);for(let i=1;i<run.length;i++)ctx.quadraticCurveTo(...run[i-1],(run[i-1][0]+run[i][0])/2,(run[i-1][1]+run[i][1])/2);ctx.lineTo(...run.at(-1))}run=[]};for(const q of t){if(q.st===null)continue;if(prev!==null&&q.x-prev>=.2)flush();run.push([X(q.x),Y(q.st)]);prev=q.x}flush();ctx.stroke()}
function box(ctx,x,y,w,h,r){ctx.beginPath();ctx.roundRect?ctx.roundRect(x,y,w,h,r):ctx.rect(x,y,w,h);ctx.fill()}
function voiceTips(p,v,you){const W=p.words||[],cl=s=>s.trim().replace(/^[^\w']+|[^\w']+$/g,''),strong=[...v.stress].sort((a,b)=>a-b).filter(i=>i<W.length).slice(0,4).map(i=>cl(W[i].word)),after=[...new Set(v.pauses.map(([a])=>W.findLast(wd=>wd.start-p.start<a)).filter(Boolean).map(wd=>'“'+cl(wd.word)+'”'))],end=ending(v.src),mine=you?.length?you:null,n=mine?pauses(mine).length:0,yEnd=mine?ending(mine):'',tip=(t,val,y,ok)=>`<div><small>${t}</small><b>${esc(val)}</b>${y!=null?`<span class="${ok?'ok':''}">You: ${esc(y)}${ok?' ✓':''}</span>`:''}</div>`;return tip('Say these stronger',strong.length?strong.join(', '):'No word stands out')+tip('Pause',after.length?'After '+after.join(', '):'None. Say it in one go.',mine?(n?n+(n>1?' pauses':' pause'):'no pauses'):null,n===v.pauses.length)+tip('At the end, the voice',end||'Hard to tell',mine?yEnd||'hard to tell':null,!!end&&yEnd===end)}
function paintWave(){const{ctx,w,h}=canvasCtx($('#waveform'));const p=lesson?.phrases[index];if(!p)return;const src=voice?.src,you=live?liveTrack():voice?.you,span=Math.max(p.end-p.start,you?.length?you.at(-1).x+.1:0),X=x=>x/span*w,top=16,bot=h-30,mid=(top+bot)/2,Y=st=>mid-Math.max(-9,Math.min(9,st))*(bot-top)/20,ph=recording&&live?live.x:!original.paused?original.currentTime-p.start:!take.paused&&voice?.you&&!live?take.currentTime*voice.scale+voice.shift:null;ctx.textAlign='center';for(const[a,b]of voice?.pauses||[]){ctx.fillStyle='#f7ede8';box(ctx,X(a),top-6,X(b)-X(a),bot-top+12,4);if(X(b)-X(a)>=26){ctx.fillStyle='#c0786a';ctx.font='500 9px system-ui,sans-serif';ctx.fillText('pause',X((a+b)/2),top+5)}}pitchLine(ctx,src,X,Y,you?.length?'rgba(79,122,92,.4)':'#4f7a5c',3.5);pitchLine(ctx,you,X,Y,'#c58b53',2.5);let last=-1;(p.words||[]).forEach((wd,i)=>{const a=wd.start-p.start,b=wd.end-p.start,c=X((a+b)/2),em=voice?.stress?.has(i),now=ph!=null&&ph>=a&&ph<b,txt=wd.word.trim();ctx.font=(em?'700 12px':'11px')+' system-ui,sans-serif';const tw=ctx.measureText(txt).width;if(c-tw/2<=last+4)return;if(now){ctx.fillStyle='rgba(197,139,83,.2)';box(ctx,c-tw/2-5,h-20,tw+10,18,6)}ctx.fillStyle=em||now?'#20382f':'#8b948a';ctx.fillText(txt,c,h-7);last=c+tw/2});if(ph!=null&&ph>=0){ctx.strokeStyle='rgba(32,56,47,.35)';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(X(ph),top-6);ctx.lineTo(X(ph),bot+4);ctx.stroke()}$('#youKey').hidden=!(recording||you?.length);const html=src?`<p>The line rises when the voice goes up and falls when it goes down. Match its shape, not the speaker&#39;s natural pitch.</p><div class="voice-tips">${voiceTips(p,voice,recording?null:you)}</div>`:voiceErr?`<p>Couldn&#39;t load the speaker&#39;s voice. Quit Shadow Studio and any Terminal window running it, then open it again.</p>`:'';if(html!==paintWave.html){paintWave.html=html;$('#voiceStats').innerHTML=html}}
function detectPitch(buf,sr){const n=buf.length>>1,s=sr/2,x=new Float32Array(n);let m=0,e=0;for(let i=0;i<n;i++){x[i]=(buf[2*i]+buf[2*i+1])/2;m+=x[i]}m/=n;for(let i=0;i<n;i++){x[i]-=m;e+=x[i]*x[i]}const rms=Math.sqrt(e/n);if(rms<.01)return{rms,hz:null};const lo=Math.floor(s/400),hi=Math.min(n>>1,Math.ceil(s/60)),c=new Float32Array(hi+2);let best=0;for(let l=lo;l<=hi;l++){let sum=0;for(let i=0;i<n-l;i++)sum+=x[i]*x[i+l];c[l]=sum/(n-l);if(c[l]>best)best=c[l]}if(best/(e/n)<.45)return{rms,hz:null};for(let l=lo+1;l<hi;l++)if(c[l]>=.9*best&&c[l]>=c[l-1]&&c[l]>=c[l+1])return{rms,hz:s/l};return{rms,hz:null}}
function startLive(){stopLive();try{const C=window.AudioContext||window.webkitAudioContext,ctx=new C(),an=ctx.createAnalyser(),g=ctx.createGain();an.fftSize=2048;g.gain.value=0;ctx.createMediaStreamSource(micStream).connect(an);an.connect(g);g.connect(ctx.destination);ctx.resume().catch(()=>{});liveCtx=ctx;live={key:lesson.id+':'+index,an,buf:new Float32Array(2048),frames:[],shadow:mode==='shadow',speed:mode==='shadow'?+$('#speed').value:1,x:null,at:0,max:.02}}catch{live=null}}
function stopLive(){liveCtx?.close().catch(()=>{});liveCtx=null}
function sampleLive(){const L=live,now=performance.now(),p=lesson.phrases[index];L.an.getFloatTimeDomainData(L.buf);const{rms,hz}=detectPitch(L.buf,liveCtx.sampleRate);if(L.shadow){if(!original.paused)L.x=original.currentTime-p.start;else if(L.x!==null)L.x+=(now-L.at)/1000*L.speed}else if(L.x!==null)L.x+=(now-L.at)/1000;else if(hz&&rms>.015)L.x=onX(voice?.src);L.at=now;if(L.x===null)return;L.max=Math.max(L.max,rms);L.frames.push({x:L.x,rms,hz})}
function animateVoice(){if(visRaf)return;const step=()=>{if(recording&&live&&liveCtx)sampleLive();paintWave();visRaf=recording||!original.paused||!take.paused?requestAnimationFrame(step):0};visRaf=requestAnimationFrame(step)}
async function startRecording(){
  if(!lesson?.phrases[index]?.revision||busy||recording||starting||stopping||takeDraft)return;
  if(!navigator.mediaDevices?.getUserMedia||!window.MediaRecorder)throw new Error('Microphone recording needs a supported browser. Open this local address in Safari or Chrome.');
  const {id:lid}=lesson, ix=index, {revision}=lesson.phrases[ix], shadow=mode==='shadow';
  const params=new URLSearchParams({speed:shadow?$('#speed').value:1,revision});
  const id=Array.from(crypto.getRandomValues(new Uint8Array(16)),byte=>byte.toString(16).padStart(2,'0')).join('');
  const target='/api/record/'+lid+'/'+ix+'/'+id+'?'+params;
  starting=true;captureInterrupted=false;setControlsLocked(true);stopPlayback();$('#recordButton').disabled=true;
  window.addEventListener('beforeunload',protectRecording);
  let capture;
  try{
    micStream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true}});
    if(captureInterrupted||document.hidden)throw new Error('The page was hidden before recording started. Select Record to try again.');
    const type=['audio/webm;codecs=opus','audio/mp4','audio/webm'].find(t=>MediaRecorder.isTypeSupported(t));
    capture=recorder=new MediaRecorder(micStream,type?{mimeType:type}:{});
    chunks=[];
    recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data)};
    recorder.onerror=()=>{if(recorder===capture)stopRecording(true)};
    recorder.onstop=()=>{
      if(recorder!==capture)return;
      const interrupted=captureInterrupted||recording;
      const blob=new Blob(chunks,{type:capture.mimeType});
      if(blob.size)takeDraft={lid,target,blob};
      resetRecording();
      if(!blob.size){toast('No audio was captured. Try again.');return}
      if(interrupted)showTakeDraft('Recording stopped after an interruption. You can submit the captured audio or discard it.');
      else finishRecording();
    };
    for(const track of micStream.getAudioTracks()){
      const interrupted=()=>{if(recorder===capture)stopRecording(true)};
      track.addEventListener('ended',interrupted);
      track.addEventListener('mute',interrupted);
    }
    recorder.start(100);recording=true;starting=false;
    startLive();animateVoice();recordStart=Date.now();
    $('#recordButton').innerHTML='■ Stop recording';$('#recordButton').classList.add('recording');$('#recordButton').disabled=false;
    $('#recordingMeter').hidden=false;$('#recordingTime').textContent='00:00';
    recordTimer=setInterval(()=>$('#recordingTime').textContent=fmt((Date.now()-recordStart)/1000),200);
    autoStop=setTimeout(stopRecording,34000);
    if(shadow)await playOriginal({once:true,onDone:()=>{clearTimeout(autoStop);autoStop=setTimeout(stopRecording,500)}});
  }catch(e){
    if(capture&&recorder!==capture)return;
    if(recording)stopRecording(true);
    else if(!stopping)resetRecording();
    throw new Error(e.name==='NotAllowedError'?'Microphone access was denied. Open this site’s settings from the address bar (Safari: Safari menu → Settings for This Website), set Microphone to Allow, then select Record again.':e.message);
  }
}
function protectRecording(event){event.preventDefault();event.returnValue='There is an unsaved take.'}
function releaseMic(){micStream?.getTracks().forEach(t=>t.stop());micStream=null}
function setControlsLocked(lock){$$('.mode,.chip,#speed,#prevPhrase,#nextPhrase,#editPhrase,#lessonMenu,#resplitLesson,.phrase-item,#newTop,#libraryNav,#practiceNav,#playTake,#compareAB,#openTakeHistory').forEach(b=>b.disabled=lock);if(!lock&&lesson){$('#prevPhrase').disabled=index===0;$('#nextPhrase').disabled=index===lesson.phrases.length-1}}
function resetRecording(){
  recording=false;stopping=false;starting=false;stopPlayback();stopLive();live=null;
  clearInterval(recordTimer);clearTimeout(autoStop);releaseMic();recorder=null;chunks=[];
  $('#recordButton').innerHTML='<span class="mic-dot"></span> Record a take';
  $('#recordButton').classList.remove('recording');$('#recordButton').disabled=Boolean(takeDraft);$('#recordingMeter').hidden=true;
  setControlsLocked(Boolean(takeDraft));
  if(!takeDraft)window.removeEventListener('beforeunload',protectRecording);
  if(lesson)paintWave();
}
function stopRecording(interrupted=false){
  if(!recording||stopping)return;
  captureInterrupted=interrupted;stopping=true;recording=false;
  clearInterval(recordTimer);clearTimeout(autoStop);stopPlayback();stopLive();$('#recordButton').disabled=true;
  if(recorder.state!=='inactive')recorder.stop();
}
function showTakeDraft(message){$('#takeDraftMessage').textContent=message;$('#takeDraft').hidden=false}
function clearTakeDraft(){takeDraft=null;$('#takeDraft').hidden=true;resetRecording()}
async function finishRecording(){
  if(!takeDraft||busy)return;
  const {lid,target,blob}=takeDraft, title='Reviewing your take';
  const upload=()=>api(target,{method:'POST',headers:{'Content-Type':blob.type},body:blob});
  setBusy(true,title,'Listening to your recording…');
  try{
    let submission;
    try{submission=await upload()}
    catch(error){
      if(error.status!==403||error.message!=='Refresh the app and try again.')throw error;
      const html=new DOMParser().parseFromString(await (await apiResponse('/')).text(),'text/html');
      token=html.querySelector('meta[name="shadow-token"]')?.content||token;
      submission=await upload();
    }
    if(submission.jobId)await waitJob(submission.jobId,title);
    setBusy(true,title,'Refreshing the phrase…');
    clearTakeDraft();
    try{
      const refreshed=await loadLesson(lid);
      const latest=refreshed?lesson.phrases[index]?.latest:null;
      toast(latest?.id===submission.takeId?'Your feedback is ready. Listen back, then choose one detail to practise.':'Your recording and feedback are saved in Take history.');
    }catch{toast('Your take was saved. Reopen this session to see the feedback.')}
  }catch(error){showTakeDraft((error instanceof TypeError?'The local engine could not be reached.':error.message)+' The captured audio is still here. Retry submission or discard it.')}
  finally{setBusy(false)}
}
document.addEventListener('visibilitychange',()=>{if(document.hidden){if(starting)captureInterrupted=true;stopRecording(true)}});
$('#retryTake').onclick=finishRecording;
$('#discardTakeDraft').onclick=()=>{if(!busy)clearTakeDraft()};
const importJobKey='shadow-import-job';
let pendingImport;
try{pendingImport=sessionStorage.getItem(importJobKey)}catch{}
if(!/^[0-9a-f]{32}$/.test(pendingImport)&&pendingImport!=='sending')pendingImport=null;
function saveImportJob(id){
  pendingImport=id;
  try{if(id===null)sessionStorage.removeItem(importJobKey);else sessionStorage.setItem(importJobKey,id)}catch{}
}
function showImportStatus(message){
  const canCheck=!!pendingImport&&pendingImport!=='sending';
  $('#importSubmit').disabled=canCheck;
  $('#checkImport').hidden=!canCheck;
  if(message!==undefined)$('#importError').textContent=message;
  if(!$('#importDialog').open)$('#importDialog').showModal();
}
function openImport(){if(recording||starting||stopping||busy||takeDraft)return;showImportStatus()}
const missingImport='The engine no longer has this import job. It may have restarted. Check your library before importing again.';
const unconfirmedImport='The engine’s reply was interrupted before this browser got a job ID. Check your library before importing again.';
async function recoverImport(){
  const id=pendingImport;
  if(id==='sending'){showImportStatus(unconfirmedImport);return false}
  if(!id)return false;
  stopPlayback();
  try{
    const lid=await waitJob(id,'Importing your practice session',true);
    $('#jobMessage').textContent='Opening your saved session…';
    const loaded=await loadLesson(lid,true);
    saveImportJob(null);
    if(!loaded)throw new Error('The import finished, but the session is no longer in your library.');
  }catch(error){
    setBusy(false);
    showImportStatus(pendingImport?'Could not check the import. Make sure the local engine is running, then choose Check import status.':error.message);
    return false;
  }
  setBusy(false);
  $('#importForm').reset();$('#fileLabel').textContent='Choose an audio or video file';$('#importError').textContent='';
  showView('studio');toast('Your practice session is ready. Start by listening to the first phrase.');
  return true;
}
$('#checkImport').onclick=()=>{if(busy)return;$('#importDialog').close();void recoverImport()};
['#newTop','#addLibrary','#emptyImport'].forEach(s=>$(s).onclick=openImport);$$('.close-dialog').forEach(b=>b.onclick=()=>b.closest('dialog').close());$('#cancelDelete').onclick=()=>$('#deleteDialog').close();$('#practiceNav').onclick=()=>showView('studio');$('#libraryNav').onclick=guarded(async()=>{await refreshLibrary();showView('library')});$('#continueLesson').onclick=guarded(async()=>{if(lesson?.phrases[index]&&await loadLesson(lesson.id))showView('studio')});$('#sampleButton').onclick=guarded(async()=>{if(sampleId)await loadLesson(sampleId)});$('#prevPhrase').onclick=()=>selectPhrase(index-1);$('#nextPhrase').onclick=()=>selectPhrase(index+1);$('#playOriginal').onclick=guarded(togglePlay);$('#loop').onclick=()=>{looping=!looping;$('#loop').setAttribute('aria-pressed',looping)};$('#hideText').onclick=()=>{concealed=!concealed;$('#phraseText').textContent=lesson.phrases[index].text;applyConceal()};$('#reveal').onclick=()=>{concealed=false;applyConceal()};$$('.mode').forEach(b=>b.onclick=()=>setMode(b.dataset.mode));$('#speed').onchange=()=>original.playbackRate=+$('#speed').value;$('#recordButton').onclick=guarded(async()=>recording?stopRecording():startRecording());$('#playTake').onclick=guarded(async()=>{if(!take.paused){stopPlayback();return}stopPlayback();take.currentTime=0;await take.play()});$('#compareAB').onclick=guarded(async()=>{await playOriginal({once:true,rate:lesson.phrases[index].latest?.playbackSpeed||1,onDone:()=>{take.currentTime=0;take.play().catch(e=>toast(e.message))}})});original.onplay=take.onplay=animateVoice;original.onerror=()=>toast(lesson?.sample?'The guided sample audio could not be loaded. Reopen it from the library or choose Add a voice.':'The audio could not be loaded. Reopen the session from your library.');
$('#audioFile').onchange=()=>{$('#fileLabel').textContent=$('#audioFile').files[0]?.name||'Choose an audio or video file';if($('#audioFile').files.length)$('#youtubeUrl').value=''};$('#youtubeUrl').oninput=()=>{if($('#youtubeUrl').value){$('#audioFile').value='';$('#fileLabel').textContent='Choose an audio or video file'}};
$('#importForm').onsubmit=async e=>{
  e.preventDefault();
  if(busy||(pendingImport&&pendingImport!=='sending'))return;
  $('#importError').textContent='';
  const file=$('#audioFile').files[0],url=$('#youtubeUrl').value.trim(),language=$('#importLanguage').value;
  if(!file&&!url){$('#importError').textContent='Paste a YouTube link or choose a file.';return}
  if(file?.size>150*1024*1024){$('#importError').textContent='Choose a file smaller than 150 MB.';return}
  $('#importDialog').close();stopPlayback();
  saveImportJob('sending');
  setBusy(true,'Starting your import',file?'Sending your file to the local engine…':'Sending the YouTube link to the local engine…');
  try{
    let j;
    if(file){const form=new FormData();form.append('file',file);form.append('language',language);j=await api('/api/upload',{method:'POST',body:form})}
    else{j=await api('/api/import',json('POST',{url,language}))}
    if(!/^[0-9a-f]{32}$/.test(j.jobId))throw new Error(unconfirmedImport);
    saveImportJob(j.jobId);
  }catch(error){
    if(error.status>=400&&error.status<500)saveImportJob(null);
    setBusy(false);
    showImportStatus(pendingImport?unconfirmedImport:error.message);
    return;
  }
  await recoverImport();
};
$('#editPhrase').onclick=()=>{if(!lesson)return;stopPlayback();const p=lesson.phrases[index];$('#editText').value=p.text;$('#editStart').value=p.start;$('#editEnd').value=p.end;$('#editError').textContent='';$('#editDialog').showModal()};$('#editForm').onsubmit=async e=>{e.preventDefault();try{lesson=await api(`/api/phrase/${lesson.id}/${index}`,json('PATCH',{text:$('#editText').value,start:+$('#editStart').value,end:+$('#editEnd').value,revision:lesson.phrases[index]?.revision}));$('#editDialog').close();rememberPhrase();renderPhrase();toast('Phrase saved.')}catch(err){$('#editError').textContent=err.message}};
$('#lessonMenu').onclick=()=>{stopPlayback();$('#deleteDialog').showModal()};$('#confirmDelete').onclick=guarded(async()=>{const old=lesson.id;try{await api('/api/lesson/'+old,{method:'DELETE'})}
catch(error){if(error.status!==404)throw error;$('#deleteDialog').close();clearMissingLesson(old);await refreshLibrary();return}
$('#deleteDialog').close();forgetLesson(old);location.reload()});
$('#resplitLesson').onclick=()=>{if(!lesson||busy)return;stopPlayback();$('#resplitDialog').showModal()};$('#cancelResplit').onclick=()=>$('#resplitDialog').close();$('#confirmResplit').onclick=guarded(async()=>{const lid=lesson.id;$('#resplitDialog').close();setBusy(true,'Finding new phrases');const j=await api('/api/resplit/'+lid,{method:'POST'}).catch(e=>{setBusy(false);throw e});await waitJob(j.jobId,'Finding new phrases');writePreference(phraseKey(lid),null);if(await loadLesson(lid,true))toast('New phrases are ready. Start again from the first phrase.')});
document.addEventListener('keydown',e=>{if(['INPUT','TEXTAREA','SELECT','BUTTON','SUMMARY'].includes(document.activeElement.tagName)||document.querySelector('dialog[open]')||busy||recording||starting||stopping||takeDraft)return;if(e.code==='Space'){e.preventDefault();guarded(togglePlay)()}if(e.code==='ArrowRight')selectPhrase(index+1);if(e.code==='ArrowLeft')selectPhrase(index-1)});window.addEventListener('resize',()=>{if(lesson)paintWave()});window.addEventListener('beforeunload',e=>{if(recording||starting||stopping||busy){e.preventDefault();e.returnValue=''}});
guarded(async()=>{if(pendingImport&&await recoverImport())return;const list=await refreshLibrary(),last=readPreference(lastLessonKey);if(busy||lesson||last===null)return;if(list.some(x=>x.id===last))await loadLesson(last);else clearMissingLesson(last)})();

function openTakeHistory(){
  if(!lesson||busy||recording||starting||stopping)return;
  stopPlayback();
  const history=lesson.takeHistory||[], current=lesson.phrases[index]?.revision, active=new Set(lesson.phrases.map(p=>p.revision));
  $('#takeHistoryHint').hidden=!history.length;
  $('#takeHistoryStatus').textContent=history.length?'':'No saved takes in this session yet.';
  $('#takeHistoryList').innerHTML=history.map((result,i)=>{
    const p=result.phraseRevision, date=result.created==null?'Date unavailable':new Date(result.created*1000).toLocaleString();
    const label=p?.id===current?'Current phrase':active.has(p?.id)?'Another phrase':'Earlier phrase version';
    const speed=result.playbackSpeed==null?'Speed unavailable':`${result.playbackSpeed}× speed`;
    return `<li><div class="take-history-heading"><strong>${esc(date)}${result.legacy?' · Legacy take':''}</strong><button class="button quiet" data-history-index="${i}">Replay</button></div>${p?`<p class="history-phrase">${esc(p.text)}</p><p>${label} · ${fmt(p.start)} – ${fmt(p.end)}</p>`:''}<p>${esc(speed)} · Word accuracy ${esc(result.accuracy)}% · Pace &amp; rhythm ${esc(result.rhythm)}% · Intonation ${result.intonation==null?'N/A':esc(result.intonation)+'%'}</p>${result.tips?.length?`<details><summary>Feedback</summary><ul>${result.tips.map(t=>'<li>'+esc(t)+'</li>').join('')}</ul></details>`:''}</li>`;
  }).join('');
  $$('#takeHistoryList [data-history-index]').forEach(b=>b.onclick=async()=>{
    const result=history[+b.dataset.historyIndex];
    historyAudio.hidden=false;historyAudio.src=result.audio;
    $('#takeHistoryStatus').textContent='';historyAudio.focus();
    try{await historyAudio.play()}catch(error){if(error.name!=='AbortError'&&historyDialog.open)$('#takeHistoryStatus').textContent='Audio for this take is unavailable.'}
  });
  historyDialog.showModal();
}
$('#openTakeHistory').onclick=openTakeHistory;
$('#closeTakeHistory').onclick=()=>historyDialog.close();
historyDialog.onclose=()=>{historyAudio.pause();historyAudio.removeAttribute('src');historyAudio.load();historyAudio.hidden=true};
