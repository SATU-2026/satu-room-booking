(function(root){
'use strict';
const statuses={pending:'รอตรวจสอบ',reviewed:'รอหัวหน้าอนุมัติ',approved:'อนุมัติแล้ว',rejected:'ไม่อนุมัติ',cancelled:'ยกเลิกแล้ว',blocked:'ปิดให้บริการ'};
const active=['pending','reviewed','approved','blocked'];
const pad=n=>String(n).padStart(2,'0');
function bangkokDate(d=new Date()){return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).format(d);}
function addDays(day,n){const d=new Date(day+'T12:00:00+07:00');d.setUTCDate(d.getUTCDate()+n);return bangkokDate(d);}
function stamp(day,time){return new Date(day+'T'+time+':00+07:00').toISOString();}
function overlap(a,b){return a.room_id===b.room_id&&active.includes(a.status)&&active.includes(b.status)&&new Date(a.starts_at)<new Date(b.ends_at)&&new Date(a.ends_at)>new Date(b.starts_at);}
function phone(v){return String(v||'').replace(/[\s()-]/g,'');}
function validate(p,now=new Date()){
 if(!/^0\d{8,9}$/.test(phone(p.phone)))throw Error('กรุณากรอกเบอร์โทรไทย 9–10 หลัก เริ่มต้นด้วย 0');
 for(const k of ['fullname','student_id','group_name','faculty','detail','room_id']) if(!String(p[k]||'').trim())throw Error('กรุณากรอกข้อมูลที่จำเป็นให้ครบ');
 if(!Number.isInteger(+p.participants)||+p.participants<1||+p.participants>100000)throw Error('จำนวนผู้เข้าร่วมต้องเป็นจำนวนเต็มตั้งแต่ 1');
 const s=new Date(p.starts_at),e=new Date(p.ends_at);
 if(!Number.isFinite(+s)||!Number.isFinite(+e)||e<=s)throw Error('เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม');
 if(bangkokDate(s)!==bangkokDate(e))throw Error('เวลาเริ่มและสิ้นสุดต้องเป็นวันเดียวกัน');
 if(bangkokDate(s)<addDays(bangkokDate(now),5))throw Error('กรุณาจองล่วงหน้าอย่างน้อย 5 วัน');
 return true;
}
function canCancel(b,now=new Date()){return ['pending','reviewed','approved'].includes(b.status)&&new Date(b.starts_at)-now>=3600000;}
function canEdit(b,now=new Date()){return ['pending','reviewed','approved'].includes(b.status)&&new Date(b.starts_at)>now;}
function canScope(scopes,campus,roles=['staff','head','admin']){return scopes.some(s=>roles.includes(s.role)&&(s.role==='admin'||s.campus_id===campus));}
function publicRecord(b){return {id:b.id,reference:b.reference,room_id:b.room_id,campus_id:b.campus_id,starts_at:b.starts_at,ends_at:b.ends_at,status:b.status,kind:b.kind};}
const api={statuses,active,pad,bangkokDate,addDays,stamp,overlap,phone,validate,canCancel,canEdit,canScope,publicRecord};
if(typeof module!=='undefined')module.exports=api;else root.BookingCore=api;
})(typeof window==='undefined'?globalThis:window);
