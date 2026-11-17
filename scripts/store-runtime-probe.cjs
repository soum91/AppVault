// Offline smoke test: initializes the supplied WASM runtime, without Apple accounts or network.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { webcrypto } = require('node:crypto');
const { performance } = require('node:perf_hooks');
const runtime = process.env.APPVAULT_RUNTIME || '/tmp/appvault-ipadn/iPadn-iOS/vendor/SAPRuntime/files';
const base = 'https://localhost/runtime/';
let context;
let wasmFetches = 0;
let soFetches = 0;
const document = {
  currentScript: { src: base + 'sap-signer.js' }, baseURI: base + 'index.html',
  createElement() { return {}; },
  head: {
    appendChild(script) {
      const filename = new URL(script.src).pathname.split('/').pop();
      const previous = document.currentScript;
      document.currentScript = script;
      try {
        vm.runInContext(fs.readFileSync(path.join(runtime, filename), 'utf8'), context, { filename });
        queueMicrotask(() => script.onload());
      } catch (error) { queueMicrotask(() => script.onerror(error)); }
      finally { document.currentScript = previous; }
    }
  }
};
const sandbox = {
  console, URL, TextEncoder, TextDecoder, WebAssembly, crypto: webcrypto, performance,
  setTimeout, clearTimeout, setInterval, clearInterval, document,
  atob: value => Buffer.from(value, 'base64').toString('binary'),
  btoa: value => Buffer.from(value, 'binary').toString('base64'),
  fetch: async (address, options = {}) => {
    const url = new URL(address);
    assert.equal(url.host, 'localhost');
    if (url.pathname === '/proxy') {
      const upstream = url.searchParams.get('url');
      assert.ok(['https://s.mzstatic.com/sap/setupCert.plist','https://fpinit.itunes.apple.com/v1/signSapSetup/legacy','https://auth.itunes.apple.com/auth/v1/otp/1.5/finish'].includes(upstream));
      const body = options.body ? Buffer.from(options.body) : undefined;
      return fetch(upstream, {...options, body, redirect:'manual', headers:{...options.headers,'User-Agent':UA}});
    }
    const data=fs.readFileSync(path.join(runtime,url.pathname.split('/').pop()));
    return {ok:true,status:200,arrayBuffer:async()=>data.buffer.slice(data.byteOffset,data.byteOffset+data.byteLength)};

  }
};
sandbox.window = sandbox;
context = vm.createContext(sandbox);
const timeout = setTimeout(() => { console.error('Store authentication probe timed out'); process.exit(1); }, 180_000);
const UA='Configurator/2.21 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6';

(async()=>{
  vm.runInContext(fs.readFileSync(path.join(runtime,'sap-signer.js'),'utf8'),context,{filename:'sap-signer.js'});
  const guid=webcrypto.randomUUID().replaceAll('-','').slice(0,12).toUpperCase();
  const email=webcrypto.randomUUID()+'@example.invalid',password=webcrypto.randomUUID();
  const bag=await fetch('https://init.itunes.apple.com/bag.xml?guid='+guid+'&ix=6',{headers:{'User-Agent':UA}}).then(r=>r.text());
  const initial=bag.match(/<key>authenticateAccount<\/key>\s*<string>([^<]+)<\/string>/)?.[1];
  assert.ok(initial,'Bag did not advertise auth endpoint');
  let url=new URL(initial.replaceAll('&amp;','&'));url.searchParams.set('guid',guid);
  assert.equal(url.hostname,'auth.itunes.apple.com');
  const body='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>appleId</key><string>'+email+'</string><key>attempt</key><string>1</string><key>guid</key><string>'+guid+'</string><key>password</key><string>'+password+'</string><key>rmp</key><string>0</string><key>why</key><string>signIn</string></dict></plist>';
  await context.sapInitialize(guid,{proxyURL:'https://localhost/proxy'});
  const signature=await context.sapSign(Buffer.from(body).toString('base64'));
  await context.sapClose();
  let state={identifier:webcrypto.randomUUID().replaceAll('-','').slice(0,16),files:{}};
  for(let step=0;step<4;step++){
    let proof=JSON.parse(await context.sapStoreProofHeaders(JSON.stringify(state),{proxyURL:'https://localhost/proxy'}));state=proof.state;
    const response=await fetch(url,{method:'POST',redirect:'manual',headers:{'User-Agent':UA,'Content-Type':'application/x-apple-plist','X-Apple-ActionSignature':signature,...proof.headers},body});
    const text=await response.text();
    const action=response.headers.get('x-apple-amd-action')||text.match(/AMD-Action::(SP|RP)/)?.[1]||'';
    console.log(JSON.stringify({stage:'authentication',status:response.status,action,bytes:Buffer.byteLength(text),proof:proof.provisioned}));
    if(action==='RP'){state={identifier:webcrypto.randomUUID().replaceAll('-','').slice(0,16),files:{}};continue;}
    if(action==='SP'){
      const challenge=response.headers.get('x-apple-amd-data');assert.ok(challenge);
      const result=JSON.parse(await context.sapStoreProvision(JSON.stringify(state),challenge,guid,{proxyURL:'https://localhost/proxy'}));assert.equal(result.provisioned,true);state=result.state;continue;
    }
    if([301,302,303,307,308].includes(response.status)&&response.headers.get('location')){url=new URL(response.headers.get('location'),url);assert.ok(url.protocol==='https:'&&url.hostname.endsWith('.itunes.apple.com'));continue;}
    assert.equal(response.status,200,'Attested authentication did not reach business response');
    assert.ok(text.includes('<plist')&&text.includes('customerMessage'),'No Apple business authentication result');
    console.log('PASS: SAP + Store device attestation reached Apple business authentication. Real account login not tested.');
    clearTimeout(timeout);process.exit(0);
  }
  throw Error('Device proof loop exceeded bounded attempts');
})().catch(error=>{console.error(error.message);clearTimeout(timeout);process.exit(1)});
