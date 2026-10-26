/* Data adapter: demo uses localStorage; live uses restricted Supabase RPCs. */
(function(){
'use strict';
const C=BookingCore,KEY='satu-booking-demo-v1';
const copy=o=>JSON.parse(JSON.stringify(o));
const uuid=()=>crypto.randomUUID?crypto.randomUUID():('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const r=crypto.getRandomValues(new Uint8Array(1))[0]%16;return(c==='x'?r:(r&3|8)).toString(16);}));
const token=()=>Array.from(crypto.getRandomValues(new Uint8Array(24)),b=>b.toString(16).padStart(2,'0')).join('');
function seed(){
 const d=copy(BOOKING_DATA),day=C.addDays(C.bangkokDate(),6);
 const make=(id,room,h1,h2,status,n)=>({id,reference:'DEMO-00'+n,kind:'booking',campus_id:room.startsWith('tp')?'tp':'rs',room_id:room,starts_at:C.stamp(day,h1),ends_at:C.stamp(day,h2),status,fullname:'ผู้จองตัวอย่าง '+n,phone:'0800000000',student_id:'DEMO000'+n,group_name:'ชมรมตัวอย่าง',faculty:'คณะตัวอย่าง',detail:'กิจกรรมตัวอย่างเพื่อทดลองระบบ',participants:15,created_at:new Date(Date.now()-n*3600000).toISOString(),token:'DEMO1234',history:[{at:new Date().toISOString(),actor:'ระบบสาธิต',action:'สร้างคำขอตัวอย่าง',reason:''}],reason:'',files:[]});
 return {...d,bookings:[make('demo-1','rs-a205','09:00','11:00','approved',1),make('demo-2','rs-a210','13:00','16:00','pending',2),make('demo-3','tp-01','09:00','12:00','reviewed',3)],scopes:[{user_id:'staff-rs',name:'เจ้าหน้าที่รังสิต (ตัวอย่าง)',campus_id:'rs',role:'staff'},{user_id:'staff-tp',name:'เจ้าหน้าที่ท่าพระจันทร์ (ตัวอย่าง)',campus_id:'tp',role:'staff'},{user_id:'head',name:'หัวหน้า (ตัวอย่าง)',campus_id:'rs',role:'head'},{user_id:'head',name:'หัวหน้า (ตัวอย่าง)',campus_id:'tp',role:'head'},{user_id:'admin',name:'แอดมิน (ตัวอย่าง)',campus_id:null,role:'admin'}]};
}
class Demo{
 constructor(){this.live=false;this.user=null;this.scopes=[];try{this.db=JSON.parse(localStorage.getItem(KEY))||seed();}catch{this.db=seed();}const signature=JSON.stringify(BOOKING_DATA);if(this.db.catalog_source!==signature){for(const c of BOOKING_DATA.campuses){const old=this.db.campuses.find(v=>v.id===c.id);if(old)Object.assign(old,copy(c));else this.db.campuses.push(copy(c));}for(const r of BOOKING_DATA.rooms){const old=this.db.rooms.find(v=>v.id===r.id);if(old)Object.assign(old,copy(r));else this.db.rooms.push(copy(r));}this.db.catalog_source=signature;}this.persist();}
 persist(){localStorage.setItem(KEY,JSON.stringify(this.db));}
 reload(){try{this.db=JSON.parse(localStorage.getItem(KEY))||this.db;}catch{} }
 async mutate(fn){const run=()=>{this.reload();const backup=copy(this.db);try{const result=fn();this.persist();return copy(result);}catch(e){this.db=backup;throw e;}};return navigator.locks?navigator.locks.request(KEY,run):run();}
 async init(){return this.meta();}
 async meta(){this.reload();return copy({campuses:this.db.campuses,rooms:this.db.rooms,settings:this.db.settings});}
 async login(id){this.user={id};this.scopes=copy(this.db.scopes.filter(s=>s.user_id===id));if(!this.scopes.length)throw Error('บัญชีนี้ยังไม่ได้รับสิทธิ์');return this.scopes;}
 async logout(){this.user=null;this.scopes=[];}
 async calendar(campus,start,end){this.reload();return this.db.bookings.filter(b=>b.campus_id===campus&&C.active.includes(b.status)&&b.starts_at<end&&b.ends_at>start).map(C.publicRecord);}
 async lookup(phone){this.reload();return this.db.bookings.filter(b=>b.kind==='booking'&&(b.phone===C.phone(phone)||b.student_id===String(phone).trim())).sort((a,b)=>b.created_at.localeCompare(a.created_at)).map(C.publicRecord);}
 room(id){const r=this.db.rooms.find(r=>r.id===id);if(!r)throw Error('ไม่พบห้อง');return r;}
 checkScope(campus,roles){if(!C.canScope(this.scopes,campus,roles))throw Error('ไม่มีสิทธิ์จัดการศูนย์นี้');}
 audit(b,action,reason=''){b.history.push({at:new Date().toISOString(),actor:this.user?(this.scopes[0]?.name||this.user.id):'ผู้จอง',action,reason});}
 async create(p,key,secret){return this.mutate(()=>{const old=this.db.bookings.find(b=>b.idempotency_key===key);if(old){if(old.token!==secret)throw Error('รหัสส่งคำขอไม่ตรงกัน');return old;}
 C.validate(p);const r=this.room(p.room_id);if(!r.active)throw Error('ห้องนี้ปิดรับจอง');
 const b={...p,phone:C.phone(p.phone),id:uuid(),idempotency_key:key,reference:'BK-'+Date.now().toString(36).toUpperCase(),campus_id:r.campus_id,status:'pending',kind:'booking',token:secret,created_at:new Date().toISOString(),reason:'',history:[],files:[]};
 if(this.db.bookings.some(v=>C.overlap(v,b)))throw Error('ห้องไม่ว่างในช่วงเวลานี้ กรุณาเลือกเวลาใหม่');
 this.audit(b,'ส่งคำขอและกันห้อง');this.db.bookings.push(b);return b;});}
 authorize(id,secret){const b=this.db.bookings.find(b=>b.id===id);if(!b)throw Error('ไม่พบรายการ');if(secret){if(b.token!==secret)throw Error('รหัสจัดการคำขอไม่ถูกต้อง');}else this.checkScope(b.campus_id);return b;}
 async get(id,secret){this.reload();const b=copy(this.authorize(id,secret));delete b.token;delete b.idempotency_key;return b;}
 async edit(id,secret,p){return this.mutate(()=>{const b=this.authorize(id,secret);if(!C.canEdit(b))throw Error('รายการนี้ไม่สามารถแก้ไขได้แล้ว');if(!p.detail.trim()||!Number.isInteger(+p.participants)||+p.participants<1||+p.participants>100000)throw Error('กรุณาระบุรายละเอียดและจำนวนผู้เข้าร่วมให้ถูกต้อง');b.detail=p.detail;b.participants=+p.participants;b.status='pending';b.reason='';this.audit(b,'แก้รายละเอียด — ส่งกลับรอตรวจสอบ');return true;});}
 async cancel(id,secret,reason){return this.mutate(()=>{const b=this.authorize(id,secret);if(!reason.trim())throw Error('กรุณาระบุเหตุผล');if(!C.canCancel(b))throw Error('เลยกำหนดยกเลิกเองแล้ว กรุณาติดต่อเจ้าหน้าที่');b.status='cancelled';b.reason=reason;this.audit(b,'ยกเลิกโดยผู้จอง',reason);return true;});}
 async staffList(campus){this.reload();this.checkScope(campus);return copy(this.db.bookings.filter(b=>b.campus_id===campus).map(b=>{const x={...b};delete x.token;delete x.idempotency_key;return x;}));}
 async action(id,action,reason){return this.mutate(()=>{const b=this.authorize(id);const role=action==='review'?['staff','admin']:action==='approve'?['head','admin']:['staff','head','admin'];this.checkScope(b.campus_id,role);
 const allowed={review:['pending'],approve:['reviewed'],reject:['pending','reviewed'],cancel:['pending','reviewed','approved','blocked']};if(!allowed[action]?.includes(b.status))throw Error('สถานะเปลี่ยนแล้ว กรุณาโหลดรายการใหม่');if(['reject','cancel'].includes(action)&&!reason.trim())throw Error('กรุณาระบุเหตุผล');
 b.status={review:'reviewed',approve:'approved',reject:'rejected',cancel:'cancelled'}[action];b.reason=reason||'';this.audit(b,{review:'ตรวจสอบผ่าน',approve:'อนุมัติ',reject:'ไม่อนุมัติ',cancel:'ยกเลิกโดยเจ้าหน้าที่'}[action],reason);return true;});}
 async block(p){return this.mutate(()=>{const r=this.room(p.room_id);this.checkScope(r.campus_id,['staff','admin']);if(!p.reason.trim()||new Date(p.ends_at)<=new Date(p.starts_at)||new Date(p.starts_at)<new Date())throw Error('ระบุเหตุผลและช่วงเวลาในอนาคตให้ถูกต้อง');const b={...p,id:uuid(),reference:'BLOCK-'+Date.now().toString(36).toUpperCase(),campus_id:r.campus_id,status:'blocked',kind:'block',created_at:new Date().toISOString(),history:[],files:[]};const conflicts=this.db.bookings.filter(v=>C.overlap(v,b));if(conflicts.length)throw Error('ปิดห้องไม่ได้ มีรายการชน '+conflicts.map(v=>v.reference).join(', ')+' กรุณาจัดการรายการเดิมก่อน');this.audit(b,'ปิดห้องเฉพาะช่วง',p.reason);this.db.bookings.push(b);return true;});}
 async saveRoom(p){return this.mutate(()=>{this.checkScope(null,['admin']);if(!p.name.trim()||!this.db.campuses.some(c=>c.id===p.campus_id))throw Error('ข้อมูลห้องไม่ครบ');let r=p.id?this.room(p.id):null;if(r){if(r.campus_id!==p.campus_id)throw Error('ย้ายศูนย์ของห้องเดิมไม่ได้ ให้สร้างห้องใหม่');Object.assign(r,p);}else this.db.rooms.push({...p,id:uuid()});return true;});}
 async saveContact(p){return this.mutate(()=>{this.checkScope(null,['admin']);Object.assign(this.db.campuses.find(c=>c.id===p.id),p);return true;});}
 async listScopes(){this.checkScope(null,['admin']);return copy(this.db.scopes);}
 async saveScope(p){return this.mutate(()=>{this.checkScope(null,['admin']);if(p.user_id===this.user.id)throw Error('แก้สิทธิ์บัญชีตนเองจากหน้านี้ไม่ได้');const i=this.db.scopes.findIndex(s=>s.user_id===p.user_id&&s.campus_id===p.campus_id);if(p.remove){if(i>=0)this.db.scopes.splice(i,1);}else if(i>=0)this.db.scopes[i]=p;else this.db.scopes.push(p);return true;});}
 async files(id,secret){return (await this.get(id,secret)).files||[];}
 async upload(id,secret,file){if(file.size>5*1024*1024)throw Error('ไฟล์ใหญ่เกิน 5 MB');if(!['application/pdf','image/jpeg','image/png'].includes(file.type))throw Error('รองรับ PDF/JPG/PNG เท่านั้น');
 const data=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(file);});
 return this.mutate(()=>{const b=this.authorize(id,secret);if(!C.canEdit(b))throw Error('รายการนี้แนบไฟล์ไม่ได้แล้ว');if(b.files.length>=3)throw Error('แนบได้สูงสุด 3 ไฟล์');b.files.push({id:uuid(),name:file.name,data,size:file.size,mime:file.type});b.status='pending';this.audit(b,'แนบเอกสาร — ส่งกลับรอตรวจสอบ');return true;});}
 async download(id,secret,fileId){const b=await this.get(id,secret),f=b.files.find(f=>f.id===fileId);if(!f)throw Error('ไม่พบไฟล์');return {url:f.data,name:f.name};}
}
class Live{
 constructor(client){this.live=true;this.client=client;this.user=null;this.scopes=[];}
 async rpc(name,p={}){const {data,error}=await this.client.rpc('bkg_'+name,p);if(error)throw Error(error.message);const normalize=v=>Array.isArray(v)?v.map(normalize):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).map(([k,x])=>[k,['starts_at','ends_at','created_at','at'].includes(k)&&typeof x==='string'?new Date(x).toISOString():normalize(x)])):v;return normalize(data);}
 async init(){const {data,error}=await this.client.auth.getSession();if(error)throw error;this.user=data.session?.user||null;if(this.user)this.scopes=await this.rpc('my_scopes');return this.meta();}
 meta(){return this.rpc('meta');}
 async login(email,password){const {data,error}=await this.client.auth.signInWithPassword({email,password});if(error)throw Error('เข้าสู่ระบบไม่สำเร็จ กรุณาตรวจสอบอีเมลและรหัสผ่าน');this.user=data.user;this.scopes=await this.rpc('my_scopes');if(!this.scopes.length){await this.logout();throw Error('บัญชีนี้ยังไม่ได้รับสิทธิ์ กรุณาติดต่อแอดมิน');}return this.scopes;}
 async logout(){await this.client.auth.signOut();this.user=null;this.scopes=[];}
 calendar(campus,start,end){return this.rpc('calendar',{p_campus:campus,p_start:start,p_end:end});}
 lookup(phone){return this.rpc('lookup',{p_phone:String(phone).trim()});}
 create(p,key,secret){return this.rpc('create',{p_data:{...p,phone:C.phone(p.phone)},p_key:key,p_token:secret});}
 get(id,secret){return this.rpc('detail',{p_id:id,p_token:secret||null});}
 edit(id,secret,p){return this.rpc('edit',{p_id:id,p_token:secret,p_detail:p.detail,p_participants:+p.participants});}
 cancel(id,secret,reason){return this.rpc('cancel',{p_id:id,p_token:secret,p_reason:reason});}
 staffList(campus){return this.rpc('staff_list',{p_campus:campus});}
 action(id,action,reason){return this.rpc('action',{p_id:id,p_action:action,p_reason:reason});}
 block(p){return this.rpc('block',{p_data:p});}
 saveRoom(p){return this.rpc('save_room',{p_data:p});}
 saveContact(p){return this.rpc('save_contact',{p_data:p});}
 listScopes(){return this.rpc('list_scopes');}
 saveScope(p){return this.rpc('save_scope',{p_data:p});}
 async fileCall(action,id,secret,extra={}){const session=(await this.client.auth.getSession()).data.session;const headers={'apikey':BOOKING_CONFIG.supabasePublishableKey};if(session)headers.Authorization='Bearer '+session.access_token;let body;
 if(extra.file){body=new FormData();body.append('action',action);body.append('id',id);body.append('token',secret||'');body.append('file',extra.file);}else{headers['Content-Type']='application/json';body=JSON.stringify({action,id,token:secret||null,...extra});}
 const r=await fetch(BOOKING_CONFIG.supabaseUrl+'/functions/v1/'+BOOKING_CONFIG.fileFunction,{method:'POST',headers,body});let d;try{d=await r.json();}catch{throw Error('บริการไฟล์ยังไม่พร้อม กรุณาตรวจการติดตั้ง booking-files');}if(!r.ok)throw Error(d.error||'ดำเนินการกับไฟล์ไม่สำเร็จ');return d;
 }
 files(id,secret){return this.fileCall('list',id,secret);}
 upload(id,secret,file){return this.fileCall('upload',id,secret,{file});}
 download(id,secret,fileId){return this.fileCall('download',id,secret,{fileId});}
}
window.BookingAPI={uuid,token,Demo,async open(){if(BOOKING_CONFIG.mode==='demo')return new Demo();if(BOOKING_CONFIG.mode!=='live')throw Error('mode ต้องเป็น demo หรือ live');if(!/^https:\/\//.test(BOOKING_CONFIG.supabaseUrl)||!BOOKING_CONFIG.supabasePublishableKey)throw Error('กรุณาตั้งค่า Supabase URL และ Publishable key ใน config.js');await new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.57.4/dist/umd/supabase.js';s.onload=resolve;s.onerror=()=>reject(Error('โหลด Supabase ไม่สำเร็จ กรุณาตรวจการเชื่อมต่ออินเทอร์เน็ต'));document.head.append(s);});return new Live(supabase.createClient(BOOKING_CONFIG.supabaseUrl,BOOKING_CONFIG.supabasePublishableKey));}};
})();
