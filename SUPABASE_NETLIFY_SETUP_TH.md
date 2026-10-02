# คู่มือเอาเว็บการ์ดขึ้น Netlify และเชื่อม Supabase

ทำตามลำดับนี้ได้เลย: **สร้าง Supabase → ติดตั้งฐานข้อมูล → นำเว็บขึ้น Netlify → ใส่ URL/คีย์ → ตั้งทางกลับหลังล็อกอิน → ทดสอบ**

## เตรียมก่อนเริ่ม

- สมัคร/เข้าสู่ระบบ [Supabase Dashboard](https://supabase.com/dashboard)
- มีบัญชี [GitHub](https://github.com/) และ [Netlify](https://app.netlify.com/) สำหรับนำเว็บขึ้นออนไลน์
- ดาวน์โหลด [ไฟล์โปรเจกต์ ZIP](</home/ubuntu/vanguard-card-netlify-project.zip>) แล้วแตกไฟล์
- ในโฟลเดอร์ที่แตกออกมา ให้เข้า `netlify-card-app` — โฟลเดอร์นี้ควรมี `netlify.toml`, `package.json`, `README.md` และ `supabase/` อยู่ด้วย

> **สำคัญ:** ไฟล์ migration ที่เตรียมไว้สำหรับฐานข้อมูลใหม่ในโปรเจกต์ Supabase ใหม่ อย่ารันกับฐานข้อมูลที่มีตารางหรือข้อมูลเดิมอยู่แล้ว และอย่ากด Run ซ้ำถ้าไม่แน่ใจว่ารอบแรกสำเร็จหรือไม่
>
> **คำเตือน DRAFT ONLY:** ไฟล์นี้ผ่านการตรวจไวยากรณ์ SQL แล้ว แต่ยังไม่ได้รันใน local Supabase จริง จึง **อย่าเพิ่งวางแล้วกด Run ใน Supabase Dashboard ออนไลน์** ให้ทดสอบใน local ตามส่วนที่ 2 ก่อน ข้อความก่อนหน้านี้ที่แนะนำให้รันบน Dashboard ทันทีเร็วเกินไป—ขออภัยครับ

---

## ส่วนที่ 1: สร้างโปรเจกต์ Supabase

1. เปิด [supabase.com/dashboard](https://supabase.com/dashboard) แล้วสมัครหรือเข้าสู่ระบบ
2. ถ้ายังไม่มี Organization ให้สร้างตามหน้าจอ แล้วกด **New project**
3. กรอกข้อมูลโปรเจกต์:
   - **Name:** ตั้งชื่อ เช่น `vanguard-card-collection`
   - **Database Password:** ตั้งรหัสผ่านที่คาดเดายากและเก็บไว้ในที่ปลอดภัย นี่คือรหัสฐานข้อมูล **ไม่ใช่** API key และไม่ต้องนำไปใส่ใน Netlify
   - **Region:** เลือกภูมิภาคใกล้ผู้ใช้หลัก เช่น Singapore หากมีให้เลือก
   - เลือก Plan ตามที่ต้องการ แล้วกด **Create new project**
4. รอจนสถานะโปรเจกต์พร้อมใช้งาน จากนั้นคลิกชื่อโปรเจกต์เพื่อเข้า Dashboard

---

## ส่วนที่ 2: ทดสอบ migration ใน local ก่อน (ต้องทำก่อนใช้กับโปรเจกต์ออนไลน์)

บรรทัดที่ขึ้นต้นด้วย `--` ในไฟล์ SQL เป็นคอมเมนต์ จึงไม่ถูกรัน แต่คำเตือน **DRAFT ONLY** เป็นคำแนะนำให้ทดสอบ schema จริงก่อนใช้กับฐานข้อมูลออนไลน์ ไฟล์นี้สร้างตาราง Card List/Products, Banlist, เด็ค, Collection, Gacha/Pity, PR Craft, Feed, RLS และ Storage policies

1. ติดตั้งและเปิด Docker Desktop บนคอมพิวเตอร์ แล้วติดตั้ง Supabase CLI ตาม [คู่มือทางการ](https://supabase.com/docs/guides/local-development/cli/getting-started)
2. เปิด Terminal/PowerShell แล้วสร้างโฟลเดอร์ทดสอบแยกจากเว็บ เพื่อไม่ให้ชนกับโฟลเดอร์ `supabase/` ที่อยู่ในโปรเจกต์:
   ```sh
   mkdir cardlist-supabase-test
   cd cardlist-supabase-test
   supabase init
   ```
   ถ้าติดตั้ง CLI ผ่าน npm และไม่มีคำสั่ง `supabase` ให้ใช้รูปแบบ `npx supabase ...` ตามเอกสารติดตั้ง CLI
3. คัดลอกไฟล์ `20261002000000_initial_schema.sql` จากโปรเจกต์ ไปไว้ใน `cardlist-supabase-test/supabase/migrations/`
4. จาก Terminal ในโฟลเดอร์ `cardlist-supabase-test` เริ่ม Supabase local และทดสอบ migration:
   ```sh
   supabase start
   supabase db reset
   ```
   `db reset` จะรีเซ็ตเฉพาะฐานข้อมูล **local สำหรับทดสอบ** แล้วสร้าง schema ใหม่จาก migration ห้ามใช้กับฐานข้อมูลจริงหรือโฟลเดอร์ที่ link ไปยังโปรเจกต์ออนไลน์
5. ถ้าคำสั่งจบโดยไม่มี SQL error และ local Supabase เริ่มทำงานได้ ให้ตรวจตารางใน local Studio ตาม URL ที่คำสั่ง `supabase start` แสดง

**ถ้า local test ผ่านแล้วเท่านั้น:** กลับไป Supabase Dashboard โปรเจกต์ออนไลน์ที่สร้างใหม่ → **SQL Editor → New query** วางเนื้อหาไฟล์ migration ทั้งหมดแล้วกด **Run หนึ่งครั้ง** เพื่อสร้าง schema บนโปรเจกต์นั้น

**ถ้า CLI หรือ local test ขึ้น error:** หยุดก่อน อย่าเอา migration ไปลองรันบนโปรเจกต์ออนไลน์เพื่อแก้ขัด จด error และขั้นตอนที่ทำ แล้วขอให้ช่วยตรวจต่อได้

---

## ส่วนที่ 3: คัดลอก Project URL และ Publishable key

1. ใน Supabase Dashboard เปิดโปรเจกต์ของคุณ
2. จากเมนูด้านซ้ายเลือก **Integrations → Data API** แล้วคัดลอก **Project URL / API URL** — รูปแบบประมาณ `https://....supabase.co` และให้คัดลอกเฉพาะ base URL ไม่ต้องเอา `/rest/v1` ต่อท้าย
3. ถ้าเมนู Integrations หรือ Data API ไม่ปรากฏ ให้ดูแถบ URL ของเบราว์เซอร์ขณะอยู่ในโปรเจกต์ เช่น `supabase.com/dashboard/project/abcdefghijk/...` ค่า `abcdefghijk` คือ Project ref; Project URL ปกติจะเป็น `https://abcdefghijk.supabase.co`
4. คัดลอก **Publishable key** แยกต่างหาก โดยไปที่ **Project Settings → API Keys** (หรือกด **Connect** หากปุ่มนี้แสดงอยู่) แล้วเลือกคีย์ที่ขึ้นต้น `sb_publishable_...`
5. เก็บ URL และ key ไว้ชั่วคราวในตัวจัดการรหัสผ่านหรือโน้ตส่วนตัว เพื่อไปกรอกใน Netlify

> แอปชุดนี้ใช้ชื่อตัวแปร `SUPABASE_ANON_KEY` ตาม build script แต่ให้ใส่ **ค่า Publishable key ปัจจุบัน (`sb_publishable_...`)** ลงในตัวแปรนี้ได้เลย ชื่อช่องยังเป็น `SUPABASE_ANON_KEY` แต่ค่าที่ใส่เป็น publishable key
>
> ห้ามนำ **Secret key** ที่ขึ้นต้น `sb_secret_` หรือคีย์เก่า `service_role` ไปใส่ในเว็บหรือ Netlify เพราะมีสิทธิ์สูงและข้าม RLS ได้ ส่วน Project URL และ Publishable key ถูกออกแบบให้ใช้จากเว็บได้ โดย RLS เป็นตัวจำกัดข้อมูล

---

## ส่วนที่ 4: อัปโหลดโปรเจกต์ไป GitHub

วิธีเชื่อม Netlify ที่แนะนำคือเก็บโค้ดใน GitHub แล้วให้ Netlify Build จาก repository

1. สร้าง Repository ใหม่ใน GitHub เช่น `vanguard-card-collection`
2. นำ **ไฟล์และโฟลเดอร์ทั้งหมดที่อยู่ข้างใน `netlify-card-app`** ขึ้น Repository โดยให้ `netlify.toml` และ `package.json` อยู่ที่ระดับบนสุดของ Repository
   - ถ้าใช้ GitHub Desktop ให้เลือก/สร้าง Repository ในโฟลเดอร์ `netlify-card-app` แล้ว Publish repository ไปยัง GitHub
   - อย่าอัปโหลด ZIP เป็นไฟล์เดียว เพราะ Netlify ต้องเห็น `package.json`, `netlify.toml`, `scripts/` และ `index.html` เป็นไฟล์ใน Repository
3. ตรวจใน GitHub ว่าหน้าแรกของ Repository เห็น `netlify.toml` และ `package.json`

ถ้า `netlify-card-app` ถูกวางเป็นโฟลเดอร์ย่อยใน Repository แทนที่จะเป็นราก Repository ให้ตั้ง **Base directory** ของ Netlify เป็น `netlify-card-app` ด้วย วิธีง่ายที่สุดคืออัปโหลด “เนื้อหาข้างในโฟลเดอร์” ให้เป็นราก Repository

---

## ส่วนที่ 5: เชื่อม Repository และ Build ใน Netlify

1. เปิด [Netlify Dashboard](https://app.netlify.com/) แล้วเข้าสู่ระบบ
2. กด **Add new project** / **Add new site** แล้วเลือก **Import an existing project**
3. เลือก **GitHub** และอนุญาต Netlify ให้เข้าถึง Repository ที่เพิ่งสร้าง
4. เลือก Repository `vanguard-card-collection`
5. ตรวจค่าตั้ง Build (ไฟล์ `netlify.toml` ระบุไว้แล้ว):
   - **Build command:** `npm run build`
   - **Publish directory:** `dist`
   - **Base directory:** ว่างไว้ ถ้าไฟล์ `netlify.toml` อยู่ที่ราก Repository
6. กด Deploy/Save ตามหน้าจอ แล้วรอให้ Netlify สร้างไซต์

หากต้องตั้งค่าเองใน Netlify: ไปที่ Project configuration / Site configuration → Build & deploy → Build settings แล้วกรอก Build command กับ Publish directory ตามด้านบน

---

## ส่วนที่ 6: ใส่ Supabase variables ใน Netlify

ทำก่อนสั่ง Deploy รอบสุดท้าย เพราะตัว build จะเขียนค่านี้ลง `dist/config.js` เพื่อให้เว็บเชื่อม Supabase ได้

1. เข้าไซต์/โปรเจกต์ของคุณใน Netlify
2. เปิด **Project configuration → Environment variables** (บางหน้าจออาจใช้ชื่อ **Site configuration → Environment variables**)
3. กด **Add a variable** แล้วสร้างตัวแปร 2 ตัว:

| ชื่อตัวแปร (Key) | ค่า (Value) |
|---|---|
| `SUPABASE_URL` | Project URL จาก Supabase เช่น `https://....supabase.co` |
| `SUPABASE_ANON_KEY` | Publishable key จาก Supabase ซึ่งมักขึ้นต้น `sb_publishable_` |

4. ถ้ามีตัวเลือก Scope ให้แน่ใจว่าเปิดใช้กับ **Builds**
5. บันทึกตัวแปรทั้งสองตัว
6. ไปที่ Deploys แล้วเลือก **Trigger deploy → Deploy site** หรือ Push commit ใหม่ใน GitHub
7. รอ Build สำเร็จ แล้วเปิด URL ของไซต์ Netlify

> ถ้าตั้ง Environment variables หลังจาก Netlify Build ไปแล้ว ต้อง Build/Deploy ใหม่ทุกครั้ง ค่าจะถูกฝังในไฟล์ `config.js` ตอน Build; แค่บันทึกตัวแปรอย่างเดียวยังไม่เปลี่ยนเว็บที่ Deploy ไปแล้ว

---

## ส่วนที่ 7: ตั้ง URL สำหรับยืนยันอีเมล/กลับจากล็อกอิน

หลัง Netlify ให้ URL ไซต์แล้ว (เช่น `https://your-site-name.netlify.app`):

1. กลับไป Supabase Dashboard → โปรเจกต์ของคุณ
2. เลือก **Authentication → URL Configuration**
3. ตั้ง **Site URL** เป็น URL จริงของเว็บ เช่น:
   `https://your-site-name.netlify.app/`
4. ใน **Redirect URLs** เพิ่ม URL ของเว็บที่อนุญาตให้ Supabase กลับมาหลังยืนยัน/เข้าสู่ระบบ เช่น:
   `https://your-site-name.netlify.app/`
5. กด Save

ถ้าใช้ Netlify Deploy Preview หรือเปลี่ยนเป็น custom domain ภายหลัง ให้เพิ่ม URL ที่ตรงกับโดเมนนั้นใน Redirect URLs และเปลี่ยน Site URL ให้เป็นโดเมนหลักจริง อย่าใส่ URL ตัวอย่างตรง ๆ ให้เปลี่ยน `your-site-name` เป็นชื่อไซต์ที่ Netlify ให้มา

---

## ส่วนที่ 8: ทดสอบเว็บ

1. เปิด URL Netlify แล้วสมัครบัญชีทดสอบด้วยอีเมลของคุณ
2. ถ้า Supabase เปิดยืนยันอีเมลไว้ ให้เปิดอีเมลยืนยันก่อน แล้วกลับมาเข้าสู่ระบบ
3. เพิ่มการ์ด/สินค้าใน Catalog แล้วลองเปิดซอง
4. ลองสร้างเด็คและตรวจว่าเด็ค/Collection อยู่ในบัญชีเจ้าของ
5. ลองเปิดหน้าชุมชน แล้วแชร์เฉพาะเด็คหรือ Rare Pull ที่ต้องการเผยแพร่
6. หากต้องการทดสอบความเป็นส่วนตัวจริง ให้สมัครบัญชีที่สองในหน้าต่าง Incognito/เบราว์เซอร์อีกตัว: Catalog และ Banlist เป็นข้อมูลร่วม ส่วน Collection, Pity, ประวัติเปิดซอง และเด็คที่ยังไม่แชร์ต้องไม่ปรากฏในบัญชีที่สอง

## ถ้าเว็บเปิดได้แต่ยังขึ้นว่าเชื่อม Cloud ไม่ได้

- ตรวจว่า Environment variable สะกดตรงทุกตัว: `SUPABASE_URL`, `SUPABASE_ANON_KEY`
- ตรวจว่า `SUPABASE_URL` ไม่มีช่องว่างและเป็น Project URL ที่ลงท้ายโดเมน Supabase
- ตรวจว่า `SUPABASE_ANON_KEY` เป็น **Publishable key** ไม่ใช่ Database password หรือ Secret/service_role key
- สั่ง Deploy ใหม่หลังแก้ตัวแปร
- ตรวจ Netlify Deploy log ว่ามี Build error หรือไม่
- ตรวจ Supabase Auth → URL Configuration ว่า Site URL เป็น URL Netlify จริง
- ถ้ามีข้อความ SQL error ให้หยุดก่อน อย่ารัน migration ซ้ำบนฐานข้อมูลที่อาจสร้างตารางไปบางส่วนแล้ว

## เอกสารทางการ

- [Supabase Dashboard และโปรเจกต์](https://supabase.com/docs/guides/platform)
- [Supabase API keys: publishable กับ secret](https://supabase.com/docs/guides/getting-started/api-keys)
- [Supabase Auth Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- [Supabase Database / SQL Editor](https://supabase.com/docs/guides/database/overview)
- [Netlify environment variables](https://docs.netlify.com/build/configure-builds/environment-variables/)
