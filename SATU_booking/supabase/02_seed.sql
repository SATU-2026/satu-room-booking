-- Catalog only. No real bookings, personal data, or authentication credentials.
begin;
insert into public.bkg_campuses(id,name,short,contact_name,contact_phone) values
('rs','ศูนย์รังสิต','รังสิต','เจ้าหน้าที่ตัวอย่าง — รังสิต','0X-XXX-XXXX'),
('tp','ศูนย์ท่าพระจันทร์','ท่าพระจันทร์','เจ้าหน้าที่ตัวอย่าง — ท่าพระจันทร์','0X-XXX-XXXX') on conflict(id) do nothing;
insert into public.bkg_rooms(id,campus_id,name,capacity,is_sample,active) values
('rs-a-glass','rs','ลานใต้อาคาร A (ฝั่งหน้ากระจก)',null,false,true),
('rs-a-stage','rs','ลานใต้อาคาร A (ฝั่งเวทีกลาง)',null,false,true),
('rs-a-lift','rs','ลานใต้อาคาร A (หน้าลิฟท์)',null,false,true),
('rs-circle','rs','ลานเวที (วงกลม)',null,false,true),
('rs-a205','rs','ห้องประชุม A205',null,false,true),
('rs-a210','rs','ห้องเอนกประสงค์ A210',null,false,true),
('rs-a409','rs','ห้องเอนกประสงค์ A409',null,false,true),
('rs-b411','rs','ห้องเอนกประสงค์ B411',null,false,true),
('tp-01','tp','ห้องประชุม 203',null,false,true),
('tp-02','tp','ห้องประชุม 303 (จารุพงษ์)',null,false,true),
('tp-03','tp','ห้องกิจกรรม1 โซน A',null,false,true),
('tp-04','tp','ห้องกิจกรรม1 โซน B',null,false,true),
('tp-05','tp','ห้องกิจกรรม1 โซน C',null,false,true),
('tp-06','tp','ห้องกิจกรรม 2',null,false,true),
('tp-07','tp','ห้องกิจกรรม 3',null,false,true),
('tp-08','tp','ห้องกิจกรรมชั้น 5',null,false,true),
('tp-09','tp','ห้องพักนักศึกษา',null,false,true),
('tp-10','tp','ลานกิจกรรมชั้น 1',null,false,true),
('tp-11','tp','โรงยิมเนเซียม',null,false,true) on conflict(id) do nothing;
commit;
