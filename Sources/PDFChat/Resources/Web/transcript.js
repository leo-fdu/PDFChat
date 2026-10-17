'use strict';
marked.setOptions({gfm:true, breaks:false});
const root=document.getElementById('messages'), latest=document.getElementById('latest');
const nodes=new Map(), data=new Map();
let following=true, lastRevision=-1, updateInFlight=false;
function bridge(value) { window.webkit.messageHandlers.action.postMessage(value); }
function escapeHtml(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function bottom() { window.scrollTo(0,document.documentElement.scrollHeight); }
function nearBottom() { return document.documentElement.scrollHeight-window.innerHeight-window.scrollY<90; }
window.addEventListener('scroll',()=>{ if(!updateInFlight) following=nearBottom(); latest.hidden=following; },{passive:true});
window.addEventListener('wheel',e=>{ if(e.deltaY<0) { following=false; latest.hidden=false; } },{passive:true});
latest.onclick=()=>{ following=true; bottom(); latest.hidden=true; };
function renderText(element, text, streaming) {
    const selection=window.getSelection();
    if(selection && !selection.isCollapsed && element.contains(selection.anchorNode)) return false;
    const html=restoreMath(marked.parse(protectMath(text)));
    element.innerHTML=DOMPurify.sanitize(html,{FORBID_TAGS:['img','style','svg','math','iframe','form','input','button'], ALLOWED_URI_REGEXP:/^(?:(?:https?|mailto|pdfchat):|[#/])/i});
    renderMathInElement(element,{delimiters:[{left:'$$',right:'$$',display:true},{left:'\\[',right:'\\]',display:true},{left:'\\(',right:'\\)',display:false},{left:'$',right:'$',display:false}],throwOnError:false,trust:false,ignoredTags:['script','style','textarea','pre','code']});
    return true;
}
function createMessage(m) {
    const el=document.createElement('article'); el.className='message '+m.role;
    el.setAttribute('aria-label',m.role==='user'?'Your message':'Assistant response');
    el.innerHTML=(m.role==='user'?'':'<div class="role"></div>')+'<div class="bubble"><div class="quote" hidden></div><div class="images"></div><div class="content"></div><div class="pending" hidden>Waiting for response</div></div><div class="actions"><button class="copy" aria-label="Copy message" title="Copy"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" aria-hidden="true"><rect x="8" y="3" width="13" height="14" rx="3"/><path d="M16 17v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h3"/></svg></button><button class="retry" hidden>Retry</button><span class="state"></span></div><details hidden><summary>Usage and tool activity</summary><pre></pre></details>';
    el.querySelector('.copy').onclick=()=>bridge({type:'copy',id:m.id});
    el.querySelector('.retry').onclick=()=>bridge({type:'retry',id:m.id});
    nodes.set(m.id,el); return el;
}
function updateMessage(m) {
    const el=nodes.get(m.id) || createMessage(m);
    const role=el.querySelector('.role');
    if(role) role.textContent=m.model||'Reading Assistant';
    const content=el.querySelector('.content');
    if(el._text!==m.text || el._streaming!==m.streaming) {
        const applied=m.role==='user' ? (content.textContent=m.text,true) : renderText(content,m.text,m.streaming);
        if(applied) { el._text=m.text; el._streaming=m.streaming; }
    }
    const quote=el.querySelector('.quote'); quote.hidden=!m.quote;
    if(m.quote) quote.textContent='Page '+m.quote.page+' · '+m.quote.text;
    if(m.images && !el._images) {
        for(const src of m.images) { if(!src.startsWith('data:image/')) continue; const img=document.createElement('img'); img.src=src; el.querySelector('.images').append(img); }
        el._images=true;
    }
    el.querySelector('.pending').hidden=!(m.streaming && !m.text);
    el.querySelector('.state').textContent=m.status==='stopped'?'Stopped':m.status==='error'?'Request failed':m.streaming?'Generating':'';
    el.querySelector('.state').classList.toggle('error',m.status==='error');
    el.querySelector('.retry').hidden=m.status!=='error';
    const details=el.querySelector('details'); details.hidden=!m.details;
    details.querySelector('pre').textContent=m.details||'';
    data.set(m.id,m);
    return el;
}
function applyUpdate(payload) {
    if(payload.revision<lastRevision) return;
    lastRevision=payload.revision;
    const keepFollowing=following;
    updateInFlight=true;
    if(payload.reset) { root.replaceChildren(); nodes.clear(); data.clear(); following=true; }
    if(payload.order.length===0) {
        root.innerHTML='<div class="empty"><div class="symbol">✦</div><h2>A little help with your reading</h2><p>Send the full PDF, including text and figures.<br>Select a passage to ask about it.</p><div class="suggestions"><button data-prompt="Summarize the main question, methods, and findings of this document. Cite page numbers.">Summarize this document ↗</button><button data-prompt="Explain the key concepts in this document and cite the relevant pages.">Explain key concepts ↗</button><button data-prompt="Review the evidence and limitations in this document. Cite the relevant pages.">Review evidence and limitations ↗</button></div></div>';
        root.querySelectorAll('[data-prompt]').forEach(b=>b.onclick=()=>bridge({type:'prompt',text:b.dataset.prompt}));
    } else {
        root.querySelector('.empty')?.remove();
        for(const m of payload.updates) updateMessage(m);
        const valid=new Set(payload.order);
        for(const [id,node] of nodes) { if(!valid.has(id)) { node.remove(); nodes.delete(id); data.delete(id); } }
        payload.order.forEach((id,index)=>{ const node=nodes.get(id); if(node && root.children[index]!==node) root.insertBefore(node,root.children[index]||null); });
    }
    requestAnimationFrame(()=>{ if(keepFollowing || payload.reset) { following=true; bottom(); } latest.hidden=following; updateInFlight=false; });
}
document.addEventListener('selectionchange',()=>{ const s=window.getSelection(); if(s && s.isCollapsed) for(const m of data.values()) { const el=nodes.get(m.id); if(el && el._text!==m.text) updateMessage(m); } });
document.addEventListener('click',e=>{ const a=e.target.closest('a'); if(a) { e.preventDefault(); bridge({type:'link',url:a.getAttribute('href')}); } });
new ResizeObserver(()=>{ if(following) requestAnimationFrame(bottom); }).observe(root);
window.webkit.messageHandlers.ready.postMessage('ready');
