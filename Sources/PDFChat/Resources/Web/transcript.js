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
    el.innerHTML='<div class="role"></div><div class="quote" hidden></div><div class="images"></div><div class="content"></div><div class="pending" hidden>等待模型响应</div><div class="actions"><button class="copy">复制</button><button class="retry" hidden>重试</button><span class="state"></span></div><details hidden><summary>用量与工具过程</summary><pre></pre></details>';
    el.querySelector('.copy').onclick=()=>bridge({type:'copy',id:m.id});
    el.querySelector('.retry').onclick=()=>bridge({type:'retry',id:m.id});
    nodes.set(m.id,el); return el;
}
function updateMessage(m) {
    const el=nodes.get(m.id) || createMessage(m);
    el.querySelector('.role').textContent=m.role==='user' ? '你'+(m.mode?' · '+m.mode:'') : (m.model||'阅读助手');
    const content=el.querySelector('.content');
    if(el._text!==m.text || el._streaming!==m.streaming) {
        const applied=m.role==='user' ? (content.textContent=m.text,true) : renderText(content,m.text,m.streaming);
        if(applied) { el._text=m.text; el._streaming=m.streaming; }
    }
    const quote=el.querySelector('.quote'); quote.hidden=!m.quote;
    if(m.quote) quote.textContent='第 '+m.quote.page+' 页 · '+m.quote.text;
    if(m.images && !el._images) {
        for(const src of m.images) { if(!src.startsWith('data:image/')) continue; const img=document.createElement('img'); img.src=src; el.querySelector('.images').append(img); }
        el._images=true;
    }
    el.querySelector('.pending').hidden=!(m.streaming && !m.text);
    el.querySelector('.state').textContent=m.status==='stopped'?'已停止':m.status==='error'?'请求失败':m.streaming?'生成中':'';
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
        root.innerHTML='<div class="empty"><div class="symbol">✦</div><h2>读到这里，聊一聊</h2><p>默认发送完整 PDF，图表与文字一起理解。<br>选中段落可以引用提问。</p><div class="suggestions"><button data-prompt="请概括这份文档的核心问题、方法和结论，并引用页码。">概括这份文档 ↗</button><button data-prompt="请解释这份文档最重要的概念，并指出对应页码。">解释关键概念 ↗</button><button data-prompt="请梳理这份文档的论据与局限，并引用原文页码。">梳理论据与局限 ↗</button></div></div>';
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
