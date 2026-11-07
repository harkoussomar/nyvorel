use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::HashMap, fs, io::Write, net::{IpAddr, SocketAddr, TcpStream, UdpSocket}, os::{unix::fs::OpenOptionsExt, fd::AsRawFd}, path::{Path, PathBuf}, process::{Command, Stdio}, thread, time::{Duration, Instant}};
use zbus::{blocking::{Connection, Proxy}, zvariant::OwnedObjectPath};

const NM: &str = "org.freedesktop.NetworkManager";
#[derive(Clone, Debug, Serialize)]
struct Active { name:String, uuid:String, kind:String, device:String, default:bool }
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
struct Dns { v4:String, auto4:String, v6:String, auto6:String }
#[derive(Serialize, Deserialize)]
struct Undo { uuid:String, device:String, before:Dns, applied:Dns }
fn cmd(program:&str, args:&[&str], seconds:u64)->Result<String,String>{
 let mut child=Command::new(program).args(args).env("LANG","C").env("LC_ALL","C").stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().map_err(|e|format!("{program}: {e}"))?;
 let start=Instant::now(); loop {match child.try_wait(){
  Ok(Some(_))=>{let o=child.wait_with_output().map_err(|e|e.to_string())?; return if o.status.success(){Ok(String::from_utf8_lossy(&o.stdout).trim_end().into())}else{Err(format!("{program}: {}",String::from_utf8_lossy(&o.stderr).trim()))}},
  Ok(None) if start.elapsed()<Duration::from_secs(seconds)=>thread::sleep(Duration::from_millis(20)),
  Ok(None)=>{let _=child.kill();let _=child.wait();return Err(format!("{program} timed out"))}, Err(e)=>return Err(e.to_string())}}
}
fn active()->Result<(String,Vec<Active>),String>{
 let bus=Connection::system().map_err(|e|e.to_string())?;
 let nm=Proxy::new(&bus,NM,"/org/freedesktop/NetworkManager",NM).map_err(|e|e.to_string())?;
 let state:u32=nm.get_property("Connectivity").map_err(|e|e.to_string())?;
 let paths:Vec<OwnedObjectPath>=nm.get_property("ActiveConnections").map_err(|e|e.to_string())?;
 let mut all=Vec::new();for path in paths {
  let Ok(p)=Proxy::new(&bus,NM,path.as_str(),"org.freedesktop.NetworkManager.Connection.Active") else{continue};
  let (Ok(name),Ok(uuid),Ok(kind))=(p.get_property::<String>("Id"),p.get_property::<String>("Uuid"),p.get_property::<String>("Type"))else{continue};
  let default=p.get_property("Default").unwrap_or(false);
  let devs:Vec<OwnedObjectPath>=p.get_property("Devices").unwrap_or_default();
  let device=devs.first().and_then(|d|Proxy::new(&bus,NM,d.as_str(),"org.freedesktop.NetworkManager.Device").ok()?.get_property::<String>("Interface").ok()).unwrap_or_default();
  all.push(Active{name,uuid,kind,device,default});
 }
 Ok((match state{4=>"full",3=>"limited",2=>"portal",1=>"none",_=>"unknown"}.into(),all))
}
fn selected(all:&[Active])->Result<&Active,String>{all.iter().find(|a|a.default&&physical(a)).or_else(||all.iter().find(|a|physical(a))).ok_or("No active physical network profile".into())}
fn physical(a:&Active)->bool{a.kind=="802-11-wireless"||a.kind=="802-3-ethernet"}
fn fields(uuid:&str)->Result<Dns,String>{
 let s=cmd("nmcli",&["-g","ipv4.dns,ipv4.ignore-auto-dns,ipv6.dns,ipv6.ignore-auto-dns","connection","show","uuid",uuid],4)?;
 let mut l:Vec<_>=s.split('\n').collect();l.resize(4,"");Ok(Dns{v4:l[0].trim().into(),auto4:l[1].trim().into(),v6:l[2].trim().into(),auto6:l[3].trim().into()})
}
fn addresses(s:&str)->Vec<String>{s.split([',',';',' ']).map(str::trim).filter(|x|!x.is_empty()).map(str::to_string).collect()}
fn provider(d:&Dns)->&'static str{
 let mut v=addresses(&d.v4);v.sort();
 if v.is_empty()&&d.v6.is_empty()&&d.auto4!="yes"&&d.auto6!="yes" {return "Automatic"}
 for (name,a,b) in [("Cloudflare","1.1.1.1","1.0.0.1"),("Google","8.8.8.8","8.8.4.4"),("Quad9","9.9.9.9","149.112.112.112"),("AdGuard DNS","94.140.14.14","94.140.15.15")]{let mut p=vec![a.to_string(),b.to_string()];p.sort();if v==p&&d.auto4=="yes"&&d.v6.is_empty(){return name}}
 "Custom"
}
fn links()->(HashMap<String,Vec<String>>,Vec<String>){
 let mut dns=HashMap::new();let mut routes=Vec::new();
 for (kind,output) in [("dns",cmd("resolvectl",&["dns"],3).unwrap_or_default()),("domain",cmd("resolvectl",&["domain"],3).unwrap_or_default())]{for line in output.lines(){
  let iface=line.split('(').nth(1).and_then(|s|s.split(')').next());let tail=line.split_once(": ").map(|(_,t)|t);
  if let (Some(i),Some(t))=(iface,tail){if kind=="dns"{dns.insert(i.to_string(),t.split_whitespace().map(str::to_string).collect());}else if t.split_whitespace().any(|s|s=="~."){routes.push(i.to_string())}}
 }}(dns,routes)
}
fn read(path:impl AsRef<Path>)->String{fs::read_to_string(path).unwrap_or_default().trim().to_string()}
fn interfaces()->Vec<Value>{let mut out=Vec::new();if let Ok(dir)=fs::read_dir("/sys/class/net"){for e in dir.flatten(){let n=e.file_name().to_string_lossy().to_string();if n=="lo"{continue}let p=e.path();let kind=if p.join("wireless").exists(){"Wi-Fi"}else if n.starts_with("tailscale")||n.starts_with("wg"){"Private"}else if p.join("device").exists(){"Ethernet"}else{"Virtual"};let driver=fs::read_link(p.join("device/driver")).ok().and_then(|p|p.file_name().map(|s|s.to_string_lossy().to_string())).unwrap_or_default();out.push(json!({"name":n,"kind":kind,"state":read(p.join("operstate")),"driver":driver,"rx":read(p.join("statistics/rx_bytes")).parse::<u64>().unwrap_or(0),"tx":read(p.join("statistics/tx_bytes")).parse::<u64>().unwrap_or(0)}));}}out.sort_by_key(|v|v["name"].as_str().unwrap_or("").to_string());out}
fn gateway(dev:&str)->String{for l in read("/proc/net/route").lines().skip(1){let c:Vec<_>=l.split_whitespace().collect();if c.len()>2&&c[0]==dev&&c[1]=="00000000"{if let Ok(n)=u32::from_str_radix(c[2],16){return std::net::Ipv4Addr::from(n.to_le_bytes()).to_string()}}}String::new()}
fn ip(dev:&str)->(Vec<String>,Vec<String>){let v:Value=serde_json::from_str(&cmd("ip",&["-j","address","show","dev",dev],3).unwrap_or_default()).unwrap_or(Value::Null);let mut a=Vec::new();let mut b=Vec::new();if let Some(items)=v.get(0).and_then(|v|v["addr_info"].as_array()){for x in items{let s=format!("{}/{}",x["local"].as_str().unwrap_or(""),x["prefixlen"].as_u64().unwrap_or(0));match x["family"].as_str(){Some("inet")=>a.push(s),Some("inet6")=>b.push(s),_=>{}}}}(a,b)}
fn wifi(dev:&str)->Value{let mut bssid=String::new();let mut freq=String::new();let mut signal=String::new();let mut bitrate=String::new();for l in cmd("iw",&["dev",dev,"link"],3).unwrap_or_default().lines().map(str::trim){if let Some(s)=l.strip_prefix("Connected to "){bssid=s.split_whitespace().next().unwrap_or("").into()}if let Some(s)=l.strip_prefix("freq: "){freq=s.into()}if let Some(s)=l.strip_prefix("signal: "){signal=s.into()}if let Some(s)=l.strip_prefix("tx bitrate: "){bitrate=s.into()}}json!({"bssid":bssid,"frequency":freq,"signal":signal,"bitrate":bitrate})}
fn state_file()->PathBuf{Path::new(&std::env::var("HOME").unwrap_or_default()).join(".local/state/nyvorel/network-dns-rollback.json")}
fn can_undo(uuid:&str)->bool{fs::read_to_string(state_file()).ok().and_then(|s|serde_json::from_str::<Undo>(&s).ok()).is_some_and(|u|u.uuid==uuid)}
fn snapshot()->Value{let (connectivity,all)=match active(){Ok(x)=>x,Err(e)=>return json!({"ok":false,"error":e})};let devices=interfaces();let Ok(a)=selected(&all)else{return json!({"ok":true,"connectivity":connectivity,"active":null,"connections":all,"interfaces":devices})};let d=fields(&a.uuid).unwrap_or_default();let (servers,routes)=links();let other:Vec<_>=routes.into_iter().filter(|r|r!=&a.device).collect();let effective=other.first().cloned().unwrap_or_else(||a.device.clone());let (v4,v6)=ip(&a.device);let traffic=devices.iter().find(|v|v["name"]==a.device).cloned().unwrap_or(Value::Null);json!({"ok":true,"connectivity":connectivity,"active":a,"connections":all,"interfaces":devices,"ipv4":v4,"ipv6":v6,"gateway":gateway(&a.device),"wifi":if a.kind=="802-11-wireless"{wifi(&a.device)}else{Value::Null},"traffic":traffic,"dns":{"provider":provider(&d),"profile_ipv4":addresses(&d.v4),"profile_ipv6":addresses(&d.v6),"link_servers":servers.get(&a.device).cloned().unwrap_or_default(),"effective_servers":servers.get(&effective).cloned().unwrap_or_default(),"route_interface":effective,"override_active":effective!=a.device,"catch_all_overrides":other,"rollback_available":can_undo(&a.uuid),"ipv6_custom":!d.v6.is_empty()}})}
fn query(ip:IpAddr, ms:u64)->Result<u128,String>{let s=UdpSocket::bind(if ip.is_ipv4(){"0.0.0.0:0"}else{"[::]:0"}).map_err(|e|e.to_string())?;s.set_read_timeout(Some(Duration::from_millis(ms))).map_err(|e|e.to_string())?;let id=(std::process::id() as u16).to_be_bytes();let mut p=vec![id[0],id[1],1,0,0,1,0,0,0,0,0,0];for label in "example.com".split('.') {p.push(label.len() as u8);p.extend_from_slice(label.as_bytes())}p.extend_from_slice(&[0,0,1,0,1]);let start=Instant::now();s.send_to(&p,SocketAddr::new(ip,53)).map_err(|e|e.to_string())?;let mut answer=[0u8;1500];let (n,from)=s.recv_from(&mut answer).map_err(|e|e.to_string())?;if n<12||from.ip()!=ip||answer[..2]!=id||answer[3]&15!=0||answer[7]==0{return Err("Invalid or empty DNS answer".into())}Ok(start.elapsed().as_millis())}
fn compare()->Value{let mut out=Vec::new();for (name,s) in [("Cloudflare","1.1.1.1"),("Google","8.8.8.8"),("Quad9","9.9.9.9"),("AdGuard DNS","94.140.14.14")]{match query(s.parse().unwrap(),1500){Ok(t)=>out.push(json!({"name":name,"address":s,"ok":true,"ms":t})),Err(e)=>out.push(json!({"name":name,"address":s,"ok":false,"error":e}))}}json!({"ok":true,"results":out})}
fn dns_lock()->Result<fs::File,String>{let path=state_file().with_file_name("network-dns.lock");fs::create_dir_all(path.parent().unwrap()).map_err(|e|e.to_string())?;let file=fs::OpenOptions::new().write(true).create(true).mode(0o600).open(path).map_err(|e|e.to_string())?;let rc=unsafe{libc::flock(file.as_raw_fd(),libc::LOCK_EX|libc::LOCK_NB)};if rc!=0{return Err("Another DNS change is still running".into())}Ok(file)}
fn save_undo(u:&Undo)->Result<(),String>{let path=state_file();fs::create_dir_all(path.parent().unwrap()).map_err(|e|e.to_string())?;let mut f=fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(path).map_err(|e|e.to_string())?;f.write_all(serde_json::to_string(u).unwrap().as_bytes()).map_err(|e|e.to_string())}
fn apply(uuid:&str,dev:&str,d:&Dns)->Result<(),String>{cmd("nmcli",&["connection","modify","uuid",uuid,"ipv4.dns",&d.v4,"ipv4.ignore-auto-dns",&d.auto4,"ipv6.dns",&d.v6,"ipv6.ignore-auto-dns",&d.auto6],8)?;cmd("nmcli",&["device","reapply",dev],8)?;Ok(())}
fn set_dns(args:&[String])->Value{let choice=args.first().map(String::as_str).unwrap_or("");let (v4,v6):(Vec<String>,Vec<String>)=match choice{"automatic"=>(vec![],vec![]),"cloudflare"=>(vec!["1.1.1.1".into(),"1.0.0.1".into()],vec![]),"google"=>(vec!["8.8.8.8".into(),"8.8.4.4".into()],vec![]),"quad9"=>(vec!["9.9.9.9".into(),"149.112.112.112".into()],vec![]),"adguard"=>(vec!["94.140.14.14".into(),"94.140.15.15".into()],vec![]),"custom"=>{let mut a=Vec::new();let mut b=Vec::new();for s in args.iter().skip(1).filter(|s|!s.trim().is_empty()){match s.parse::<IpAddr>(){Ok(IpAddr::V4(ip))=>a.push(ip.to_string()),Ok(IpAddr::V6(ip))=>b.push(ip.to_string()),Err(_)=>return json!({"ok":false,"error":format!("Invalid DNS address: {s}")})}}if a.is_empty()&&b.is_empty(){return json!({"ok":false,"error":"Enter a DNS address"})}if a.len()>2||b.len()>2{return json!({"ok":false,"error":"At most two DNS servers per IP family"})}(a,b)},_=>return json!({"ok":false,"error":"Unknown provider"})};let _lock=match dns_lock(){Ok(x)=>x,Err(e)=>return json!({"ok":false,"error":e})};let (_,all)=match active(){Ok(x)=>x,Err(e)=>return json!({"ok":false,"error":e})};let a=match selected(&all){Ok(x)=>x,Err(e)=>return json!({"ok":false,"error":e})};let before=match fields(&a.uuid){Ok(x)=>x,Err(e)=>return json!({"ok":false,"error":e})};let mut next=before.clone();if choice=="automatic"{next.v4.clear();next.v6.clear();next.auto4="no".into();next.auto6="no".into()}else{if !v4.is_empty(){next.v4=v4.join(",");next.auto4="yes".into()}if !v6.is_empty(){next.v6=v6.join(",");next.auto6="yes".into()}}if next==before{return json!({"ok":true,"changed":false,"message":"Already configured"})}if let Err(e)=save_undo(&Undo{uuid:a.uuid.clone(),device:a.device.clone(),before,applied:next.clone()}){return json!({"ok":false,"error":format!("Could not save rollback: {e}")})}if let Err(e)=apply(&a.uuid,&a.device,&next){return json!({"ok":false,"error":e,"rollback_available":true})}let primary=v4.first().or_else(||v6.first());let direct=primary.and_then(|s|s.parse::<IpAddr>().ok()).map(|ip|query(ip,2000));let system=cmd("resolvectl",&["query","example.com"],4).is_ok();let (servers,routes)=links();let applied=servers.get(&a.device).is_some_and(|s|if choice=="automatic"{!s.is_empty()}else{primary.is_some_and(|p|s.contains(p))});let verified=system&&applied&&direct.as_ref().is_none_or(|r|r.is_ok());json!({"ok":verified,"changed":true,"rollback_available":true,"system_dns_works":system,"link_updated":applied,"override_active":routes.iter().any(|r|r!=&a.device),"direct_latency_ms":direct.as_ref().and_then(|r|r.as_ref().ok()),"message":if verified{"DNS profile updated and verified"}else{"DNS verification failed; rollback is available"}})}
fn rollback()->Value{let _lock=match dns_lock(){Ok(x)=>x,Err(e)=>return json!({"ok":false,"error":e})};let u:Undo=match fs::read_to_string(state_file()).ok().and_then(|s|serde_json::from_str(&s).ok()){Some(x)=>x,None=>return json!({"ok":false,"error":"No rollback saved"})};let (_,all)=match active(){Ok(x)=>x,Err(e)=>return json!({"ok":false,"error":e})};let a=match selected(&all){Ok(x)=>x,Err(e)=>return json!({"ok":false,"error":e})};if a.uuid!=u.uuid||a.device!=u.device{return json!({"ok":false,"error":"Original connection is not active"})}if fields(&u.uuid).ok()!=Some(u.applied){return json!({"ok":false,"error":"Profile changed outside this panel; rollback would overwrite it"})}match apply(&u.uuid,&u.device,&u.before){Ok(())=>{let _=fs::remove_file(state_file());json!({"ok":true,"message":"Previous DNS settings restored"})},Err(e)=>json!({"ok":false,"error":e})}}
fn doctor()->Value{let s=snapshot();if s["ok"]!=true{return s}let dev=s["active"]["device"].as_str().unwrap_or("");let gw=s["gateway"].as_str().unwrap_or("");let dns=s["dns"]["link_servers"].as_array().and_then(|a|a.first()).and_then(Value::as_str).and_then(|x|x.parse::<IpAddr>().ok());let gateway_ok=!gw.is_empty()&&cmd("ping",&["-n","-c","1","-W","1",gw],2).is_ok();let dns_test=dns.map(|ip|query(ip,2000));let system=cmd("resolvectl",&["query","example.com"],4).is_ok();let internet=TcpStream::connect_timeout(&"1.1.1.1:443".parse().unwrap(),Duration::from_secs(2)).is_ok();let link=read(Path::new("/sys/class/net").join(dev).join("operstate"));json!({"ok":true,"checks":[{"name":"Adapter link","passed":link=="up","detail":dev},{"name":"Gateway ICMP","passed":gateway_ok,"detail":gw},{"name":"Wi-Fi link DNS","passed":dns_test.as_ref().is_some_and(|r|r.is_ok()),"detail":dns.map(|x|x.to_string()).unwrap_or_default()},{"name":"System DNS","passed":system,"detail":if s["dns"]["override_active"]==true{"VPN catch-all route may handle this query"}else{"System resolver query"}},{"name":"Internet TCP","passed":internet,"detail":"1.1.1.1:443"}]})}
fn main(){let a:Vec<String>=std::env::args().skip(1).collect();let result=match a.first().map(String::as_str){Some("snapshot")=>snapshot(),Some("compare")=>compare(),Some("doctor")=>doctor(),Some("dns") if a.get(1).map(String::as_str)==Some("set")=>set_dns(&a[2..]),Some("dns") if a.get(1).map(String::as_str)==Some("rollback")=>rollback(),_=>json!({"ok":false,"error":"Usage: snapshot|compare|doctor|dns set PROVIDER|dns rollback"})};println!("{result}")}

#[cfg(test)]
mod tests {
 use super::*;
 #[test] fn detects_auto_and_presets() {
  let mut d=Dns{auto4:"no".into(),auto6:"no".into(),..Dns::default()};
  assert_eq!(provider(&d),"Automatic");
  d.v4="1.1.1.1,1.0.0.1".into(); d.auto4="yes".into();
  assert_eq!(provider(&d),"Cloudflare");
  d.v4="8.8.8.8,1.1.1.1".into(); assert_eq!(provider(&d),"Custom");
 }
 #[test] fn validates_custom_before_touching_network_manager() {
  let result=set_dns(&["custom".into(),"not-an-address".into()]);
  assert_eq!(result["ok"],false);
  assert!(result["error"].as_str().unwrap().contains("Invalid"));
 }
}
