// ข้อมูลตัวอย่าง แก้ชื่อห้อง/ผู้ประสานงานได้ที่นี่ในโหมด demo
// โหมด live จะใช้ข้อมูลจาก Supabase (เปลี่ยนผ่านหน้าแอดมิน)
window.BOOKING_DATA = {
 campuses: [
  {id:'rs',name:'ศูนย์รังสิต',short:'รังสิต',contact_name:'เจ้าหน้าที่ตัวอย่าง — รังสิต',contact_phone:'0X-XXX-XXXX'},
  {id:'tp',name:'ศูนย์ท่าพระจันทร์',short:'ท่าพระจันทร์',contact_name:'เจ้าหน้าที่ตัวอย่าง — ท่าพระจันทร์',contact_phone:'0X-XXX-XXXX'}
 ],
 rooms: [
  {id:'rs-a-glass',campus_id:'rs',name:'ลานใต้อาคาร A (ฝั่งหน้ากระจก)',capacity:null},
  {id:'rs-a-stage',campus_id:'rs',name:'ลานใต้อาคาร A (ฝั่งเวทีกลาง)',capacity:null},
  {id:'rs-a-lift',campus_id:'rs',name:'ลานใต้อาคาร A (หน้าลิฟท์)',capacity:null},
  {id:'rs-circle',campus_id:'rs',name:'ลานเวที (วงกลม)',capacity:null},
  {id:'rs-a205',campus_id:'rs',name:'ห้องประชุม A205',capacity:null},
  {id:'rs-a210',campus_id:'rs',name:'ห้องเอนกประสงค์ A210',capacity:null},
  {id:'rs-a409',campus_id:'rs',name:'ห้องเอนกประสงค์ A409',capacity:null},
  {id:'rs-b411',campus_id:'rs',name:'ห้องเอนกประสงค์ B411',capacity:null},
  {id:'tp-01',campus_id:'tp',name:'ห้องประชุม 203',capacity:null},
  {id:'tp-02',campus_id:'tp',name:'ห้องประชุม 303 (จารุพงษ์)',capacity:null},
  {id:'tp-03',campus_id:'tp',name:'ห้องกิจกรรม1 โซน A',capacity:null},
  {id:'tp-04',campus_id:'tp',name:'ห้องกิจกรรม1 โซน B',capacity:null},
  {id:'tp-05',campus_id:'tp',name:'ห้องกิจกรรม1 โซน C',capacity:null},
  {id:'tp-06',campus_id:'tp',name:'ห้องกิจกรรม 2',capacity:null},
  {id:'tp-07',campus_id:'tp',name:'ห้องกิจกรรม 3',capacity:null},
  {id:'tp-08',campus_id:'tp',name:'ห้องกิจกรรมชั้น 5',capacity:null},
  {id:'tp-09',campus_id:'tp',name:'ห้องพักนักศึกษา',capacity:null},
  {id:'tp-10',campus_id:'tp',name:'ลานกิจกรรมชั้น 1',capacity:null},
  {id:'tp-11',campus_id:'tp',name:'โรงยิมเนเซียม',capacity:null}
 ].map(r=>({...r,active:true,is_sample:!!r.is_sample})),
 settings:{advance_days:5,cancel_hours:1,approval:'staff_then_head'}
};
