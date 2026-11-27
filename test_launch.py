import http.server, json, os, subprocess, threading, tempfile, textwrap
import pathlib
ROOT=str(pathlib.Path(__file__).resolve().parents[2])
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def send(self,code,body=b"{}"):
        self.send_response(code); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        p=self.path; port=self.server.server_port
        if port==19001:
            if self.headers.get("apikey")!="anon-ok": return self.send(401)
            return self.send(200) if p in("/auth/v1/health","/rest/v1/") else self.send(404)
        if port==19002:
            if self.headers.get("Authorization")!="Bearer sk-good": return self.send(401)
            return self.send(200,json.dumps({"data":[{"id":"gpt-4o-mini"}]}).encode())
        if port==19003:
            return self.send(200) if p=="/v1/prices/price_ok" and "Authorization" in self.headers else self.send(404)
servers=[http.server.ThreadingHTTPServer(("127.0.0.1",p),H) for p in (19001,19002,19003)]
for s in servers: threading.Thread(target=s.serve_forever,daemon=True).start()
BASE=dict(PATH=os.environ['PATH'],SKIP_TOOLS='1',OPENAI_BASE_URL='http://127.0.0.1:19002',STRIPE_BASE_URL='http://127.0.0.1:19003',SUPABASE_CHECK_URL='http://127.0.0.1:19001')
import shutil
LEGAL=tempfile.mkdtemp()
for _f in ('privacy-policy.md','terms-of-use.md'): open(LEGAL+'/'+_f,'w').write('# final text\n')
GOOD=dict(LEGAL_DIR=LEGAL,SUPABASE_PROJECT_REF='abc',SUPABASE_URL='https://abc.supabase.co',SUPABASE_ANON_KEY='anon-ok',DATABASE_URL='postgresql://x',PAGES_PROJECT='gt',WEB_ORIGIN='https://gt.pages.dev',OPENAI_API_KEY='sk-good',PRIVACY_URL='https://p',TERMS_URL='https://t',SUPPORT_EMAIL='a@b.co',ADMIN_EMAIL='me@x.com')
def run(cmd,**env):
    e=dict(BASE); e.update(env)
    r=subprocess.run(cmd,cwd=ROOT,env=e,capture_output=True,text=True,timeout=60)
    return r.returncode,r.stdout+r.stderr
fails=0
def check(name,cond,detail=''):
    global fails
    print(('PASS  ' if cond else 'FAIL  ')+name+('' if cond else '\n'+detail)); fails+= (not cond)

rc,out=run(['scripts/preflight.sh'],OFFLINE='1',**{**GOOD,'LEGAL_DIR':ROOT+'/docs/legal'})
check('preflight: unfinished legal drafts stop the launch',rc==1 and 'placeholder' in out,out)
rc,out=run(['scripts/preflight.sh'],OFFLINE='1',**{**GOOD,'LEGAL_DIR':ROOT+'/docs/legal','ALLOW_LEGAL_DRAFT':'1'})
check('preflight: ALLOW_LEGAL_DRAFT=1 only warns',rc==0 and 'not final' in out,out)
rc,out=run(['scripts/preflight.sh'],OFFLINE='1',**GOOD)
check('preflight offline: complete settings pass',rc==0 and 'Ready to launch' in out,out)
rc,out=run(['scripts/preflight.sh'],**GOOD)
check('preflight online: good keys pass (Supabase, OpenAI, model)',rc==0 and 'OpenAI accepts the key' in out and 'model gpt-4o-mini is available' in out,out)
rc,out=run(['scripts/preflight.sh'],**{**GOOD,'OPENAI_API_KEY':'sk-bad'})
check('preflight: a wrong OpenAI key is caught',rc==1 and 'rejected the key' in out,out)
rc,out=run(['scripts/preflight.sh'],**{**GOOD,'SUPABASE_ANON_KEY':'wrong'})
check('preflight: a wrong Supabase key is caught',rc==1 and 'not reachable' in out,out)
rc,out=run(['scripts/preflight.sh'],**{**GOOD,'STRIPE_SECRET_KEY':'sk_test_1','STRIPE_WEBHOOK_SECRET':'whsec','STRIPE_PRICE_MONTHLY':'price_ok','STRIPE_PRICE_QUARTERLY':'price_ok','STRIPE_PRICE_YEARLY':'price_missing'})
check('preflight: a missing Stripe price is caught, existing ones pass',rc==1 and 'STRIPE_PRICE_YEARLY not found' in out and 'STRIPE_PRICE_MONTHLY exists' in out,out)
rc,out=run(['scripts/preflight.sh'],OFFLINE='1',**{**GOOD,'SUPABASE_URL':'https://other.supabase.co','DATABASE_URL':'mysql://x','WEB_ORIGIN':'http://gt.pages.dev/'})
check('preflight: mismatching ids, bad database url and http/slash address are caught',rc==1 and out.count('FAIL')>=3,out)
miss={k:v for k,v in GOOD.items() if k!='OPENAI_API_KEY'}
rc,out=run(['scripts/preflight.sh'],OFFLINE='1',**miss)
check('preflight: a missing setting is named',rc==1 and 'OPENAI_API_KEY is missing' in out,out)
rc,out=run(['scripts/preflight.sh'],OFFLINE='1',**{**GOOD,'TURNSTILE_SITE_KEY':'k'})
check('preflight: Turnstile site key without secret is caught',rc==1 and 'TURNSTILE_SECRET is missing' in out,out)

with tempfile.NamedTemporaryFile('w',suffix='.env',delete=False) as f:
    f.write('\n'.join(f'{k}={v}' for k,v in GOOD.items())+'\nSUPABASE_ACCESS_TOKEN=tok\nTURNSTILE_SECRET=sec\nTURNSTILE_SITE_KEY=site\nSTRIPE_SECRET_KEY=sk_test_1\nSTRIPE_WEBHOOK_SECRET=whsec\nSTRIPE_PRICE_MONTHLY=price_ok\nSTRIPE_PRICE_QUARTERLY=price_ok\nSTRIPE_PRICE_YEARLY=price_ok\n')
    envfile=f.name
rc,out=run(['scripts/launch_website.sh'],ENV_FILE=envfile,DRY_RUN='1')
steps=[f'== {i}/7' for i in range(1,8)]
check('dry run: all 7 steps are shown and nothing is executed',rc==0 and all(s in out for s in steps) and out.count('[dry run]')>=5,out)
check('dry run: secrets are listed by name only, never by value',('OPENAI_API_KEY' in out) and ('sk-good' not in out) and ('sk_test_1' not in out) and ('whsec' not in out),out)
check('dry run: auth settings and captcha are planned',"PATCH https://api.supabase.com/v1/projects/abc/config/auth" in out and 'captcha' in out,out)
rc,out=run(['scripts/launch_website.sh'],ENV_FILE='/nonexistent.env',DRY_RUN='1')
check('missing .env file gives a clear message',rc!=0 and 'launch/.env' in out,out)
bad=envfile+'.bad'; open(bad,'w').write(open(envfile).read().replace('OPENAI_API_KEY=sk-good','OPENAI_API_KEY='))
rc,out=run(['scripts/launch_website.sh'],ENV_FILE=bad,DRY_RUN='1')
check('a missing setting stops the launch before anything is deployed',rc!=0 and '== 2/7' not in out,out)
print('\n%d failed'%fails)
raise SystemExit(1 if fails else 0)
