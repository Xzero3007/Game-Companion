#!/usr/bin/env python3
# A made-up Jellyfin server for checking the Jellyfin tab without a real one
# (development only): 127.0.0.1:8096, user "me", password "pw". Its files
# (a 20 s test video whose top is marked, two pictures) are made with ffmpeg
# in a folder given as the first argument (default: a temporary one), and it
# logs each request to requests.log there. See CLAUDE.md.
import http.server, json, re, sys, os, subprocess, tempfile, urllib.parse
DIR = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="fake-jellyfin-")
os.makedirs(DIR, exist_ok=True)
def make(name, *args):
    if not os.path.exists(os.path.join(DIR, name)):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", *args, os.path.join(DIR, name)], check=True)
make("clip.mp4", "-f", "lavfi", "-i", "testsrc=size=640x360:rate=25", "-f", "lavfi", "-i", "sine", "-t", "20",
     "-vf", "drawbox=x=0:y=0:w=640:h=40:color=red@1:t=fill,drawtext=text='TOP':x=10:y=8:fontsize=28:fontcolor=white",
     "-c:v", "libx264", "-c:a", "aac", "-movflags", "+faststart")
make("song.ogg", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "6", "-c:a", "libvorbis")
make("still.jpg", "-f", "lavfi", "-i", "color=c=0x6b4fa0:size=400x225", "-frames:v", "1", "-vf", "drawtext=text='STILL':x=150:y=90:fontsize=40:fontcolor=white")
make("poster.jpg", "-f", "lavfi", "-i", "color=c=0x2f6b4f:size=240x360", "-frames:v", "1", "-vf", "drawtext=text='POSTER':x=40:y=160:fontsize=36:fontcolor=white")
print("fake Jellyfin on 127.0.0.1:8096, files in", DIR, flush=True)
U="a"*32; TOK="tok123"
MOVIE="1"*32; EP="2"*32; SERIES="3"*32; SEASON="4"*32; LIBM="5"*32; LIBS="6"*32; EP2="7"*32
MUSIC="8"*32; ALBUM="9"*32; SONG1="b"*32; SONG2="c"*32
T=10_000_000
def album(): return {"Id":ALBUM,"Type":"MusicAlbum","Name":"Made-up album","AlbumArtist":"Made-up band","ProductionYear":2020,
    "IsFolder":True,"ImageTags":{"Primary":"p"}}
def song(i,n,name): return {"Id":i,"Type":"Audio","MediaType":"Audio","Name":name,"IndexNumber":n,"AlbumId":ALBUM,
    "AlbumPrimaryImageTag":"p","AlbumArtist":"Made-up band","RunTimeTicks":6*T,"ImageTags":{}}
def movie(): return {"Id":MOVIE,"Type":"Movie","Name":"Made-up film","ProductionYear":2021,"RunTimeTicks":20*T,
    "UserData":{"PlaybackPositionTicks":6*T,"Played":False},"ImageTags":{"Primary":"p","Thumb":"t"}}
def ep(i=EP,n=1,name="Pilot"): return {"Id":i,"Type":"Episode","Name":name,"SeriesName":"Made-up show","SeriesId":SERIES,"SeasonId":SEASON,
    "ParentIndexNumber":1,"IndexNumber":n,"RunTimeTicks":20*T,"UserData":{"PlaybackPositionTicks":0,"Played":n==1},
    "ImageTags":{"Primary":"p"},"SeriesPrimaryImageTag":"s"}
