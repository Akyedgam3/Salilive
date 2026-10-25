# SalliLive — غرف دردشة صوتية

```
sallilive/
├─ supabase/schema.sql                  ← قاعدة البيانات + الصلاحيات + بيانات أولية
├─ supabase/functions/agora-token/      ← دالة توليد توكن الصوت
├─ admin/                               ← لوحة التحكم (ملفات ثابتة)
├─ app/                                 ← تطبيق Flutter (أندرويد)
└─ .github/workflows/build-apk.yml      ← بناء الـ APK سحابياً
```

## 1) Supabase
1. أنشئ مشروعاً على supabase.com.
2. **SQL Editor** ← الصق محتوى `supabase/schema.sql` ← Run.
3. **Authentication → Providers → Email**: عطّل `Confirm email` (لتسجيل فوري بدون تأكيد).
4. من **Project Settings → API** انسخ `Project URL` و `anon public key`.

## 2) الصوت (Agora)
1. سجّل على agora.io وأنشئ مشروع **Secured mode (App ID + Token)**، وانسخ App ID و App Certificate.
2. في Supabase: **Edge Functions → Deploy a new function** باسم `agora-token` والصق محتوى `index.ts`.
3. **Edge Functions → Secrets** أضف: `AGORA_APP_ID` و `AGORA_APP_CERTIFICATE`.

## 3) لوحة التحكم
1. عدّل `admin/config.js` بالـ URL والـ anon key.
2. ارفع مجلد `admin` على Netlify (Drag & Drop) أو Cloudflare Pages.
3. سجّل حساباً من التطبيق، ثم نفّذ في SQL Editor:
   ```sql
   update public.profiles set is_admin = true
    where id = (select id from auth.users where email = 'بريدك@example.com');
   ```
4. ادخل اللوحة بنفس البريد وأضف: طرق الدفع، الباقات، الهدايا، البانرات.

## 4) بناء الـ APK
1. ارفع محتوى هذا المجلد كاملاً إلى مستودع GitHub (خاص).
2. **Settings → Secrets and variables → Actions** أضف: `SUPABASE_URL` و `SUPABASE_ANON_KEY`.
3. تبويب **Actions → Build APK → Run workflow**. بعد ~8 دقائق نزّل `sallilive-apk` من الـ Artifacts.

## كيف يعمل الشحن
المستخدم يختار باقة وطريقة دفع (تعرّفها أنت من اللوحة)، يحوّل المبلغ ويرفع صورة الإيصال ← يظهر الطلب في **طلبات الشحن** ← تضغط «قبول» فتُضاف الكوينز تلقائياً مع سجل في `coin_ledger`.
