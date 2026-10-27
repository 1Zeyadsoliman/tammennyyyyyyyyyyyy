// وصلت؟ طمّني — Backend (Node 18+, بدون مكتبات)
const http = require('http'), fs = require('fs'), path = require('path'), crypto = require('crypto');
try { fs.readFileSync(path.join(__dirname, '.env'), 'utf8').split('\n').forEach(l => { const m = l.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/); if (m && !process.env[m[1]]) process.env[m[1]] = m[2]; }); } catch {}

const PORT = process.env.PORT || 3000;
const KEY = process.env.ANTHROPIC_API_KEY;
const DB = path.join(__dirname, 'data.json');
let db = { trips: {} };
try { db = JSON.parse(fs.readFileSync(DB, 'utf8')); } catch {}
const save = () => fs.writeFile(DB, JSON.stringify(db), () => {});

const SILENT_MS = 10 * 60 * 1000; // لو مفيش تحديث 10 دقايق
const json = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(obj)); };
const readBody = req => new Promise(r => { let s = ''; req.on('data', c => { s += c; if (s.length > 1e5) req.destroy(); }); req.on('end', () => { try { r(JSON.parse(s || '{}')); } catch { r({}); } }); });
const clean = (s, n = 80) => String(s || '').replace(/[<>]/g, '').trim().slice(0, n);

function view(t) {
  const now = Date.now(), last = t.points[t.points.length - 1] || null;
  let status = 'onway';
  if (t.arrivedAt) status = 'arrived';
  else if (now > t.eta) status = 'late';
  else if (now - (last ? last.t : t.startedAt) > SILENT_MS) status = 'silent';
  return { id: t.id, name: t.name, from: t.from, to: t.to, startedAt: t.startedAt, eta: t.eta, arrivedAt: t.arrivedAt,
    status, lateMinutes: status === 'late' ? Math.round((now - t.eta) / 60000) : 0, last, points: t.points.slice(-150), now };
}

// ---------- كشف الأخبار ----------
function heuristic(text) {
  const flags = [];
  const rules = [
    [/عاجل|عاجلل|خطير جدا|خطير جداً/, 'صياغة مستعجلة بتلعب على الخوف'],
    [/شير|انشر|ابعت(ها)? لكل|قبل ما (يتحذف|تتحذف|يمسحوه)/, 'بتطلب منك تنشر بسرعة'],
    [/(مصدر|مصادر) (مؤكد|خاص|موثوق)|بيقولوا|سمعت إن|حد قريب من/, 'مصدر مجهول أو غير محدد'],
    [/(الحكومة|الدولة|الأطباء|العلماء) (بتخبي|مخبيين|بيخبوا|يخفون)/, 'ادعاء "إخفاء الحقيقة" من غير دليل'],
    [/100%|مضمون|علاج (نهائي|سحري)|معجزة/, 'مبالغة وادعاءات مطلقة'],
    [/!{3,}|؟{3,}/, 'علامات تعجب كتير'],
  ];
  rules.forEach(([re, msg]) => re.test(text) && flags.push(msg));
  if (!/https?:\/\/|المصدر|حسب|وفقا|وفقاً|بحسب|أعلن|صرّح|صرح/.test(text)) flags.push('مفيش مصدر أو رابط واضح');
  const score = flags.length;
  const verdict = score >= 3 ? 'مشكوك فيه' : score === 2 ? 'محتاج تحقق' : 'مفيش علامات خطر واضحة';
  return { verdict, confidence: Math.min(40 + score * 10, 70), reasons: flags.length ? flags : ['مفيش علامات تضليل واضحة في الصياغة'],
    tips: ['دوّر على الخبر في موقع رسمي أو وكالة أنباء معروفة', 'اعمل بحث عكسي عن الصورة (Google Lens)', 'متشيرش قبل ما تتأكد'],
    engine: 'heuristic', note: 'ده فحص مبدئي بالأنماط، مش تأكيد للحقيقة. فعّل ANTHROPIC_API_KEY لتحليل أدق.' };
}

