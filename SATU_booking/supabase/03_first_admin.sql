-- สร้างบัญชีด้วย Supabase Dashboard > Authentication > Users ก่อน
-- คัดลอก UUID ของบัญชีตัวเอง แล้วแทน YOUR-USER-UUID ด้านล่างก่อนรัน
insert into public.bkg_scopes(user_id,role,campus_id,name)
values ('YOUR-USER-UUID'::uuid,'admin',null,'ผู้ดูแลระบบ')
on conflict do nothing;
-- จากนั้นเข้าสู่หน้าเว็บ > สำหรับเจ้าหน้าที่ > ตั้งค่าระบบ
-- สร้างบัญชีเจ้าหน้าที่/หัวหน้าใน Authentication แล้วนำ UID มากำหนดศูนย์ในเว็บ
-- หัวหน้าคนเดียวสองศูนย์: เพิ่ม UID เดียวกันสองครั้ง ศูนย์ rs และ tp