LOG=open(os.path.join(DIR,"requests.log"),"a")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def send(self,code,body=b"",kind="application/json"):
        if isinstance(body,(dict,list)): body=json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type",kind); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def handle_any(self,method):
        auth=self.headers.get("Authorization","")
        LOG.write(f"{method} {self.path} token={'yes' if TOK in auth else 'no'} host={self.headers.get('Host')}\n"); LOG.flush()
        path=urllib.parse.urlparse(self.path).path
        if path=="/System/Info/Public": return self.send(200,{"Id":"srv","ServerName":"Fake home server"})
        if path=="/Users/AuthenticateByName":
            body=json.loads(self.rfile.read(int(self.headers.get("Content-Length",0))) or b"{}")
            if body.get("Username")=="me" and body.get("Pw")=="pw": return self.send(200,{"AccessToken":TOK,"User":{"Id":U,"Name":"me"}})
            return self.send(401,b"")
        if TOK not in auth: return self.send(401,b"")
        if path=="/UserItems/Resume": return self.send(404,b"")
        if path==f"/Users/{U}/Items/Resume": return self.send(200,{"Items":[movie(),ep(EP2,2,"Second")]})
        if path=="/Shows/NextUp": return self.send(200,{"Items":[ep(EP2,2,"Second")]})
        if path=="/UserViews": return self.send(200,{"Items":[{"Id":LIBM,"Name":"Films","CollectionType":"movies","Type":"CollectionFolder","ImageTags":{"Primary":"p"}},
            {"Id":LIBS,"Name":"Shows","CollectionType":"tvshows","Type":"CollectionFolder","ImageTags":{}},{"Id":MUSIC,"Name":"Music","CollectionType":"music"}]})
        if path=="/Items" and "ParentId="+LIBM in self.path: return self.send(200,{"Items":[movie()],"TotalRecordCount":1})
        if path=="/Items" and "ParentId="+LIBS in self.path: return self.send(200,{"Items":[{"Id":SERIES,"Type":"Series","Name":"Made-up show","IsFolder":True,"ImageTags":{"Primary":"p"},"UserData":{"UnplayedItemCount":1}}],"TotalRecordCount":1})
        if path=="/Items" and "ParentId="+MUSIC in self.path: return self.send(200,{"Items":[album()],"TotalRecordCount":1})
        if path=="/Items" and "ParentId="+ALBUM in self.path: return self.send(200,{"Items":[song(SONG1,1,"First song"),song(SONG2,2,"Second song")],"TotalRecordCount":2})
        if path=="/Items" and "searchTerm=" in self.path: return self.send(200,{"Items":[movie()]})
        if path==f"/Shows/{SERIES}/Seasons": return self.send(200,{"Items":[{"Id":SEASON,"Type":"Season","Name":"Season 1","SeriesId":SERIES,"IsFolder":True,"ImageTags":{}}]})
        if path==f"/Shows/{SERIES}/Episodes":
            if "startItemId="+EP in self.path: return self.send(200,{"Items":[ep(),ep(EP2,2,"Second")]})
            return self.send(200,{"Items":[ep(),ep(EP2,2,"Second")]})
        m=re.match(r"/Items/(\w+)/PlaybackInfo",path)
        if m and m.group(1) in (SONG1,SONG2): return self.send(200,{"PlaySessionId":"sess2","MediaSources":[{"Id":m.group(1),"MediaStreams":[
            {"Index":0,"Type":"Audio","DisplayTitle":"Vorbis - Stereo"},{"Index":1,"Type":"EmbeddedImage"}]}]})
        if m: return self.send(200,{"PlaySessionId":"sess1","MediaSources":[{"Id":m.group(1),"DefaultAudioStreamIndex":1,"MediaStreams":[
            {"Index":0,"Type":"Video"},{"Index":1,"Type":"Audio","DisplayTitle":"English - AAC"},{"Index":2,"Type":"Subtitle","Codec":"srt","IsExternal":True,"DisplayTitle":"Deutsch"}]}]})
        m=re.match(r"/MediaSegments/(\w+)",path)
        if m: return self.send(200,{"Items":[{"Type":"Intro","StartTicks":2*T,"EndTicks":8*T}]})
        m=re.match(r"/Items/(\w+)/Images/(\w+)",path)
        if m: return self.send(200,open(os.path.join(DIR,"poster.jpg" if m.group(2)=="Primary" and m.group(1) in (SERIES,LIBM) else "still.jpg"),"rb").read(),"image/jpeg")
        if re.match(r"/Audio/\w+/stream",path): return self.send(200,open(os.path.join(DIR,"song.ogg"),"rb").read(),"audio/ogg")
        if re.match(r"/Videos/\w+/stream",path):
            data=open(os.path.join(DIR,"clip.mp4"),"rb").read()
            r=re.match(r"bytes=(\d+)-(\d*)",self.headers.get("Range",""))
            if not r: return self.send(200,data,"video/mp4")
            a=int(r.group(1)); b=int(r.group(2)) if r.group(2) else len(data)-1
            part=data[a:b+1]
            self.send_response(206); self.send_header("Content-Type","video/mp4"); self.send_header("Accept-Ranges","bytes")
            self.send_header("Content-Range",f"bytes {a}-{b}/{len(data)}"); self.send_header("Content-Length",str(len(part))); self.end_headers(); self.wfile.write(part); return
        if re.match(r"/Videos/\w+/\w+/Subtitles/2/0/Stream.srt",path): return self.send(200,b"1\n00:00:00,500 --> 00:00:19,000\nUNTERTITEL AUS DEM SERVER\n","text/plain")
        if path.startswith("/Sessions/") or path.startswith(f"/Users/{U}/PlayedItems/"): return self.send(204,b"")
        return self.send(404,b"")
    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")
    def do_DELETE(self): self.handle_any("DELETE")
http.server.ThreadingHTTPServer(("127.0.0.1",8096),H).serve_forever()