async function factcheck(text) {
  if (!KEY) return heuristic(text);
  try {
    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({
        model: 'claude-sonnet-5-5', max_tokens: 800,
        system: 'أنت محلل تحقق من الأخبار. حلل النص المعطى (قد يكون باللهجة المصرية) من حيث: الصياغة التحريضية، غياب المصدر، الادعاءات القابلة للتحقق، التناقض مع معلومات معروفة. لا تدّعي أنك تأكدت من الواقع لحظيًا؛ وضّح حدود معرفتك. رد بـ JSON فقط بدون أي نص آخر بالشكل: {"verdict":"مرجّح كاذب|مشكوك فيه|محتاج تحقق|مرجّح صحيح|لا يمكن الحكم","confidence":0-100,"reasons":["..."],"tips":["..."]} واكتب بالعربية المبسطة.',
        messages: [{ role: 'user', content: text }],
      }),
    });
    const d = await r.json();
    const raw = (d.content || []).map(c => c.text || '').join('').replace(/```json|```/g, '').trim();
    return { ...JSON.parse(raw), engine: 'claude', note: 'تحليل بالذكاء الاصطناعي، مش بديل عن المصادر الرسمية.' };
  } catch (e) { console.error('factcheck:', e.message); return { ...heuristic(text), note: 'تعذّر الاتصال بالذكاء الاصطناعي، ده فحص مبدئي.' }; }
}

// ---------- الراوتر ----------
const pub = path.join(__dirname, 'public');
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/manifest+json' };
const hits = {};
const limited = ip => { const n = Date.now(), a = (hits[ip] = (hits[ip] || []).filter(x => n - x < 60000)); a.push(n); return a.length > 60; };

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x'), p = url.pathname;
  if (p.startsWith('/api/')) {
    if (limited(req.socket.remoteAddress)) return json(res, 429, { error: 'طلبات كتير، استنى شوية' });
    let m;
    try {
      if (req.method === 'POST' && p === '/api/trips') {
        const b = await readBody(req), mins = Math.min(Math.max(+b.etaMinutes || 0, 1), 1440);
        if (!b.name || !mins) return json(res, 400, { error: 'الاسم ووقت الوصول مطلوبين' });
        const t = { id: crypto.randomBytes(4).toString('hex'), token: crypto.randomBytes(12).toString('hex'), name: clean(b.name, 40),
          from: clean(b.from), to: clean(b.to), startedAt: Date.now(), eta: Date.now() + mins * 60000, arrivedAt: null, points: [] };
        db.trips[t.id] = t; save(); return json(res, 201, { id: t.id, token: t.token });
      }
      if ((m = p.match(/^\/api\/trips\/(\w+)(?:\/(\w+))?$/))) {
        const t = db.trips[m[1]]; if (!t) return json(res, 404, { error: 'الرحلة مش موجودة' });
        if (req.method === 'GET' && !m[2]) return json(res, 200, view(t));
        if (req.method === 'POST' && m[2]) {
          const b = await readBody(req);
          if (b.token !== t.token) return json(res, 403, { error: 'مش مسموح' });
          if (m[2] === 'location') {
            if (!isFinite(b.lat) || !isFinite(b.lng)) return json(res, 400, { error: 'إحداثيات غلط' });
            if (!t.arrivedAt) { t.points.push({ lat: +b.lat, lng: +b.lng, t: Date.now() }); if (t.points.length > 500) t.points.shift(); save(); }
          } else if (m[2] === 'extend') { t.eta += Math.min(Math.max(+b.minutes || 10, 1), 240) * 60000; save(); }
          else if (m[2] === 'arrived') { t.arrivedAt = Date.now(); save(); }
          else return json(res, 404, { error: 'مش موجود' });
          return json(res, 200, view(t));
        }
      }
      if (req.method === 'POST' && p === '/api/factcheck') {
        const b = await readBody(req), text = clean(b.text, 3000);
        if (text.length < 10) return json(res, 400, { error: 'اكتب الخبر (10 حروف على الأقل)' });
        return json(res, 200, await factcheck(text));
      }
      return json(res, 404, { error: 'مش موجود' });
    } catch (e) { console.error(e); return json(res, 500, { error: 'خطأ في السيرفر' }); }
  }
  // ملفات ثابتة + صفحة المتابعة /t/:id
  let f = p === '/' || p.startsWith('/t/') ? 'index.html' : p.slice(1);
  const fp = path.join(pub, path.normalize(f));
  if (!fp.startsWith(pub)) { res.writeHead(403); return res.end(); }
  fs.readFile(fp, (e, data) => {
    if (e) { res.writeHead(404); return res.end('Not found'); }
    res.writeHead(200, { 'Content-Type': mime[path.extname(fp)] || 'application/octet-stream' }); res.end(data);
  });
}).listen(PORT, () => console.log(`وصلت؟ طمّني شغّال على http://localhost:${PORT}  |  كشف الأخبار: ${KEY ? 'Claude' : 'فحص مبدئي'}`));
