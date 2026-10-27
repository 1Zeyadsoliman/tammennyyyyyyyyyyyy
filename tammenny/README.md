# وصلت؟ طمّني — اطمن وطمنهم

## التشغيل
    node server.js            # محتاج Node 18+
    # أو مع الذكاء الاصطناعي لكشف الأخبار:
    ANTHROPIC_API_KEY=sk-ant-... node server.js

افتح http://localhost:3000

## ملاحظات مهمة
- GPS في الموبايل مبيشتغلش إلا على HTTPS. للتجربة من موبايلك استخدم `ngrok http 3000`
  أو انشره على Render / Railway / Fly.io (أمر التشغيل: `node server.js`).
- من غير ANTHROPIC_API_KEY كاشف الأخبار بيشتغل بفحص مبدئي بالكلمات والأنماط (أقل دقة).
- التخزين في ملف data.json. للإنتاج الفعلي بدّله بقاعدة بيانات.

## الـ API
- POST /api/trips            {name,from,to,etaMinutes} -> {id,token}
- POST /api/trips/:id/location {token,lat,lng}
- POST /api/trips/:id/extend   {token,minutes}
- POST /api/trips/:id/arrived  {token}
- GET  /api/trips/:id
- POST /api/factcheck        {text}
